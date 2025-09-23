/// A virtualized, scrollable, and sortable table component.
const std = @import("std");
const rl = @import("raylib");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const useScrollContainer = @import("../hooks/useScrollContainer.zig");
const scrollbar = @import("../elements/scrollbar.zig");

/// Configuration options for the scroll_table's appearance.
pub const Options = struct {
    row_height: f32 = 28,
    header_height: f32 = 32,
    font_size: u16 = 20,
    header_font_size: u16 = 22,
};

/// Specifies the sort direction.
pub const Direction = enum {
    asc,
    desc,

    pub fn opposite(self: Direction) Direction {
        return switch (self) {
            .asc => .desc,
            .desc => .asc,
        };
    }
};

/// The scroll tables operates on the generic item type provided by the user.
pub fn ScrollTable(comptime Item: type) type {
    return struct {
        // All the generic types are now concrete structs inside this namespace
        pub const Column = struct {
            name: []const u8,
            width: f32,
            alignment: cl.ChildAlignment = .{ .x = .left, .y = .center },
            // sort_fn: ?*const fn (a: *const columnType, b: *const columnType) bool,

            /// The user provides this function to render a cell.
            /// This function is on the column-level because this is where we save the type of the cells.
            render_cell_fn: *const fn (item: *const Item, ctx: *UIContext, options: Options) void,
        };

        pub const State = struct {
            const Self = @This();
            allocator: std.mem.Allocator,
            selected_index: ?usize = null,
            scroll_state: useScrollContainer.State = .{},
            sort_column_index: ?usize = null,
            sort_direction: Direction = .asc,
        };

        /// Bundles context for the callbacks passed to the scroll_container.
        const CallbackContext = struct {
            state: *State,
            options: Options,
            table_id: cl.ElementId,
            items: []const Item, // borrows the items for this frame
            columns: []const Column, // borrows the columns for this frame
        };

        // This function renders the user provided data (items) and configuration (columns) every frame
        pub fn render(
            ctx: *UIContext,
            id: cl.ElementId,
            state: *State,
            items: []const Item,
            columns: []const Column,
            options: Options,
            mouse_wheel: cl.Vector2,
        ) void {
            const theme = ctx.theme;

            var total_content_width: f32 = 0;
            for (columns) |col| {
                total_content_width += col.width;
            }

            const sc_options = useScrollContainer.Options{
                .total_content_dims = .{ .h = @as(f32, @floatFromInt(items.len)) * options.row_height, .w = total_content_width },
                .item_height = options.row_height,
                .enable_horizontal_scroll = true,
                .scrollbar_width = 12,
                .scrollbar_height = 12,
            };

            const layout = useScrollContainer.useScrollContainer(ctx, id, &state.scroll_state, sc_options, mouse_wheel);

            if (ctx.focused_id != null and ctx.focused_id.?.id == id.id) {
                handleKeyboardInputCallback(ctx, state, items.len, options.row_height, layout.viewport_dims.h);
            }

            cl.UI()(.{
                .id = id,
                .layout = .{ .direction = .top_to_bottom, .sizing = .grow, .child_gap = 4 },
            })({ // Main Container
                // --- Header --- //
                cl.UI()(.{
                    .id = cl.ElementId.localID("Header"),
                    .layout = .{ .sizing = .{ .w = .grow, .h = .fixed(options.header_height) } },
                    .background_color = theme.color_base_200,
                    .clip = .{ .horizontal = true, .child_offset = .{ .x = layout.child_offset.x, .y = 0 } },
                })({
                    cl.UI()(.{
                        .id = cl.ElementId.localID("HeaderContainer"),
                        .layout = .{ .direction = .left_to_right, .sizing = .{ .w = .fixed(total_content_width), .h = .grow } },
                    })({
                        for (columns, 0..) |col, i| {
                            const header_id = cl.ElementId.localIDI("header", @intCast(i));
                            const is_sort_col = state.sort_column_index != null and state.sort_column_index.? == i;

                            var clicked = false;
                            var is_hovered = false;
                            cl.UI()(.{ .id = header_id, .layout = .{ .sizing = .{ .w = .fixed(col.width), .h = .grow } } })({
                                is_hovered = cl.hovered();
                                if (is_hovered and rl.isMouseButtonPressed(.left)) {
                                    clicked = true;
                                }
                            });

                            if (clicked) { // and col.sort_fn != null) {
                                if (is_sort_col) {
                                    state.sort_direction = state.sort_direction.opposite();
                                } else {
                                    state.sort_column_index = i;
                                    state.sort_direction = .asc;
                                }
                                // TODO: state.sort(columns);
                            }

                            const bg_color = if (is_hovered) theme.color_base_300 else theme.color_base_200;

                            cl.UI()(.{
                                .layout = .{
                                    .direction = .left_to_right,
                                    .sizing = .{ .w = .fixed(col.width), .h = .grow },
                                    .padding = .{ .left = 8, .right = 8 },
                                    .child_alignment = col.alignment,
                                    .child_gap = 8,
                                },
                                .background_color = bg_color,
                            })({
                                cl.text(col.name, .{ .font_size = options.header_font_size, .color = theme.color_base_content });
                                if (is_sort_col) {
                                    const sort_char = if (state.sort_direction == .asc) "▲" else "▼";
                                    cl.text(sort_char, .{ .font_size = options.font_size, .color = theme.color_base_content });
                                }
                            });
                        }
                    });
                });

                // --- Body and Vertical Scrollbar --- //
                cl.UI()(.{
                    .layout = .{ .direction = .left_to_right, .sizing = .grow, .child_gap = 4 },
                })({
                    cl.UI()(.{
                        .id = cl.ElementId.localID("TableBody"),
                        .layout = .{ .sizing = .grow },
                        .clip = .{ .vertical = true, .horizontal = true, .child_offset = layout.child_offset },
                    })({
                        cl.UI()(.{
                            .layout = .{ .direction = .top_to_bottom, .sizing = .{ .w = .fixed(total_content_width), .h = .fixed(sc_options.total_content_dims.h) } },
                        })({
                            if (layout.top_spacer_height > 0) {
                                cl.UI()(.{ .layout = .{ .sizing = .{ .h = .fixed(layout.top_spacer_height) } } })({});
                            }

                            renderItems(ctx, state, items, columns, options, layout.first_visible_item, layout.last_visible_item);

                            if (layout.bottom_spacer_height > 0) {
                                cl.UI()(.{ .layout = .{ .sizing = .{ .h = .fixed(layout.bottom_spacer_height) } } })({});
                            }
                        });
                    });

                    scrollbar.vertical(ctx, sc_options.scrollbar_width, layout.v_scrollbar);
                });

                // --- Horizontal Scrollbar --- //
                scrollbar.horizontal(ctx, sc_options.scrollbar_height, layout.h_scrollbar);
            });
        }

        fn renderItems(
            ui_ctx: *UIContext,
            inner_state: *State,
            items: []const Item,
            columns: []const Column,
            inner_options: Options,
            first: usize,
            last: usize,
        ) void {
            const inner_theme = ui_ctx.theme;

            for (items[first..last], first..) |*item, i| {
                const is_selected = inner_state.selected_index != null and inner_state.selected_index.? == i;
                const row_id = cl.ElementId.localIDI("row", @intCast(i));

                var is_hovered = false;
                cl.UI()(.{ .id = row_id, .layout = .{ .sizing = .{ .w = .grow, .h = .fixed(inner_options.row_height) } } })({
                    is_hovered = cl.hovered();
                });

                const bg_color = if (is_selected) inner_theme.color_primary else if (is_hovered) inner_theme.color_base_300 else inner_theme.color_base_100;

                cl.UI()(.{
                    .layout = .{
                        .direction = .left_to_right,
                        .sizing = .{ .w = .grow, .h = .fixed(inner_options.row_height) },
                        .child_alignment = .{ .y = .center },
                    },
                    .background_color = bg_color,
                })({
                    if (cl.hovered() and rl.isMouseButtonPressed(.left)) {
                        inner_state.selected_index = i;
                    }

                    for (columns) |col| {
                        cl.UI()(.{
                            .layout = .{
                                .sizing = .{ .w = .fixed(col.width), .h = .grow },
                                .padding = .{ .left = 8, .right = 8 },
                                .child_alignment = col.alignment,
                            },
                        })({
                            col.render_cell_fn(item, ui_ctx, inner_options);
                        });
                    }
                });
            }
        }

        fn handleKeyboardInputCallback(
            ui_ctx: *UIContext,
            inner_state: *State,
            items_len: usize,
            item_height: f32,
            viewport_height: f32,
        ) void {
            if (items_len == 0) return;

            var selection_changed = false;
            const current_index: usize = if (inner_state.selected_index) |idx| idx else 0;

            if (ui_ctx.input.getKey(.down).isRepeated()) {
                inner_state.selected_index = @min(current_index + 1, items_len - 1);
                selection_changed = true;
            } else if (ui_ctx.input.getKey(.up).isRepeated()) {
                if (current_index > 0) {
                    inner_state.selected_index = current_index - 1;
                    selection_changed = true;
                }
            } else if (ui_ctx.input.getKey(.home).isPressed()) {
                inner_state.selected_index = 0;
                selection_changed = true;
            } else if (ui_ctx.input.getKey(.end).isPressed()) {
                inner_state.selected_index = items_len - 1;
                selection_changed = true;
            } else if (ui_ctx.input.getKey(.page_down).isRepeated()) {
                const items_per_page = @as(usize, @intFromFloat(@floor(viewport_height / item_height)));
                inner_state.selected_index = @min(current_index + items_per_page, items_len - 1);
                selection_changed = true;
            } else if (ui_ctx.input.getKey(.page_up).isRepeated()) {
                const items_per_page = @as(usize, @intFromFloat(@floor(viewport_height / item_height)));
                inner_state.selected_index = if (current_index > items_per_page) current_index - items_per_page else 0;
                selection_changed = true;
            }

            if (selection_changed and inner_state.selected_index != null) {
                useScrollContainer.ensureSelectionIsVisible(&inner_state.scroll_state, inner_state.selected_index.?, item_height, viewport_height);
            }
        }
    };
}

/// The renderer namespace provides default renderes for the supported CellValue types.
/// It will get called during the render() function of the scroll_table to provide
/// cl.text() elements for the specific CellValues.
pub const renderer = struct {
    /// Takes a concrete CellValue type and a generic render function (that accepts anytype)
    /// and returns a specific, non-generic function pointer.
    pub fn bind(
        comptime CellValue: type,
        comptime generic_render_fn: anytype,
    ) *const fn (cell: CellValue, ctx: *UIContext, options: Options) void {
        // This struct is created at compile time. Its sole purpose is to hold
        // a non-generic function that we can take a pointer to.
        const Wrapper = struct {
            fn wrapped(cell: CellValue, ctx: *UIContext, options: Options) void {
                // Inside, we call the original generic function.
                // The compiler knows to instantiate it here with the concrete CellValue type.
                generic_render_fn(cell, ctx, options);
            }
        };

        // Return a pointer to the specific, wrapped function.
        return Wrapper.wrapped;
    }

    pub fn integer(cell: anytype, ctx: *UIContext, options: Options) void {
        // This renderer assumes the cell is an integer.
        // A failed assertion here means the user moscinfigured their columns
        std.debug.assert(cell.tag == .integer);

        var buf: [32]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "{d}", .{cell.data.integer}) catch unreachable;
        cl.text(str, .{ .font_size = options.font_size, .color = ctx.theme.color_base_content });
    }

    pub fn string(cell: anytype, ctx: *UIContext, options: Options) void {
        std.debug.assert(cell.tag == .string);
        cl.text(cell.data.string, .{ .font_size = options.font_size, .color = ctx.theme.color_base_content });
    }
};
