/// A virtualized, scrollable, and sortable table component.
const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const element = @import("../core/element.zig");
const useScrollContainer = @import("../hooks/useScrollContainer.zig");
const PrimitiveScrollView = @import("../primitives/scroll_view.zig");
const types = @import("../core/types.zig");
const t = @import("../core/theme.zig");

pub const Options = struct {
    row_height: f32 = 28,
    header_height: f32 = 32,
    font_size: u16 = 20,
    header_font_size: u16 = 22,
    scrollbar_width: f32 = 12,
    scrollbar_height: f32 = 12,
    theme_overrides: ?t.ThemeOverrides = null,
};

pub const Column = struct {
    name: []const u8,
    width: f32,
    alignment: cl.ChildAlignment = .{ .x = .left, .y = .center },
};

pub const TableWalker = struct {
    ctx: *UIContext,
    state: *types.ScrollTableState,
    layout: useScrollContainer.ScrollLayout,
    options: Options,
    total_count: usize,
    columns: []const Column,
    total_content_width: f32,
    id: cl.ElementId,
    theme: t.THEME,

    // Internal iteration state
    current_col_index: usize = 0,

    /// Returns an iterator over the visible row indices.
    /// Also opens the Body container hierarchy.
    pub fn iterator(self: *const TableWalker) TableIterator {
        // --- Open Body Containers using PrimitiveScrollView ---
        // This replaces the manual Body Clip opening.
        // The PrimitiveScrollView handles the V-Scrollbar (next to body) and H-Scrollbar (below body).
        const sv_state = PrimitiveScrollView.begin(self.ctx, .{
            .id = cl.ElementId.localIDI("body", self.id.id), // Use BODY ID
            .layout = self.layout,
            .background_color = .{ 0, 0, 0, 0 },
            .scrollbar_width = self.options.scrollbar_width,
            .scrollbar_height = self.options.scrollbar_height,
        });

        const total_h = @as(f32, @floatFromInt(self.total_count)) * self.options.row_height;

        // Inner Content for Virtualization
        element.open(.{
            .layout = .{ .direction = .top_to_bottom, .sizing = .{ .w = .fixed(self.total_content_width), .h = .fixed(total_h) } },
        });

        // Top Spacer
        if (self.layout.top_spacer_height > 0) {
            cl.UI()(.{ .layout = .{ .sizing = .{ .h = .fixed(self.layout.top_spacer_height) } } })({});
        }

        return TableIterator{
            .current = self.layout.first_visible_item,
            .end = self.layout.last_visible_item,
            .total = self.total_count,
            .bottom_spacer_height = self.layout.bottom_spacer_height,
            .sv_state = sv_state,
        };
    }

    /// Renders the table header.
    /// Handles sorting clicks automatically.
    pub fn header(self: *const TableWalker) void {
        const theme = self.theme;
        const total_width = self.total_content_width;

        element.open(.{ // Header Wrapper
            .id = cl.ElementId.localID("Header"),
            .layout = .{ .sizing = .{ .w = .grow, .h = .fixed(self.options.header_height) } },
            .background_color = theme.color_base_200,
            .clip = .{ .horizontal = true, .child_offset = .{ .x = self.layout.child_offset.x, .y = 0 } },
        });

        element.open(.{ // Header Content
            .id = cl.ElementId.localID("HeaderContainer"),
            .layout = .{ .direction = .left_to_right, .sizing = .{ .w = .fixed(total_width), .h = .grow } },
        });

        for (self.columns, 0..) |col, i| {
            const header_id = cl.ElementId.localIDI("header", @intCast(i));
            const is_sort_col = self.state.sort_column_index != null and self.state.sort_column_index.? == i;
            const is_hovered = cl.pointerOver(header_id);
            var clicked = false;

            if (is_hovered and self.ctx.input.getMouse().left_button.isPressed()) {
                clicked = true;
            }

            if (clicked) {
                if (is_sort_col) {
                    self.state.sort_direction = self.state.sort_direction.opposite();
                } else {
                    self.state.sort_column_index = i;
                    self.state.sort_direction = .asc;
                }
            }

            const bg_color = if (is_hovered) theme.color_base_300 else theme.color_base_200;

            cl.UI()(.{
                .id = header_id,
                .layout = .{
                    .direction = .left_to_right,
                    .sizing = .{ .w = .fixed(col.width), .h = .grow },
                    .padding = .{ .left = 8, .right = 8 },
                    .child_alignment = col.alignment,
                    .child_gap = 8,
                },
                .background_color = bg_color,
            })({
                cl.text(col.name, .{ .font_size = self.options.header_font_size, .color = theme.color_base_content });
                if (is_sort_col) {
                    const sort_char = if (self.state.sort_direction == .asc) "^" else "v";
                    cl.text(sort_char, .{ .font_size = self.options.font_size, .color = theme.color_base_content });
                }
            });
        }

        element.close(); // Header Content
        element.close(); // Header Wrapper
    }

    /// Starts a row container.
    /// Must be called inside the iterator loop.
    /// Resets the internal column index for cell rendering.
    pub fn row(self: *TableWalker, index: usize) bool {
        self.current_col_index = 0; // Reset cell cursor

        const is_selected = self.state.selected_index != null and self.state.selected_index.? == index;
        const row_id = cl.ElementId.localIDI(self.id.string_id.chars[0..@intCast(self.id.string_id.length)], @intCast(index));
        const is_actually_hovered = cl.pointerOver(row_id);
        const bg_color = if (is_selected) self.theme.color_primary else if (is_actually_hovered) self.theme.color_base_300 else self.theme.color_base_100;

        var clicked = false;

        element.open(.{
            .id = row_id,
            .layout = .{
                .direction = .left_to_right,
                .sizing = .{ .w = .grow, .h = .fixed(self.options.row_height) },
                .child_alignment = .{ .y = .center },
            },
            .background_color = bg_color,
        });

        if (is_actually_hovered and self.ctx.input.getMouse().left_button.isPressed()) {
            self.state.selected_index = index;
            clicked = true;
        }

        return clicked;
    }

    /// Closes the current row container.
    pub fn endRow(_: *const TableWalker) void {
        element.close();
    }

    /// Renders a simple text cell.
    /// Advances the column cursor.
    pub fn textCell(self: *TableWalker, text: []const u8) void {
        if (self.current_col_index >= self.columns.len) return;
        const col = self.columns[self.current_col_index];
        self.current_col_index += 1;

        cl.UI()(.{
            .layout = .{
                .sizing = .{ .w = .fixed(col.width), .h = .grow },
                .padding = .{ .left = 8, .right = 8 },
                .child_alignment = col.alignment,
            },
        })({
            cl.text(text, .{ .font_size = self.options.font_size, .color = self.theme.color_base_content });
        });
    }

    /// Renders a custom cell content.
    /// Returns a CellWalker to allow defer end().
    pub fn customCell(self: *TableWalker) CellWalker {
        if (self.current_col_index >= self.columns.len) {
            return CellWalker{};
        }
        const col = self.columns[self.current_col_index];
        self.current_col_index += 1;

        element.open(.{
            .layout = .{
                .sizing = .{ .w = .fixed(col.width), .h = .grow },
                .padding = .{ .left = 8, .right = 8 },
                .child_alignment = col.alignment,
            },
        });

        return CellWalker{ .active = true };
    }
};

pub const CellWalker = struct {
    active: bool = false,
    pub fn end(self: CellWalker) void {
        if (self.active) {
            element.close();
        }
    }
};

pub const TableIterator = struct {
    current: usize,
    end: usize,
    total: usize,
    bottom_spacer_height: f32,
    sv_state: PrimitiveScrollView.State,

    pub fn next(self: *TableIterator) ?usize {
        if (self.current >= self.end or self.current >= self.total) return null;
        const idx = self.current;
        self.current += 1;
        return idx;
    }

    pub fn deinit(self: TableIterator) void {
        // Bottom Spacer
        if (self.bottom_spacer_height > 0) {
            cl.UI()(.{ .layout = .{ .sizing = .{ .h = .fixed(self.bottom_spacer_height) } } })({});
        }
        element.close(); // Close Body Content

        PrimitiveScrollView.end(self.sv_state);
    }
};

pub fn begin(id_str: []const u8, count: usize, columns: []const Column, options: Options) !TableWalker {
    const ctx = try UIContext.getCurrent();
    const id_hash = std.hash.Wyhash.hash(0, id_str);
    const id = cl.ElementId.ID(id_str);
    const theme = t.merge(ctx.theme.*, options.theme_overrides);

    // Register Focus (Main ID)
    ctx.registerFocusable(id);

    // State (Main ID)
    const state_ptr = try ctx.getWidgetState(id_hash, .{ .scroll_table = .{} });
    const state = &state_ptr.scroll_table;

    // Check Focus
    const is_focused = ctx.focused_id != null and ctx.focused_id.?.id == id.id;
    const border_color = if (is_focused) theme.color_primary else theme.color_base_200;

    // Auto-select first item if focused and nothing selected
    if (is_focused and state.selected_index == null and count > 0) {
        state.selected_index = 0;
    }

    // Calc Width
    var total_content_width: f32 = 0;
    for (columns) |col| total_content_width += col.width;

    // --- VIEWPORT OVERRIDE CALCULATION ---
    // Calculate the actual available height for the scroll body.
    // Wrapper (H) = Border(2) + Content(4) + Header(32) + Gap(4) + Body + Border(2)
    // Overhead = 2 + 4 + 32 + 4 + 2 = 44px
    // Note: Border width depends on focus (2 or 0), but we should probably assume worst case or current case.
    // Let's use current case.
    const border_w: f32 = if (is_focused) 2 else 0;
    const reserved_height = (border_w * 2) + 4 + options.header_height + 4;

    const main_box = cl.getElementData(id).bounding_box;
    var viewport_override: ?cl.Dimensions = null;

    if (main_box.width > 0 and main_box.height > reserved_height) {
        viewport_override = .{
            .w = main_box.width - (border_w * 2) - 8, // Width overhead: Border(2*2) + Gap(4) ? No, Gap is child_gap. Wrapper is LR. Gap is 4.
            // Wrapper LR: Border | Gap | Content | Border.
            // Actually ScrollTable wrapper is:
            // .layout = .{ .direction = .left_to_right, .child_gap = 4 }
            // Content is inside.
            // So Width = MainW - Borders - Gap?
            // Wait, ScrollBar is vertical.
            .h = main_box.height - reserved_height,
        };
    }

    // Layout
    const sc_options = useScrollContainer.Options{
        .total_content_dims = .{ .h = @as(f32, @floatFromInt(count)) * options.row_height, .w = total_content_width },
        .item_height = options.row_height,
        .enable_horizontal_scroll = true,
        .scrollbar_width = options.scrollbar_width,
        .scrollbar_height = options.scrollbar_height,
        .viewport_size_override = viewport_override,
    };

    // Use ID (Main Wrapper) for scroll container logic (input handling, etc.)
    const layout = useScrollContainer.useScrollContainer(ctx, id, &state.scroll, sc_options);

    // Keyboard
    if (ctx.focused_id != null and ctx.focused_id.?.id == id.id) {
        handleKeyboardInput(ctx, state, count, options.row_height, layout.viewport_dims.h);
    }

    // Outer Wrapper (LR)
    element.open(.{
        .id = id,
        .layout = .{ .direction = .left_to_right, .sizing = .grow, .child_gap = 4 },
        .border = .{ .width = .all(if (is_focused) 2 else 0), .color = border_color },
        .corner_radius = .all(theme.radius_box),
    });

    // Content Column (TB)
    element.open(.{
        .layout = .{ .direction = .top_to_bottom, .sizing = .grow, .child_gap = 4 },
    });

    return TableWalker{
        .ctx = ctx,
        .state = state,
        .layout = layout,
        .options = options,
        .total_count = count,
        .columns = columns,
        .total_content_width = total_content_width,
        .id = id,
        .theme = theme,
    };
}

pub fn end(_: TableWalker) void {
    // Scrollbars are handled by iterator.deinit() which calls PrimitiveScrollView.end()

    element.close(); // Close Content Column
    element.close(); // Close Outer Wrapper
}

// Logic helper
fn handleKeyboardInput(
    ctx: *UIContext,
    state: *types.ScrollTableState,
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
            selection_changed = true;
        }
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
