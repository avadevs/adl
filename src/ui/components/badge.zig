const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const PrimitiveBadge = @import("../primitives/badge.zig");

pub const Variant = enum {
    neutral,
    primary,
    secondary,
    accent,
    outline,
    ghost,
    info,
    success,
    warning,
    failure, // 'error' is a keyword
};

pub const Size = enum {
    sm,
    md,
    lg,
};

pub const Options = struct {
    text: []const u8,
    variant: Variant = .neutral,
    size: Size = .md,
};

pub fn render(ctx: *UIContext, id: cl.ElementId, opts: Options) void {
    const theme = ctx.theme;

    // 1. Resolve Colors
    var bg_color: cl.Color = undefined;
    var text_color: cl.Color = undefined;
    var border_color: cl.Color = undefined;
    const transparent = cl.Color{ 0, 0, 0, 0 };

    const SolidColors = struct { main: cl.Color, content: cl.Color };

    const colors: SolidColors = switch (opts.variant) {
        .neutral => .{ .main = theme.color_neutral, .content = theme.color_neutral_content },
        .primary => .{ .main = theme.color_primary, .content = theme.color_primary_content },
        .secondary => .{ .main = theme.color_second, .content = theme.color_second_content },
        .accent => .{ .main = theme.color_accent, .content = theme.color_accent_content },
        .info => .{ .main = theme.color_info, .content = theme.color_info_content },
        .success => .{ .main = theme.color_success, .content = theme.color_success_content },
        .warning => .{ .main = theme.color_warning, .content = theme.color_warning_content },
        .failure => .{ .main = theme.color_error, .content = theme.color_error_content },
        .outline, .ghost => .{ .main = theme.color_base_content, .content = theme.color_base_content },
    };

    switch (opts.variant) {
        .outline => {
            bg_color = transparent;
            text_color = colors.main;
            border_color = colors.main;
        },
        .ghost => {
            bg_color = theme.color_base_200;
            text_color = theme.color_base_content;
            border_color = transparent;
        },
        else => {
            bg_color = colors.main;
            text_color = colors.content;
            border_color = colors.main;
        },
    }

    // 2. Resolve Size/Padding
    const SizeConfig = struct { font_size: u16, padding_x: u16, padding_y: u16 };
    const size_cfg: SizeConfig = switch (opts.size) {
        .sm => .{ .font_size = 12, .padding_x = 8, .padding_y = 2 },
        .md => .{ .font_size = 14, .padding_x = 12, .padding_y = 4 },
        .lg => .{ .font_size = 16, .padding_x = 16, .padding_y = 6 },
    };

    // 3. Configure Primitive
    const config = PrimitiveBadge.Config{
        .id = id,
        .sizing = .{ .w = .fit, .h = .fit },
        .padding = .{ .left = size_cfg.padding_x, .right = size_cfg.padding_x, .top = size_cfg.padding_y, .bottom = size_cfg.padding_y },
        .background_color = bg_color,
        .border = .{ .width = .all(if (opts.variant == .outline) theme.border else 0), .color = border_color },
        .corner_radius = .all(theme.radius_box),
    };

    // 4. Content Wrapper
    const TextWrapper = struct {
        text: []const u8,
        color: cl.Color,
        font_size: u16,

        pub fn render(self: @This()) void {
            cl.text(self.text, .{ .font_size = self.font_size, .color = self.color });
        }
    };

    _ = PrimitiveBadge.render(ctx, config, TextWrapper{ .text = opts.text, .color = text_color, .font_size = size_cfg.font_size });
}
