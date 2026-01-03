const std = @import("std");
const ScreenFactory = @import("screen.zig").ScreenFactory;

/// A map of parameter names to values extracted from the URL.
/// e.g. "/users/123" -> {"id": "123"}
pub const RouteArgs = std.StringArrayHashMap([]const u8);

/// Configures what happens with screens when navigating to another screen.
pub const HistoryPolicy = enum {
    /// Keep this screen alive in the history stack when hidden.
    KeepAll,
    /// Destroy this screen when it becomes hidden (navigated away from).
    /// It will be re-initialized when navigated back to.
    DestroyHidden,
};

pub const Route = struct {
    /// A route template is seperated by using `/`.
    /// It can have dynamic parts identified by using `:` e.g. `/users/:id`.
    template: []const u8,
    factory: ScreenFactory,
    /// Override the router's default history policy for this specific route.
    history_policy: ?HistoryPolicy = null,

    pub const MatchURLError = error{
        OutOfMemory,
        UrlTooShort,
        UrltooLong,
        UrlStaticMismatch,
        /// Throws when you dont provide a name for a dyamic part of a template e.g `/users/:/` <-- the `:` is the problem.
        TemplateDynamicIdentifierNameMissing,
    };

    /// This function matches a user supplied url string to the supplied template of the route instance.
    /// Returning null means the matching was successful but there are no dynamic arguments supplied in the URL.
    pub fn matchURL(self: *Route, allocator: std.mem.Allocator, url: []const u8) MatchURLError!?RouteArgs {
        var params: ?RouteArgs = null;

        var template_it = std.mem.splitScalar(u8, self.template, '/');
        var url_it = std.mem.splitScalar(u8, url, '/');

        while (template_it.next()) |t_seg| {
            const u_seg = url_it.next() orelse return MatchURLError.UrltooLong;

            if (std.mem.startsWith(u8, t_seg, ":")) {
                // dynamic url segment
                if (t_seg.len < 2) return MatchURLError.TemplateDynamicIdentifierNameMissing;

                const key = t_seg[1..]; // leave out the `:` for the key name
                if (params == null) params = RouteArgs.init(allocator); // Initialize param map if we didnt yet.

                try params.?.put(key, u_seg);
            } else {
                // static url segment
                if (!std.mem.eql(u8, t_seg, u_seg)) {
                    return MatchURLError.UrlStaticMismatch;
                }
            }
        }

        return params;
    }
};
