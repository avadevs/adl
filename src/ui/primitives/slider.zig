const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;

pub const Config = struct {
    id: cl.ElementId,
    value: f32, // Normalized 0.0 to 1.0

    // Visuals
    width: cl.SizingAxis = .grow,
    height: f32 = 20,
    track_color: cl.Color,
    thumb_color: cl.Color,
    thumb_highlight_color: cl.Color,
    corner_radius: f32 = 4,
    thumb_width: f32 = 16,
    disabled: bool = false,
    keyboard_step: f32 = 0.01,
};

pub const State = struct {
    value: f32,
    changed: bool,
    hovered: bool,
    dragging: bool,
};

pub fn render(ctx: *UIContext, config: Config) State {
    const id = config.id;
    const is_hovered = cl.pointerOver(id);
    var is_dragging = false;
    var is_focused = false;
    var new_value = config.value;
    var changed = false;

    if (!config.disabled) {
        // Register for keyboard navigation
        ctx.registerFocusable(id);

        if (ctx.focused_id) |focused| {
            if (focused.id == id.id) is_focused = true;
        }

        // Mouse Input Handling
        if (is_hovered and ctx.input.getMouse().left_button.isPressed()) {
            ctx.active_id = id;
            ctx.focused_id = id;
            is_focused = true;
        }

        // Keyboard Input Handling
        if (is_focused) {
            // Arrow keys for fine adjustment (approx 5% per keypress)
            // Ideally, step size should be configurable or passed down, but for a primitive
            // operating in 0.0-1.0 space, a small delta is reasonable.
            // Holding shift could make it faster.
            var delta: f32 = config.keyboard_step;
            if (ctx.input.getKey(.left_shift).is_down or ctx.input.getKey(.right_shift).is_down) {
                delta *= 10.0;
            }

            if (ctx.input.getKey(.left).isRepeated()) {
                new_value = std.math.clamp(new_value - delta, 0.0, 1.0);
                changed = true;
            }
            if (ctx.input.getKey(.right).isRepeated()) {
                new_value = std.math.clamp(new_value + delta, 0.0, 1.0);
                changed = true;
            }
        }

        if (ctx.active_id) |active| {
            if (active.id == id.id) {
                is_dragging = true;

                // Calculate value
                const mouse_x = ctx.input.getMouse().pos.x;
                const bbox = cl.getElementData(id).bounding_box;

                // We want the thumb center to follow the mouse, but clamped within the track.
                // Usable track length = bbox.width - config.thumb_width.
                // Left edge of thumb position = value * usable_length.

                if (bbox.width > config.thumb_width) {
                    const usable_width = bbox.width - config.thumb_width;

                    // Mouse position relative to the start of the draggable area (left edge + half thumb)
                    // relative_x is where the left edge of the thumb should be ideally (mouse_x - half_thumb)
                    // normalized relative to the track start (bbox.x)

                    const mouse_relative = mouse_x - bbox.x;
                    const thumb_half = config.thumb_width / 2.0;

                    // We want: mouse_x corresponds to center of thumb.
                    // thumb_center = bbox.x + (value * usable_width) + thumb_half
                    // value = (thumb_center - bbox.x - thumb_half) / usable_width
                    //       = (mouse_x - bbox.x - thumb_half) / usable_width

                    const val = (mouse_relative - thumb_half) / usable_width;

                    new_value = std.math.clamp(val, 0.0, 1.0);

                    if (new_value != config.value) {
                        changed = true;
                    }
                }
            }
        }

        if (is_dragging and ctx.input.getMouse().left_button.isReleased()) {
            ctx.active_id = null;
            is_dragging = false;
        }
    }

    // Render
    const thumb_col = if (is_dragging or is_hovered or is_focused) config.thumb_highlight_color else config.thumb_color;

    // Get layout from previous frame for rendering current frame spacer
    const bbox = cl.getElementData(id).bounding_box;
    const usable_width = if (bbox.width > config.thumb_width) bbox.width - config.thumb_width else 0;
    const spacer_width = usable_width * new_value;

    cl.UI()(.{
        .id = id,
        .layout = .{
            .sizing = .{ .w = config.width, .h = .fixed(config.height) },
            .direction = .left_to_right,
            .child_alignment = .{ .y = .center },
        },
        .background_color = config.track_color,
        .corner_radius = .all(config.corner_radius),
        .border = if (is_hovered or is_dragging or is_focused) .{ .width = .all(2), .color = config.thumb_highlight_color } else .{},
    })({

        // Spacer
        cl.UI()(.{ .layout = .{ .sizing = .{ .w = .fixed(spacer_width), .h = .grow } } })({});

        // Thumb
        cl.UI()(.{
            .id = cl.ElementId.localIDI("thumb", id.id),
            .layout = .{ .sizing = .{ .w = .fixed(config.thumb_width), .h = .fixed(config.height - 6) } },
            .background_color = thumb_col,
            .corner_radius = .all(config.corner_radius - 2),
        })({});
    });

    return .{ .value = new_value, .changed = changed, .hovered = is_hovered, .dragging = is_dragging };
}
