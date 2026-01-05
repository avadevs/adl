const std = @import("std");
const cl = @import("zclay");
const t = @import("../core/theme.zig");
const UIContext = @import("../core/context.zig").UIContext;
const PrimitiveTextbox = @import("../primitives/textbox.zig");

pub const Options = struct {
    placeholder: []const u8 = "...",
    font_size: u16 = 20,
    theme_overrides: ?t.ThemeOverrides = null,
};

pub fn render(id_str: []const u8, text: *std.ArrayList(u8), options: Options) !void {
    const ctx = try UIContext.getCurrent();
    const id_hash = std.hash.Wyhash.hash(0, id_str);
    const id = cl.ElementId.ID(id_str);

    // Determine theme
    const theme = t.merge(ctx.theme.*, options.theme_overrides);

    const is_focused = ctx.focused_id != null and ctx.focused_id.?.id == id.id;
    const is_hovered = cl.pointerOver(id);

    // Determine colors
    const border_color = if (is_focused) theme.color_primary else theme.color_base_300;
    const bg_color = if (is_hovered) theme.color_base_200 else theme.color_base_100;
    
    var placeholder_color = theme.color_base_content;
    placeholder_color[3] = 150; // Make it semi-transparent

    const config = PrimitiveTextbox.PrimitiveTextboxConfig{
        .id = id,
        .state_id = id_hash,
        .text = text,
        
        .sizing = .{ .w = .grow, .h = .fixed(40) },
        .padding = .{ .left = 8, .right = 8 },
        .font_size = options.font_size,
        
        .background_color = bg_color,
        .border = .{ .width = .all(theme.border), .color = border_color },
        .corner_radius = .all(theme.radius_field),
        
        .text_color = theme.color_base_content,
        .placeholder_color = placeholder_color,
        .cursor_color = theme.color_primary,
        
        .placeholder = options.placeholder,
    };

    try PrimitiveTextbox.render(ctx, config);
}
