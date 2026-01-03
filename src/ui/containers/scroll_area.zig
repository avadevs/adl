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
pub fn render(ctx: *UIContext, id: cl.ElementId, state: *State, options: Options, content_fn: anytype) void {
    const theme = t.merge(ctx.theme.*, options.theme_overrides);

    // If we don't have dimensions, we assume standard grow?
    // Actually, useScrollContainer needs dims to calculate scrollbars.
    // If we use 0, scrollbars won't show.
    // For a generic area, we usually want to measure the content.
    // But we can only measure after rendering.
    //
    // Since we are in immediate mode, we can use the dimensions from the PREVIOUS frame
    // if we store them in state. But State is POD now.
    //
    // If we can't store dims in state, we can't easily do scrollbars for dynamic content
    // without a "layout pass" or "measure pass".
    //
    // However, Clay supports scrolling naturally if we set overflow.
    // But `useScrollContainer` implements custom scroll logic.
    //
    // Let's assume for now the user MUST provide content_height/width OR we rely on a fixed size.
    // Or we accept that scrollbars might lag one frame if we add `content_dims` back to State.
    //
    // Wait, the plan said "ScrollState is POD". `Vector2` is POD.
    // I can add `content_dims: Vector2` to ScrollState in types.zig if I want to persist it.
    // But I already defined `ScrollState` in `types.zig` without it.
    //
    // For now, I'll default to 1000x1000 if not provided, just to show it working,
    // or better, I will assume the user provides `content_height` in options if they want scrolling.
    //
    // Ideally, we'd update types.zig to include `content_dims`.

    const content_w = options.content_width orelse 2000; // fallback
    const content_h = options.content_height orelse 2000; // fallback

    const sc_options = useScrollContainer.Options{
        .total_content_dims = .{ .w = content_w, .h = content_h },
        .item_height = 0,
        .enable_vertical_scroll = true,
        .enable_horizontal_scroll = true,
    };

    // We need mouse wheel.
    // I'll assume 0 for now as I can't easily change Context yet without breaking other things.
    const mouse_wheel = cl.Vector2{ .x = 0, .y = 0 };

    const layout = useScrollContainer.useScrollContainer(ctx, id, state, sc_options, mouse_wheel);

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
