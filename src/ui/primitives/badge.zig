const std = @import("std");
const cl = @import("zclay");
const UIContext = @import("../core/context.zig").UIContext;

pub const Config = struct {
    id: cl.ElementId,
    sizing: cl.Sizing = .{ .w = .fit, .h = .fit },
    padding: cl.Padding = .{ .left = 8, .right = 8, .top = 4, .bottom = 4 },
    background_color: cl.Color,
    border: cl.BorderElementConfig = .{},
    corner_radius: cl.CornerRadius = .{},
};

pub const State = struct {};

pub fn render(ctx: *UIContext, config: Config, child_content: anytype) State {
    _ = ctx; // Context might be used for focus in future, but unused for static badge

    const closer = cl.UI()(.{
        .id = config.id,
        .layout = .{
            .direction = .left_to_right,
            .sizing = config.sizing,
            .padding = config.padding,
            .child_alignment = .{ .x = .center, .y = .center },
        },
        .background_color = config.background_color,
        .border = config.border,
        .corner_radius = config.corner_radius,
    });

    child_content.render();

    closer({});

    return .{};
}
