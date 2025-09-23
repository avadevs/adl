const std = @import("std");
const rl = @import("raylib");

/// Tracks the state of a single key for one frame.
pub const KeyState = struct {
    is_down: bool = false,
    was_down: bool = false,
    time_down: f32 = 0.0,
    repeat_triggered_this_frame: bool = false,

    /// Returns true only on the single frame the key is first pressed.
    pub fn isPressed(self: KeyState) bool {
        return self.is_down and !self.was_down;
    }

    /// Returns true on the first frame a key is pressed, and also on subsequent
    /// frames at a regular interval if the key is held down.
    pub fn isRepeated(self: KeyState) bool {
        return self.isPressed() or self.repeat_triggered_this_frame;
    }
};

/// Tracks the state of a single mouse button for one frame.
pub const MouseButtonState = struct {
    is_down: bool = false,
    was_down: bool = false,

    /// Returns true only on the single frame the button is first pressed.
    pub fn isPressed(self: MouseButtonState) bool {
        return self.is_down and !self.was_down;
    }

    /// Returns true only on the single frame the button is released.
    pub fn isReleased(self: MouseButtonState) bool {
        return !self.is_down and self.was_down;
    }
};

/// Holds all mouse-related state for the current frame.
pub const MouseState = struct {
    pos: rl.Vector2 = .{ .x = 0, .y = 0 },
    prev_pos: rl.Vector2 = .{ .x = 0, .y = 0 },
    delta: rl.Vector2 = .{ .x = 0, .y = 0 },
    wheel_move: f32 = 0,

    left_button: MouseButtonState = .{},
    right_button: MouseButtonState = .{},
    middle_button: MouseButtonState = .{},
};

/// A centralized, generic manager for processing keyboard and mouse input.
/// It tracks the state of every key and the mouse, allowing for consistent
/// repeat behavior and state management (e.g., pressed, released, delta)
/// across all UI components.
pub const InputManager = struct {
    allocator: std.mem.Allocator,
    key_states: std.AutoHashMap(rl.KeyboardKey, KeyState),
    mouse_state: MouseState = .{},

    // Configurable timings, in seconds (matching raylib.getFrameTime()).
    // These can be changed at runtime.
    key_repeat_delay: f32 = 0.4,
    key_repeat_interval: f32 = 0.04,

    pub fn init(allocator: std.mem.Allocator) !InputManager {
        return .{
            .allocator = allocator,
            .key_states = std.AutoHashMap(rl.KeyboardKey, KeyState).init(allocator),
            .mouse_state = .{},
        };
    }

    pub fn deinit(self: *InputManager) void {
        self.key_states.deinit();
    }

    /// Updates the state of all keys and the mouse. This should be called once per frame.
    pub fn update(self: *InputManager, delta_time: f32) !void {
        // 1. Update Keyboard State
        // Add any newly pressed keys to our tracking map.
        while (true) {
            const key_code = rl.getKeyPressed();
            if (@intFromEnum(key_code) == 0) break;

            if (!self.key_states.contains(key_code)) {
                try self.key_states.put(key_code, .{});
            }
        }

        // Iterate the map of active/tracked keys and update their state.
        var key_iter = self.key_states.iterator();
        while (key_iter.next()) |entry| {
            self.updateKey(entry.key_ptr, entry.value_ptr, delta_time);

            // If the key is no longer down, remove it from the map.
            if (!entry.value_ptr.is_down) {
                _ = self.key_states.remove(entry.key_ptr.*);
            }
        }

        // 2. Update Mouse State
        self.updateMouse();
    }

    fn updateMouse(self: *InputManager) void {
        // Update position and calculate delta
        self.mouse_state.prev_pos = self.mouse_state.pos;
        self.mouse_state.pos = rl.getMousePosition();
        self.mouse_state.delta = .{
            .x = self.mouse_state.pos.x - self.mouse_state.prev_pos.x,
            .y = self.mouse_state.pos.y - self.mouse_state.prev_pos.y,
        };

        // Update wheel
        self.mouse_state.wheel_move = rl.getMouseWheelMove();

        // Update buttons
        self.mouse_state.left_button.was_down = self.mouse_state.left_button.is_down;
        self.mouse_state.left_button.is_down = rl.isMouseButtonDown(.left);

        self.mouse_state.right_button.was_down = self.mouse_state.right_button.is_down;
        self.mouse_state.right_button.is_down = rl.isMouseButtonDown(.right);

        self.mouse_state.middle_button.was_down = self.mouse_state.middle_button.is_down;
        self.mouse_state.middle_button.is_down = rl.isMouseButtonDown(.middle);
    }

    fn updateKey(self: *InputManager, key: *rl.KeyboardKey, key_state: *KeyState, delta_time: f32) void {
        key_state.was_down = key_state.is_down;
        key_state.is_down = rl.isKeyDown(key.*);
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

    /// Public query function for components to get the state of any key.
    pub fn getKey(self: *const InputManager, key: rl.KeyboardKey) KeyState {
        return self.key_states.get(key) orelse KeyState{};
    }

    /// Public query function to get a pointer to the full mouse state for this frame.
    pub fn getMouse(self: *const InputManager) *const MouseState {
        return &self.mouse_state;
    }
};
