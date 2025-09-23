const std = @import("std");
const rl = @import("raylib");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const useScrollContainer = @import("../hooks/useScrollContainer.zig");
const scrollbar = @import("../elements/scrollbar.zig");

pub fn ScrollList(comptime Item: type) type {
    return struct {
        pub const Options = struct {
            item_height: f32 = 28,
            font_size: u16 = 20,
            scrollbar_width: f32 = 12,
        };

        pub const State = struct {
            selected_index: ?usize = null,
            scroll_state: useScrollContainer.State = .{},
        };

        const CallbackContext = struct {
            list_state: *State,
            list_options: Options,
            container_id: cl.ElementId,
            items: []const Item,
            render_item_fn: *const fn (*const Item, *UIContext, bool, bool) void,
        };

        pub fn render(
            ctx: *UIContext,
            id: cl.ElementId,
            state: *State,
            items: []const Item,
            render_item_fn: *const fn (*const Item, *UIContext, bool, bool) void,
            options: Options,
            mouse_wheel: cl.Vector2,
        ) void {
            const sc_options = useScrollContainer.Options{
                .total_content_dims = .{ .h = @as(f32, @floatFromInt(items.len)) * options.item_height, .w = 0 },
                .item_height = options.item_height,
                .enable_horizontal_scroll = false,
                .scrollbar_width = options.scrollbar_width,
            };

            const layout = useScrollContainer.useScrollContainer(ctx, id, &state.scroll_state, sc_options, mouse_wheel);

            if (ctx.focused_id != null and ctx.focused_id.?.id == id.id) {
                handleKeyboardInput(ctx, state, items.len, options.item_height, layout.viewport_dims.h);
            }

            cl.UI()(.{
                .layout = .{ .direction = .left_to_right, .sizing = .grow, .child_gap = 4 },
            })({
                cl.UI()(.{
                    .id = id,
                    .layout = .{ .sizing = .grow },
                    .clip = .{ .vertical = true, .child_offset = layout.child_offset },
                })({
                    cl.UI()(.{
                        .layout = .{ .direction = .top_to_bottom, .sizing = .{ .w = .grow, .h = .fixed(sc_options.total_content_dims.h) } },
                    })({
                        if (layout.top_spacer_height > 0) {
                            cl.UI()(.{ .layout = .{ .sizing = .{ .h = .fixed(layout.top_spacer_height) } } })({});
                        }

                        for (items[layout.first_visible_item..layout.last_visible_item], layout.first_visible_item..) |*item, i| {
                            const is_selected = state.selected_index != null and state.selected_index.? == i;
                            const row_id = cl.ElementId.localIDI(id.string_id.chars[0..@intCast(id.string_id.length)], @intCast(i));
                            var is_hovered = false;

                            cl.UI()(.{ .id = row_id, .layout = .{ .sizing = .{ .w = .grow, .h = .fixed(options.item_height) } } })({
                                is_hovered = cl.hovered();
                                if (is_hovered and rl.isMouseButtonPressed(.left)) {
                                    state.selected_index = i;
                                }

                                render_item_fn(item, ctx, is_selected, is_hovered);
                            });
                        }

                        if (layout.bottom_spacer_height > 0) {
                            cl.UI()(.{ .layout = .{ .sizing = .{ .h = .fixed(layout.bottom_spacer_height) } } })({});
                        }
                    });
                });

                scrollbar.vertical(ctx, options.scrollbar_width, layout.v_scrollbar);
            });
        }

        fn handleKeyboardInput(
            ctx: *UIContext,
            state: *State,
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
                useScrollContainer.ensureSelectionIsVisible(&state.scroll_state, state.selected_index.?, item_height, viewport_height);
            }
        }
    };
}
