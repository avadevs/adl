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
