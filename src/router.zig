/// The router helps the developer with screen management,
/// furthermore will it be able to produce static links (URLSs) that the
/// developer can use to redirect the user to the correct screen.
const std = @import("std");

pub const ScreenVTable = struct {
    /// Should return a pointer to an screen state, will be saved in a ScreenInstance.
    init: *const fn (allocator: std.mem.Allocator, context: ?*anyopaque) anyerror!ScreenInstance,

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

    /// Saves an array of strings that represent the urls the user entered.
    history: std.ArrayList([]u8),

    /// The active screen in the history.
    history_index: usize = 0,

    fn init(allocator: std.mem.Allocator, history_size: usize) !Router {
        return .{
            .allocator = allocator,
            .routes = try std.ArrayList(Route).initCapacity(allocator, 16),
            .history = try std.ArrayList([]u8).initCapacity(allocator, history_size),
        };
    }

    /// Deinitializes the router and all active screens that the router managed.
    /// You need to take care of the memory of the context object that was used in the functions of the screen.
    fn deinit(self: *Router) void {
        // deinit history
        for (self.history.items) |url| {
            self.allocator.free(url);
        }
        self.history.deinit(self.allocator);

        // deinit all active states
        for (self.routes.items) |*r| {
            if (r.screen.state) |state| {
                r.screen.vtable.deinit(state, r.screen.context);
            }
        }

        // deinit all urls in routes
        for (self.routes.items) |*r| {
            r.url.deinit();
        }

        self.routes.deinit(self.allocator);
    }

    pub const RouteError = error{
        RouteNotFound,
        CompetingRoutes,
        ScreenCreationFailure,
        OutOfMemory,
    };

    fn route(self: *Router, url_str: []const u8) RouteError!void {
        var possible_routes = try std.ArrayList(*Route).initCapacity(self.allocator, self.routes.items.len);
        defer possible_routes.deinit(self.allocator);

        // Save all routes that did match
        for (0..self.routes.items.len) |i| {
            var r = &self.routes.items[i];
            // The parse function can fail, but that just means it's not a match.
            // We use `if` with an `else |_| {}` to ignore the error.
            if (r.url.parse(url_str)) |_| {
                try possible_routes.append(self.allocator, r);
            } else |_| {}
        }

        if (possible_routes.items.len == 0) return error.RouteNotFound;

        var exact_route: *Route = possible_routes.items[0];

        if (possible_routes.items.len > 1) {
            // If multiple routes match we need to select the most specific one
            // this means the route with the least amount of parsed dynamic data.
            for (possible_routes.items[1..]) |r| {
                if (r.url.parsed_dynamic.items.len < exact_route.url.parsed_dynamic.items.len) {
                    exact_route = r;
                }
            }

            // Now check if there are other routes with the same level of specificity.
            var competing_found = false;
            for (possible_routes.items) |r| {
                if (r != exact_route and r.url.parsed_dynamic.items.len == exact_route.url.parsed_dynamic.items.len) {
                    competing_found = true;
                    break;
                }
            }
            if (competing_found) return error.CompetingRoutes;
        }

        // Initialize the new screen if needed
        const screen_context = &exact_route.url.parsed_dynamic;
        if (exact_route.screen.state == null) {
            const new_screen = exact_route.screen.vtable.init(self.allocator, screen_context) catch |err| {
                std.log.err("failed to create screen: {any}", .{err});
                return error.ScreenCreationFailure;
            };

            exact_route.screen = new_screen;
        }

        // --- History Management ---

        // If we are navigating from within the history, we truncate the forward history.
        if (self.history.items.len > 0 and self.history_index < self.history.items.len - 1) {
            for (self.history.items[self.history_index + 1 ..]) |url_to_free| {
                self.allocator.free(url_to_free);
            }
            self.history.shrinkRetainingCapacity(self.history_index + 1);
        }

        // Add new url to history
        const dupe_url = try self.allocator.dupe(u8, url_str);
        self.history.append(self.allocator, dupe_url) catch {
            self.allocator.free(dupe_url);
            return error.OutOfMemory;
        };
        self.history_index = self.history.items.len - 1;
    }

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

    // Adds new screen on the stack. Call .forward() to navigate to it
    // fn appendScreen(self: *Router, screen: ScreenInstance) bool {
    //     self.history.append(self.allocator, screen) catch |err| {
    //         std.log.warn("Could not add screen to router: {any}", .{err});
    //         return false;
    //     };

    //     return true;
    // }

    // Removes the last (most upper) screen.
    // Expects one screen to exist after removal.
    // TODO: This function needs to be re-evaluated. The history now stores URLs,
    // not ScreenInstances. The concept of "popping a screen" needs to be
    // reconciled with a URL-based history (e.g., by navigating to the previous URL).
    // fn popScreen(self: *Router) bool {
    //     const start_index = self.history_index;
    //     if (self.history.items.len <= 1) return false;

    //     if (self.history_index == self.history.items.len - 1) self.back();

    //     const screen = self.history.items[start_index];
    //     screen.vtable.deinit(screen.state, screen.context);
    // }

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
    allocator: std.mem.Allocator, // save the allocator to deinit on demand
    message: []const u8,
};

// --- VTable Functions (defined at the top-level) ---
fn testScreenInit(allocator: std.mem.Allocator, context: ?*anyopaque) anyerror!ScreenInstance {
    // In a real app, 'context' might be the parsed URL params.
    _ = context;

    // 1. Allocate the actual state for our screen on the heap.
    const screen_state = try allocator.create(TestScreen);
    screen_state.* = .{ .allocator = allocator, .message = "Hello World" };

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
    _ = context;

    const screen_state: *TestScreen = @ptrCast(@alignCast(state));
    screen_state.allocator.destroy(screen_state);

    std.log.debug("Deinit screen called", .{});
}

// --- The single, constant VTable for TestScreen ---
const TEST_SCREEN_VTABLE = ScreenVTable{
    .init = testScreenInit,
    .render = testScreenRender,
    .deinit = testScreenDeinit,
};

test "router construct" {
    const allocator = std.testing.allocator;

    var router = try Router.init(allocator, 64);
    defer router.deinit();

    const url = try URL.init(allocator, "/hello/world");
    // The URL is moved into the routes list, the list is responsible for deinit
    // defer url.deinit();

    const route: Route = .{
        .url = url,
        .screen = .{
            .context = null,
            .state = null,
            .vtable = &TEST_SCREEN_VTABLE,
        },
    };

    try router.routes.append(router.allocator, route);
}

test "router route" {
    const allocator = std.testing.allocator;

    var router = try Router.init(allocator, 64);
    defer router.deinit();

    const url1 = try URL.init(allocator, "/hello/:name");
    const route1: Route = .{
        .url = url1,
        .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null },
    };
    try router.routes.append(router.allocator, route1);

    const url2 = try URL.init(allocator, "/hello/world");
    const route2: Route = .{
        .url = url2,
        .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null },
    };
    try router.routes.append(router.allocator, route2);

    try router.route("/hello/world");

    try std.testing.expectEqual(@as(usize, 1), router.history.items.len);
    try std.testing.expectEqualSlices(u8, "/hello/world", router.history.items[0]);
    try std.testing.expectEqual(@as(usize, 0), router.history_index);

    // Route to a new url
    try router.route("/hello/zig");
    try std.testing.expectEqual(@as(usize, 2), router.history.items.len);
    try std.testing.expectEqualSlices(u8, "/hello/zig", router.history.items[1]);
    try std.testing.expectEqual(@as(usize, 1), router.history_index);
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
