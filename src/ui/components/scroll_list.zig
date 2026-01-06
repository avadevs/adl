const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const element = @import("../core/element.zig");
const useScrollContainer = @import("../hooks/useScrollContainer.zig");
const PrimitiveScrollView = @import("../primitives/scroll_view.zig");
const types = @import("../core/types.zig");
const t = @import("../core/theme.zig");

pub const Options = struct {
    item_height: f32 = 28,
    font_size: u16 = 20,
    scrollbar_width: f32 = 12,
    theme_overrides: ?t.ThemeOverrides = null,
};

/// The main object returned by `beginList`.
/// User uses this to iterate visible items and handle selection.
pub const ListWalker = struct {
    ctx: *UIContext,
    state: *types.ScrollListState,
    layout: useScrollContainer.ScrollLayout,
    sv_state: PrimitiveScrollView.State,
    options: Options,
    total_count: usize,
    id: cl.ElementId,
    theme: t.THEME,

    /// Returns an iterator over the visible item indices.
    pub fn iterator(self: *const ListWalker) ListIterator {
        return ListIterator{
            .current = self.layout.first_visible_item,
            .end = self.layout.last_visible_item,
            .total = self.total_count,
        };
    }

    /// Renders a row container and handles selection logic.
    /// Returns `true` if the row was clicked this frame.
    /// Use this inside the iterator loop.
    pub fn row(self: *const ListWalker, index: usize) bool {
        const is_selected = self.state.selected_index != null and self.state.selected_index.? == index;
        const row_id = cl.ElementId.localIDI(self.id.string_id.chars[0..@intCast(self.id.string_id.length)], @intCast(index));

        // --- Interaction Check (Before Layout) ---
        const is_actually_hovered = cl.pointerOver(row_id);
        const final_bg = if (is_selected) self.theme.color_primary else if (is_actually_hovered) self.theme.color_base_300 else self.theme.color_base_100;

        var clicked = false;

        // Render Row Container (Open)
        element.open(.{
            .id = row_id,
            .layout = .{
                .direction = .left_to_right,
                .sizing = .{ .w = .grow, .h = .fixed(self.options.item_height) },
                .child_alignment = .{ .y = .center },
                .padding = .{ .left = 8, .right = 8 },
            },
            .background_color = final_bg,
        });

        if (is_actually_hovered and self.ctx.input.getMouse().left_button.isPressed()) {
            self.state.selected_index = index;
            clicked = true;
        }

        return clicked;
    }

    // Helper for proper usage (must be called after row content is done)
    pub fn endRow(_: *const ListWalker) void {
        element.close();
    }
};

pub const ListIterator = struct {
    current: usize,
    end: usize,
    total: usize,

    pub fn next(self: *ListIterator) ?usize {
        if (self.current >= self.end or self.current >= self.total) return null;
        const idx = self.current;
        self.current += 1;
        return idx;
    }
};

pub fn begin(id_str: []const u8, count: usize, options: Options) !ListWalker {
    const ctx = try UIContext.getCurrent();
    const id_hash = std.hash.Wyhash.hash(0, id_str);
    const id = cl.ElementId.ID(id_str);

    // Register Focus
    ctx.registerFocusable(id);

    // State
    const state_ptr = try ctx.getWidgetState(id_hash, .{ .scroll_list = .{} });
    const state = &state_ptr.scroll_list;
    const theme = t.merge(ctx.theme.*, options.theme_overrides);

    // Check Focus
    const is_focused = ctx.focused_id != null and ctx.focused_id.?.id == id.id;
    const border_color = if (is_focused) theme.color_primary else theme.color_base_200; // Use base_200 if not focused, to hide or match bg

    // Auto-select first item if focused and nothing selected
    if (is_focused and state.selected_index == null and count > 0) {
        state.selected_index = 0;
    }

    // --- VIEWPORT OVERRIDE CALCULATION ---
    // Wrapper (H) = Border(2) + Gap(4) + Body + Border(2)
    // Overhead = 2 + 4 + 2 = 8px
    const border_w: f32 = if (is_focused) 2 else 0;
    const reserved_height = (border_w * 2) + 4;

    const main_box = cl.getElementData(id).bounding_box;
    var viewport_override: ?cl.Dimensions = null;

    if (main_box.width > 0 and main_box.height > reserved_height) {
        viewport_override = .{ .w = main_box.width - (border_w * 2) - 4, .h = main_box.height - reserved_height };
    }

    // Layout
    const sc_options = useScrollContainer.Options{
        .total_content_dims = .{ .h = @as(f32, @floatFromInt(count)) * options.item_height, .w = 0 },
        .item_height = options.item_height,
        .enable_horizontal_scroll = false,
        .scrollbar_width = options.scrollbar_width,
        .viewport_size_override = viewport_override,
    };

    const layout = useScrollContainer.useScrollContainer(ctx, id, &state.scroll, sc_options);

    // Keyboard Navigation
    if (ctx.focused_id != null and ctx.focused_id.?.id == id.id) {
        handleKeyboardInput(ctx, state, count, options.item_height, layout.viewport_dims.h);
    }

    // Start Primitive ScrollView (replaces Outer Wrapper + Clip)
    const sv_state = PrimitiveScrollView.begin(ctx, .{
        .id = id,
        .layout = layout,
        .border = .{ .width = .all(if (is_focused) 2 else 0), .color = border_color },
        .corner_radius = .all(theme.radius_box),
        .scrollbar_width = options.scrollbar_width,
    });

    // Content Container (Fixed Height for Virtualization)
    element.open(.{ // Content
        .layout = .{ .direction = .top_to_bottom, .sizing = .{ .w = .grow, .h = .fixed(sc_options.total_content_dims.h) } },
    });

    // Top Spacer
    if (layout.top_spacer_height > 0) {
        cl.UI()(.{ .layout = .{ .sizing = .{ .h = .fixed(layout.top_spacer_height) } } })({});
    }

    return ListWalker{
        .ctx = ctx,
        .state = state,
        .layout = layout,
        .sv_state = sv_state,
        .options = options,
        .total_count = count,
        .id = id,
        .theme = theme,
    };
}

pub fn end(walker: ListWalker) void {
    // Bottom Spacer
    if (walker.layout.bottom_spacer_height > 0) {
        cl.UI()(.{ .layout = .{ .sizing = .{ .h = .fixed(walker.layout.bottom_spacer_height) } } })({});
    }

    element.close(); // Close Content Container

    // End Primitive ScrollView (Closes Clip, renders Scrollbars, closes Wrapper)
    PrimitiveScrollView.end(walker.sv_state);
}

// Logic helper
fn handleKeyboardInput(
    ctx: *UIContext,
    state: *types.ScrollListState,
    items_len: usize,
    item_height: f32,
    viewport_height: f32,
) void {
    if (items_len == 0) return;

    var selection_changed = false;
    const current_index: usize = if (state.selected_index) |idx| idx else 0;

    if (ctx.input.getKey(.down).isRepeated()) {
        state.selected_index = @min(current_index + 1, items_len - 1);
        selection_changed = true;
    } else if (ctx.input.getKey(.up).isRepeated()) {
        if (current_index > 0) {
            state.selected_index = current_index - 1;
        }
        selection_changed = true;
    } else if (ctx.input.getKey(.home).isPressed()) {
        state.selected_index = 0;
        selection_changed = true;
    } else if (ctx.input.getKey(.end).isPressed()) {
        state.selected_index = items_len - 1;
        selection_changed = true;
    } else if (ctx.input.getKey(.page_down).isRepeated()) {
        const items_per_page = @as(usize, @intFromFloat(@floor(viewport_height / item_height)));
        state.selected_index = @min(current_index + items_per_page, items_len - 1);
        selection_changed = true;
    } else if (ctx.input.getKey(.page_up).isRepeated()) {
        const items_per_page = @as(usize, @intFromFloat(@floor(viewport_height / item_height)));
        state.selected_index = if (current_index > items_per_page) current_index - items_per_page else 0;
        selection_changed = true;
    }

    if (selection_changed and state.selected_index != null) {
        useScrollContainer.ensureSelectionIsVisible(&state.scroll, state.selected_index.?, item_height, viewport_height);
    }
}
