const std = @import("std");
const RouteArgs = @import("route.zig").RouteArgs;
const UIContext = @import("../ui/core/context.zig").UIContext;

/// The type-erased interface for any screen managed by the router.
/// Internal use only. User code should not implement this directly.
pub const AnyScreen = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Called to render the screen. Should be lightweight.
        render: *const fn (ptr: *anyopaque, ctx: *UIContext) void,

        /// Called to update an existing screen with new arguments.
        /// Returns true if the update was handled, false if the router should recreate the screen.
        update: ?*const fn (ptr: *anyopaque, args: ?RouteArgs) anyerror!bool,

        /// Called to destroy the screen and free its resources.
        deinit: *const fn (ptr: *anyopaque, ctx: *UIContext) void,
    };

    pub fn render(self: AnyScreen, ctx: *UIContext) void {
        self.vtable.render(self.ptr, ctx);
    }

    pub fn update(self: AnyScreen, args: ?RouteArgs) !bool {
        if (self.vtable.update) |f| {
            return f(self.ptr, args);
        }
        return false;
    }

    pub fn deinit(self: AnyScreen, ctx: *UIContext) void {
        self.vtable.deinit(self.ptr, ctx);
    }
};

/// A factory that knows how to handle specific screen types.
pub const ScreenFactory = struct {
    createFn: *const fn (allocator: std.mem.Allocator, args: ?RouteArgs) anyerror!AnyScreen,

    /// Wraps a user-defined struct T into a ScreenFactory.
    ///
    /// The struct T must implement:
    /// - `pub fn init(allocator: std.mem.Allocator, args: RouteArgs) !T`
    ///   **Note:** The `args` map and its content are temporary and valid only during the `init` call.
    ///   If you need to persist any string values, you MUST copy/duplicate them using the allocator.
    /// - `pub fn render(self: *T) void`
    /// - `pub fn deinit(self: *T) void`
    ///
    /// Optional:
    /// - `pub fn update(self: *T, args: RouteArgs) !void` for keep-alive screens.
    pub fn wrap(comptime T: type) ScreenFactory {
        const gen = struct {
            fn create(allocator: std.mem.Allocator, args: ?RouteArgs) !AnyScreen {
                const ptr = try allocator.create(T);
                errdefer allocator.destroy(ptr);

                // Initialize the concrete type
                ptr.* = try T.init(allocator, args);

                return AnyScreen{
                    .ptr = ptr,
                    .vtable = &vtable,
                };
            }

            const vtable = AnyScreen.VTable{
                .render = renderImpl,
                .update = if (@hasDecl(T, "update")) updateImpl else null,
                .deinit = deinitImpl,
            };

            fn renderImpl(ptr: *anyopaque, ctx: *UIContext) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                // Automatically manage scope for this screen instance
                ctx.beginScope(@intFromPtr(self)) catch {};
                defer ctx.endScope();

                self.render();
            }

            fn updateImpl(ptr: *anyopaque, args: ?RouteArgs) !bool {
                const self: *T = @ptrCast(@alignCast(ptr));
                try self.update(args);
                return true;
            }

            fn deinitImpl(ptr: *anyopaque, ctx: *UIContext) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                self.deinit();
                // Clean up all UI state associated with this screen instance
                ctx.freeScope(@intFromPtr(self));
                self.allocator.destroy(self);
            }
        };

        return ScreenFactory{ .createFn = gen.create };
    }
};
