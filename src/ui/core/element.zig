const std = @import("std");
const zclay = @import("zclay");

/// Opens a new Clay element.
/// This must be paired with a corresponding call to close().
pub fn open(config: zclay.ElementDeclaration) void {
    // std.log.debug("Open Element: {d}", .{config.id.id});
    zclay.cdefs.Clay__OpenElement();
    zclay.cdefs.Clay__ConfigureOpenElement(config);
}

/// Closes the most recently opened Clay element.
pub fn close() void {
    // std.log.debug("Close Element", .{});
    zclay.cdefs.Clay__CloseElement();
}

/// Opens an element, runs the body function, and closes the element.
/// This is a convenience wrapper similar to zclay.UI().
pub fn element(config: zclay.ElementDeclaration, body: anytype) void {
    open(config);
    defer close();
    body();
}
