const std = @import("std");

/// A generic, thread-safe container for managing a piece of shared state.
/// It allows multiple parts of an application to subscribe to state changes,
/// ensuring that data access is safe and that the UI can react to updates.
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
                .subscribers = std.ArrayList(Subscriber).initCapacity(allocator, 16),
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
            try self.subscribers.append(subscriber);
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
    };
}
