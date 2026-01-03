const std = @import("std");
const types = @import("types.zig");

pub const KeyState = struct {
    is_down: bool = false,
    was_down: bool = false,
    time_down: f32 = 0.0,
    repeat_triggered_this_frame: bool = false,

    pub fn isPressed(self: KeyState) bool {
        return self.is_down and !self.was_down;
    }

    pub fn isRepeated(self: KeyState) bool {
        return self.isPressed() or self.repeat_triggered_this_frame;
    }
};

pub const MouseButtonState = struct {
    is_down: bool = false,
    was_down: bool = false,

    pub fn isPressed(self: MouseButtonState) bool {
        return self.is_down and !self.was_down;
    }

    pub fn isReleased(self: MouseButtonState) bool {
        return !self.is_down and self.was_down;
    }
};

pub const MouseState = struct {
    pos: types.Vector2 = .{ .x = 0, .y = 0 },
    prev_pos: types.Vector2 = .{ .x = 0, .y = 0 },
    delta: types.Vector2 = .{ .x = 0, .y = 0 },
    wheel_move: f32 = 0,

    left_button: MouseButtonState = .{},
    right_button: MouseButtonState = .{},
    middle_button: MouseButtonState = .{},
};

/// Interface that platform backends must implement to provide raw input to ADL
pub const InputBackend = struct {
    context: *anyopaque,

    // Core functions
    getMousePosition: *const fn (ctx: *anyopaque) types.Vector2,
    getMouseWheelMove: *const fn (ctx: *anyopaque) f32,
    isMouseButtonDown: *const fn (ctx: *anyopaque, button: types.MouseButton) bool,
    isKeyDown: *const fn (ctx: *anyopaque, key: types.Key) bool,
    getKeyPressed: *const fn (ctx: *anyopaque) ?types.Key,
    getCharPressed: *const fn (ctx: *anyopaque) u32,
    setMouseCursor: *const fn (ctx: *anyopaque, cursor: types.CursorShape) void,
};

pub const InputManager = struct {
    allocator: std.mem.Allocator,
    key_states: std.AutoHashMap(types.Key, KeyState),
    mouse_state: MouseState = .{},
    backend: InputBackend,

    // Configurable timings
    key_repeat_delay: f32 = 0.4,
    key_repeat_interval: f32 = 0.04,

    pub fn init(allocator: std.mem.Allocator, backend: InputBackend) !InputManager {
        return .{
            .allocator = allocator,
            .key_states = std.AutoHashMap(types.Key, KeyState).init(allocator),
            .mouse_state = .{},
            .backend = backend,
        };
    }

    pub fn deinit(self: *InputManager) void {
        self.key_states.deinit();
    }

    pub fn update(self: *InputManager, delta_time: f32) !void {
        // 1. Update Keyboard State
        while (true) {
            const key_opt = self.backend.getKeyPressed(self.backend.context);
            if (key_opt) |key| {
                if (!self.key_states.contains(key)) {
                    try self.key_states.put(key, .{});
                }
            } else {
                break;
            }
        }

        var key_iter = self.key_states.iterator();
        while (key_iter.next()) |entry| {
            self.updateKey(entry.key_ptr, entry.value_ptr, delta_time);

            if (!entry.value_ptr.is_down) {
                _ = self.key_states.remove(entry.key_ptr.*);
            }
        }

        // 2. Update Mouse State
        self.updateMouse();
    }

    fn updateMouse(self: *InputManager) void {
        self.mouse_state.prev_pos = self.mouse_state.pos;
        self.mouse_state.pos = self.backend.getMousePosition(self.backend.context);
        self.mouse_state.delta = .{
            .x = self.mouse_state.pos.x - self.mouse_state.prev_pos.x,
            .y = self.mouse_state.pos.y - self.mouse_state.prev_pos.y,
        };

        self.mouse_state.wheel_move = self.backend.getMouseWheelMove(self.backend.context);

        self.mouse_state.left_button.was_down = self.mouse_state.left_button.is_down;
        self.mouse_state.left_button.is_down = self.backend.isMouseButtonDown(self.backend.context, .left);

        self.mouse_state.right_button.was_down = self.mouse_state.right_button.is_down;
        self.mouse_state.right_button.is_down = self.backend.isMouseButtonDown(self.backend.context, .right);

        self.mouse_state.middle_button.was_down = self.mouse_state.middle_button.is_down;
        self.mouse_state.middle_button.is_down = self.backend.isMouseButtonDown(self.backend.context, .middle);
    }

    fn updateKey(self: *InputManager, key: *types.Key, key_state: *KeyState, delta_time: f32) void {
        key_state.was_down = key_state.is_down;
        key_state.is_down = self.backend.isKeyDown(self.backend.context, key.*);
        key_state.repeat_triggered_this_frame = false;

        if (key_state.is_down) {
            const old_time_down = key_state.time_down;
            key_state.time_down += delta_time;

            if (key_state.time_down > self.key_repeat_delay) {
                const old_intervals = @floor((old_time_down - self.key_repeat_delay) / self.key_repeat_interval);
                const new_intervals = @floor((key_state.time_down - self.key_repeat_delay) / self.key_repeat_interval);
                if (new_intervals > old_intervals) {
                    key_state.repeat_triggered_this_frame = true;
                }
            }
        } else {
            key_state.time_down = 0.0;
        }
    }

    pub fn getKey(self: *const InputManager, key: types.Key) KeyState {
        return self.key_states.get(key) orelse KeyState{};
    }

    pub fn getMouse(self: *const InputManager) *const MouseState {
        return &self.mouse_state;
    }

    pub fn getCharPressed(self: *const InputManager) u32 {
        return self.backend.getCharPressed(self.backend.context);
    }

    pub fn setMouseCursor(self: *const InputManager, cursor: types.CursorShape) void {
        self.backend.setMouseCursor(self.backend.context, cursor);
    }
};
