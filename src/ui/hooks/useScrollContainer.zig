/// A headless hook that encapsulates all the logic for a virtualized scroll container.
///
/// This component contains NO rendering logic. It is a pure logic function that you
/// call at the beginning of your component's render pass. It handles scroll input
/// (mouse wheel, drag), calculates virtualization ranges, and returns a struct
/// (`ScrollLayout`) with all the necessary data for the caller to render the UI.
const std = @import("std");
const rl = @import("raylib");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;

/// Configuration options for the scroll container logic.
pub const Options = struct {
    total_content_dims: cl.Dimensions,
    item_height: f32,
    enable_vertical_scroll: bool = true,
    enable_horizontal_scroll: bool = false,
    scrollbar_width: f32 = 12,
    scrollbar_height: f32 = 12,
};

/// Holds the persistent scrolling state for the container.
/// This is owned and managed by the parent UI.
pub const State = struct {
    scroll_offset: cl.Vector2 = .{ .x = 0, .y = 0 },
    is_dragging_thumb_y: bool = false,
    drag_start_mouse_y: f32 = 0,
    drag_start_scroll_y: f32 = 0,
    is_dragging_thumb_x: bool = false,
    drag_start_mouse_x: f32 = 0,
    drag_start_scroll_x: f32 = 0,
};

pub const Scrollbar = struct {
    is_needed: bool,
    track_id: cl.ElementId,
    thumb_id: cl.ElementId,
    thumb_axis: f32,
    thumb_size: f32,
};

/// This struct holds all the data the caller needs to render the layout.
pub const ScrollLayout = struct {
    child_offset: cl.Vector2,
    first_visible_item: usize,
    last_visible_item: usize,
    top_spacer_height: f32,
    bottom_spacer_height: f32,
    viewport_dims: cl.Dimensions,

    v_scrollbar: Scrollbar,
    h_scrollbar: Scrollbar,
};

pub fn useScrollContainer(
    ctx: *UIContext,
    id: cl.ElementId,
    state: *State,
    options: Options,
    mouse_wheel: cl.Vector2,
) ScrollLayout {
    const viewport_box = cl.getElementData(id).bounding_box;

    const v_scroll_needed = options.enable_vertical_scroll and options.total_content_dims.h > viewport_box.height;
    const h_scroll_needed = options.enable_horizontal_scroll and options.total_content_dims.w > viewport_box.width;

    const viewport_width = if (v_scroll_needed) viewport_box.width - options.scrollbar_width - 4 else viewport_box.width;
    const viewport_height = if (h_scroll_needed) viewport_box.height - options.scrollbar_height - 4 else viewport_box.height;

    var layout: ScrollLayout = .{
        .child_offset = .{ .x = 0, .y = 0 },
        .first_visible_item = 0,
        .last_visible_item = 0,
        .top_spacer_height = 0,
        .bottom_spacer_height = 0,
        .viewport_dims = .{ .w = viewport_width, .h = viewport_height },
        .v_scrollbar = .{ .is_needed = v_scroll_needed, .track_id = cl.ElementId.localID("v_track"), .thumb_id = cl.ElementId.localID("v_thumb"), .thumb_axis = 0, .thumb_size = 0 },
        .h_scrollbar = .{ .is_needed = h_scroll_needed, .track_id = cl.ElementId.localID("h_track"), .thumb_id = cl.ElementId.localID("h_thumb"), .thumb_axis = 0, .thumb_size = 0 },
    };

    // --- Input Handling ---
    if (cl.pointerOver(id) and rl.isMouseButtonPressed(.left)) {
        ctx.focused_id = id;
    }

    if (ctx.input.getMouse().left_button.isReleased()) {
        if (state.is_dragging_thumb_y) {
            state.is_dragging_thumb_y = false;
            ctx.active_id = null;
        }
        if (state.is_dragging_thumb_x) {
            state.is_dragging_thumb_x = false;
            ctx.active_id = null;
        }
    }

    // Vertical scrollbar interaction
    if (v_scroll_needed) {
        if (cl.pointerOver(layout.v_scrollbar.thumb_id) and rl.isMouseButtonPressed(.left)) {
            state.is_dragging_thumb_y = true;
            state.drag_start_mouse_y = ctx.input.getMouse().pos.y;
            state.drag_start_scroll_y = state.scroll_offset.y;
            ctx.active_id = layout.v_scrollbar.thumb_id;
        } else if (cl.pointerOver(layout.v_scrollbar.track_id) and rl.isMouseButtonPressed(.left)) {
            if (!state.is_dragging_thumb_y) {
                const thumb_h = @max(20, viewport_height * (viewport_height / options.total_content_dims.h));
                const click_y_relative = ctx.input.getMouse().pos.y - cl.getElementData(layout.v_scrollbar.track_id).bounding_box.y;
                const scroll_ratio = (click_y_relative - (thumb_h / 2)) / (viewport_height - thumb_h);
                state.scroll_offset.y = scroll_ratio * (options.total_content_dims.h - viewport_height);
            }
        }
    }

    // TODO: Horizontal scrollbar interaction

    if (state.is_dragging_thumb_y) {
        const mouse_delta_y = ctx.input.getMouse().pos.y - state.drag_start_mouse_y;
        const scroll_ratio = if (viewport_height > 0) options.total_content_dims.h / viewport_height else 1.0;
        state.scroll_offset.y = state.drag_start_scroll_y + (mouse_delta_y * scroll_ratio);
    } else if (cl.pointerOver(id)) {
        if (v_scroll_needed) {
            state.scroll_offset.y -= mouse_wheel.y;
        }
        if (h_scroll_needed) {
            state.scroll_offset.x -= mouse_wheel.x;
        }
    }

    if (v_scroll_needed) {
        const max_scroll = options.total_content_dims.h - viewport_height;
        state.scroll_offset.y = std.math.clamp(state.scroll_offset.y, 0, max_scroll);
    }
    if (h_scroll_needed) {
        const max_scroll = options.total_content_dims.w - viewport_width;
        state.scroll_offset.x = std.math.clamp(state.scroll_offset.x, 0, max_scroll);
    }

    layout.child_offset = .{ .x = -state.scroll_offset.x, .y = -state.scroll_offset.y };

    // --- Virtualization Logic ---
    if (options.item_height > 0 and v_scroll_needed) {
        const total_items = @as(usize, @intFromFloat(options.total_content_dims.h / options.item_height));
        layout.first_visible_item = @intFromFloat(@floor(state.scroll_offset.y / options.item_height));
        layout.last_visible_item = layout.first_visible_item + @as(usize, @intFromFloat(@ceil(viewport_height / options.item_height))) + 1;
        if (layout.last_visible_item > total_items) {
            layout.last_visible_item = total_items;
        }
        layout.top_spacer_height = @as(f32, @floatFromInt(layout.first_visible_item)) * options.item_height;
        const total_items_f: f32 = options.total_content_dims.h / options.item_height;
        layout.bottom_spacer_height = (total_items_f - @as(f32, @floatFromInt(layout.last_visible_item))) * options.item_height;
    } else {
        // If not virtualizing (the content fits), we show all items.
        // We have to calculate the total amout of items because we dont have access to the caller of this hook (as thus we dont know how many items there are)
        const total_items = if (options.item_height > 0) @as(usize, @intFromFloat(@round(options.total_content_dims.h / options.item_height))) else 0;
        layout.first_visible_item = 0;
        layout.last_visible_item = total_items;
    }

    // --- Scrollbar Render Data ---
    if (v_scroll_needed) {
        layout.v_scrollbar.thumb_size = @max(20, viewport_height * (viewport_height / options.total_content_dims.h));
        const max_thumb_y = viewport_height - layout.v_scrollbar.thumb_size;
        const scroll_ratio = if (options.total_content_dims.h > viewport_height) state.scroll_offset.y / (options.total_content_dims.h - viewport_height) else 0;
        layout.v_scrollbar.thumb_axis = scroll_ratio * max_thumb_y;
    }

    // TODO: Horizontal scrollbar render data

    return layout;
}

/// Adjusts the vertical scroll offset to ensure the selected item is in view.
pub fn ensureSelectionIsVisible(state: *State, selected_index: usize, item_height: f32, viewport_height: f32) void {
    const item_y_start = @as(f32, @floatFromInt(selected_index)) * item_height;
    const item_y_end = item_y_start + item_height;

    const view_y_start = state.scroll_offset.y;
    const view_y_end = state.scroll_offset.y + viewport_height;

    if (item_y_start < view_y_start) {
        state.scroll_offset.y = item_y_start;
    } else if (item_y_end > view_y_end) {
        state.scroll_offset.y = item_y_end - viewport_height;
    }
}
