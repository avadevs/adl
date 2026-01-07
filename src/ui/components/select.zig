const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const PrimitiveDropdown = @import("../primitives/dropdown.zig");
const PrimitiveButton = @import("../primitives/button.zig");
const ScrollList = @import("scroll_list.zig");
const t = @import("../core/theme.zig");

pub fn Select(comptime T: type) type {
    return struct {
        pub const Options = struct {
            items: []const T,
            selected_index: ?usize = null,
            placeholder: []const u8 = "Select...",
            label_fn: *const fn (T) []const u8,
            width: cl.SizingAxis = .fixed(200),
            max_height: f32 = 300,
        };

        pub const State = struct {
            is_open: bool = false,
        };

        pub fn render(id_str: []const u8, opts: Options) !?usize {
            const ctx = try UIContext.getCurrent();
            const id = cl.ElementId.ID(id_str);
            const id_hash = std.hash.Wyhash.hash(0, id_str);

            // 1. Get State
            const state = try ctx.getOrInitCustom(id_hash, State);

            // Unique IDs for children
            const trigger_id_str = std.fmt.allocPrint(ctx.frame_allocator, "{s}_trigger", .{id_str}) catch "trigger";
            const list_id_str = std.fmt.allocPrint(ctx.frame_allocator, "{s}_list", .{id_str}) catch "list";

            var new_selection: ?usize = null;

            // 2. Prepare Trigger Content
            const current_text = if (opts.selected_index) |idx|
                if (idx < opts.items.len) opts.label_fn(opts.items[idx]) else opts.placeholder
            else
                opts.placeholder;

            const TriggerWrapper = struct {
                ctx: *UIContext,
                text: []const u8,
                width: cl.SizingAxis,
                is_open: bool,
                ptr_state: *State,
                trigger_id: []const u8,

                pub fn render(self: @This()) void {
                    const theme = self.ctx.theme;
                    const config = PrimitiveButton.PrimitiveButtonConfig{
                        .id = cl.ElementId.ID(self.trigger_id),
                        .sizing = .{ .w = self.width, .h = .fixed(40) },
                        .padding = .{ .left = 12, .right = 12 },
                        .background_color = theme.color_base_100,
                        .border = .{ .width = .all(1), .color = if (self.is_open) theme.color_primary else theme.color_base_300 },
                        .corner_radius = .all(theme.radius_box),
                    };
                    const Content = struct {
                        text: []const u8,
                        color: cl.Color,
                        pub fn render(inner: @This()) void {
                            cl.text(inner.text, .{ .font_size = 20, .color = inner.color });
                        }
                    };
                    const btn_state = PrimitiveButton.render(self.ctx, config, Content{ .text = self.text, .color = theme.color_base_content });

                    if (btn_state.clicked) {
                        self.ptr_state.is_open = !self.ptr_state.is_open;
                    }
                }
            };

            const DropdownContent = struct {
                ctx: *UIContext,
                opts: Options,
                state_ptr: *State,
                out_selection: *?usize,
                list_id: []const u8,

                pub fn render(self: @This()) void {
                    // Background for the list
                    const theme = self.ctx.theme;
                    const bg = cl.UI()(.{
                        .layout = .{
                            .sizing = .{ .w = .grow, .h = .fit }, // Height grows with list up to max?
                            // ScrollList handles sizing.
                            .padding = .all(4),
                        },
                        .background_color = theme.color_base_100,
                        .border = .{ .width = .all(1), .color = theme.color_base_300 },
                        .corner_radius = .all(theme.radius_box),
                    });

                    // Render List
                    // We need a unique ID for the list
                    // Since this runs inside the primitive's floating container, ID should be safe.
                    const list_id = self.list_id;

                    // Limit height
                    // Calculate expected height
                    const total_height = @as(f32, @floatFromInt(self.opts.items.len)) * 32.0; // 32 is hardcoded item height currently
                    const final_height = @min(total_height, self.opts.max_height);

                    // Ideally we wrap ScrollList in a sized container
                    const container = cl.UI()(.{
                        .layout = .{ .sizing = .{ .w = .grow, .h = .fixed(final_height) }, .direction = .top_to_bottom },
                    });

                    // We need to catch errors here but .render() is void.
                    // This is a limitation of the current design.
                    // We'll assume success for now or log error.
                    if (ScrollList.begin(list_id, self.opts.items.len, .{ .item_height = 32 })) |list| {
                        var iter = list.iterator();
                        while (iter.next()) |i| {
                            const is_selected = (self.opts.selected_index == i);

                            // Highlight selected
                            // ScrollList handles selection state internally too, but we want to close on click.

                            if (list.row(i)) {
                                self.out_selection.* = i;
                                self.state_ptr.is_open = false;
                            }

                            const item = self.opts.items[i];
                            cl.text(self.opts.label_fn(item), .{ .font_size = 20, .color = if (is_selected) theme.color_primary else theme.color_base_content });

                            list.endRow();
                        }
                        ScrollList.end(list);
                    } else |_| {
                        // Handle error
                    }

                    container({});
                    bg({});
                }
            };

            const result = PrimitiveDropdown.render(ctx, .{ .id = id, .width = opts.width, .offset = .{ .x = 0, .y = 0 } }, state.is_open, TriggerWrapper{ .ctx = ctx, .text = current_text, .width = opts.width, .is_open = state.is_open, .ptr_state = state, .trigger_id = trigger_id_str }, DropdownContent{ .ctx = ctx, .opts = opts, .state_ptr = state, .out_selection = &new_selection, .list_id = list_id_str });

            if (result.should_close) {
                state.is_open = false;
            }

            return new_selection;
        }
    };
}
