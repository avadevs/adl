const std = @import("std");
const route = @import("route.zig");
const screen = @import("screen.zig");

pub const Route = route.Route;
pub const RouteArgs = route.RouteArgs;
pub const HistoryPolicy = route.HistoryPolicy;

const log = std.log.scoped(.ADL_router);

pub const RouterConfig = struct {
    /// Default policy for how screens are managed in history.
    default_history_policy: route.HistoryPolicy = .KeepAll,

    /// Maximum number of screens to keep alive in the history stack.
    /// If this limit is reached, screens furthest from the active index will be dehydrated (destroyed).
    max_alive_screens: usize = 16,

    /// Maximum number of entries to keep in the history stack.
    /// When the stack exceeds this size, the oldest entries (at the beginning) are removed.
    max_history_size: usize = 128,
};

const HistoryEntry = struct {
    url: []const u8,

    /// Index into the router.routes array to show which route this history item is belonging to.
    route_index: usize,

    // TODO: Possibly use a index into a screen array in the future,
    // this would allow safe serialization.
    screen: ?screen.AnyScreen,

    pub fn deinit(self: *HistoryEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        if (self.screen) |s| s.deinit();
    }
};

/// Responsible for handling urls and routing navigation requests to the actual screen.
pub const Router = struct {
    allocator: std.mem.Allocator,
    config: RouterConfig,

    routes: std.ArrayList(route.Route),
    history: std.ArrayList(HistoryEntry),
    history_index: usize = 0,

    pub const NavigateError = error{
        OutOfMemory,
        NoPossibleRoute,
        anyerror, // we can not prevent this because screens are user supplied and generic
    };

    pub fn init(allocator: std.mem.Allocator, config: RouterConfig) !Router {
        return .{
            .allocator = allocator,
            .config = config,
            .routes = try std.ArrayList(route.Route).initCapacity(allocator, 16),
            .history = try std.ArrayList(HistoryEntry).initCapacity(allocator, 16),
        };
    }

    pub fn deinit(self: *Router) void {
        // Clear history
        for (self.history.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.history.deinit(self.allocator);

        // Clear routes
        for (self.routes.items) |*entry| {
            self.allocator.free(entry.template);
        }
        self.routes.deinit(self.allocator);
    }

    /// Register a route with a path template and a screen type.
    ///
    /// `ScreenType` gets converted to `AnyScreen` internally. The type must implement:
    /// - `pub fn init(allocator: std.mem.Allocator, args: ?route.RouteArgs) !Self`
    /// - `pub fn deinit(self: *Self) void`
    /// - `pub fn render(self: *Self) void`
    ///
    /// Optional:
    /// - `pub fn update(self: *Self, args: ?route.RouteArgs) !void` (used for keep-alive routes)
    pub fn register(self: *Router, template: []const u8, comptime ScreenType: type, policy_override: ?route.HistoryPolicy) !void {
        try self.routes.append(self.allocator, .{
            .template = try self.allocator.dupe(u8, template),
            .factory = screen.ScreenFactory.wrap(ScreenType),
            .history_policy = policy_override,
        });

        log.debug("Registered route template: '{s}'", .{template});
    }

    /// Navigates to a specific URL.
    pub fn navigate(self: *Router, url: []const u8) NavigateError!void {
        var active_history_item: ?*HistoryEntry = null;

        // If we navigate to the same url that is already in use -> skip work
        if (self.history.items.len > 0) {
            active_history_item = &self.history.items[self.history_index];
            if (std.mem.eql(u8, active_history_item.?.url, url)) return;
        }

        // We have confirmed we need to navigate to a different route.
        // 1. Match user URL to registered route definition
        // extract active route and url parameters.
        var matching_route: ?*route.Route = null;
        var matching_route_index: usize = 0;
        var url_params: ?route.RouteArgs = null;
        defer if (url_params) |*p| p.deinit();

        // iterate every route and try to find a matching route
        for (self.routes.items, 0..) |*r, i| {
            url_params = r.matchURL(self.allocator, url) catch continue;

            log.debug("Matched route (template: '{s}') for url: '{s}'", .{ r.template, url });
            matching_route = r;
            matching_route_index = i;
            break;
        }

        // if we did not find a matching route return with error early -> we can't navigate anywhere
        if (matching_route == null) {
            log.warn("No route found for URL: '{s}'", .{url});
            return error.NoPossibleRoute;
        }

        // 2. Truncate history.
        // We will push a history item to history_index + 1, but there might be items from that point on
        // we need to get rid of these items (this scenario can happens through back/forward usage of the router).
        if (self.history.items.len > 0 and self.history_index < self.history.items.len - 1) {
            const start_remove = self.history_index + 1;
            for (self.history.items[start_remove..]) |*entry| {
                entry.deinit(self.allocator);
            }

            self.history.shrinkRetainingCapacity(start_remove);
            log.debug("Truncated history (if necerssary)", .{});
        }

        // Active route and start creating new history entry
        var new_history_entry = HistoryEntry{
            .url = try self.allocator.dupe(u8, url),
            .route_index = matching_route_index,
            .screen = null,
        };
        errdefer new_history_entry.deinit(self.allocator);

        // 3. Try to reuse active screen.
        var reused_screen: bool = false;
        if (active_history_item) |item| {
            if (item.route_index == matching_route_index) {
                if (item.screen) |active_s| {
                    // Try to update the screen
                    if (active_s.update(url_params) catch false) {
                        // Steal the screen from old history item
                        new_history_entry.screen = active_s;
                        item.screen = null; // Important: Dehydrate old entry
                        reused_screen = true;

                        log.debug("Reused already active screen - sent update", .{});
                    }
                }
            }
        }

        // 4. if we could not reuse a screen create new screen
        if (!reused_screen) {
            new_history_entry.screen = matching_route.?.factory.createFn(self.allocator, url_params) catch return NavigateError.anyerror;
            log.debug("Created new screen for navigation request", .{});
        }

        // 5. Commit
        try self.history.append(self.allocator, new_history_entry);
        self.history_index = self.history.items.len - 1;

        std.debug.assert(new_history_entry.screen != null);
        log.info("Navigated to: '{s}'", .{new_history_entry.url});
    }

    pub fn back(self: *Router) !bool {
        if (self.history_index == 0) return false; // we dont have a possible history that we can go back to.

        // 1. Handle leaving current history item
        const current_entry = &self.history.items[self.history_index];
        const entry_route = &self.routes.items[current_entry.route_index];

        // Try to route specific policy for history handling - use router policy as fallback
        const policy: route.HistoryPolicy = entry_route.history_policy orelse self.config.default_history_policy;

        switch (policy) {
            .DestroyHidden => { // Destroy screen if there.
                if (current_entry.screen) |s| {
                    s.deinit();
                    current_entry.screen = null;
                }
            },
            else => {},
        }

        self.history_index -= 1;

        // 2. Revive history item (we switch to) if needed
        const target = &self.history.items[self.history_index];
        if (target.screen == null) {
            const r = &self.routes.items[target.route_index];

            const params = try r.matchURL(self.allocator, target.url);
            target.screen = try r.factory.createFn(self.allocator, params);
        }

        log.info("Navigated back to url: '{s}", .{target.url});
        return true;
    }

    pub fn forward(self: *Router) !bool {
        // we cant go forward if we dont have a history or are the last item in the history (newest entry)
        if (self.history.items.len == 0 or self.history_index >= self.history.items.len - 1) return false;

        // 1. Handle leaving current history item
        const current_entry = &self.history.items[self.history_index];
        const entry_route = &self.routes.items[current_entry.route_index];

        // Try to route specific policy for history handling - use router policy as fallback
        const policy: route.HistoryPolicy = entry_route.history_policy orelse self.config.default_history_policy;

        switch (policy) {
            .DestroyHidden => { // Destroy screen if there.
                if (current_entry.screen) |s| {
                    s.deinit();
                    current_entry.screen = null;
                }
            },
            else => {},
        }

        self.history_index += 1;

        // 2. Revive history item (we switch to) if needed
        const target = &self.history.items[self.history_index];
        if (target.screen == null) {
            const r = &self.routes.items[target.route_index];

            const params = try r.matchURL(self.allocator, target.url);
            target.screen = try r.factory.createFn(self.allocator, params);
        }

        log.info("Navigated forward to url: '{s}", .{target.url});
        return true;
    }

    pub fn render(self: *Router) void {
        if (self.history.items.len == 0) return;
        const entry = &self.history.items[self.history_index];
        if (entry.screen) |s| {
            s.render();
        }

        log.debug("Rendered screen for URL: '{s}'", .{entry.url});
    }
};

// --- Tests ---

const TestScreen = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    init_count: usize,

    pub var global_init_count: usize = 0;
    pub var global_deinit_count: usize = 0;
    pub var global_render_count: usize = 0;

    pub fn init(allocator: std.mem.Allocator, args: ?route.RouteArgs) !TestScreen {
        global_init_count += 1;
        const id_ref = if (args) |a| a.get("id").? else "default";
        return TestScreen{
            .allocator = allocator,
            .id = try allocator.dupe(u8, id_ref),
            .init_count = global_init_count,
        };
    }

    pub fn deinit(self: *TestScreen) void {
        global_deinit_count += 1;
        self.allocator.free(self.id);
    }

    pub fn render(self: *TestScreen) void {
        global_render_count += 1;
        std.debug.print("ID: {s}\n", .{self.id});
    }
};

test "Router: Basic init test" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, .{ .default_history_policy = .KeepAll });
    defer router.deinit();

    TestScreen.global_init_count = 0;
    TestScreen.global_deinit_count = 0;

    try router.register("/test", TestScreen, null);
    try router.navigate("/test");

    router.render();

    try std.testing.expect(TestScreen.global_init_count == 1);
}

test "Router: basic dynamic url test" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, .{ .default_history_policy = .KeepAll });
    defer router.deinit();

    TestScreen.global_init_count = 0;
    TestScreen.global_deinit_count = 0;

    try router.register("/users/:id", TestScreen, null);
    std.debug.print("\nExpecting id to be: 1\n", .{});
    try router.navigate("/users/1");

    router.render();

    try std.testing.expect(TestScreen.global_init_count == 1);
}

test "Router: Error when no route matches URL" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, .{ .default_history_policy = .KeepAll });
    defer router.deinit();

    TestScreen.global_init_count = 0;
    TestScreen.global_deinit_count = 0;

    try router.register("/users/:id", TestScreen, null);
    try std.testing.expectError(error.NoPossibleRoute, router.navigate("/not-there"));

    router.render();

    try std.testing.expect(TestScreen.global_init_count == 1);
}

test "Router: Basic .render() test" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, .{ .default_history_policy = .KeepAll });
    defer router.deinit();

    TestScreen.global_render_count = 0;

    try router.register("/test", TestScreen, null);
    try router.navigate("/test");

    router.render();

    try std.testing.expect(TestScreen.global_render_count == 1);

    router.render();
    try std.testing.expect(TestScreen.global_render_count == 2);
}

test "Router: Basic .back() + .forward() test" {
    const allocator = std.testing.allocator;
    var router = try Router.init(allocator, .{ .default_history_policy = .KeepAll });
    defer router.deinit();

    TestScreen.global_render_count = 0;

    try router.register("/pageA", TestScreen, null);
    try router.register("/pageB", TestScreen, null);

    try router.navigate("/pageA");

    try router.navigate("/pageB");

    _ = try router.back();

    var current_page_url = router.history.items[router.history_index].url;
    try std.testing.expect(std.mem.eql(u8, current_page_url, "/pageA"));

    _ = try router.forward();
    current_page_url = router.history.items[router.history_index].url;
    try std.testing.expect(std.mem.eql(u8, current_page_url, "/pageB"));
}
