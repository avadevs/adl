const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const ToggleState = @import("../core/types.zig").ToggleState;

pub const ToggleMode = enum {
    checkbox,
    toggle_switch,
};

pub const PrimitiveToggleConfig = struct {
    id: cl.ElementId,
    state_id: u64,
    checked: bool,
    is_disabled: bool = false,

    mode: ToggleMode,

    // Visuals
    width: f32,
    height: f32,
    track_color: cl.Color,
    indicator_color: cl.Color, // Checkmark color (checkbox) or Knob color (switch)
    border: cl.BorderElementConfig = .{},
    corner_radius: cl.CornerRadius = .{},
};

pub const ToggleResult = struct {
    clicked: bool,
    hovered: bool,
    focused: bool,
};

pub fn render(ctx: *UIContext, config: PrimitiveToggleConfig) !ToggleResult {
    const id = config.id;

    // 1. Retrieve State
    const state_ptr = try ctx.getWidgetState(config.state_id, .{ .toggle = .{} });
    const state = &state_ptr.toggle;

    // 2. Interaction Logic
    const is_hovered = cl.pointerOver(id);
    var clicked = false;
    var is_focused = false;
    var is_active = false;

    if (!config.is_disabled) {
        ctx.registerFocusable(id);

        if (is_hovered) {
            ctx.input.setMouseCursor(.pointing_hand);
        }

        if (ctx.focused_id) |focused| {
            if (focused.id == id.id) is_focused = true;
        }

        // Mouse Interaction
        if (is_hovered and ctx.input.getMouse().left_button.isPressed()) {
            ctx.active_id = id;
            ctx.focused_id = id;
            is_active = true;
        }

        if (ctx.active_id) |active| {
            if (active.id == id.id) is_active = true;
        }

        if (is_active and ctx.input.getMouse().left_button.isReleased()) {
            if (is_hovered) {
                clicked = true;
            }
            ctx.active_id = null;
        }

        // Keyboard Interaction
        if (is_focused) {
            if (ctx.input.getKey(.enter).isPressed() or ctx.input.getKey(.space).isPressed()) {
                clicked = true;
            }
        }
    } else {
        if (is_hovered) {
            ctx.input.setMouseCursor(.not_allowed);
        }
    }

    // 3. Animation Logic
    const target: f32 = if (config.checked) 1.0 else 0.0;
    // Simple lerp: current + (target - current) * speed * dt
    const speed: f32 = 15.0;
    state.animation_value += (target - state.animation_value) * speed * ctx.delta_time;

    // Clamp to avoid overshoot/drift
    if (std.math.approxEqAbs(f32, state.animation_value, target, 0.01)) {
        state.animation_value = target;
    }

    // 4. Render
    // Determine alignment based on mode
    const alignment: cl.ChildAlignment = switch (config.mode) {
        .checkbox => .{ .x = .center, .y = .center },
        .toggle_switch => .{ .x = .left, .y = .center },
    };

    const closer = cl.UI()(.{
        .id = id,
        .layout = .{
            .sizing = .{ .w = .fixed(config.width), .h = .fixed(config.height) },
            .child_alignment = alignment,
            .direction = .left_to_right,
        },
        .background_color = config.track_color,
        .border = config.border,
        .corner_radius = config.corner_radius,
    });

    switch (config.mode) {
        .checkbox => {
            // Only render checkmark if visible enough
            if (state.animation_value > 0.1) {
                cl.text("x", .{
                    .font_size = @intFromFloat(config.height * 0.7),
                    .color = config.indicator_color,
                    .wrap_mode = .none,
                });
            }
        },
        .toggle_switch => {
            // Render Knob logic
            const padding: f32 = 2;
            const knob_size = config.height - (padding * 2);
            const track_width = config.width;

            const min_x = padding;
            const max_x = track_width - padding - knob_size;
            const current_x = min_x + (max_x - min_x) * state.animation_value;

            // Spacer to push knob
            if (current_x > 0) {
                cl.UI()(.{
                    .layout = .{ .sizing = .{ .w = .fixed(current_x), .h = .grow } },
                })({});
            }

            // Knob
            cl.UI()(.{
                .layout = .{
                    .sizing = .{ .w = .fixed(knob_size), .h = .fixed(knob_size) },
                },
                .corner_radius = .all(knob_size / 2.0),
                .background_color = config.indicator_color,
            })({});
        },
    }

    closer({});

    return ToggleResult{
        .clicked = clicked,
        .hovered = is_hovered,
        .focused = is_focused,
    };
}
