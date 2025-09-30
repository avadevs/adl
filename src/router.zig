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
    /// These are the tempates that can be triggered by a concrete URL the user
    /// will enter into the system.
    routes: std.ArrayList(Route),

    /// The URLs the user entered into the system.
    history: std.ArrayList([]u8),

    /// The active url in the history.
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
        const exact_route = try self.findRoute(url_str);

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

    fn findRoute(self: *Router, url_str: []const u8) RouteError!*Route {
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

        return exact_route;
    }

    /// Use this function to render the active screen.
    /// This will call the render function of the active screen via its vtable.
    pub fn render(self: *Router) void {
        const r = findRoute(self, self.history.items[self.history_index]) catch |err| {
            std.log.err("Could not find route. Error: {any}", .{err});
            return;
        };

        r.screen.vtable.render(r.screen.state, r.url.parsed_dynamic);
    }

    /// Go back to the last URL.
    pub fn back(self: *Router) bool {
        if (self.history_index > 0) {
            self.history_index -= 1;

            const url_str = self.history.items[self.history_index];
            _ = self.findRoute(url_str) catch |err| {
                std.log.err("Could not find route for history url {s}: {any}", .{ url_str, err });
                return false;
            };

            return true;
        }

        return false;
    }

    /// If you used the .back() function you can use .forward()
    pub fn forward(self: *Router) bool {
        if (self.history.items.len > 0 and self.history_index < self.history.items.len - 1) {
            self.history_index += 1;

            const url_str = self.history.items[self.history_index];
            _ = self.findRoute(url_str) catch |err| {
                std.log.err("Could not find route for history url {s}: {any}", .{ url_str, err });
                return false;
            };

            return true;
        }

        return false;
    }
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

// --- Test Infrastructure for checking context ---
var g_last_screen_context: ?*anyopaque = null;

fn testScreenWithContextInit(allocator: std.mem.Allocator, context: ?*anyopaque) anyerror!ScreenInstance {
    g_last_screen_context = context;
    const screen_state = try allocator.create(TestScreen);
    screen_state.* = .{ .allocator = allocator, .message = "Context Test" };
    return ScreenInstance{
        .state = screen_state,
        .context = null,
        .vtable = &TEST_SCREEN_WITH_CONTEXT_VTABLE,
    };
}

const TEST_SCREEN_WITH_CONTEXT_VTABLE = ScreenVTable{
    .init = testScreenWithContextInit,
    .render = testScreenRender,
    .deinit = testScreenDeinit,
};

// --- Test Infrastructure for lifecycle and state ---
const LifecycleTestScreen = struct {
    allocator: std.mem.Allocator,
    init_count: u32,
    message: []const u8,
};

var g_init_call_count: u32 = 0;

fn lifecycleScreenInit(allocator: std.mem.Allocator, context: ?*anyopaque) anyerror!ScreenInstance {
    _ = context;
    g_init_call_count += 1;
    const screen_state = try allocator.create(LifecycleTestScreen);
    screen_state.* = .{
        .allocator = allocator,
        .init_count = g_init_call_count,
        .message = "Lifecycle Test",
    };
    return ScreenInstance{ .state = screen_state, .context = null, .vtable = &LIFECYCLE_SCREEN_VTABLE };
}

fn lifecycleScreenDeinit(state: *anyopaque, context: ?*anyopaque) void {
    _ = context;
    const screen_state: *LifecycleTestScreen = @ptrCast(@alignCast(state));
    screen_state.allocator.destroy(screen_state);
}

const LIFECYCLE_SCREEN_VTABLE = ScreenVTable{
    .init = lifecycleScreenInit,
    .render = testScreenRender, // Render is not important for this test
    .deinit = lifecycleScreenDeinit,
};

// --- Test Infrastructure for creation failure ---
fn failingScreenInit(allocator: std.mem.Allocator, context: ?*anyopaque) anyerror!ScreenInstance {
    _ = allocator;
    _ = context;
    return error.TestScreenInitFailed;
}

const FAILING_SCREEN_VTABLE = ScreenVTable{
    .init = failingScreenInit,
    .render = testScreenRender,
    .deinit = testScreenDeinit,
};

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

test "route: simple static route" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url = try URL.init(allocator, "/home");
    const route: Route = .{ .url = url, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } };
    try router.routes.append(router.allocator, route);

    try router.route("/home");

    try std.testing.expectEqual(@as(usize, 1), router.history.items.len);
    try std.testing.expectEqualSlices(u8, "/home", router.history.items[0]);
    try std.testing.expectEqual(@as(usize, 0), router.history_index);
}

test "route: simple dynamic route" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url = try URL.init(allocator, "/users/:id");
    const route: Route = .{ .url = url, .screen = .{ .vtable = &TEST_SCREEN_WITH_CONTEXT_VTABLE, .state = null, .context = null } };
    try router.routes.append(router.allocator, route);

    try router.route("/users/123");

    try std.testing.expectEqual(@as(usize, 1), router.history.items.len);
    try std.testing.expectEqualSlices(u8, "/users/123", router.history.items[0]);

    const context: *const std.ArrayList([]const u8) = @ptrCast(@alignCast(g_last_screen_context.?));
    try std.testing.expectEqual(@as(usize, 1), context.items.len);
    try std.testing.expectEqualSlices(u8, "123", context.items[0]);
}

test "route: sequential routing" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url_a = try URL.init(allocator, "/a");
    try router.routes.append(router.allocator, .{ .url = url_a, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_b = try URL.init(allocator, "/b");
    try router.routes.append(router.allocator, .{ .url = url_b, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_c = try URL.init(allocator, "/c");
    try router.routes.append(router.allocator, .{ .url = url_c, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/a");
    try router.route("/b");
    try router.route("/c");

    try std.testing.expectEqual(@as(usize, 3), router.history.items.len);
    try std.testing.expectEqualSlices(u8, "/a", router.history.items[0]);
    try std.testing.expectEqualSlices(u8, "/b", router.history.items[1]);
    try std.testing.expectEqualSlices(u8, "/c", router.history.items[2]);
    try std.testing.expectEqual(@as(usize, 2), router.history_index);
}

test "route: not found" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url = try URL.init(allocator, "/home");
    try router.routes.append(router.allocator, .{ .url = url, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try std.testing.expectError(Router.RouteError.RouteNotFound, router.route("/does-not-exist"));
}

test "route: static preferred over dynamic" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const static_url = try URL.init(allocator, "/users/view");
    try router.routes.append(router.allocator, .{ .url = static_url, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    const dynamic_url = try URL.init(allocator, "/users/:id");
    try router.routes.append(router.allocator, .{ .url = dynamic_url, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/users/view");

    var static_route_state: ?*anyopaque = null;
    var dynamic_route_state: ?*anyopaque = null;
    for (router.routes.items) |r| {
        if (std.mem.eql(u8, r.url.template, "/users/view")) {
            static_route_state = r.screen.state;
        } else if (std.mem.eql(u8, r.url.template, "/users/:id")) {
            dynamic_route_state = r.screen.state;
        }
    }

    try std.testing.expect(static_route_state != null);
    try std.testing.expect(dynamic_route_state == null);
}

test "route: more specific dynamic preferred" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const more_specific_url = try URL.init(allocator, "/users/:id/profile"); // 1 param
    try router.routes.append(router.allocator, .{ .url = more_specific_url, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    const less_specific_url = try URL.init(allocator, "/users/:id/:page"); // 2 params
    try router.routes.append(router.allocator, .{ .url = less_specific_url, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/users/123/profile");

    var more_specific_state: ?*anyopaque = null;
    var less_specific_state: ?*anyopaque = null;
    for (router.routes.items) |r| {
        if (std.mem.eql(u8, r.url.template, "/users/:id/profile")) {
            more_specific_state = r.screen.state;
        } else if (std.mem.eql(u8, r.url.template, "/users/:id/:page")) {
            less_specific_state = r.screen.state;
        }
    }

    try std.testing.expect(more_specific_state != null);
    try std.testing.expect(less_specific_state == null);
}

test "route: competing routes error" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const template1 = try URL.init(allocator, "/:entity/:id");
    try router.routes.append(router.allocator, .{ .url = template1, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    const template2 = try URL.init(allocator, "/:type/:name");
    try router.routes.append(router.allocator, .{ .url = template2, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try std.testing.expectError(Router.RouteError.CompetingRoutes, router.route("/products/123"));
}

test "route: state preservation and init once" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    g_init_call_count = 0;

    const url = try URL.init(allocator, "/lifecycle");
    try router.routes.append(router.allocator, .{ .url = url, .screen = .{ .vtable = &LIFECYCLE_SCREEN_VTABLE, .state = null, .context = null } });

    // First route, should init
    try router.route("/lifecycle");
    try std.testing.expectEqual(@as(u32, 1), g_init_call_count);

    // Check that the state was stored
    const route1 = &router.routes.items[0];
    try std.testing.expect(route1.screen.state != null);
    const screen1: *LifecycleTestScreen = @ptrCast(@alignCast(route1.screen.state.?));
    try std.testing.expectEqual(@as(u32, 1), screen1.init_count);

    // Route to a different page (we need to register it first)
    const other_url = try URL.init(allocator, "/other");
    try router.routes.append(router.allocator, .{ .url = other_url, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    try router.route("/other");

    // Route back to the lifecycle page
    try router.route("/lifecycle");

    // Assert init was NOT called again
    try std.testing.expectEqual(@as(u32, 1), g_init_call_count);

    // And the state is the same
    const route2 = &router.routes.items[0];
    const screen2: *LifecycleTestScreen = @ptrCast(@alignCast(route2.screen.state.?));
    try std.testing.expect(screen1 == screen2); // Check pointer equality
}

test "route: screen creation failure" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url = try URL.init(allocator, "/fail");
    try router.routes.append(router.allocator, .{ .url = url, .screen = .{ .vtable = &FAILING_SCREEN_VTABLE, .state = null, .context = null } });

    try std.testing.expectError(error.ScreenCreationFailure, router.route("/fail"));

    // Also assert that history was not updated
    try std.testing.expectEqual(@as(usize, 0), router.history.items.len);
}

test "route: forward history truncation" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url_a = try URL.init(allocator, "/a");
    try router.routes.append(router.allocator, .{ .url = url_a, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_b = try URL.init(allocator, "/b");
    try router.routes.append(router.allocator, .{ .url = url_b, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_c = try URL.init(allocator, "/c");
    try router.routes.append(router.allocator, .{ .url = url_c, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_d = try URL.init(allocator, "/d");
    try router.routes.append(router.allocator, .{ .url = url_d, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/a");
    try router.route("/b");
    try router.route("/c");

    // History is ["/a", "/b", "/c"], index is 2
    try std.testing.expectEqual(@as(usize, 3), router.history.items.len);
    try std.testing.expectEqual(@as(usize, 2), router.history_index);

    // Manually navigate back by changing the index
    router.history_index = 1; // Pointing at "/b"

    // Route to a new page
    try router.route("/d");

    // History should now be ["/a", "/b", "/d"]
    try std.testing.expectEqual(@as(usize, 3), router.history.items.len);
    try std.testing.expectEqualSlices(u8, "/a", router.history.items[0]);
    try std.testing.expectEqualSlices(u8, "/b", router.history.items[1]);
    try std.testing.expectEqualSlices(u8, "/d", router.history.items[2]);
    try std.testing.expectEqual(@as(usize, 2), router.history_index);
}

test "route: to same url twice" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url = try URL.init(allocator, "/a");
    try router.routes.append(router.allocator, .{ .url = url, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/a");
    try router.route("/a");

    try std.testing.expectEqual(@as(usize, 2), router.history.items.len);
    try std.testing.expectEqualSlices(u8, "/a", router.history.items[0]);
    try std.testing.expectEqualSlices(u8, "/a", router.history.items[1]);
    try std.testing.expectEqual(@as(usize, 1), router.history_index);
}

test "route: empty url" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url = try URL.init(allocator, "");
    try router.routes.append(router.allocator, .{ .url = url, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("");
    try std.testing.expectEqual(@as(usize, 1), router.history.items.len);
    try std.testing.expectEqualSlices(u8, "", router.history.items[0]);
}

test "route: root url" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url = try URL.init(allocator, "/");
    try router.routes.append(router.allocator, .{ .url = url, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/");
    try std.testing.expectEqual(@as(usize, 1), router.history.items.len);
    try std.testing.expectEqualSlices(u8, "/", router.history.items[0]);
}

test "route: url with extra slashes" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url = try URL.init(allocator, "/a//:b/");
    try router.routes.append(router.allocator, .{ .url = url, .screen = .{ .vtable = &TEST_SCREEN_WITH_CONTEXT_VTABLE, .state = null, .context = null } });

    try router.route("/a//foo/");

    try std.testing.expectEqual(@as(usize, 1), router.history.items.len);
    try std.testing.expectEqualSlices(u8, "/a//foo/", router.history.items[0]);

    const context: *const std.ArrayList([]const u8) = @ptrCast(@alignCast(g_last_screen_context.?));
    try std.testing.expectEqual(@as(usize, 1), context.items.len);
    try std.testing.expectEqualSlices(u8, "foo", context.items[0]);
}

test "route: out of memory on history duplication" {
    var fa = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 5 });
    const allocator = fa.allocator();

    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url = try URL.init(allocator, "/a");
    try router.routes.append(allocator, .{ .url = url, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try std.testing.expectError(Router.RouteError.OutOfMemory, router.route("/a"));
    try std.testing.expectEqual(@as(usize, 0), router.history.items.len);
}

test "back: basic navigation" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url_a = try URL.init(allocator, "/a");
    try router.routes.append(router.allocator, .{ .url = url_a, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_b = try URL.init(allocator, "/b");
    try router.routes.append(router.allocator, .{ .url = url_b, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_c = try URL.init(allocator, "/c");
    try router.routes.append(router.allocator, .{ .url = url_c, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/a");
    try router.route("/b");
    try router.route("/c");

    try std.testing.expect(router.back());
    try std.testing.expectEqual(@as(usize, 1), router.history_index);
    try std.testing.expectEqualSlices(u8, "/b", router.history.items[router.history_index]);
}

test "back: at beginning of history" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url_a = try URL.init(allocator, "/a");
    try router.routes.append(router.allocator, .{ .url = url_a, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/a");

    try std.testing.expect(!router.back());
    try std.testing.expectEqual(@as(usize, 0), router.history_index);
}

test "back: multiple steps" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url_a = try URL.init(allocator, "/a");
    try router.routes.append(router.allocator, .{ .url = url_a, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_b = try URL.init(allocator, "/b");
    try router.routes.append(router.allocator, .{ .url = url_b, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_c = try URL.init(allocator, "/c");
    try router.routes.append(router.allocator, .{ .url = url_c, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/a");
    try router.route("/b");
    try router.route("/c");

    try std.testing.expect(router.back()); // -> /b
    try std.testing.expect(router.back()); // -> /a
    try std.testing.expectEqual(@as(usize, 0), router.history_index);
    try std.testing.expectEqualSlices(u8, "/a", router.history.items[router.history_index]);

    try std.testing.expect(!router.back());
    try std.testing.expectEqual(@as(usize, 0), router.history_index);
}

test "forward: basic navigation" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url_a = try URL.init(allocator, "/a");
    try router.routes.append(router.allocator, .{ .url = url_a, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_b = try URL.init(allocator, "/b");
    try router.routes.append(router.allocator, .{ .url = url_b, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_c = try URL.init(allocator, "/c");
    try router.routes.append(router.allocator, .{ .url = url_c, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/a");
    try router.route("/b");
    try router.route("/c");

    _ = router.back(); // -> /b

    try std.testing.expect(router.forward());
    try std.testing.expectEqual(@as(usize, 2), router.history_index);
    try std.testing.expectEqualSlices(u8, "/c", router.history.items[router.history_index]);
}

test "forward: at end of history" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url_a = try URL.init(allocator, "/a");
    try router.routes.append(router.allocator, .{ .url = url_a, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_b = try URL.init(allocator, "/b");
    try router.routes.append(router.allocator, .{ .url = url_b, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/a");
    try router.route("/b");

    try std.testing.expect(!router.forward());
    try std.testing.expectEqual(@as(usize, 1), router.history_index);
}

test "forward: multiple steps" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url_a = try URL.init(allocator, "/a");
    try router.routes.append(router.allocator, .{ .url = url_a, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_b = try URL.init(allocator, "/b");
    try router.routes.append(router.allocator, .{ .url = url_b, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_c = try URL.init(allocator, "/c");
    try router.routes.append(router.allocator, .{ .url = url_c, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_d = try URL.init(allocator, "/d");
    try router.routes.append(router.allocator, .{ .url = url_d, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/a");
    try router.route("/b");
    try router.route("/c");
    try router.route("/d");

    _ = router.back(); // -> /c
    _ = router.back(); // -> /b
    _ = router.back(); // -> /a

    try std.testing.expect(router.forward()); // -> /b
    try std.testing.expect(router.forward()); // -> /c
    try std.testing.expectEqual(@as(usize, 2), router.history_index);
    try std.testing.expectEqualSlices(u8, "/c", router.history.items[router.history_index]);
}

test "back and forward: alternating navigation" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url_a = try URL.init(allocator, "/a");
    try router.routes.append(router.allocator, .{ .url = url_a, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_b = try URL.init(allocator, "/b");
    try router.routes.append(router.allocator, .{ .url = url_b, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_c = try URL.init(allocator, "/c");
    try router.routes.append(router.allocator, .{ .url = url_c, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/a");
    try router.route("/b");
    try router.route("/c");

    try std.testing.expect(router.back()); // -> /b
    try std.testing.expectEqual(@as(usize, 1), router.history_index);

    try std.testing.expect(router.back()); // -> /a
    try std.testing.expectEqual(@as(usize, 0), router.history_index);

    try std.testing.expect(router.forward()); // -> /b
    try std.testing.expectEqual(@as(usize, 1), router.history_index);

    try std.testing.expect(router.forward()); // -> /c
    try std.testing.expectEqual(@as(usize, 2), router.history_index);

    try std.testing.expect(!router.forward()); // (end)
    try std.testing.expectEqual(@as(usize, 2), router.history_index);
}

test "back and forward: new route truncates forward history" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url_a = try URL.init(allocator, "/a");
    try router.routes.append(router.allocator, .{ .url = url_a, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_b = try URL.init(allocator, "/b");
    try router.routes.append(router.allocator, .{ .url = url_b, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_c = try URL.init(allocator, "/c");
    try router.routes.append(router.allocator, .{ .url = url_c, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });
    const url_d = try URL.init(allocator, "/d");
    try router.routes.append(router.allocator, .{ .url = url_d, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/a");
    try router.route("/b");
    try router.route("/c");

    _ = router.back(); // -> /b

    try router.route("/d");

    try std.testing.expectEqual(@as(usize, 3), router.history.items.len);
    try std.testing.expectEqualSlices(u8, "/d", router.history.items[2]);

    try std.testing.expect(!router.forward());
}

test "back and forward: on empty history" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    try std.testing.expect(!router.back());
    try std.testing.expect(!router.forward());
}

test "back and forward: on single-entry history" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, 16);
    defer router.deinit();

    const url_a = try URL.init(allocator, "/a");
    try router.routes.append(router.allocator, .{ .url = url_a, .screen = .{ .vtable = &TEST_SCREEN_VTABLE, .state = null, .context = null } });

    try router.route("/a");

    try std.testing.expect(!router.back());
    try std.testing.expect(!router.forward());
    try std.testing.expectEqual(@as(usize, 0), router.history_index);
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
