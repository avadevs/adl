const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;
const element = @import("../core/element.zig");

pub const Config = struct {
    id: cl.ElementId,
    /// Width of the dropdown content. Defaults to matching the trigger width if .grow, or specific size.
    width: cl.SizingAxis = .grow,
    /// Offset from the bottom-left of the trigger (usually).
    offset: cl.Vector2 = .{ .x = 0, .y = 0 },
    /// Z-Index for the floating element
    z_index: i16 = 100,
};

pub const State = struct {
    /// True if the user clicked outside the dropdown content and trigger while it was open.
    should_close: bool,
};

pub const PopupContext = struct {
    ctx: *UIContext,
    content_id: cl.ElementId,
    trigger_id: cl.ElementId,

    pub fn end(self: PopupContext) State {
        element.close(); // Close floating container

        var should_close = false;
        // Handle Click Outside
        if (self.ctx.input.getMouse().left_button.isPressed()) {
            const over_content = cl.pointerOver(self.content_id);
            const over_trigger = cl.pointerOver(self.trigger_id);

            // If not over content and not over trigger, close it.
            if (!over_content and !over_trigger) {
                should_close = true;
            }
        }
        return .{ .should_close = should_close };
    }
};

/// Begins a floating dropdown/popup.
/// Returns a context if open (caller must call .end()), or null if closed.
pub fn begin(
    ctx: *UIContext,
    config: Config,
) ?PopupContext {
    // We assume the floating element is attached to the parent of this call (usually the trigger container).

    // Clay Floating Config
    const content_id_str = std.fmt.allocPrint(ctx.frame_allocator, "dropdown_content_{d}", .{config.id.id}) catch "dropdown_content_err";
    const content_id = cl.ElementId.ID(content_id_str);

    element.open(.{
        .id = content_id,
        .layout = .{
            .sizing = .{ .w = config.width, .h = .fit },
            .direction = .top_to_bottom, // Standard list direction usually
        },
        .floating = .{
            .offset = config.offset,
            .z_index = config.z_index,
            .attach_to = .to_parent,
            .attach_points = .{ .element = .left_top, .parent = .left_bottom },
        },
    });

    return PopupContext{
        .ctx = ctx,
        .content_id = content_id,
        .trigger_id = config.id,
    };
}

/// A primitive that handles the layout and interaction logic for a dropdown/popover.
/// It renders the `trigger_content` inline, and if `is_open` is true, renders
/// `dropdown_content` as a floating element relative to the trigger.
pub fn render(
    ctx: *UIContext,
    config: Config,
    is_open: bool,
    trigger_content: anytype,
    dropdown_content: anytype,
) State {
    const id = config.id;
    var should_close = false;

    // 1. Render Trigger Container
    // We wrap the trigger in a container to serve as the anchor for the floating element.
    const trigger_closer = cl.UI()(.{
        .id = id,
        .layout = .{
            .direction = .top_to_bottom, // Standard stacking
            .sizing = .{ .w = .fit, .h = .fit }, // Fit around trigger content
        },
    });

    trigger_content.render();

    if (is_open) {
        if (begin(ctx, config)) |popup| {
            dropdown_content.render();
            const result = popup.end();
            should_close = result.should_close;
        }
    }

    trigger_closer({});

    return .{ .should_close = should_close };
}
