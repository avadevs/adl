const std = @import("std");
const cl = @import("zclay");
const t = @import("../core/theme.zig");
const UIContext = @import("../core/context.zig").UIContext;
const PrimitiveButton = @import("../primitives/button.zig");

pub const Variant = enum {
    primary,
    secondary,
    accent,
    outline,
    ghost,
};

pub const Options = struct {
    text: []const u8,
    variant: Variant = .primary,
    is_disabled: bool = false,
    width: ?cl.SizingAxis = null,
};

pub fn render(ctx: *UIContext, id: cl.ElementId, opts: Options) bool {
    const theme = ctx.theme;

    // 1. Determine State (Pre-calculation for styling)
    const is_hovered = cl.pointerOver(id);
    var is_active = false;
    var is_focused = false;

    if (ctx.active_id) |active| {
        if (active.id == id.id) is_active = true;
    }
    if (ctx.focused_id) |focused| {
        if (focused.id == id.id) is_focused = true;
    }

    // 2. Resolve Colors
    var bg_color: cl.Color = undefined;
    var text_color: cl.Color = undefined;
    var border_color: cl.Color = undefined;
    const transparent = cl.Color{ 0, 0, 0, 0 };

    const SolidColors = struct { main: cl.Color, content: cl.Color };

    const colors: SolidColors = switch (opts.variant) {
        .primary, .outline, .ghost => .{ .main = theme.color_primary, .content = theme.color_primary_content },
        .secondary => .{ .main = theme.color_second, .content = theme.color_second_content },
        .accent => .{ .main = theme.color_accent, .content = theme.color_accent_content },
    };

    switch (opts.variant) {
        .primary, .secondary, .accent => {
            bg_color = colors.main;
            text_color = colors.content;
            border_color = colors.main;

            if (is_active) {
                bg_color = theme.color_base_300;
                text_color = colors.main;
            } else if (is_hovered) {
                bg_color = theme.color_base_200;
                text_color = colors.main;
            }
        },
        .outline => {
            bg_color = transparent;
            text_color = colors.main;
            border_color = colors.main;

            if (is_hovered or is_active) {
                bg_color = colors.main;
                text_color = colors.content;
            }
        },
        .ghost => {
            bg_color = transparent;
            text_color = colors.main;
            border_color = transparent;

            if (is_hovered or is_active) {
                bg_color = theme.color_base_300;
            }
        },
    }

    if (opts.is_disabled) {
        bg_color = theme.color_base_200;
        text_color = theme.color_base_content;
        border_color = theme.color_base_200;
    } else if (is_focused) {
        border_color = theme.color_accent;
    }

    // 3. Configure Primitive
    const sizing_h = opts.width orelse cl.SizingAxis.fit;
    const config = PrimitiveButton.PrimitiveButtonConfig{
        .id = id,
        .sizing = .{ .w = sizing_h, .h = .fixed(40) },
        .padding = .{ .left = 16, .right = 16 },
        .background_color = bg_color,
        .border = .{ .width = .all(theme.border), .color = border_color },
        .corner_radius = .all(theme.radius_box),
        .is_disabled = opts.is_disabled,
    };

    // 4. Content Wrapper
    const TextWrapper = struct {
        text: []const u8,
        color: cl.Color,

        pub fn render(self: @This()) void {
            cl.text(self.text, .{ .font_size = 20, .color = self.color });
        }
    };

    const state = PrimitiveButton.render(ctx, config, TextWrapper{ .text = opts.text, .color = text_color });

    return state.clicked;
}
