const std = @import("std");
const cl = @import("zclay");
const t = @import("./theme.zig");
const input = @import("./input.zig");
const types = @import("./types.zig");

/// UIContext holds the global state for the entire UI for a single frame.
/// A pointer to this struct is passed to every UI component. It is the "single
/// source of truth" for global state like input, focus, and styling.
///
/// Usage:
/// ```zig
/// var ui_context = try UIContext.init(allocator, &my_theme, my_measure_text_fn, my_input_backend);
/// defer ui_context.deinit();
///
/// // In your main loop:
/// while (!rl.windowShouldClose()) {
///     ui_context.beginFrame(rl.getFrameTime());
///
///     // ... render all your UI components here, passing &ui_context ...
///
///     rl.beginDrawing();
///     // ...
///     rl.endDrawing();
/// }
/// ```
pub const UIContext = struct {
    allocator: std.mem.Allocator,
    theme: *const t.THEME,
    measure_text_fn: ?*const fn (clay_text: []const u8, config: *cl.TextElementConfig, _: void) cl.Dimensions = null,
    input: input.InputManager,
    frame_allocator: std.mem.Allocator = undefined,

    // --- State Model ---
    // The hot-active-focused model is a standard pattern for immediate mode GUIs.
    // It allows for complex interactions to be built from simple, stateless components.

    /// 'hot_id': The element the mouse is currently hovering over.
    /// This is transient and reset every frame. It's used for hover effects (e.g. a
    /// button changing color) and to identify the target for a potential click.
    hot_id: ?cl.ElementId = null,

    /// 'active_id': The element currently being manipulated (e.g., a slider being
    /// dragged, a dropdown menu that is open). An element becomes active when it's
    /// clicked, and it stays active across multiple frames until the interaction
    /// is complete (e.g., mouse button is released). This allows for interactions
    /// that persist even if the mouse moves outside the element's bounds.
    active_id: ?cl.ElementId = null,

    /// 'focused_id': The element that receives keyboard input (e.g., a textbox).
    /// It becomes focused when clicked and stays focused until another element
    /// takes focus. There can only be one focused element at a time.
    focused_id: ?cl.ElementId = null,

    /// A global timer that increments each frame. Useful for animations like
    /// the blinking cursor in a textbox.
    anim_timer: f32 = 0,

    pub fn init(allocator: std.mem.Allocator, theme: *const t.THEME, measure_text_fn: ?*const fn (clay_text: []const u8, config: *cl.TextElementConfig, _: void) cl.Dimensions, backend: input.InputBackend) !UIContext {
        return .{
            .allocator = allocator,
            .theme = theme,
            .measure_text_fn = measure_text_fn,
            .input = try input.InputManager.init(allocator, backend),
        };
    }

    pub fn deinit(self: *UIContext) void {
        self.input.deinit();
    }

    /// Call this at the beginning of each frame's UI rendering pass.
    pub fn beginFrame(self: *UIContext, delta_time: f32) void {
        self.input.update(delta_time) catch {}; // Update input state
        // Hot is always reset at the start of the frame. Components will re-declare
        // themselves as hot if the mouse is over them.
        self.hot_id = null;
        self.anim_timer += delta_time;

        // Reset cursor to default at start of frame
        self.input.setMouseCursor(.default);
    }
};

pub fn dummyMeasureText(_: []const u8, _: *cl.TextElementConfig, _: void) cl.Dimensions {
    return .{ .w = 0, .h = 0 };
}

fn dummyGetMousePos(_: *anyopaque) types.Vector2 {
    return .{};
}
fn dummyGetMouseWheel(_: *anyopaque) f32 {
    return 0;
}
fn dummyIsBtnDown(_: *anyopaque, _: types.MouseButton) bool {
    return false;
}
fn dummyIsKeyDown(_: *anyopaque, _: types.Key) bool {
    return false;
}
fn dummyGetKeyPressed(_: *anyopaque) ?types.Key {
    return null;
}
fn dummyGetCharPressed(_: *anyopaque) u32 {
    return 0;
}
fn dummySetMouseCursor(_: *anyopaque, _: types.CursorShape) void {}

test "UIContext init and beginFrame logic" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;

    const dummy_backend = input.InputBackend{
        .context = undefined,
        .getMousePosition = dummyGetMousePos,
        .getMouseWheelMove = dummyGetMouseWheel,
        .isMouseButtonDown = dummyIsBtnDown,
        .isKeyDown = dummyIsKeyDown,
        .getKeyPressed = dummyGetKeyPressed,
        .getCharPressed = dummyGetCharPressed,
        .setMouseCursor = dummySetMouseCursor,
    };

    // 1. Test init()
    var theme = t.THEME.init();
    var ctx = try UIContext.init(allocator, &theme, &dummyMeasureText, dummy_backend);
    defer ctx.deinit();

    try expect(ctx.theme == &theme);
    try expect(ctx.measure_text_fn != null);
    try expect(ctx.hot_id == null);
    try expect(ctx.active_id == null);
    try expect(ctx.focused_id == null);
    try expect(ctx.anim_timer == 0.0);

    // 2. Test beginFrame()
    // Setup a fake state
    ctx.hot_id = cl.ElementId.init(1);
    ctx.focused_id = cl.ElementId.init(2); // focused_id should NOT be reset
    ctx.anim_timer = 10.0;

    // Call the function to be tested
    const delta_time = 0.16;
    ctx.beginFrame(delta_time);

    // Assert the expected outcomes
    try expect(ctx.hot_id == null); // hot_id should be reset
    try expect(ctx.focused_id != null and ctx.focused_id.?.id == cl.ElementId.init(2).id); // focused_id should persist
    try expect(ctx.anim_timer == 10.0 + delta_time); // anim_timer should be incremented
}
