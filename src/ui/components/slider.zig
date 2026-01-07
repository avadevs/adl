const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const Primitive = @import("../primitives/slider.zig");

pub const Options = struct {
    min: f32 = 0.0,
    max: f32 = 1.0,
    step: f32 = 0.0, // 0.0 means continuous
    width: ?cl.SizingAxis = null,
    disabled: bool = false,
};

pub fn render(ctx: *UIContext, id: cl.ElementId, value: *f32, options: Options) bool {
    const theme = ctx.theme;

    // Normalize value for primitive (0.0 - 1.0)
    const range = options.max - options.min;
    const clamped_val = std.math.clamp(value.*, options.min, options.max);
    const normalized = if (range > std.math.floatEps(f32)) (clamped_val - options.min) / range else 0.0;

    // Calculate normalized step
    const norm_step = if (options.step > 0 and range > std.math.floatEps(f32)) options.step / range else 0.01;

    const config = Primitive.Config{
        .id = id,
        .value = normalized,
        .width = options.width orelse .grow,
        .height = 24,
        .track_color = theme.color_base_300,
        .thumb_color = theme.color_primary,
        .thumb_highlight_color = theme.color_primary, // Could be adjusted if we had a lighter/focus variant
        .corner_radius = theme.radius_box,
        .thumb_width = 20,
        .disabled = options.disabled,
        .keyboard_step = norm_step,
    };

    const state = Primitive.render(ctx, config);

    if (state.changed) {
        var new_val = options.min + (state.value * range);

        // Handle step
        if (options.step > 0) {
            const steps = @round(new_val / options.step);
            new_val = steps * options.step;
        }

        // Clamp to ensure we stay within bounds (rounding might push slightly out)
        new_val = std.math.clamp(new_val, options.min, options.max);

        value.* = new_val;
    }

    return state.changed or state.dragging;
}
