const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const useScrollContainer = @import("../hooks/useScrollContainer.zig");
const scrollbar = @import("../elements/scrollbar.zig");
const element = @import("../core/element.zig");

pub const Config = struct {
    id: cl.ElementId,
    layout: useScrollContainer.ScrollLayout,

    // Styling
    background_color: cl.Color = .{ 0, 0, 0, 0 },
    border: cl.BorderElementConfig = .{},
    corner_radius: cl.CornerRadius = .{},

    // Scrollbar dimensions
    scrollbar_width: f32 = 12,
    scrollbar_height: f32 = 12,
};

pub const State = struct {
    ctx: *UIContext,
    layout: useScrollContainer.ScrollLayout,
    scrollbar_width: f32,
    scrollbar_height: f32,
};

pub fn begin(ctx: *UIContext, config: Config) State {
    // 1. Outer Wrapper (Row) - Holds [ContentCol, VScrollbar]
    element.open(.{
        .id = config.id,
        .layout = .{ .direction = .left_to_right, .sizing = .grow },
        .background_color = config.background_color,
        .border = config.border,
        .corner_radius = config.corner_radius,
    });

    // 2. Inner Content Column - Holds [Clip, HScrollbar]
    element.open(.{
        .layout = .{ .direction = .top_to_bottom, .sizing = .grow },
        .background_color = .{ 0, 0, 0, 0 }, // Pass through
    });

    // 3. Clip Container
    element.open(.{
        .id = cl.ElementId.localIDI("clip", config.id.id),
        .layout = .{ .sizing = .grow },
        .clip = .{ .vertical = true, .horizontal = true, .child_offset = config.layout.child_offset },
    });

    return .{
        .ctx = ctx,
        .layout = config.layout,
        .scrollbar_width = config.scrollbar_width,
        .scrollbar_height = config.scrollbar_height,
    };
}

pub fn end(state: State) void {
    element.close(); // Close Clip Container

    // 4. Render Horizontal Scrollbar
    if (state.layout.h_scrollbar.is_needed) {
        scrollbar.horizontal(state.ctx, state.scrollbar_height, state.layout.h_scrollbar);
    }

    element.close(); // Close Inner Content Column

    // 5. Render Vertical Scrollbar
    if (state.layout.v_scrollbar.is_needed) {
        scrollbar.vertical(state.ctx, state.scrollbar_width, state.layout.v_scrollbar);
    }

    element.close(); // Close Outer Wrapper
}
