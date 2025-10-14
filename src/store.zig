const std = @import("std");

/// A generic, thread-safe container for managing a piece of shared state.
/// It allows multiple parts of an application to safely access and modify
/// state from different threads.
/// The store is meant to be read frequently so it does not provide the usuale
/// subscribe mechanisms you might be used to, this is because this is a
/// library for itermediate UI.
pub fn Store(comptime T: type) type {
    return struct {
        const Self = @This();

        // --- Core State ---
        allocator: std.mem.Allocator,
        lock: std.Thread.RwLock = .{},
        state: T,

        /// Initializes the store with an initial piece of state.
        pub fn init(allocator: std.mem.Allocator, initial_state: T) Self {
            return Self{
                .allocator = allocator,
                .state = initial_state,
            };
        }

        /// Deinitializes the store.
        pub fn deinit(self: *Self) void {
            // In this simplified version, deinit is a no-op but is kept
            // for API consistency and future compatibility.
            _ = self;
        }

        /// Provides safe, read-only, locked access to the state by calling a
        /// method on a given instance.
        /// The provided `method` must have the signature:
        /// `fn(self: *TypeOf(instance), state: *const T) void`
        pub fn with(
            self: *Self,
            instance: anytype,
            comptime method: fn (@TypeOf(instance), *const T) void,
        ) void {
            self.lock.lockShared();
            defer self.lock.unlockShared();

            @call(.auto, method, .{ instance, &self.state });
        }

        /// Provides safe, writeable, locked access to the state by calling a
        /// method on a given instance.
        /// The provided `method` must have the signature:
        /// `fn(self: *TypeOf(instance), state: *T) void`
        pub fn updateWith(
            self: *Self,
            instance: anytype,
            comptime method: fn (@TypeOf(instance), *T) void,
        ) void {
            self.lock.lock();
            defer self.lock.unlock();

            @call(.auto, method, .{ instance, &self.state });
        }

        /// Returns a copy of the current state.
        /// This is best for simple, copyable types.
        pub fn getCopy(self: *Self) T {
            self.lock.lockShared();
            defer self.lock.unlockShared();
            return self.state;
        }

        /// Overwrites the current state with a new value.
        /// This is most efficient for simple, copyable types.
        pub fn set(self: *Self, new_state: T) void {
            self.lock.lock();
            defer self.lock.unlock();
            self.state = new_state;
        }
    };
}

//--- Tests ---
const TestContext = struct {
    read_value: u64 = 0,
    read_two: u32 = 0,

    fn read_method(self: *TestContext, state: *const u64) void {
        self.read_value = state.*;
    }

    fn update_method(self: *TestContext, state: *u64) void {
        self.read_value = 50;
        state.* = 100;
    }

    const ComplexState = struct {
        one: u64,
        two: u32,
    };
    fn read_complex(self: *TestContext, state: *const ComplexState) void {
        self.read_value = state.one;
        self.read_two = state.two;
    }
};

test "store: with" {
    const allocator = std.testing.allocator;
    var store = Store(u64).init(allocator, 42);
    defer store.deinit();

    var ctx = TestContext{};
    store.with(&ctx, TestContext.read_method);

    try std.testing.expectEqual(ctx.read_value, 42);
}

test "store: updateWith" {
    const allocator = std.testing.allocator;
    var store = Store(u64).init(allocator, 0);
    defer store.deinit();

    var ctx = TestContext{};
    store.updateWith(&ctx, TestContext.update_method);

    // Check that the method modified its own state
    try std.testing.expectEqual(ctx.read_value, 50);

    // Check that the method modified the store's state
    const new_store_val = store.getCopy();
    try std.testing.expectEqual(new_store_val, 100);
}

test "store: getCopy and set" {
    const allocator = std.testing.allocator;
    var store = Store(u64).init(allocator, 1);
    defer store.deinit();

    store.set(99);
    const val = store.getCopy();
    try std.testing.expectEqual(val, 99);
}

test "store: complex state" {
    const allocator = std.testing.allocator;
    const initial_state = TestContext.ComplexState{ .one = 123, .two = 456 };
    var store = Store(TestContext.ComplexState).init(allocator, initial_state);
    defer store.deinit();

    var ctx = TestContext{};
    store.with(&ctx, TestContext.read_complex);

    try std.testing.expectEqual(ctx.read_value, 123);
    try std.testing.expectEqual(ctx.read_two, 456);
}
