/// A standard, clickable button component inspired by DaisyUI.
///
/// Features:
/// - State: This is a stateless component. Its appearance and behavior are configured
///   entirely by the `Options` passed in each frame.
/// - Action: Returns `true` for the single frame it is clicked by mouse or activated
///   by the keyboard.
/// - Variants & Modifiers: Supports multiple color variants (primary, secondary, error, etc.)
///   and visual style modifiers (outline, ghost, link) for maximum flexibility.
/// - Keyboard Navigation: Can be focused by clicking and activated with Enter or Space.
/// - Sizing: Sizing can be passed in from the parent to allow the button to fit
///   content, grow, or have a fixed size.
const std = @import("std");
const cl = @import("zclay");
const t = @import("../core/theme.zig");
const UIContext = @import("../core/context.zig").UIContext;

/// Defines the button's semantic color role, pulling from the central theme.
pub const ColorVariant = enum {
    neutral,
    primary,
    secondary,
    accent,
    info,
    success,
    warning,
    danger,
};

/// Defines the button's visual style, altering the appearance of the chosen color variant.
pub const StyleModifier = enum {
    normal, // The default solid button
    outline,
    ghost,
    link,
};

/// Configuration for the button component, passed each frame.
pub const Options = struct {
    text: []const u8,
    is_disabled: bool = false,
    variant: ColorVariant = .neutral,
    modifier: StyleModifier = .normal,
    sizing: ?cl.Sizing = null,
};

/// Renders a button. Returns `true` for the single frame the button is clicked.
pub fn render(ctx: *UIContext, id: cl.ElementId, options: Options) bool {
    const theme = ctx.theme;

    // 1. Determine interaction state (if not disabled)
    const is_hovered = cl.pointerOver(id);
    var is_active = false;
    var is_focused = false;
    var clicked = false;

    if (!options.is_disabled) {
        if (is_hovered) {
            ctx.input.setMouseCursor(.pointing_hand);
        }
        is_focused = (ctx.focused_id != null and ctx.focused_id.?.id == id.id);
        is_active = (ctx.active_id != null and ctx.active_id.?.id == id.id);

        // On mouse down, the button becomes active and gains focus.
        if (is_hovered and ctx.input.getMouse().left_button.isPressed()) {
            ctx.active_id = id;
            ctx.focused_id = id;
            is_active = true;
            is_focused = true;
        }

        // If the button is active, the click action happens on mouse release.
        if (is_active and ctx.input.getMouse().left_button.isReleased()) {
            if (is_hovered) {
                clicked = true;
            }
            ctx.active_id = null;
        }

        // Handle keyboard activation when focused.
        if (is_focused) {
            if (ctx.input.getKey(.enter).isPressed() or ctx.input.getKey(.space).isPressed()) {
                clicked = true;
                is_active = true; // Briefly set active for visual feedback
            }
        }
    } else { // If button is disabled
        if (is_hovered) {
            ctx.input.setMouseCursor(.not_allowed);
        }
    }

    // --- Style Resolver --- //

    // Helper struct to hold the chosen color set for the variant
    const VariantColors = struct {
        main: cl.Color,
        content: cl.Color,
    };

    // 2. Select the base colors for the chosen variant from the theme.
    const variant_colors = switch (options.variant) {
        .primary => VariantColors{ .main = theme.color_primary, .content = theme.color_primary_content },
        .secondary => VariantColors{ .main = theme.color_second, .content = theme.color_second_content },
        .accent => VariantColors{ .main = theme.color_accent, .content = theme.color_accent_content },
        .info => VariantColors{ .main = theme.color_info, .content = theme.color_info_content },
        .success => VariantColors{ .main = theme.color_success, .content = theme.color_success_content },
        .warning => VariantColors{ .main = theme.color_warning, .content = theme.color_warning_content },
        .danger => VariantColors{ .main = theme.color_error, .content = theme.color_error_content },
        .neutral => VariantColors{ .main = theme.color_neutral, .content = theme.color_neutral_content },
    };

    // 3. Resolve the final style based on the modifier and interaction state.
    var bg_color: cl.Color = undefined;
    var text_color: cl.Color = undefined;
    var border_color: cl.Color = undefined;
    const transparent = cl.Color{ 0, 0, 0, 0 };

    switch (options.modifier) {
        .normal => {
            bg_color = variant_colors.main;
            text_color = variant_colors.content;
            border_color = variant_colors.main;
            if (is_active) {
                bg_color = theme.color_base_300;
                text_color = variant_colors.main;
            } else if (is_hovered) {
                bg_color = theme.color_base_200;
                text_color = variant_colors.main;
            }
        },
        .outline => {
            bg_color = transparent;
            text_color = variant_colors.main;
            border_color = variant_colors.main;
            if (is_hovered or is_active) {
                bg_color = variant_colors.main;
                text_color = variant_colors.content;
            }
        },
        .ghost => {
            bg_color = transparent;
            text_color = variant_colors.main;
            border_color = transparent;
            if (is_hovered or is_active) {
                bg_color = theme.color_base_300;
            }
        },
        .link => {
            bg_color = transparent;
            text_color = variant_colors.main;
            border_color = transparent;
            if (is_hovered or is_active) {
                text_color = theme.color_accent;
            }
        },
    }

    // 4. Apply overrides for disabled and focused states.
    if (options.is_disabled) {
        bg_color = theme.color_base_200;
        text_color = theme.color_base_content;
        border_color = theme.color_base_200;
    } else if (is_focused) {
        border_color = theme.color_accent;
    }

    // 5. Render the button
    const default_sizing: cl.Sizing = .{ .w = .fit, .h = .fixed(40) };
    const final_sizing = options.sizing orelse default_sizing;

    cl.UI()(.{
        .id = id,
        .layout = .{
            .direction = .left_to_right,
            .sizing = final_sizing,
            .padding = .{ .left = 16, .right = 16 },
            .child_alignment = .{ .x = .center, .y = .center },
        },
        .background_color = bg_color,
        .border = .{ .width = .all(theme.border), .color = border_color },
        .corner_radius = .all(theme.radius_box),
    })({
        cl.text(options.text, .{ .font_size = 20, .color = text_color });
    });

    return clicked;
}
