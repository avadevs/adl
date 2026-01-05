const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const useScrollContainer = @import("../hooks/useScrollContainer.zig");
const scrollbar = @import("../elements/scrollbar.zig");
const types = @import("../core/types.zig");
const t = @import("../core/theme.zig");

pub const State = types.ScrollState;

pub const Options = struct {
    // If set, forces the content height (useful for virtualized lists where we know the total height)
    content_height: ?f32 = null,
    content_width: ?f32 = null,
    theme_overrides: ?t.ThemeOverrides = null,
};

/// Renders a scrollable area.
///
/// `content_fn` is a function that renders the content inside the scroll area.
/// It must be of type `fn() void`.
pub fn render(id_str: []const u8, options: Options, content_fn: anytype) !void {
    const ctx = try UIContext.getCurrent();
    const id_hash = std.hash.Wyhash.hash(0, id_str);

    // Retrieve/Init State
    const state_ptr = try ctx.getWidgetState(id_hash, .{ .scroll_area = .{} });
    const state = &state_ptr.scroll_area;

    const theme = t.merge(ctx.theme.*, options.theme_overrides);

    const content_w = options.content_width orelse 2000; // fallback
    const content_h = options.content_height orelse 2000; // fallback

    const sc_options = useScrollContainer.Options{
        .total_content_dims = .{ .w = content_w, .h = content_h },
        .item_height = 0,
        .enable_vertical_scroll = true,
        .enable_horizontal_scroll = true,
    };

    const id = cl.ElementId.ID(id_str);
    const layout = useScrollContainer.useScrollContainer(ctx, id, state, sc_options);

    cl.UI()(.{
        .id = id,
        .layout = .{ .direction = .left_to_right, .sizing = .grow },
        .background_color = theme.color_base_100, // Use theme background
    })({
        // Content Wrapper (Clipped)
        cl.UI()(.{
            .id = cl.ElementId.localID("clip"),
            .layout = .{ .sizing = .grow },
            .clip = .{ .vertical = true, .horizontal = true, .child_offset = layout.child_offset },
        })({
            content_fn();
        });

        // Render Scrollbars
        if (layout.v_scrollbar.is_needed) {
            scrollbar.vertical(ctx, 12, layout.v_scrollbar);
        }
    });
}
