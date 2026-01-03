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

        pub const ReadGuard = struct {
            parent: *Self,
            state: *const T,

            pub fn release(self: *const ReadGuard) void {
                self.parent.lock.unlockShared();
            }
        };

        pub const WriteGuard = struct {
            parent: *Self,
            state: *T,

            pub fn release(self: *const WriteGuard) void {
                self.parent.lock.unlock();
            }
        };

        /// Acquires a read lock and returns a guard containing the state.
        /// You must call `guard.release()` or `defer guard.release()` when done.
        pub fn read(self: *Self) ReadGuard {
            self.lock.lockShared();
            return .{
                .parent = self,
                .state = &self.state,
            };
        }

        /// Acquires a write lock and returns a guard containing the state.
        /// You must call `guard.release()` or `defer guard.release()` when done.
        pub fn write(self: *Self) WriteGuard {
            self.lock.lock();
            return .{
                .parent = self,
                .state = &self.state,
            };
        }

        /// Returns a copy of the current state.
        /// This is best for simple, copyable types.
        pub fn getCopy(self: *Self) T {
            const guard = self.read();
            defer guard.release();
            return guard.state.*;
        }

        /// Overwrites the current state with a new value.
        /// This is most efficient for simple, copyable types.
        pub fn set(self: *Self, new_state: T) void {
            const guard = self.write();
            defer guard.release();
            guard.state.* = new_state;
        }
    };
}

//--- Tests ---

test "store: read" {
    const allocator = std.testing.allocator;
    var store = Store(u64).init(allocator, 42);
    defer store.deinit();

    const guard = store.read();
    defer guard.release();

    try std.testing.expectEqual(guard.state.*, 42);
}

test "store: write" {
    const allocator = std.testing.allocator;
    var store = Store(u64).init(allocator, 0);
    defer store.deinit();

    {
        const guard = store.write();
        defer guard.release();
        guard.state.* = 100;
    }

    const guard = store.read();
    defer guard.release();
    try std.testing.expectEqual(guard.state.*, 100);
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
    const ComplexState = struct {
        one: u64,
        two: u32,
    };

    const allocator = std.testing.allocator;
    const initial_state = ComplexState{ .one = 123, .two = 456 };
    var store = Store(ComplexState).init(allocator, initial_state);
    defer store.deinit();

    const guard = store.read();
    defer guard.release();

    try std.testing.expectEqual(guard.state.one, 123);
    try std.testing.expectEqual(guard.state.two, 456);
}
