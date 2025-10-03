const std = @import("std");

/// A generic, threa.d-safe container for managing a piece of shared state.
/// It allows multiple parts of an application to subscribe to state changes,
/// ensuring that data access is safe and that the UI can react to updates
pub fn Store(comptime T: type) type {
    return struct {
        const Self = @This();

        // --- Core State ---
        allocator: std.mem.Allocator,
        lock: std.Thread.RwLock = .{},
        state: T,

        // --- Subscription Machinery ---
        subscribers: std.ArrayList(Subscriber),

        const Subscriber = struct {
            context: ?*anyopaque,
            callback: *const fn (context: ?*anyopaque, state: *const T) void,
        };

        /// Initializes the store with an initial piece of state.
        pub fn init(allocator: std.mem.Allocator, initial_state: T) !Self {
            return Self{
                .allocator = allocator,
                .state = initial_state,
                .subscribers = try std.ArrayList(Subscriber).initCapacity(allocator, 16),
            };
        }

        /// Deinitializes the store, freeing the list of subscribers.
        pub fn deinit(self: *Self) void {
            self.subscribers.deinit(self.allocator);
        }

        /// Registers a callback function to be called whenever the state changes.
        pub fn subscribe(self: *Self, subscriber: Subscriber) !void {
            self.lock.lock();
            defer self.lock.unlock();
            try self.subscribers.append(self.allocator, subscriber);
        }

        /// Removes all callbacks associated with a given context pointer.
        pub fn unsubscribe(self: *Self, context_to_remove: ?*anyopaque) void {
            self.lock.lock();
            defer self.lock.unlock();

            var i = self.subscribers.items.len;
            while (i > 0) {
                i -= 1;
                if (self.subscribers.items[i].context == context_to_remove) {
                    _ = self.subscribers.orderedRemove(i);
                }
            }
        }

        /// Provides safe, read-only, locked access to the state via a callback.
        pub fn get(self: *Self, context: anytype, comptime callback: fn (ctx: anytype, state: *const T) void) void {
            self.lock.lockShared();
            defer self.lock.unlockShared();
            callback(context, &self.state);
        }

        /// Returns a copy of the current state. This is best for simple, copyable types.
        /// For large or complex state, prefer using get with a callback to avoid copying.
        /// The upside of using this method is that you do not need to mess with callbacks.
        pub fn getCopy(self: *Self) T {
            self.lock.lockShared();
            defer self.lock.unlockShared();

            return self.state;
        }

        /// Provides safe, writeable, locked access to the state via a callback.
        /// After the callback runs, it notifies all subscribers of the change.
        pub fn update(self: *Self, context: anytype, comptime update_fn: fn (ctx: anytype, state: *T) void) void {
            // 1. Acquire exclusive lock for the update.
            self.lock.lock();
            defer self.lock.unlock();

            // 2. Perform the mutation.
            update_fn(context, &self.state);

            // 3. Notify all subscribers of the change.
            for (self.subscribers.items) |sub| {
                sub.callback(sub.context, &self.state);
            }
        }

        /// Overwrites the current state with a new value and notifies all subscribers.
        /// This is most efficient for simple, copyable types. For in-place modifications
        /// of large or complex state, prefer using update with a callback.
        pub fn set(self: *Self, new_state: T) void {
            self.lock.lock();
            defer self.lock.unlock();

            self.state = new_state;

            for (self.subscribers.items) |sub| {
                sub.callback(sub.context, &self.state);
            }
        }
    };
}

//--- Tests ---

var basic_value: u64 = undefined;

const ComplexStruct = struct {
    one: u64,
    two: u32,
    three: i64,
};
var complex_value: ComplexStruct = undefined;

var notification_counter: u32 = 0;
var last_seen_state: u64 = 0;

fn on_state_change(context: ?*anyopaque, state: *const u64) void {
    _ = context;
    notification_counter += 1;
    last_seen_state = state.*;
}

test "store: basic usage" {
    const allocator = std.testing.allocator;

    var store = try Store(u64).init(allocator, 1);
    defer store.deinit();

    store.get(null, struct {
        fn read_state(context: anytype, state: *const u64) void {
            _ = context;
            basic_value = state.*;
        }
    }.read_state);

    try std.testing.expectEqual(basic_value, 1);
}

test "store: read struct" {
    const allocator = std.testing.allocator;

    var store = try Store(ComplexStruct).init(allocator, .{ .one = 0, .two = 1, .three = 2 });
    defer store.deinit();

    store.get(null, struct {
        fn read_state(context: anytype, state: *const ComplexStruct) void {
            _ = context;
            complex_value = state.*;
        }
    }.read_state);

    try std.testing.expectEqual(complex_value, ComplexStruct{ .one = 0, .two = 1, .three = 2 });
}

test "store: subscribe to changes" {
    const allocator = std.testing.allocator;

    var store = try Store(u64).init(allocator, 0);
    defer store.deinit();

    // Register callback
    try store.subscribe(.{ .context = null, .callback = &on_state_change });

    // This will trigger the callback
    store.update(null, struct {
        fn set_value(_: anytype, state: *u64) void {
            state.* = 99;
        }
    }.set_value);

    try std.testing.expectEqual(notification_counter, 1);
    try std.testing.expectEqual(last_seen_state, 99);
}

test "store: getCopy and set" {
    const allocator = std.testing.allocator;

    var store = try Store(u64).init(allocator, 42);
    defer store.deinit();

    // Test getCopy
    const value = store.getCopy();
    try std.testing.expectEqual(value, 42);

    // Register callback to test notification
    notification_counter = 0;
    last_seen_state = 0;
    try store.subscribe(.{ .context = null, .callback = &on_state_change });

    // Test set
    store.set(100);

    // Verify state was updated
    const new_value = store.getCopy();
    try std.testing.expectEqual(new_value, 100);

    // Verify subscriber was notified
    try std.testing.expectEqual(notification_counter, 1);
    try std.testing.expectEqual(last_seen_state, 100);
}
