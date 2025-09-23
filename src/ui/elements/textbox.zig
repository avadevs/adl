/// A single-line text input component with horizontal scrolling.
///
/// Features:
/// - State: Manages its own state (`text`, `cursor_pos`, `scroll_offset_x`) via the `State` struct, which is owned by the parent.
/// - Input: Accepts keyboard input, backspace and delete.
/// - Focus: Gains focus on click, indicated by a border color change. Will put the cursor where your mouse position is.
/// - Hover: Changes the mouse cursor to an I-beam on hover.
/// - Cursor: Renders a blinking cursor at the current position. Can be moved with arrow keys or by clicking.
/// - Scrolling: The text view scrolls horizontally to keep the cursor in view.
/// - Placeholder: Displays placeholder text when empty.
const std = @import("std");
const cl = @import("zclay");
const rl = @import("raylib");
const t = @import("../core/theme.zig");
const UIContext = @import("../core/context.zig").UIContext;

const CURSOR_SIZE: f32 = 0.88;

pub const Options = struct {
    placeholder: []const u8 = "...",
    font_size: u16 = 20,
};

/// State for a single textbox instance. This should be created and owned by the parent UI.
/// It uses an ArrayList, so it requires an allocator.
pub const State = struct {
    allocator: std.mem.Allocator,
    text: std.ArrayList(u8),
    cursor_pos: u32 = 0,
    scroll_offset_x: f32 = 0,

    // Frame-local context, updated at the start of each `render` call.
    // This is a safe way to pass context to callbacks without breaking encapsulation.
    ctx: ?*UIContext = null,
    options: Options = .{},

    pub fn init(allocator: std.mem.Allocator) !State {
        return .{
            .allocator = allocator,
            .text = try std.ArrayList(u8).initCapacity(allocator, 128),
        };
    }

    pub fn deinit(self: *State) void {
        self.text.deinit(self.allocator);
    }

    /// Inserts a character at the cursor position.
    fn insertChar(self: *State, char: u8) !void {
        try self.text.insert(self.allocator, self.cursor_pos, char);
        self.cursor_pos += 1;
    }

    /// Deletes a character before the cursor position.
    fn backspace(self: *State) void {
        if (self.cursor_pos > 0) {
            _ = self.text.orderedRemove(self.cursor_pos - 1);
            self.cursor_pos -= 1;
        }
    }

    /// Deletes a character after the cursor position.
    fn delete(self: *State) void {
        if (self.cursor_pos < self.text.items.len) {
            _ = self.text.orderedRemove(self.cursor_pos);
        }
    }
};

/// Internal callback for the hover event on the textbox.
fn onHoverCallback(id: cl.ElementId, pointerInfo: cl.PointerData, state: *State) void {
    // This callback receives the component's state as its context.
    // The state contains pointers and data relevant to the current frame,
    // which were set at the beginning of the `render` call.
    const ctx = state.ctx.?;
    const options = state.options;

    // Change the mouse cursor to the I-beam to indicate text input.
    rl.setMouseCursor(.ibeam);

    // If pressed -> set focus and move cursor
    if (pointerInfo.state == .pressed_this_frame) {
        ctx.focused_id = id;

        // Move cursor to click position
        const element_box = cl.getElementData(id).bounding_box;
        const text_padding: f32 = 8;
        const click_x_relative = (pointerInfo.position.x - element_box.x - text_padding) + state.scroll_offset_x;

        if (ctx.measure_text_fn) |measure_fn| {
            var config: cl.TextElementConfig = .{ .font_size = options.font_size };
            var last_char_x: f32 = 0;
            var new_cursor_pos: u32 = 0;

            for (state.text.items, 0..) |char, i| {
                const char_slice = &.{char};
                const char_width = measure_fn(char_slice, &config, {}).w;
                const char_midpoint = last_char_x + (char_width / 2);

                if (click_x_relative < char_midpoint) {
                    new_cursor_pos = @intCast(i);
                    break;
                }
                last_char_x += char_width;
                new_cursor_pos = @intCast(i + 1);
            }
            state.cursor_pos = new_cursor_pos;
        }
    }
}

/// Renders a textbox component.
///
/// This is an "immediate mode" UI component that must be called every frame.
/// The parent UI is responsible for creating and managing the `textbox.State`.
///
/// Usage:
/// ```zig
/// // In your parent UI's state struct:
/// var textbox_state: textbox.State,
///
/// // In your parent UI's init function:
/// self.textbox_state = try textbox.State.init(allocator);
///
/// // In your parent UI's deinit function:
/// self.textbox_state.deinit();
///
/// // In your parent UI's render function (inside a cl.UI block):
/// textbox.render(ctx, .localID("my_textbox"), &self.textbox_state, .{
///     .placeholder = "Enter text...",
/// });
/// ```
pub fn render(ctx: *UIContext, id: cl.ElementId, state: *State, options: Options) void {
    // Update the frame-local context within our persistent state.
    // This makes it safely available to callbacks later in the frame.
    state.ctx = ctx;
    state.options = options;

    const is_focused = ctx.focused_id != null and ctx.focused_id.?.id == id.id;

    // Handle keyboard input only if this textbox is focused.
    if (is_focused) {
        // Raylib's GetCharPressed gets unicode characters, which we cast to u8.
        // This loop handles multiple characters per frame if needed.
        // This is for TEXT INPUT and is separate from our key state manager.
        while (true) {
            const char_code = rl.getCharPressed();
            if (char_code == 0) break;

            if (char_code >= 32 and char_code <= 125) { // Basic ASCII range
                const char = @as(u8, @intCast(char_code));
                state.insertChar(char) catch {}; // Ignore allocation errors for simplicity
            }
        }

        // Handle ACTIONS using the new input manager.
        if (ctx.input.getKey(.backspace).isRepeated()) {
            state.backspace();
        }

        if (ctx.input.getKey(.delete).isRepeated()) {
            state.delete();
        }

        if (ctx.input.getKey(.right).isRepeated()) {
            if (state.cursor_pos < state.text.items.len) {
                state.cursor_pos += 1;
            }
        }
        if (ctx.input.getKey(.left).isRepeated()) {
            if (state.cursor_pos > 0) {
                state.cursor_pos -= 1;
            }
        }
    }

    // Scroll view to keep cursor visible
    if (ctx.measure_text_fn) |measure_fn| {
        const textbox_width = cl.getElementData(id).bounding_box.width;
        if (textbox_width > 0) { // Only update scroll if the element has been rendered at least once
            var config: cl.TextElementConfig = .{ .font_size = options.font_size };
            const cursor_x_pos = measure_fn(state.text.items[0..state.cursor_pos], &config, {}).w;

            const padding: f32 = 8;
            const view_start_x = state.scroll_offset_x;
            const view_end_x = state.scroll_offset_x + textbox_width - (padding * 2);

            if (cursor_x_pos < view_start_x + padding) {
                state.scroll_offset_x = cursor_x_pos - padding;
            } else if (cursor_x_pos > view_end_x) {
                state.scroll_offset_x = cursor_x_pos - textbox_width + (padding * 2);
            }

            // Clamp scroll offset
            const max_text_dim = measure_fn(state.text.items, &config, {});
            const max_scroll = if (max_text_dim.w > textbox_width) max_text_dim.w - textbox_width + padding else 0;
            if (state.scroll_offset_x > max_scroll) {
                state.scroll_offset_x = max_scroll;
            }
            if (state.scroll_offset_x < 0) {
                state.scroll_offset_x = 0;
            }
        }
    }

    // Determine colors based on the current state (focused, hovered, or normal).
    const border_color = if (is_focused) ctx.theme.color_primary else ctx.theme.color_base_300;
    const bg_color = if (cl.hovered()) ctx.theme.color_base_200 else ctx.theme.color_base_100;

    cl.UI()(.{
        .id = id,
        .layout = .{
            .direction = .left_to_right,
            .sizing = .{ .w = .grow, .h = .fixed(40) },
            .padding = .{ .left = 8, .right = 8 },
        },
        .background_color = bg_color,
        .border = .{ .width = .all(ctx.theme.border), .color = border_color },
        .corner_radius = .all(ctx.theme.radius_field),
    })({
        cl.UI()(.{
            .layout = .{ .sizing = .grow, .child_alignment = .{ .y = .center } },
            .clip = .{ .horizontal = true, .child_offset = .{ .x = -state.scroll_offset_x, .y = 0 } },
        })({
            // If the textbox is empty and not focused, show the placeholder.
            if (state.text.items.len == 0 and !is_focused) {
                var placeholder_color = ctx.theme.color_base_content;
                placeholder_color[3] = 150; // Make it semi-transparent

                cl.text(options.placeholder, .{
                    .font_size = options.font_size,
                    .color = placeholder_color,
                    .wrap_mode = .none,
                });
            } else {
                // --- Cursor Rendering Logic ---
                // To render the cursor, we split the text into two parts and draw a small
                // UI element for the cursor in between them.

                // 1. Text before the cursor
                if (state.cursor_pos > 0) {
                    cl.text(state.text.items[0..state.cursor_pos], .{
                        .font_size = options.font_size,
                        .color = ctx.theme.color_base_content,
                        .wrap_mode = .none,
                    });
                }

                // 2. The cursor itself (only shown if focused and blink is on)
                const show_cursor = @mod(ctx.anim_timer, 1.0) < 0.5;

                if (is_focused and show_cursor) {
                    cl.UI()(.{
                        .layout = .{ .sizing = .{ .w = .fixed(2), .h = .fixed(@as(f32, @floatFromInt(options.font_size)) * CURSOR_SIZE) } },
                        .background_color = ctx.theme.color_primary,
                    })({});
                }

                // 3. Text after the cursor
                if (state.cursor_pos < state.text.items.len) {
                    cl.text(state.text.items[state.cursor_pos..], .{
                        .font_size = options.font_size,
                        .color = ctx.theme.color_base_content,
                        .wrap_mode = .none,
                    });
                }
            }
        });
        // Register the internal hover callback to change the mouse cursor.
        cl.onHover(*State, state, onHoverCallback);
    });
}

test "textbox state management" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;
    const expectEqualSlices = std.testing.expectEqualSlices;

    // 1. Initialization
    var state = try State.init(allocator);
    defer state.deinit();

    try expect(state.text.items.len == 0);
    try expect(state.cursor_pos == 0);

    // 2. Insert characters
    try state.insertChar('a');
    try expectEqualSlices(u8, "a", state.text.items);
    try expect(state.cursor_pos == 1);

    try state.insertChar('b');
    try state.insertChar('c');
    try expectEqualSlices(u8, "abc", state.text.items);
    try expect(state.cursor_pos == 3);

    // 3. Backspace from the end
    state.backspace();
    try expectEqualSlices(u8, "ab", state.text.items);
    try expect(state.cursor_pos == 2);

    // 4. Insert in the middle
    state.cursor_pos = 1;
    try state.insertChar('X');
    try expectEqualSlices(u8, "aXb", state.text.items);
    try expect(state.cursor_pos == 2);

    // 5. Backspace from the middle
    state.backspace();
    try expectEqualSlices(u8, "ab", state.text.items);
    try expect(state.cursor_pos == 1);

    // 6. Backspace at the beginning (should do nothing)
    state.cursor_pos = 0;
    state.backspace();
    try expectEqualSlices(u8, "ab", state.text.items);
    try expect(state.cursor_pos == 0);

    // 7. Backspace until empty
    state.cursor_pos = 2;
    state.backspace();
    state.backspace();
    try expectEqualSlices(u8, "", state.text.items);
    try expect(state.cursor_pos == 0);

    // 8. Backspace on empty (should do nothing)
    state.backspace();
    try expectEqualSlices(u8, "", state.text.items);
    try expect(state.cursor_pos == 0);
}
