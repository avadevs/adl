const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const PrimitiveDropdown = @import("../primitives/dropdown.zig");
const PrimitiveButton = @import("../primitives/button.zig");
const t = @import("../core/theme.zig");
const element = @import("../core/element.zig");

pub const DropdownMenu = struct {
    pub const Options = struct {
        label: []const u8 = "Menu",
        // icon: ?Icon = null, // TODO: Add icon support when Icon type is standardized
        width: cl.SizingAxis = .fixed(200),
    };

    pub const ItemOptions = struct {
        // icon: ?Icon = null,
        shortcut: ?[]const u8 = null,
        destructive: bool = false,
        disabled: bool = false,
    };

    pub const State = struct {
        is_open: bool = false,
    };

    /// Context returned by begin() to allow adding items to the menu
    pub const MenuContext = struct {
        ctx: *UIContext,
        state_ptr: *State,
        popup: PrimitiveDropdown.PopupContext,

        /// Renders a menu item. Returns true if clicked.
        pub fn item(self: MenuContext, label: []const u8, opts: ItemOptions) bool {
            const theme = self.ctx.theme;

            // Layout for the item row
            const item_id_str = std.fmt.allocPrint(self.ctx.frame_allocator, "{s}_item", .{label}) catch label;
            const item_id = cl.ElementId.ID(item_id_str);
            const hovered = cl.pointerOver(item_id);
            var clicked = false;

            if (hovered and self.ctx.input.getMouse().left_button.isPressed()) {
                clicked = true;
            }

            // Colors
            var bg_color = cl.Color{ 0, 0, 0, 0 }; // Transparent by default
            var text_color = theme.color_base_content;

            if (opts.disabled) {
                text_color = theme.color_base_300;
            } else if (hovered) {
                bg_color = theme.color_base_200;
            }

            if (opts.destructive) {
                text_color = theme.color_error;
            }

            cl.UI()(.{
                .id = item_id,
                .layout = .{
                    .sizing = .{ .w = .grow, .h = .fixed(32) }, // Standard height
                    .padding = .{ .left = 12, .right = 12 },
                    .direction = .left_to_right,
                    .child_gap = 8,
                    .child_alignment = .{ .y = .center },
                },
                .background_color = bg_color,
                .corner_radius = .all(4), // Slight rounding for hover state looks modern
            })({
                // Icon (placeholder)
                // if (opts.icon) |ic| ...

                // Label (Expand to push shortcut to right)
                cl.UI()(.{ .layout = .{ .sizing = .{ .w = .grow } } })({
                    cl.text(label, .{ .font_size = 18, .color = text_color });
                });

                // Shortcut
                if (opts.shortcut) |sc| {
                    cl.text(sc, .{ .font_size = 14, .color = theme.color_base_300 });
                }
            });

            if (clicked and !opts.disabled) {
                self.state_ptr.is_open = false;
                return true;
            }
            return false;
        }

        /// Renders a horizontal separator line
        pub fn separator(self: MenuContext) void {
            const theme = self.ctx.theme;
            cl.UI()(.{
                .layout = .{
                    .sizing = .{ .w = .grow, .h = .fixed(1) },
                    .padding = .{ .top = 4, .bottom = 4 }, // Add vertical space around line
                },
            })({
                // The actual line
                cl.UI()(.{
                    .layout = .{ .sizing = .{ .w = .grow, .h = .fixed(1) } },
                    .background_color = theme.color_base_300,
                })({});
            });
        }

        pub fn end(self: MenuContext) void {
            // Close the floating container via primitive logic
            const result = self.popup.end();
            if (result.should_close) {
                self.state_ptr.is_open = false;
            }

            // Close the Anchor container opened in begin()
            // The popup was inside it.
            element.close();
        }
    };

    pub fn begin(id_str: []const u8, opts: Options) !?MenuContext {
        const ctx = try UIContext.getCurrent();
        const id = cl.ElementId.ID(id_str);
        const id_hash = std.hash.Wyhash.hash(0, id_str);

        const state = try ctx.getOrInitCustom(id_hash, State);

        // 1. Render Trigger Button
        // We use a custom button primitive logic but inside a wrapper div to serve as attachment point.

        // IMPORTANT: PrimitiveDropdown.begin attaches to the PARENT.
        // So we must open a container here to represent the "Anchor"

        const anchor_closer = cl.UI()(.{
            .id = id,
            .layout = .{ .sizing = .{ .w = .fit, .h = .fit } },
        });

        const theme = ctx.theme;
        const config = PrimitiveButton.PrimitiveButtonConfig{
            .id = cl.ElementId.ID(std.fmt.allocPrint(ctx.frame_allocator, "{s}_btn", .{id_str}) catch "btn"), // Sub-ID to avoid conflict with anchor
            .sizing = .{ .w = .fit, .h = .fixed(40) }, // Fit label
            .padding = .{ .left = 12, .right = 12 },
            .background_color = if (state.is_open) theme.color_base_200 else theme.color_base_100,
            .border = .{ .width = .all(1), .color = theme.color_base_300 },
            .corner_radius = .all(theme.radius_box),
        };

        const TriggerContent = struct {
            label: []const u8,
            color: cl.Color,
            pub fn render(self: @This()) void {
                cl.text(self.label, .{ .font_size = 18, .color = self.color });
            }
        };

        const btn_state = PrimitiveButton.render(ctx, config, TriggerContent{ .label = opts.label, .color = theme.color_base_content });

        if (btn_state.clicked) {
            state.is_open = !state.is_open;
        }

        if (!state.is_open) {
            anchor_closer({}); // Close anchor
            return null;
        }

        // 2. Begin Floating Container using Primitive
        // Note: We pass the Anchor ID (`id`) as the primitive ID because that's what we want to verify clicks against.
        // PrimitiveDropdown.begin attaches to the parent of the floating element.
        // Since we are inside `anchor_closer`, the parent IS the anchor. Perfect.

        const popup = PrimitiveDropdown.begin(ctx, .{
            .id = id,
            .width = opts.width,
            .z_index = 200,
            .offset = .{ .x = 0, .y = 0 }, // Handled by attachment points
        });

        // However, `begin` does NOT close the anchor. We need to close it somewhere.
        // But the floating element is a child of the anchor.
        // If we close the anchor now, the floating element (which is a child) is closed too early?
        // NO. In immediate mode, the floating element declaration needs to be inside the anchor's scope.
        // But the `MenuContext` outlives this scope? No.

        // Problem: `anchor_closer` is a closure that must be called at the END of the menu rendering block?
        // If we return from this function, we must either keep the anchor open (impossible in Zig defer style without tricks)
        // OR we realize that `PrimitiveDropdown.begin` creates a floating element.
        // Floating elements in Clay break out of layout but must be declared *inside* their parent for attachment.

        // So:
        // begin() -> Open Anchor -> Render Button -> Open Popup -> Return Context
        // end() -> Close Popup -> Close Anchor

        // We can store the `anchor_closer` in the Context? No, it's a function pointer/closure.
        // We can just call `cl.close()` in `end()`.

        // Wait. `PrimitiveDropdown.begin` opens the floating element.
        // So `MenuContext.end` will call `popup.end()` which closes the floating element.
        // THEN we need to close the Anchor.

        if (popup) |p| {
            // Add inner padding/style for the menu list
            // PrimitiveDropdown just opens the container. It doesn't style the background/border of the content.
            // Wait, PrimitiveDropdown.begin DOES open a styled container?
            // Checking primitive code...
            // "cl.open( ... .background_color = ... )"
            // Yes, PrimitiveDropdown.begin opens a UI element with styling.

            // So we need to:
            // 1. Add style overrides if needed? PrimitiveDropdown uses `config` but `config` is mostly layout.
            // PrimitiveDropdown doesn't take background color in Config.
            // It hardcodes ".background_color = theme.color_base_100".
            // That's fine for menus.

            return MenuContext{
                .ctx = ctx,
                .state_ptr = state,
                .popup = p,
            };
        } else {
            // Should be unreachable due to check above
            anchor_closer({});
            return null;
        }
    }
};
