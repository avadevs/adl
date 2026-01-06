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

    // Switch Visuals
    // Off: Track = neutral/base_300, Knob = base_content
    // On:  Track = variant.main, Knob = variant.content (or white usually)

    if (opts.checked) {
        track_color = colors.main;
        indicator_color = colors.content;
        border_color = colors.main;
    } else {
        track_color = theme.color_base_300; // Dim track when off
        indicator_color = theme.color_base_content; // Light knob
        border_color = theme.color_base_300;
    }

    if (opts.is_disabled) {
        track_color = theme.color_base_200;
        indicator_color = theme.color_neutral;
        border_color = theme.color_base_200;
    }

    // Dimensions
    const height: f32 = 24;
    const width: f32 = 44;
    const radius: f32 = height / 2.0;
    var border_width: u16 = 0;

    // 2. Render
    var clicked = false;
    var is_focused = false;

    if (ctx.focused_id) |focused| {
        if (focused.id == id.id) is_focused = true;
    }

    if (is_focused) {
        border_color = theme.color_accent;
        border_width = 2;
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
                .mode = .toggle_switch,
                .width = width,
                .height = height,
                .track_color = track_color,
                .indicator_color = indicator_color,
                .border = .{ .width = .all(border_width), .color = border_color }, // Usually borderless or matches track
                .corner_radius = .all(radius),
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
            .mode = .toggle_switch,
            .width = width,
            .height = height,
            .track_color = track_color,
            .indicator_color = indicator_color,
            .border = .{ .width = .all(border_width), .color = border_color },
            .corner_radius = .all(radius),
        });
        clicked = result.clicked;
    }

    return clicked;
}
