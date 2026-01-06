const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const useScrollContainer = @import("../hooks/useScrollContainer.zig");
const PrimitiveScrollView = @import("../primitives/scroll_view.zig");
const types = @import("../core/types.zig");
const t = @import("../core/theme.zig");

pub const State = types.ScrollState;

pub const Options = struct {
    vertical: bool = true,
    horizontal: bool = false,

    // If set, forces the content height (useful for virtualized lists where we know the total height)
    content_height: ?f32 = null,
    content_width: ?f32 = null,
    theme_overrides: ?t.ThemeOverrides = null,
};

pub const ScrollArea = struct {
    state: PrimitiveScrollView.State,

    pub fn end(self: ScrollArea) void {
        PrimitiveScrollView.end(self.state);
    }
};

/// Begins a scrollable area.
/// Must be closed with `area.end()`.
pub fn begin(id_str: []const u8, options: Options) !ScrollArea {
    const ctx = try UIContext.getCurrent();
    const id_hash = std.hash.Wyhash.hash(0, id_str);

    // Retrieve/Init State
    const state_ptr = try ctx.getWidgetState(id_hash, .{ .scroll_area = .{} });
    const state = &state_ptr.scroll_area;

    const theme = t.merge(ctx.theme.*, options.theme_overrides);

    // Determine content dimensions
    // If an axis is disabled, we treat the content size as 0 (it will just fit the viewport effectively for scrolling calculations)
    // If enabled, we default to 2000 if not specified.
    const content_w = if (options.horizontal) (options.content_width orelse 2000) else 0;
    const content_h = if (options.vertical) (options.content_height orelse 2000) else 0;

    const sc_options = useScrollContainer.Options{
        .total_content_dims = .{ .w = content_w, .h = content_h },
        .item_height = 0,
        .enable_vertical_scroll = options.vertical,
        .enable_horizontal_scroll = options.horizontal,
    };

    const id = cl.ElementId.ID(id_str);
    const layout = useScrollContainer.useScrollContainer(ctx, id, state, sc_options);

    const sv_state = PrimitiveScrollView.begin(ctx, .{
        .id = id,
        .layout = layout,
        .background_color = theme.color_base_100,
    });

    return ScrollArea{
        .state = sv_state,
    };
}
