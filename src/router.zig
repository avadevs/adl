/// The router helps the developer with screen management,
/// furthermore will it be able to produce static links (URLSs) that the
/// developer can use to redirect the user to the correct screen.
const std = @import("std");

pub const ScreenVTable = struct {
    /// Should return a pointer to an screen state, will be saved in a ScreenInstance.
    init: *const fn (allocator: std.mem.Allocator, context: ?*anyopaque) ScreenInstance,

    // Called to render the screen
    render: *const fn (state: *anyopaque, context: ?*anyopaque) void,

    // Called when the screen is popped from the stach, to clean up its own resources.
    deinit: *const fn (state: *anyopaque, context: ?*anyopaque) void,
};

pub const ScreenInstance = struct {
    vtable: *const ScreenVTable,
    state: ?*anyopaque, // A type-erased pointer of the screens actual state struct.
    context: ?*anyopaque, // A type-erased pointer that can be used to pass additional context to the function. Like options, etc.
};

pub const Route = struct {
    url: URL,
    screen: ScreenInstance,
};

pub const Router = struct {
    allocator: std.mem.Allocator,

    /// The routes save the possible URLs and their respective screens.
    routes: std.ArrayList(Route),

    // Saves an array of strings that represent the urls the user entered.
    // Has a static size that get set when initializing the router.
    history: [][]u8,

    /// The active screen in the history.
    history_index: usize = 0,

    fn init(allocator: std.mem.Allocator, history_size: usize) !Router {
        return .{
            .allocator = allocator,
            .routes = try std.ArrayList(Route).initCapacity(allocator, 16),
            .history = try allocator.alloc([]u8, history_size),
        };
    }

    fn deinit(self: *Router) void {
        self.allocator.free(self.history);
        self.routes.deinit(self.allocator);
    }

    // fn route(self: *Router, url: []const u8) void {}

    // fn back(self: *Router) bool {
    //     if (self.history_index > 0) {
    //         self.history_index -= 1;
    //         return true;
    //     }

    //     return false;
    // }

    // fn forward(self: *Router) bool {
    //     if (self.history_index < self.history.len() - 1) {
    //         self.history_index += 1;
    //         return true;
    //     }

    //     return false;
    // }

    /// Adds new screen on the stack. Call .forward() to navigate to it
    // fn appendScreen(self: *Router, screen: ScreenInstance) bool {
    //     self.history.append(self.allocator, screen) catch |err| {
    //         std.log.warn("Could not add screen to router: {any}", .{err});
    //         return false;
    //     };

    //     return true;
    // }

    /// Removes the last (most upper) screen.
    /// Expects one screen to exist after removal.
    fn popScreen(self: *Router) bool {
        const start_index = self.history_index;
        if (self.history.items.len <= 1) return false; // We can only pop a screen if we have one and expect there to be one screen afterwards too.

        // Navigate index back if we are displaying the last screen
        if (self.history_index == self.history.items.len - 1) self.back();

        // Deinitialize screen that got popped
        const screen = self.history.items[start_index];
        screen.vtable.deinit(screen.state, screen.context);
    }

    // /// Navigate to a specific index in the history
    // fn navigateTo(self: *Router, index: usize) bool {
    //     if (index < self.history.len()) {
    //         self.history_index = index;
    //         return true;
    //     }

    //     return false;
    // }

    // /// Navigates to a screen in the history by relative position.
    // /// E.g. go back 1 screen, go forward two screens).
    // fn navigate(self: *Router, pos: isize) bool {
    //     const new_index: isize = self.history_index + pos;
    //     if (new_index < 0) return false; // new index must be 0 or greater

    //     if (new_index < self.history.len()) {
    //         self.history_index = new_index;
    //         return true;
    //     }

    //     return false;
    // }
};

// --- Test Screen Definition ---
const TestScreen = struct {
    message: []const u8,
};

// --- VTable Functions (defined at the top-level) ---
fn testScreenInit(allocator: std.mem.Allocator, context: ?*anyopaque) ScreenInstance {
    // In a real app, 'context' might be the parsed URL params.
    _ = context;

    // 1. Allocate the actual state for our screen on the heap.
    const screen_state = allocator.create(TestScreen) catch @panic("failed to alloc");
    screen_state.* = .{ .message = "Hello World" };

    // 2. Return a type-erased ScreenInstance.
    return ScreenInstance{
        .state = screen_state,
        .context = null,
        .vtable = &TEST_SCREEN_VTABLE, // Point to the single, constant vtable
    };
}

fn testScreenRender(state: *anyopaque, context: ?*anyopaque) void {
    // Cast the type-erased pointer back to our concrete type.
    const screen: *TestScreen = @ptrCast(@alignCast(state));
    _ = context;
    std.log.debug("Rendering screen: {s}", .{screen.message});
}

fn testScreenDeinit(state: *anyopaque, context: ?*anyopaque) void {
    // This function would free the state, but in a test with a leaking
    // allocator, we can leave it empty to simplify the example.
    _ = state;
    _ = context;
    std.log.debug("Deinit screen called", .{});
}

// --- The single, constant VTable for TestScreen ---
const TEST_SCREEN_VTABLE = ScreenVTable{
    .init = testScreenInit,
    .render = testScreenRender,
    .deinit = testScreenDeinit,
};

test "router vtable usage" {
    const allocator = std.testing.allocator;

    // In a real router, you would associate a URL template with a vtable.
    // For this test, we'll just use the vtable directly to create a screen.
    const vtable = &TEST_SCREEN_VTABLE;

    var url = try URL.init(allocator, "/hello/world");
    defer url.deinit();

    const route: Route = .{
        .url = url,
        .screen = .{
            .context = null,
            .state = null,
            .vtable = vtable,
        },
    };

    var router = try Router.init(allocator, 64);
    defer router.deinit();

    try router.routes.append(router.allocator, route);
}

/// URL type to make the router url based.
pub const URL = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// The string that denotes which parts of the original string
    /// are dynamic. The dynamic part can be any basic data type.
    /// E.g. "/groups/:group_id/users/:user_id/:str"
    /// E.g. "/hello/:str"
    template: []const u8,

    /// Will contain the parsed data as strings.
    parsed_dynamic: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, template: []const u8) !Self {
        return .{
            .allocator = allocator,
            .template = template,
            .parsed_dynamic = try std.ArrayList([]const u8).initCapacity(allocator, 8),
        };
    }

    /// Frees the memory used by the URL struct, including the copied segments.
    pub fn deinit(self: *Self) void {
        // Free each of the strings that we copied during parsing.
        for (self.parsed_dynamic.items) |item| {
            self.allocator.free(item);
        }
        // Deinitialize the list itself.
        self.parsed_dynamic.deinit(self.allocator);
    }

    pub const ParseError = error{
        /// The segments in the url does not match the template segment.
        MismatchedSegments,
        OutOfMemory,
    };

    pub fn parse(self: *Self, url_str: []const u8) ParseError!void {
        // Free each of the strings that we copied during parsing.
        for (self.parsed_dynamic.items) |item| {
            self.allocator.free(item);
        }

        // Reset parsed values from any previous run.
        self.parsed_dynamic.clearRetainingCapacity();

        // Create iterators for the passed-in url and the template string.
        var url_it = std.mem.splitScalar(u8, url_str, '/');
        var template_it = std.mem.splitScalar(u8, self.template, '/');

        // Parse each segment.
        while (template_it.next()) |template_segment| {
            const url_segment = url_it.next() orelse return error.MismatchedSegments;

            // If the template segment is dynamic (e.g., ":group_id")...
            if (std.mem.startsWith(u8, template_segment, ":")) {
                // ...append the corresponding segment from the actual URL to our list.
                const url_segment_dupe = try self.allocator.dupe(u8, url_segment);
                try self.parsed_dynamic.append(self.allocator, url_segment_dupe);
            } else { // Otherwise, it's a static segment.
                // The text must match exactly.
                if (!std.mem.eql(u8, template_segment, url_segment)) {
                    return error.MismatchedSegments;
                }
            }
        }

        // After the loop, if the URL has leftover segments, it's too long and
        // doesn't match the template.
        if (url_it.next() != null) {
            return error.MismatchedSegments;
        }
    }
};

test "URL parse: basic success case" {
    const allocator = std.testing.allocator;
    var url = try URL.init(allocator, "/group/:group_id/users/:user_id");
    defer url.deinit();

    try url.parse("/group/1000/users/100");

    try std.testing.expectEqual(@as(usize, 2), url.parsed_dynamic.items.len);
    try std.testing.expectEqualSlices(u8, "1000", url.parsed_dynamic.items[0]);
    try std.testing.expectEqualSlices(u8, "100", url.parsed_dynamic.items[1]);
}

test "URL parse: url longer than template" {
    const allocator = std.testing.allocator;
    var url = try URL.init(allocator, "/a/:b");
    defer url.deinit();
    try std.testing.expectError(URL.ParseError.MismatchedSegments, url.parse("/a/foo/bar"));
}

test "URL parse: url shorter than template" {
    const allocator = std.testing.allocator;
    var url = try URL.init(allocator, "/a/:b/c");
    defer url.deinit();
    try std.testing.expectError(URL.ParseError.MismatchedSegments, url.parse("/a/foo"));
}

test "URL parse: static segment mismatch" {
    const allocator = std.testing.allocator;
    var url = try URL.init(allocator, "/a/b");
    defer url.deinit();
    try std.testing.expectError(URL.ParseError.MismatchedSegments, url.parse("/a/c"));
}

test "URL parse: empty template and url" {
    const allocator = std.testing.allocator;
    var url = try URL.init(allocator, "");
    defer url.deinit();
    try url.parse("");
    try std.testing.expectEqual(@as(usize, 0), url.parsed_dynamic.items.len);
}

test "URL parse: slash only template and url" {
    const allocator = std.testing.allocator;
    var url = try URL.init(allocator, "/");
    defer url.deinit();
    try url.parse("/");
    try std.testing.expectEqual(@as(usize, 0), url.parsed_dynamic.items.len);
}

test "URL parse: leading and trailing slashes" {
    const allocator = std.testing.allocator;
    var url = try URL.init(allocator, "/:a/:b/");
    defer url.deinit();
    try url.parse("/foo/bar/");
    try std.testing.expectEqual(@as(usize, 2), url.parsed_dynamic.items.len);
    try std.testing.expectEqualSlices(u8, "foo", url.parsed_dynamic.items[0]);
    try std.testing.expectEqualSlices(u8, "bar", url.parsed_dynamic.items[1]);
}

test "URL parse: double slashes" {
    const allocator = std.testing.allocator;
    var url = try URL.init(allocator, "/a//:b");
    defer url.deinit();
    try url.parse("/a//foo");
    try std.testing.expectEqual(@as(usize, 1), url.parsed_dynamic.items.len);
    try std.testing.expectEqualSlices(u8, "foo", url.parsed_dynamic.items[0]);
}

test "URL parse: re-parsing to check memory" {
    const allocator = std.testing.allocator;
    var url = try URL.init(allocator, "/:a/:b");
    defer url.deinit();

    try url.parse("/1/2");
    try std.testing.expectEqualSlices(u8, "1", url.parsed_dynamic.items[0]);
    try std.testing.expectEqualSlices(u8, "2", url.parsed_dynamic.items[1]);

    try url.parse("/3/4");
    try std.testing.expectEqual(@as(usize, 2), url.parsed_dynamic.items.len);
    try std.testing.expectEqualSlices(u8, "3", url.parsed_dynamic.items[0]);
    try std.testing.expectEqualSlices(u8, "4", url.parsed_dynamic.items[1]);
}
