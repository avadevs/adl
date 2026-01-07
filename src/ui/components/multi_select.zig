const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const PrimitiveDropdown = @import("../primitives/dropdown.zig");
const PrimitiveButton = @import("../primitives/button.zig");
const ScrollList = @import("scroll_list.zig");
const t = @import("../core/theme.zig");

pub fn MultiSelect(comptime T: type) type {
    return struct {
        pub const Options = struct {
            items: []const T,
            /// Slice of booleans matching items.len. true = selected.
            selected_mask: []const bool,
            placeholder: []const u8 = "Select items...",
            label_fn: *const fn (T) []const u8,
            width: cl.SizingAxis = .fixed(200),
            max_height: f32 = 300,
        };

        pub const State = struct {
            is_open: bool = false,
        };

        /// Returns the index of the item that was toggled, if any.
        pub fn render(id_str: []const u8, opts: Options) !?usize {
            const ctx = try UIContext.getCurrent();
            const id = cl.ElementId.ID(id_str);
            const id_hash = std.hash.Wyhash.hash(0, id_str);

            const state = try ctx.getOrInitCustom(id_hash, State);

            // Unique IDs for children
            const trigger_id_str = std.fmt.allocPrint(ctx.frame_allocator, "{s}_trigger", .{id_str}) catch "trigger";
            const list_id_str = std.fmt.allocPrint(ctx.frame_allocator, "{s}_list", .{id_str}) catch "list";

            var toggled_index: ?usize = null;

            // 2. Prepare Trigger Content
            // Count selected
            var count: usize = 0;
            var first_selected: ?usize = null;
            for (opts.selected_mask, 0..) |sel, i| {
                if (sel) {
                    count += 1;
                    if (first_selected == null) first_selected = i;
                }
            }

            // Generate label
            // We need a temporary buffer for the label string if we format it.
            // Use frame allocator.
            var trigger_text: []const u8 = opts.placeholder;
            if (count > 0) {
                if (count == 1) {
                    trigger_text = opts.label_fn(opts.items[first_selected.?]);
                } else {
                    trigger_text = std.fmt.allocPrint(ctx.frame_allocator, "{d} selected", .{count}) catch opts.placeholder;
                }
            }

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
                out_toggled: *?usize,
                list_id: []const u8,

                pub fn render(self: @This()) void {
                    const theme = self.ctx.theme;
                    const bg = cl.UI()(.{
                        .layout = .{
                            .sizing = .{ .w = .grow, .h = .fit },
                            .padding = .all(4),
                        },
                        .background_color = theme.color_base_100,
                        .border = .{ .width = .all(1), .color = theme.color_base_300 },
                        .corner_radius = .all(theme.radius_box),
                    });

                    const list_id = self.list_id;

                    const total_height = @as(f32, @floatFromInt(self.opts.items.len)) * 32.0;
                    const final_height = @min(total_height, self.opts.max_height);

                    const container = cl.UI()(.{
                        .layout = .{ .sizing = .{ .w = .grow, .h = .fixed(final_height) }, .direction = .top_to_bottom },
                    });

                    if (ScrollList.begin(list_id, self.opts.items.len, .{ .item_height = 32 })) |list| {
                        var iter = list.iterator();
                        while (iter.next()) |i| {
                            const is_checked = self.opts.selected_mask[i];

                            // Row interaction handled by ScrollList (highlight/click)
                            const row_clicked = list.row(i);

                            if (row_clicked) {
                                self.out_toggled.* = i;
                                // Do NOT close on toggle
                            }

                            // Render Checkbox + Label
                            const item = self.opts.items[i];

                            // We construct a row layout
                            // Checkbox
                            // Label
                            const row_layout = cl.UI()(.{ .layout = .{ .direction = .left_to_right, .child_gap = 8, .child_alignment = .{ .y = .center } } });

                            // Checkbox
                            // We use a simplified rendering of checkbox or the component?
                            // Checkbox component requires state interaction.
                            // Here we just want to display state and maybe handle click.
                            // But click is handled by the Row.
                            // So we render a "passive" checkbox or just an icon.

                            // Let's use the Checkbox component but pass 'is_checked' and maybe disable it?
                            // Actually, standard Checkbox component handles clicks.
                            // If we nest clickable inside clickable row, it might double fire.
                            // Better: Render a visual checkbox (Primitive).

                            // For now, let's just use text "[x]" or "[ ]" if no primitive handy,
                            // OR use the Checkbox component but ignore its return value (it returns bool 'new_value').
                            // But Checkbox component expects to handle input.
                            // If we just want visuals, we can make the Checkbox disabled? No, then it looks gray.
                            // We can render a box manually.

                            const box_size: f32 = 16;
                            const box = cl.UI()(.{
                                .layout = .{ .sizing = .{ .w = .fixed(box_size), .h = .fixed(box_size) } },
                                .background_color = if (is_checked) theme.color_primary else theme.color_base_200,
                                .corner_radius = .all(4),
                            });
                            box({});

                            cl.text(self.opts.label_fn(item), .{ .font_size = 20, .color = theme.color_base_content });

                            row_layout({});
                            list.endRow();
                        }
                        ScrollList.end(list);
                    } else |_| {}

                    container({});
                    bg({});
                }
            };

            const result = PrimitiveDropdown.render(ctx, .{ .id = id, .width = opts.width, .offset = .{ .x = 0, .y = 0 } }, state.is_open, TriggerWrapper{ .ctx = ctx, .text = trigger_text, .width = opts.width, .is_open = state.is_open, .ptr_state = state, .trigger_id = trigger_id_str }, DropdownContent{ .ctx = ctx, .opts = opts, .state_ptr = state, .out_toggled = &toggled_index, .list_id = list_id_str });

            if (result.should_close) {
                state.is_open = false;
            }

            return toggled_index;
        }
    };
}
