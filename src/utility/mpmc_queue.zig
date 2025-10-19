const std = @import("std");

/// Bounded MPMC queue translated from rigtorp/mpmc (C++), adapted to Zig.
/// - Cache-line sized slot metadata to avoid false sharing.
/// - Per-slot `turn` (sequence) value paired with global head/tail counters.
/// - Blocking `push/pop` plus non-blocking`tryPush/tryPop` variants.
///
/// Safety constraints mimic the original:
/// - `T` must be trivially movable and destructible (no implicit deinit).
///   In Zig we require `@typeInfo(T) == .Struct or .Enum or .Union or .Pointer or .Int or .Float` etc.
///   We avoid running destructors automatically; caller manages lifetimes of any owned data inside `T`.
///
/// Each item in the queue is atleast one cache line in size (mostly 64 bytes).
/// This means you can make your items this size without incurring much of a performance penalty.
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();
        const AtomicUsize = std.atomic.Value(usize);

        /// Hardware cache line size assumption used for padding/alignment
        pub const hardware_interference_size: comptime_int = std.atomic.cache_line;

        const Slot = struct {
            // Ensure `turn` resides in its own cache line to avoid adjacent slot sharing
            turn: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
            // Value storage
            value: T = undefined,
            // Force the struct's alignment to hardware_interference_size
            _align: u8 align(hardware_interference_size) = 0,
        };

        allocator: std.mem.Allocator,
        capacity: usize,
        slots: []Slot,

        // Align head and tail fields individually to cache-line size to avoid false sharing
        /// The head advances as producers reserve/commit new items.
        /// Readiness is determined per slot by the turn. head/tail provide unuqiue positions,
        /// not availability. Read the .push() function for more details.
        head: AtomicUsize align(hardware_interference_size) = AtomicUsize.init(0),
        /// The tail follows (the head) as consumers dequeue items.
        tail: AtomicUsize align(hardware_interference_size) = AtomicUsize.init(0),

        pub const InitError = error{ InvalidCapacity, OutOfMemory };

        pub fn init(allocator: std.mem.Allocator, capacity: usize) InitError!Self {
            if (capacity < 1) return error.InvalidCapacity;
            // Allocate one extra slot like the C++ version to avoid last-slot sharing
            var slots = try allocator.alloc(Slot, capacity + 1);
            // Construct slots with turn = 0; value left undefined until written
            for (slots[0..capacity]) |*s| {
                s.* = .{ .turn = std.atomic.Value(usize).init(0), .value = undefined };
            }
            return .{
                .allocator = allocator,
                .capacity = capacity,
                .slots = slots,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.slots);
        }

        inline fn idx(self: *const Self, i: usize) usize {
            return i % self.capacity;
        }

        inline fn turn(self: *const Self, i: usize) usize {
            return i / self.capacity;
        }

        /// Push value by copy. Returns when slot available.
        pub fn push(self: *Self, v: T) void {
            const head_val = self.head.fetchAdd(1, .monotonic);
            const s = &self.slots[self.idx(head_val)];
            // We encode per-slot state using even/odd epochs to avoid ABA on wraparound.
            // Let e = turn(head_val) (the epoch for this position):
            //   empty for epoch e   => 2*e
            //   full for epoch e    => 2*e + 1
            //   consumed after e    => 2*e + 2 == 2*(e + 1)
            // We wait until s.turn == 2*e (slot empty for this epoch), then write
            // and publish by storing 2*e + 1 so consumers can observe the value.
            while (self.turn(head_val) * 2 != s.turn.load(.acquire)) {
                std.atomic.spinLoopHint();
            }
            s.value = v;
            s.turn.store(self.turn(head_val) * 2 + 1, .release);
        }

        /// Try to push without blocking; returns true on success, false if queue appears full.
        pub fn tryPush(self: *Self, v: T) bool {
            var head_val = self.head.load(.acquire);
            while (true) {
                const s = &self.slots[self.idx(head_val)];
                if (self.turn(head_val) * 2 == s.turn.load(.acquire)) {
                    if (self.head.cmpxchgStrong(head_val, head_val + 1, .seq_cst, .acquire)) |old| {
                        // CAS failed; retry with observed head
                        head_val = old;
                        continue;
                    } else {
                        // won reservation
                        s.value = v;
                        s.turn.store(self.turn(head_val) * 2 + 1, .release);
                        return true;
                    }
                } else {
                    const prev = head_val;
                    head_val = self.head.load(.acquire);
                    if (head_val == prev) return false;
                }
            }
        }

        /// Pop into out param, blocking until available.
        /// This copies the data from the queue into the provided pointer.
        /// No destructors are called here. Call them manually if needed.
        pub fn pop(self: *Self, out: *T) void {
            const tail_val = self.tail.fetchAdd(1, .monotonic);
            const s = &self.slots[self.idx(tail_val)];
            while (self.turn(tail_val) * 2 + 1 != s.turn.load(.acquire)) {
                std.atomic.spinLoopHint();
            }
            out.* = s.value;
            // No destructor call; user owns deinit if needed
            s.turn.store(self.turn(tail_val) * 2 + 2, .release);
        }

        /// Try to pop without blocking; returns true on success.
        /// This copies the data from the queue into the provided pointer.
        /// No destructors are called here. Call them manually if needed.
        pub fn tryPop(self: *Self, out: *T) bool {
            var tail_val = self.tail.load(.acquire);
            while (true) {
                const s = &self.slots[self.idx(tail_val)];
                if (self.turn(tail_val) * 2 + 1 == s.turn.load(.acquire)) {
                    if (self.tail.cmpxchgStrong(tail_val, tail_val + 1, .seq_cst, .acquire)) |old| {
                        tail_val = old;
                        continue;
                    } else {
                        out.* = s.value;
                        s.turn.store(self.turn(tail_val) * 2 + 2, .release);
                        return true;
                    }
                } else {
                    const prev = tail_val;
                    tail_val = self.tail.load(.acquire);
                    if (tail_val == prev) return false;
                }
            }
        }

        /// Best-effort size snapshot (can be negative in C++; here clamp at 0 for unsigned).
        /// There is a timing window between the head and tail loads where the size can be negative.
        pub fn size(self: *const Self) usize {
            const h = self.head.load(.unordered);
            const t = self.tail.load(.unordered);
            return if (h >= t) h - t else 0;
        }

        pub fn empty(self: *const Self) bool {
            return self.size() == 0;
        }
    };
}

test "mpmc queue basic single-thread" {
    const T = u32;
    const alloc = std.testing.allocator;

    var q = try Queue(T).init(alloc, 8);
    defer q.deinit();

    try std.testing.expect(q.empty());
    q.push(123);
    try std.testing.expect(q.size() == 1);
    var out: T = 0;
    q.pop(&out);
    try std.testing.expectEqual(@as(T, 123), out);
    try std.testing.expect(q.empty());
}

test "slot alignment is cache-line multiple" {
    const T = u32;
    const Q = Queue(T);
    comptime {
        std.debug.assert(@alignOf(Q.Slot) == Q.hardware_interference_size);
        std.debug.assert(@sizeOf(Q.Slot) % Q.hardware_interference_size == 0);
    }
}

test "slot alignment across multiple T sizes" {
    const Types = .{
        u8,                          u16,                          u32,    u64,    u128,
        [7]u8,                       [63]u8,                       [64]u8, [65]u8, [128]u8,
        struct { a: u8, b: [15]u8 }, struct { a: u64, b: [96]u8 },
    };

    inline for (Types) |Ty| {
        const Q = Queue(Ty);
        comptime {
            std.debug.assert(@alignOf(Q.Slot) == Q.hardware_interference_size);
            std.debug.assert(@sizeOf(Q.Slot) % Q.hardware_interference_size == 0);
        }
    }
}

test "init with capacity 0 returns InvalidCapacity" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(error.InvalidCapacity, Queue(u32).init(alloc, 0));
}

test "capacity boundary using tryPush/tryPop" {
    const T = u32;
    const alloc = std.testing.allocator;

    var q = try Queue(T).init(alloc, 4);
    defer q.deinit();

    // Fill exactly to capacity
    try std.testing.expect(q.tryPush(0));
    try std.testing.expect(q.tryPush(1));
    try std.testing.expect(q.tryPush(2));
    try std.testing.expect(q.tryPush(3));

    // Next push should fail (appears full)
    try std.testing.expect(!q.tryPush(999));
    try std.testing.expectEqual(@as(usize, 4), q.size());

    // Drain and verify order
    var out: T = 0;
    try std.testing.expect(q.tryPop(&out));
    try std.testing.expectEqual(@as(T, 0), out);
    try std.testing.expect(q.tryPop(&out));
    try std.testing.expectEqual(@as(T, 1), out);
    try std.testing.expect(q.tryPop(&out));
    try std.testing.expectEqual(@as(T, 2), out);
    try std.testing.expect(q.tryPop(&out));
    try std.testing.expectEqual(@as(T, 3), out);

    try std.testing.expect(q.empty());
    try std.testing.expectEqual(@as(usize, 0), q.size());
}

test "single-thread FIFO order with multiple items" {
    const T = u32;
    const alloc = std.testing.allocator;
    var q = try Queue(T).init(alloc, 50);
    defer q.deinit();

    // Push 0..49 and pop, verify strict FIFO
    const N: usize = 50;
    var i: usize = 0;
    while (i < N) : (i += 1) q.push(@as(T, @intCast(i)));

    var out: T = 0;
    i = 0;
    while (i < N) : (i += 1) {
        q.pop(&out);
        try std.testing.expectEqual(@as(T, @intCast(i)), out);
    }

    try std.testing.expect(q.empty());
}

test "size() and empty() correctness single-thread" {
    const T = u32;
    const alloc = std.testing.allocator;
    var q = try Queue(T).init(alloc, 8);
    defer q.deinit();

    try std.testing.expect(q.empty());
    try std.testing.expectEqual(@as(usize, 0), q.size());

    q.push(1);
    try std.testing.expect(!q.empty());
    try std.testing.expectEqual(@as(usize, 1), q.size());

    q.push(2);
    try std.testing.expectEqual(@as(usize, 2), q.size());

    var out: T = 0;
    q.pop(&out);
    try std.testing.expectEqual(@as(T, 1), out);
    try std.testing.expectEqual(@as(usize, 1), q.size());

    q.pop(&out);
    try std.testing.expectEqual(@as(T, 2), out);
    try std.testing.expect(q.empty());
    try std.testing.expectEqual(@as(usize, 0), q.size());
}

test "tryPop on empty does not modify out" {
    const T = u32;
    const alloc = std.testing.allocator;
    var q = try Queue(T).init(alloc, 4);
    defer q.deinit();

    var out: T = 7777;
    const ok = q.tryPop(&out);
    try std.testing.expect(!ok);
    try std.testing.expectEqual(@as(T, 7777), out);
}

test "tryPush on full returns false" {
    const T = u32;
    const alloc = std.testing.allocator;
    var q = try Queue(T).init(alloc, 2);
    defer q.deinit();

    try std.testing.expect(q.tryPush(1));
    try std.testing.expect(q.tryPush(2));
    try std.testing.expect(!q.tryPush(3));
}

test "reusability after full drain" {
    const T = u32;
    const alloc = std.testing.allocator;
    var q = try Queue(T).init(alloc, 4);
    defer q.deinit();

    // First cycle
    try std.testing.expect(q.tryPush(10));
    try std.testing.expect(q.tryPush(20));
    var out: T = 0;
    try std.testing.expect(q.tryPop(&out));
    try std.testing.expectEqual(@as(T, 10), out);
    try std.testing.expect(q.tryPop(&out));
    try std.testing.expectEqual(@as(T, 20), out);
    try std.testing.expect(q.empty());

    // Second cycle after drain
    try std.testing.expect(q.tryPush(30));
    try std.testing.expect(q.tryPush(40));
    try std.testing.expect(q.tryPop(&out));
    try std.testing.expectEqual(@as(T, 30), out);
    try std.testing.expect(q.tryPop(&out));
    try std.testing.expectEqual(@as(T, 40), out);
    try std.testing.expect(q.empty());
}

test "capacity=1 repeated reuse validation" {
    const T = u32;
    const alloc = std.testing.allocator;
    var q = try Queue(T).init(alloc, 1);
    defer q.deinit();

    const N: usize = 1000;
    var i: usize = 0;
    var out: T = 0;
    while (i < N) : (i += 1) {
        q.push(@as(T, @intCast(i)));
        q.pop(&out);
        try std.testing.expectEqual(@as(T, @intCast(i)), out);
    }
    try std.testing.expect(q.empty());
}

test "struct payload roundtrip equality" {
    const Payload = struct { a: u64, b: [16]u8 };
    const alloc = std.testing.allocator;
    var q = try Queue(Payload).init(alloc, 4);
    defer q.deinit();

    var p1 = Payload{ .a = 42, .b = [_]u8{1} ** 16 };
    var p2 = Payload{ .a = 99, .b = [_]u8{2} ** 16 };
    q.push(p1);
    q.push(p2);

    var out: Payload = undefined;
    q.pop(&out);
    try std.testing.expectEqual(@as(u64, 42), out.a);
    try std.testing.expectEqualSlices(u8, &p1.b, &out.b);
    q.pop(&out);
    try std.testing.expectEqual(@as(u64, 99), out.a);
    try std.testing.expectEqualSlices(u8, &p2.b, &out.b);
}

test "wraparound with small capacity and many operations" {
    const T = u32;
    const alloc = std.testing.allocator;
    var q = try Queue(T).init(alloc, 3);
    defer q.deinit();

    const N: usize = 10000;
    var next_to_push: usize = 0; // next value to attempt to push
    var consumed: usize = 0;
    var out: T = 0;
    var pending: usize = 0; // items currently enqueued but not yet consumed

    // Keep queue occupancy <= 2 using try APIs to exercise wraparound heavily
    while (consumed < N) {
        // Try to fill up to 2 pending items
        while (pending < 2 and next_to_push < N) {
            if (q.tryPush(@as(T, @intCast(next_to_push)))) {
                pending += 1;
                next_to_push += 1;
            } else {
                break;
            }
        }
        // Try to consume
        if (q.tryPop(&out)) {
            try std.testing.expectEqual(@as(T, @intCast(consumed)), out);
            consumed += 1;
            pending -= 1;
        }
    }

    try std.testing.expect(q.empty());
    try std.testing.expectEqual(@as(usize, 0), pending);
}

test "SPSC: single producer single consumer preserves order" {
    const T = u32;
    const alloc = std.testing.allocator;
    var q = try Queue(T).init(alloc, 64);
    defer q.deinit();

    const N: usize = 50_000;
    var prod = try std.Thread.spawn(.{}, struct {
        fn run(qp: *Queue(T)) void {
            var i: usize = 0;
            while (i < N) : (i += 1) qp.push(@as(T, @intCast(i)));
        }
    }.run, .{&q});

    var consumed: usize = 0;
    var out: T = 0;
    while (consumed < N) : (consumed += 1) {
        q.pop(&out);
        try std.testing.expectEqual(@as(T, @intCast(consumed)), out);
    }

    prod.join();
    try std.testing.expect(q.empty());
}

test "MPSC: multiple producers single consumer, per-producer order and uniqueness" {
    const T = struct { producer: u32, seq: u32 };
    const alloc = std.testing.allocator;
    var q = try Queue(T).init(alloc, 256);
    defer q.deinit();

    const P: usize = 4;
    const N: usize = 20_000; // per producer

    var threads: [P]std.Thread = undefined;
    var p: usize = 0;
    while (p < P) : (p += 1) {
        const pid: u32 = @as(u32, @intCast(p));
        threads[p] = try std.Thread.spawn(.{}, struct {
            fn run(qp: *Queue(T), id: u32) void {
                var i: usize = 0;
                while (i < N) : (i += 1) qp.push(.{ .producer = id, .seq = @as(u32, @intCast(i)) });
            }
        }.run, .{ &q, pid });
    }

    // Consumer collects counts and checks per-producer monotonic sequence
    var last_seq_per_producer: [P]u32 = [_]u32{0} ** P;
    var seen_counts: [P]usize = [_]usize{0} ** P;
    var total: usize = 0;
    var out: T = undefined;
    while (total < P * N) : (total += 1) {
        q.pop(&out);
        const idx = @as(usize, out.producer);
        // seq must match expected count for that producer
        try std.testing.expectEqual(@as(u32, @intCast(seen_counts[idx])), out.seq);
        seen_counts[idx] += 1;
        last_seq_per_producer[idx] = out.seq;
    }

    // Join producers
    p = 0;
    while (p < P) : (p += 1) threads[p].join();

    // All produced consumed exactly once
    p = 0;
    while (p < P) : (p += 1) {
        try std.testing.expectEqual(@as(usize, N), seen_counts[p]);
        try std.testing.expectEqual(@as(u32, @intCast(N - 1)), last_seq_per_producer[p]);
    }

    try std.testing.expect(q.empty());
}

test "SPMC: single producer multiple consumers unique coverage" {
    const T = u32;
    const alloc = std.testing.allocator;
    var q = try Queue(T).init(alloc, 256);
    defer q.deinit();

    const C: usize = 4; // consumers
    const N: usize = 50_000; // total items

    // Track uniqueness per ID using atomic flags
    const AtomicU8 = std.atomic.Value(u8);
    var flags = try alloc.alloc(AtomicU8, N);
    defer alloc.free(flags);
    for (flags) |*f| f.* = AtomicU8.init(0);

    var total = std.atomic.Value(usize).init(0);

    // Spawn consumers
    var consumers: [C]std.Thread = undefined;
    var ci: usize = 0;
    while (ci < C) : (ci += 1) {
        consumers[ci] = try std.Thread.spawn(.{}, struct {
            fn run(qp: *Queue(T), totalp: *std.atomic.Value(usize), flags_slice: []AtomicU8, N_total: usize) void {
                var out: T = 0;
                while (true) {
                    if (qp.tryPop(&out)) {
                        const idx = @as(usize, out);
                        // Check unique consumption
                        if (flags_slice[idx].cmpxchgStrong(0, 1, .seq_cst, .monotonic)) |_| {
                            // was already seen -> duplicate
                            std.debug.panic("duplicate id consumed: {}", .{out});
                        }
                        const new_total = totalp.fetchAdd(1, .seq_cst) + 1;
                        if (new_total == N_total) break;
                        continue;
                    }
                    if (totalp.load(.acquire) == N_total) break;
                    std.atomic.spinLoopHint();
                }
            }
        }.run, .{ &q, &total, flags, N });
    }

    // Producer pushes N items
    var prod = try std.Thread.spawn(.{}, struct {
        fn run(qp: *Queue(T), total_items: usize) void {
            var i: usize = 0;
            while (i < total_items) : (i += 1) qp.push(@as(T, @intCast(i)));
        }
    }.run, .{ &q, N });

    // Join threads
    prod.join();
    ci = 0;
    while (ci < C) : (ci += 1) consumers[ci].join();

    try std.testing.expectEqual(@as(usize, N), total.load(.acquire));
    try std.testing.expect(q.empty());
    // Verify all flags set
    var i: usize = 0;
    while (i < N) : (i += 1) try std.testing.expectEqual(@as(u8, 1), flags[i].load(.acquire));
}

test "MPMC: multi producers multi consumers coverage and per-producer order" {
    const Item = struct { producer: u32, seq: u32 };
    const alloc = std.testing.allocator;
    var q = try Queue(Item).init(alloc, 512);
    defer q.deinit();

    const P: usize = 4; // producers
    const C: usize = 4; // consumers
    const N: usize = 25_000; // per producer

    // Track per-producer next expected sequence for order check and total count
    var seen_counts: [P]std.atomic.Value(usize) = undefined;
    var next_expected: [P]std.atomic.Value(u32) = undefined;
    var pi: usize = 0;
    while (pi < P) : (pi += 1) {
        seen_counts[pi] = std.atomic.Value(usize).init(0);
        next_expected[pi] = std.atomic.Value(u32).init(0);
    }

    var total = std.atomic.Value(usize).init(0);

    // Spawn producers
    var prods: [P]std.Thread = undefined;
    pi = 0;
    while (pi < P) : (pi += 1) {
        const pid: u32 = @as(u32, @intCast(pi));
        prods[pi] = try std.Thread.spawn(.{}, struct {
            fn run(qp: *Queue(Item), id: u32, n_items: usize) void {
                var i: usize = 0;
                while (i < n_items) : (i += 1) qp.push(.{ .producer = id, .seq = @as(u32, @intCast(i)) });
            }
        }.run, .{ &q, pid, N });
    }

    // Spawn consumers
    var cons: [C]std.Thread = undefined;
    var ci: usize = 0;
    while (ci < C) : (ci += 1) {
        cons[ci] = try std.Thread.spawn(.{}, struct {
            fn run(qp: *Queue(Item), totalp: *std.atomic.Value(usize), seen: []std.atomic.Value(usize), next: []std.atomic.Value(u32), total_target: usize) void {
                var out: Item = undefined;
                while (true) {
                    if (qp.tryPop(&out)) {
                        const idx = @as(usize, out.producer);
                        // Per-producer order: advance next[idx] only when it matches out.seq.
                        while (true) {
                            const expected = next[idx].load(.acquire);
                            if (expected == out.seq) {
                                if (next[idx].cmpxchgStrong(expected, expected + 1, .seq_cst, .acquire)) |_| {
                                    // Lost race, retry until we can advance in order
                                    continue;
                                } else break;
                            } else if (expected > out.seq) {
                                std.debug.panic("per-producer order violated: pid={}, got={}, exp>= {}", .{ idx, out.seq, expected });
                            } else {
                                // expected < out.seq, wait for earlier items of this producer
                                std.atomic.spinLoopHint();
                                continue;
                            }
                        }
                        _ = seen[idx].fetchAdd(1, .seq_cst);
                        const new_total = totalp.fetchAdd(1, .seq_cst) + 1;
                        if (new_total == total_target) break;
                        continue;
                    }
                    if (totalp.load(.acquire) == total_target) break;
                    std.atomic.spinLoopHint();
                }
            }
        }.run, .{ &q, &total, &seen_counts, &next_expected, P * N });
    }

    // Join
    pi = 0;
    while (pi < P) : (pi += 1) prods[pi].join();
    ci = 0;
    while (ci < C) : (ci += 1) cons[ci].join();

    // Validate totals and per-producer counts
    try std.testing.expectEqual(@as(usize, P * N), total.load(.acquire));
    pi = 0;
    while (pi < P) : (pi += 1) {
        try std.testing.expectEqual(@as(usize, N), seen_counts[pi].load(.acquire));
        try std.testing.expectEqual(@as(u32, @intCast(N)), next_expected[pi].load(.acquire));
    }

    try std.testing.expect(q.empty());
}

test "blocking: pop waits for push" {
    const T = u32;
    const alloc = std.testing.allocator;
    var q = try Queue(T).init(alloc, 2);
    defer q.deinit();

    var started = std.atomic.Value(bool).init(false);
    var finished = std.atomic.Value(bool).init(false);

    var consumer = try std.Thread.spawn(.{}, struct {
        fn run(qp: *Queue(T), started_flag: *std.atomic.Value(bool), finished_flag: *std.atomic.Value(bool)) void {
            started_flag.store(true, .release);
            var out: T = 0;
            qp.pop(&out); // should block until producer pushes
            if (out != 42) std.debug.panic("unexpected value {}", .{out});
            finished_flag.store(true, .release);
        }
    }.run, .{ &q, &started, &finished });

    // Ensure consumer is waiting
    while (!started.load(.acquire)) std.atomic.spinLoopHint();

    // Now push to unblock
    q.push(42);

    consumer.join();
    try std.testing.expect(finished.load(.acquire));
    try std.testing.expect(q.empty());
}

test "blocking: push waits on full until pop" {
    const T = u32;
    const alloc = std.testing.allocator;
    var q = try Queue(T).init(alloc, 1);
    defer q.deinit();

    // Fill the single slot
    q.push(1);

    var started = std.atomic.Value(bool).init(false);
    var enqueued = std.atomic.Value(bool).init(false);

    // Start producer that will block on push
    var producer = try std.Thread.spawn(.{}, struct {
        fn run(qp: *Queue(T), started_flag: *std.atomic.Value(bool), enqueued_flag: *std.atomic.Value(bool)) void {
            started_flag.store(true, .release);
            qp.push(2); // should block until a consumer pops existing item
            enqueued_flag.store(true, .release);
        }
    }.run, .{ &q, &started, &enqueued });

    // Wait for producer to be ready and likely blocked
    while (!started.load(.acquire)) std.atomic.spinLoopHint();
    std.Thread.sleep(1_000_000); // 1ms
    try std.testing.expect(!enqueued.load(.acquire));

    // Consumer pops one, unblocking producer
    var out: T = 0;
    q.pop(&out);
    try std.testing.expectEqual(@as(T, 1), out);

    // Producer should complete shortly
    producer.join();
    try std.testing.expect(enqueued.load(.acquire));

    // Now the queue should contain the new value
    q.pop(&out);
    try std.testing.expectEqual(@as(T, 2), out);
    try std.testing.expect(q.empty());
}
