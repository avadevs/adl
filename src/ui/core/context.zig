const std = @import("std");
const cl = @import("zclay");
const t = @import("./theme.zig");
const input = @import("./input.zig");
const types = @import("./types.zig");

/// Thread-local pointer to the active UIContext.
/// This allows "implicit context" usage in the API.
threadlocal var current_instance: ?*UIContext = null;

pub const ContextError = error{
    NoActiveContext,
    OutOfMemory,
};

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

    // --- Scoped Registry ---
    // Stores UI state (cursor pos, scroll offset) organized by scope.
    // Outer Key: Scope ID (Pointer to Screen/Parent)
    // Inner Key: Element ID (Hash of user string)
    scopes: std.AutoHashMap(u64, std.AutoHashMap(u64, types.WidgetState)),

    // Stack for nested scopes (e.g. Modals -> Panels -> etc)
    scope_stack: std.ArrayList(u64),

    pub fn init(allocator: std.mem.Allocator, theme: *const t.THEME, measure_text_fn: ?*const fn (clay_text: []const u8, config: *cl.TextElementConfig, _: void) cl.Dimensions, backend: input.InputBackend) !UIContext {
        return .{
            .allocator = allocator,
            .theme = theme,
            .measure_text_fn = measure_text_fn,
            .input = try input.InputManager.init(allocator, backend),
            .scopes = std.AutoHashMap(u64, std.AutoHashMap(u64, types.WidgetState)).init(allocator),
            .scope_stack = try std.ArrayList(u64).initCapacity(allocator, 16),
        };
    }

    pub fn deinit(self: *UIContext) void {
        self.input.deinit();

        // Cleanup all scopes
        var scope_iter = self.scopes.iterator();
        while (scope_iter.next()) |scope_entry| {
            var state_iter = scope_entry.value_ptr.iterator();
            while (state_iter.next()) |state_entry| {
                self.freeWidgetState(state_entry.value_ptr);
            }
            scope_entry.value_ptr.deinit();
        }
        self.scopes.deinit();
        self.scope_stack.deinit(self.allocator);
    }

    /// Sets this UIContext as the active one for the current thread.
    /// This allows the usage of the `ui` namespace functions without explicitly passing the context.
    pub fn makeCurrent(self: *UIContext) void {
        current_instance = self;
    }

    /// Retrieves the active UIContext for the current thread.
    /// Returns error if no context is active (safety check).
    pub fn getCurrent() ContextError!*UIContext {
        if (current_instance) |ctx| return ctx;
        return ContextError.NoActiveContext;
    }

    /// Helper to free any allocated memory within a WidgetState
    fn freeWidgetState(self: *UIContext, state: *types.WidgetState) void {
        switch (state.*) {
            .custom => |wrapper| {
                wrapper.deinit_fn(wrapper.data, self.allocator);
            },
            else => {}, // POD states don't need cleanup
        }
    }

    // --- Scope Management ---

    /// Pushes a new scope ID onto the stack. All subsequent widget IDs will be looked up within this scope.
    /// Typically called automatically by the Router/Screen.
    pub fn beginScope(self: *UIContext, scope_id: u64) !void {
        try self.scope_stack.append(self.allocator, scope_id);
    }

    /// Pops the current scope from the stack.
    pub fn endScope(self: *UIContext) void {
        if (self.scope_stack.items.len > 0) {
            _ = self.scope_stack.pop();
        } else {
            std.log.warn("Attempted to endScope() but stack was empty!", .{});
        }
    }

    /// Destroys all state associated with a scope.
    /// Called by the Router when a Screen is deinitialized.
    pub fn freeScope(self: *UIContext, scope_id: u64) void {
        if (self.scopes.fetchRemove(scope_id)) |kv| {
            var inner_map = kv.value;
            var iter = inner_map.iterator();
            while (iter.next()) |entry| {
                self.freeWidgetState(entry.value_ptr);
            }
            inner_map.deinit();
        }
    }

    // --- State Access ---

    /// Retrieves or initializes a standard widget state (Textbox, Scroll, etc).
    /// Uses the current active scope.
    pub fn getWidgetState(self: *UIContext, id: u64, default_state: types.WidgetState) ContextError!*types.WidgetState {
        const current_scope = if (self.scope_stack.items.len > 0)
            self.scope_stack.getLast()
        else
            0; // Default/Global scope

        const scope_map_result = self.scopes.getOrPut(current_scope) catch return ContextError.OutOfMemory;
        if (!scope_map_result.found_existing) {
            scope_map_result.value_ptr.* = std.AutoHashMap(u64, types.WidgetState).init(self.allocator);
        }

        const state_map = scope_map_result.value_ptr;
        const state_result = state_map.getOrPut(id) catch return ContextError.OutOfMemory;

        if (!state_result.found_existing) {
            state_result.value_ptr.* = default_state;
        }

        return state_result.value_ptr;
    }

    /// Retrieves or initializes a generic custom widget state.
    /// Used for third-party extensions.
    pub fn getOrInitCustom(self: *UIContext, id: u64, comptime T: type) ContextError!*T {
        const current_scope = if (self.scope_stack.items.len > 0)
            self.scope_stack.getLast()
        else
            0;

        const scope_map_result = self.scopes.getOrPut(current_scope) catch return ContextError.OutOfMemory;
        if (!scope_map_result.found_existing) {
            scope_map_result.value_ptr.* = std.AutoHashMap(u64, types.WidgetState).init(self.allocator);
        }

        const state_map = scope_map_result.value_ptr;
        const entry = state_map.getOrPut(id) catch return ContextError.OutOfMemory;

        // Verification & Initialization
        if (entry.found_existing) {
            if (entry.value_ptr.* == .custom) {
                const wrapper = entry.value_ptr.custom;
                // Type safety check
                if (wrapper.type_id == @intFromPtr(T)) {
                    return @ptrCast(@alignCast(wrapper.data));
                }
            }
            // Collision or Type Mismatch: Overwrite
            self.freeWidgetState(entry.value_ptr);
        }

        // Initialize new
        const ptr = self.allocator.create(T) catch return ContextError.OutOfMemory;
        ptr.* = T{}; // Default init

        // Generate cleanup function
        const gen = struct {
            fn deinit_impl(raw: *anyopaque, alloc: std.mem.Allocator) void {
                const self_ptr: *T = @ptrCast(@alignCast(raw));
                if (@hasDecl(T, "deinit")) {
                    self_ptr.deinit();
                }
                alloc.destroy(self_ptr);
            }
        };

        entry.value_ptr.* = .{ .custom = .{
            .data = ptr,
            .type_id = @intFromPtr(T),
            .deinit_fn = gen.deinit_impl,
        } };

        return ptr;
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
fn dummyGetMouseWheel(_: *anyopaque) types.Vector2 {
    return .{ .x = 0, .y = 0 };
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

test "UIContext Scoped State" {
    const allocator = std.testing.allocator;
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
    var theme = t.THEME.init();
    var ctx = try UIContext.init(allocator, &theme, &dummyMeasureText, dummy_backend);
    defer ctx.deinit();

    // Setup implicit context
    ctx.makeCurrent();

    // 1. Begin Scope
    try ctx.beginScope(12345);

    // 2. Init State
    const id = 10;
    const state = try ctx.getWidgetState(id, .{ .textbox = .{} });
    state.textbox.cursor_pos = 99;

    // 3. Verify State Persists
    const state_2 = try ctx.getWidgetState(id, .{ .textbox = .{} });
    try std.testing.expectEqual(@as(usize, 99), state_2.textbox.cursor_pos);

    // 4. End Scope
    ctx.endScope();

    // 5. Free Scope
    ctx.freeScope(12345);

    // 6. Verify Cleanup
    // Re-enter scope, state should be reset (new default)
    try ctx.beginScope(12345);
    const state_3 = try ctx.getWidgetState(id, .{ .textbox = .{} });
    try std.testing.expectEqual(@as(usize, 0), state_3.textbox.cursor_pos);
}
