const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const TextboxState = @import("../core/types.zig").TextboxState;

const CURSOR_SIZE: f32 = 0.88;

pub const PrimitiveTextboxConfig = struct {
    id: cl.ElementId,
    state_id: u64, // Stable ID for state persistence
    text: *std.ArrayList(u8),

    // Sizing & Layout
    sizing: cl.Sizing = .{ .w = .grow, .h = .fixed(40) },
    padding: cl.Padding = .{ .left = 8, .right = 8 },
    font_size: u16 = 20,

    // Styling
    background_color: cl.Color,
    border: cl.BorderElementConfig = .{},
    corner_radius: cl.CornerRadius = .{},

    // Content Styling
    text_color: cl.Color,
    placeholder_color: cl.Color,
    cursor_color: cl.Color,

    placeholder: []const u8 = "...",
};

const InternalState = struct {
    id_hash: u64,
    text: *std.ArrayList(u8),
    ctx: *UIContext,
    font_size: u16,
};

/// Internal callback for the hover event on the textbox.
fn onHoverCallback(id: cl.ElementId, pointerInfo: cl.PointerData, internal_ptr: *InternalState) void {
    const ctx = internal_ptr.ctx;
    const text = internal_ptr.text;
    const font_size = internal_ptr.font_size;

    // Retrieve state safely (re-lookup to handle potential pointer invalidation)
    const state_ptr = ctx.getWidgetState(internal_ptr.id_hash, .{ .textbox = .{} }) catch return;
    const state = &state_ptr.textbox;

    // Change the mouse cursor to the I-beam to indicate text input.
    ctx.input.setMouseCursor(.ibeam);

    // If pressed -> set focus and move cursor
    if (pointerInfo.state == .pressed_this_frame) {
        ctx.focused_id = id;

        // Move cursor to click position
        const element_box = cl.getElementData(id).bounding_box;
        const text_padding: f32 = 8;
        const click_x_relative = (pointerInfo.position.x - element_box.x - text_padding) + state.scroll_offset_x;

        if (ctx.measure_text_fn) |measure_fn| {
            var config: cl.TextElementConfig = .{ .font_size = font_size };
            var last_char_x: f32 = 0;
            var new_cursor_pos: u32 = 0;

            for (text.items, 0..) |char, i| {
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

pub fn render(ctx: *UIContext, config: PrimitiveTextboxConfig) !void {
    const id = config.id;
    const text = config.text;

    // Retrieve/Init State
    const state_ptr = try ctx.getWidgetState(config.state_id, .{ .textbox = .{} });
    const state = &state_ptr.textbox;

    // We create a temporary struct to pass context to the callback
    const internal_ptr = ctx.frame_allocator.create(InternalState) catch return;
    internal_ptr.* = .{
        .id_hash = config.state_id,
        .text = text,
        .ctx = ctx,
        .font_size = config.font_size,
    };

    const is_focused = ctx.focused_id != null and ctx.focused_id.?.id == id.id;

    // Register for focus navigation
    ctx.registerFocusable(id);

    // Handle keyboard input only if this textbox is focused.
    if (is_focused) {
        while (true) {
            const char_code = ctx.input.getCharPressed();
            if (char_code == 0) break;

            if (char_code >= 32 and char_code <= 125) { // Basic ASCII range
                const char = @as(u8, @intCast(char_code));
                // Insert char
                if (state.cursor_pos <= text.items.len) {
                    text.insert(ctx.allocator, state.cursor_pos, char) catch {};
                    state.cursor_pos += 1;
                }
            }
        }

        // Handle ACTIONS
        if (ctx.input.getKey(.backspace).isRepeated()) {
            if (state.cursor_pos > 0 and text.items.len > 0) {
                _ = text.orderedRemove(state.cursor_pos - 1);
                state.cursor_pos -= 1;
            }
        }

        if (ctx.input.getKey(.delete).isRepeated()) {
            if (state.cursor_pos < text.items.len) {
                _ = text.orderedRemove(state.cursor_pos);
            }
        }

        if (ctx.input.getKey(.right).isRepeated()) {
            if (state.cursor_pos < text.items.len) {
                state.cursor_pos += 1;
            }
        }
        if (ctx.input.getKey(.left).isRepeated()) {
            if (state.cursor_pos > 0) {
                state.cursor_pos -= 1;
            }
        }
    }

    // Clamp cursor pos (safety check in case external text changed)
    if (state.cursor_pos > text.items.len) {
        state.cursor_pos = @intCast(text.items.len);
    }

    // Scroll view to keep cursor visible
    if (ctx.measure_text_fn) |measure_fn| {
        const textbox_width = cl.getElementData(id).bounding_box.width;
        if (textbox_width > 0) {
            var text_config: cl.TextElementConfig = .{ .font_size = config.font_size };
            // Handle empty text case for measurement
            const cursor_slice = if (state.cursor_pos > 0) text.items[0..state.cursor_pos] else "";
            const cursor_x_pos = measure_fn(cursor_slice, &text_config, {}).w;

            const padding: f32 = 8;
            const view_start_x = state.scroll_offset_x;
            const view_end_x = state.scroll_offset_x + textbox_width - (padding * 2);

            if (cursor_x_pos < view_start_x + padding) {
                state.scroll_offset_x = cursor_x_pos - padding;
            } else if (cursor_x_pos > view_end_x) {
                state.scroll_offset_x = cursor_x_pos - textbox_width + (padding * 2);
            }

            // Clamp scroll offset
            const max_text_dim = measure_fn(text.items, &text_config, {});
            const max_scroll = if (max_text_dim.w > textbox_width) max_text_dim.w - textbox_width + padding else 0;
            if (state.scroll_offset_x > max_scroll) {
                state.scroll_offset_x = max_scroll;
            }
            if (state.scroll_offset_x < 0) {
                state.scroll_offset_x = 0;
            }
        }
    }

    cl.UI()(.{
        .id = id,
        .layout = .{
            .direction = .left_to_right,
            .sizing = config.sizing,
            .padding = config.padding,
        },
        .background_color = config.background_color,
        .border = config.border,
        .corner_radius = config.corner_radius,
    })({
        cl.UI()(.{
            .layout = .{ .sizing = .grow, .child_alignment = .{ .y = .center } },
            .clip = .{ .horizontal = true, .child_offset = .{ .x = -state.scroll_offset_x, .y = 0 } },
        })({
            // If the textbox is empty and not focused, show the placeholder.
            if (text.items.len == 0 and !is_focused) {
                cl.text(config.placeholder, .{
                    .font_size = config.font_size,
                    .color = config.placeholder_color,
                    .wrap_mode = .none,
                });
            } else {
                // --- Cursor Rendering Logic ---
                // 1. Text before the cursor
                if (state.cursor_pos > 0) {
                    cl.text(text.items[0..state.cursor_pos], .{
                        .font_size = config.font_size,
                        .color = config.text_color,
                        .wrap_mode = .none,
                    });
                }

                // 2. The cursor itself
                const show_cursor = @mod(ctx.anim_timer, 1.0) < 0.5;

                if (is_focused and show_cursor) {
                    cl.UI()(.{
                        .layout = .{ .sizing = .{ .w = .fixed(2), .h = .fixed(@as(f32, @floatFromInt(config.font_size)) * CURSOR_SIZE) } },
                        .background_color = config.cursor_color,
                    })({});
                }

                // 3. Text after the cursor
                if (state.cursor_pos < text.items.len) {
                    cl.text(text.items[state.cursor_pos..], .{
                        .font_size = config.font_size,
                        .color = config.text_color,
                        .wrap_mode = .none,
                    });
                }
            }
        });
        // Register the internal hover callback
        cl.onHover(*InternalState, internal_ptr, onHoverCallback);
    });
}
