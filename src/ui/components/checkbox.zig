const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const PrimitiveToggle = @import("../primitives/toggle.zig");

pub const Variant = enum {
    primary,
    secondary,
    accent,
    danger,
    success,
};

pub const Options = struct {
    checked: bool,
    label: ?[]const u8 = null,
    is_disabled: bool = false,
    variant: Variant = .primary,
};

pub fn render(ctx: *UIContext, id: cl.ElementId, opts: Options) !bool {
    const theme = ctx.theme;

    // 1. Resolve Colors
    const ColorPair = struct { main: cl.Color, content: cl.Color };
    const colors: ColorPair = switch (opts.variant) {
        .primary => .{ .main = theme.color_primary, .content = theme.color_primary_content },
        .secondary => .{ .main = theme.color_second, .content = theme.color_second_content },
        .accent => .{ .main = theme.color_accent, .content = theme.color_accent_content },
        .danger => .{ .main = theme.color_error, .content = theme.color_error_content },
        .success => .{ .main = theme.color_success, .content = theme.color_success_content },
    };

    var track_color: cl.Color = undefined;
    var indicator_color: cl.Color = undefined;
    var border_color: cl.Color = undefined;

    if (opts.checked) {
        track_color = colors.main;
        border_color = colors.main;
        indicator_color = colors.content;
    } else {
        track_color = .{ 0, 0, 0, 0 };
        border_color = theme.color_neutral;
        indicator_color = theme.color_base_content;
    }

    if (opts.is_disabled) {
        track_color = theme.color_base_200;
        border_color = theme.color_base_200;
        indicator_color = theme.color_base_content;
    }

    // 2. Render
    var clicked = false;
    var is_focused = false;

    if (ctx.focused_id) |focused| {
        if (focused.id == id.id) is_focused = true;
    }

    if (is_focused) {
        border_color = theme.color_accent;
    }

    if (opts.label) |text| {
        cl.UI()(.{ .layout = .{
            .direction = .left_to_right,
            .child_gap = 8,
            .child_alignment = .{ .y = .center },
        } })({
            const result = try PrimitiveToggle.render(ctx, .{
                .id = id,
                .state_id = id.id,
                .checked = opts.checked,
                .is_disabled = opts.is_disabled,
                .mode = .checkbox,
                .width = 20,
                .height = 20,
                .track_color = track_color,
                .indicator_color = indicator_color,
                .border = .{ .width = .all(2), .color = border_color },
                .corner_radius = .all(theme.radius_box),
            });
            clicked = result.clicked;

            cl.text(text, .{
                .font_size = 20,
                .color = if (opts.is_disabled) theme.color_neutral else theme.color_base_content,
            });
        });
    } else {
        const result = try PrimitiveToggle.render(ctx, .{
            .id = id,
            .state_id = id.id,
            .checked = opts.checked,
            .is_disabled = opts.is_disabled,
            .mode = .checkbox,
            .width = 20,
            .height = 20,
            .track_color = track_color,
            .indicator_color = indicator_color,
            .border = .{ .width = .all(2), .color = border_color },
            .corner_radius = .all(theme.radius_box),
        });
        clicked = result.clicked;
    }

    return clicked;
}
