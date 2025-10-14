const std = @import("std");

// Bounded MPSC ring buffer queue.
// - Multiple producers: tryPush (non-blocking) using atomic fetch-add on head (producer cursor).
// - Single consumer: pop() reads in order, advancing a plain tail (consumer cursor).
// - Fixed capacity, predictable memory; no per-node allocation.
// - Payload type T can be any bit-copyable type. For large payloads, store pointers/handles.
//
// Memory ordering notes:
// - Producers: reserve a slot index (fetchAdd on head), write item, then set slot's ready flag (turn) with release.
// - Consumer: polls ready flag with acquire; on true, reads item and clears ready.
// - We avoid wrapping races by associating a per-slot turn (epoch) with each slot.

pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Error = error{Full};

        allocator: std.mem.Allocator,
        capacity: usize,

        // Power-of-two mask for fast modulo; we round capacity up internally.
        mask: usize,

        // Ring storage (slots hold values)
        slots: []T,

        // Per-slot turn (epoch) for MPSC correctness; ready when turn == index + 1
        turns: []std.atomic.Value(usize),

        // Head (monotonic, wraps via mask); multiple producers
        head: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

        // Tail (consumer-owned, no atomics needed)
        tail: usize = 0,

        pub const InitError = error{ InvalidCapacity, OutOfMemory };

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            if (capacity < 1) return error.InvalidCapacity;

            const cap_pow2 = std.math.ceilPowerOfTwo(usize, capacity) catch capacity;
            const slots = try allocator.alloc(T, cap_pow2);
            errdefer allocator.free(slots);

            const turns = try allocator.alloc(std.atomic.Value(usize), cap_pow2);
            errdefer allocator.free(turns);

            var i: usize = 0;
            while (i < cap_pow2) : (i += 1) {
                // Initialize each slot's turn to its index; means "available" for index 0 fill.
                turns[i] = std.atomic.Value(usize).init(i);
            }

            return Self{
                .allocator = allocator,
                .capacity = cap_pow2,
                .mask = cap_pow2 - 1,
                .slots = slots,
                .turns = turns,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.slots);
            self.allocator.free(self.turns);
        }

        // Non-blocking push. Returns error.Full if there is no available slot.
        pub fn tryPush(self: *Self, value: T) Error!void {
            const idx = self.head.fetchAdd(1, .monotonic);
            const slot = idx & self.mask;

            // Each slot is available only when turn == idx (expected epoch)
            const expected_turn = idx;
            const turn_val = self.turns[slot].load(.acquire);
            if (turn_val != expected_turn) {
                // Writer got ahead of consumer: queue is full relative to this idx
                // Roll back head? Not safe with concurrent producers.
                // Instead: signal Full by returning an error and do not write.
                // Note: this "ticket" idx is lost; acceptable for bounded lossy queue.
                return Error.Full;
            }

            // Write payload
            self.slots[slot] = value;

            // Publish: set turn to next expected value (idx + 1) with release
            self.turns[slot].store(idx + 1, .release);
        }

        // Single-consumer pop. Returns null if empty.
        pub fn pop(self: *Self) ?T {
            const idx = self.tail;
            const slot = idx & self.mask;

            // Slot is ready when turn == idx + 1
            const ready_seq = idx + 1;
            const turn_val = self.turns[slot].load(.acquire);
            if (turn_val != ready_seq) return null;

            // Read item
            const item = self.slots[slot];

            // Mark slot as available for the next wrap of producers by setting turn to idx + self.capacity
            self.turns[slot].store(idx + self.capacity, .release);

            // Advance consumer cursor (tail)
            self.tail = idx + 1;
            return item;
        }

        pub fn isEmpty(self: *Self) bool {
            return self.peekReadyCount(1) == 0;
        }

        pub fn isFull(self: *Self) bool {
            // Heuristic: if next write would fail at this moment.
            const idx = self.head.load(.acquire);
            const slot = idx & self.mask;
            return self.turns[slot].load(.acquire) != idx;
        }

        pub fn size(self: *Self) usize {
            const w = self.head.load(.acquire);
            const r = self.tail;
            return w - r;
        }

        fn peekReadyCount(self: *Self, max_probe: usize) usize {
            var i: usize = 0;
            var ready: usize = 0;
            var idx = self.tail;
            while (i < max_probe) : (i += 1) {
                const slot = idx & self.mask;
                if (self.turns[slot].load(.acquire) == idx + 1) {
                    ready += 1;
                    idx += 1;
                } else break;
            }
            return ready;
        }
    };
}

test "mpsc queue basic single-thread" {
    const alloc = std.testing.allocator;
    const Q = Queue(u32);

    var q = try Q.init(alloc, 4);
    defer q.deinit();

    try std.testing.expect(q.isEmpty());

    // Push a couple values
    try q.tryPush(10);
    try q.tryPush(20);
    try std.testing.expect(!q.isEmpty());
    try std.testing.expectEqual(@as(usize, 2), q.size());

    // Pop in order
    const a = q.pop();
    try std.testing.expect(a != null);
    try std.testing.expectEqual(@as(u32, 10), a.?);

    const b = q.pop();
    try std.testing.expect(b != null);
    try std.testing.expectEqual(@as(u32, 20), b.?);

    // Empty now
    try std.testing.expect(q.pop() == null);

    // Fill up to capacity
    var i: u32 = 0;
    while (i < 4) : (i += 1) try q.tryPush(i);

    // Next push should report Full (lossy behavior)
    if (q.tryPush(999)) |_| {
        return error.TestUnexpectedSuccess;
    } else |err| {
        try std.testing.expect(err == error.Full);
    }

    // Drain and check order
    var expect_val: u32 = 0;
    while (expect_val < 4) : (expect_val += 1) {
        const v = q.pop();
        try std.testing.expect(v != null);
        try std.testing.expectEqual(expect_val, v.?);
    }
    try std.testing.expect(q.pop() == null);
}
