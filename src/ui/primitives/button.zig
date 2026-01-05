const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;

pub const PrimitiveButtonConfig = struct {
    id: cl.ElementId,
    sizing: cl.Sizing = .{ .w = .fit, .h = .fit },
    padding: cl.Padding = .{ .left = 16, .right = 16, .top = 8, .bottom = 8 },
    background_color: cl.Color,
    border: cl.BorderElementConfig = .{},
    corner_radius: cl.CornerRadius = .{},
    is_disabled: bool = false,
};

pub const ButtonState = struct {
    clicked: bool,
    hovered: bool,
    focused: bool,
    active: bool,
};

pub fn render(ctx: *UIContext, config: PrimitiveButtonConfig, child_content: anytype) ButtonState {
    const id = config.id;

    // 1. Determine interaction state
    const is_hovered = cl.pointerOver(id);
    var is_active = false;
    var is_focused = false;
    var clicked = false;

    if (!config.is_disabled) {
        // Register for keyboard navigation
        ctx.registerFocusable(id);

        if (is_hovered) {
            ctx.input.setMouseCursor(.pointing_hand);
        }

        // Check if focused or active based on context state
        if (ctx.focused_id) |focused| {
            if (focused.id == id.id) is_focused = true;
        }
        if (ctx.active_id) |active| {
            if (active.id == id.id) is_active = true;
        }

        // Mouse Interaction
        if (is_hovered and ctx.input.getMouse().left_button.isPressed()) {
            ctx.active_id = id;
            ctx.focused_id = id;
            is_active = true;
            is_focused = true;
        }

        // On mouse release
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
                is_active = true;
            }
        }
    } else {
        if (is_hovered) {
            ctx.input.setMouseCursor(.not_allowed);
        }
    }

    // 2. Render Layout
    const closer = cl.UI()(.{
        .id = id,
        .layout = .{
            .direction = .left_to_right,
            .sizing = config.sizing,
            .padding = config.padding,
            .child_alignment = .{ .x = .center, .y = .center },
        },
        .background_color = config.background_color,
        .border = config.border,
        .corner_radius = config.corner_radius,
    });

    // Execute child content
    // Expects a struct with a .render() method
    child_content.render();

    // Close container
    closer({});

    return .{
        .clicked = clicked,
        .hovered = is_hovered,
        .focused = is_focused,
        .active = is_active,
    };
}
