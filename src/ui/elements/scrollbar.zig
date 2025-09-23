/// A purely presentational component for rendering a vertical or horizontal scrollbar.
///
/// This component is "dumb" and contains no logic. It simply renders a track and
/// a thumb based on the data provided to it, which should be calculated by a
/// headless hook like `useScrollContainer`.
const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const scrollContainerHook = @import("../hooks/useScrollContainer.zig");

/// Renders a vertical scrollbar.
pub fn vertical(
    ctx: *UIContext,
    width: f32,
    data: scrollContainerHook.Scrollbar,
) void {
    const theme = ctx.theme;

    if (!data.is_needed) return;

    cl.UI()(.{
        .id = data.track_id,
        .layout = .{ .sizing = .{ .w = .fixed(width), .h = .grow }, .direction = .top_to_bottom },
        .background_color = theme.color_base_200,
        .corner_radius = .all(6),
    })({
        // Spacer to push the thumb down.
        cl.UI()(.{ .layout = .{ .sizing = .{ .h = .fixed(data.thumb_axis) } } })({});

        // The scrollbar thumb.
        cl.UI()(.{
            .id = data.thumb_id,
            .layout = .{ .sizing = .{ .w = .grow, .h = .fixed(data.thumb_size) } },
            .background_color = theme.color_primary,
            .corner_radius = .all(6),
        })({});
    });
}

/// Renders a horizontal scrollbar.
pub fn horizontal(
    ctx: *UIContext,
    height: f32,
    data: scrollContainerHook.Scrollbar,
) void {
    const theme = ctx.theme;

    if (!data.is_needed) return;

    cl.UI()(.{
        .id = data.track_id,
        .layout = .{ .sizing = .{ .h = .fixed(height), .w = .grow }, .direction = .left_to_right },
        .background_color = theme.color_base_200,
        .corner_radius = .all(6),
    })({
        // Spacer to push the thumb right.
        cl.UI()(.{ .layout = .{ .sizing = .{ .w = .fixed(data.thumb_axis) } } })({});

        // The scrollbar thumb.
        cl.UI()(.{
            .id = data.thumb_id,
            .layout = .{ .sizing = .{ .h = .grow, .w = .fixed(data.thumb_size) } },
            .background_color = theme.color_primary,
            .corner_radius = .all(6),
        })({});
    });
}
