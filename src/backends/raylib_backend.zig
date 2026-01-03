const std = @import("std");
const rl = @import("raylib");
const cl = @import("zclay");
const adl = @import("adl");

const types = adl.ui.types;
const InputBackend = adl.ui.input.InputBackend;

// ============================================================================
// Input Backend Implementation
// ============================================================================

fn getMousePosition(_: *anyopaque) types.Vector2 {
    const pos = rl.getMousePosition();
    return .{ .x = pos.x, .y = pos.y };
}

fn getMouseWheelMove(_: *anyopaque) f32 {
    return rl.getMouseWheelMove();
}

fn isMouseButtonDown(_: *anyopaque, button: types.MouseButton) bool {
    const rl_button: rl.MouseButton = switch (button) {
        .left => .left,
        .right => .right,
        .middle => .middle,
        .side => .side,
        .extra => .extra,
        .forward => .forward,
        .back => .back,
    };
    return rl.isMouseButtonDown(rl_button);
}

fn mapKey(key: types.Key) rl.KeyboardKey {
    // This is a comprehensive mapping, but for brevity in this example we map common keys.
    // In a full implementation, you'd map every key in the enum.
    return switch (key) {
        .space => .space,
        .escape => .escape,
        .enter => .enter,
        .backspace => .backspace,
        .up => .up,
        .down => .down,
        .left => .left,
        .right => .right,
        .a => .a,
        .b => .b,
        .c => .c,
        .d => .d,
        .e => .e,
        .f => .f,
        .g => .g,
        .h => .h,
        .i => .i,
        .j => .j,
        .k => .k,
        .l => .l,
        .m => .m,
        .n => .n,
        .o => .o,
        .p => .p,
        .q => .q,
        .r => .r,
        .s => .s,
        .t => .t,
        .u => .u,
        .v => .v,
        .w => .w,
        .x => .x,
        .y => .y,
        .z => .z,
        .zero => .zero,
        .one => .one,
        .two => .two,
        .three => .three,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
        .nine => .nine,
        else => .null, // Fallback
    };
}

fn mapRlKey(key: rl.KeyboardKey) types.Key {
    return switch (key) {
        .space => .space,
        .escape => .escape,
        .enter => .enter,
        .backspace => .backspace,
        .up => .up,
        .down => .down,
        .left => .left,
        .right => .right,
        .a => .a,
        .b => .b,
        .c => .c,
        .d => .d,
        .e => .e,
        .f => .f,
        .g => .g,
        .h => .h,
        .i => .i,
        .j => .j,
        .k => .k,
        .l => .l,
        .m => .m,
        .n => .n,
        .o => .o,
        .p => .p,
        .q => .q,
        .r => .r,
        .s => .s,
        .t => .t,
        .u => .u,
        .v => .v,
        .w => .w,
        .x => .x,
        .y => .y,
        .z => .z,
        .zero => .zero,
        .one => .one,
        .two => .two,
        .three => .three,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
        .nine => .nine,
        else => .unknown,
    };
}

fn isKeyDown(_: *anyopaque, key: types.Key) bool {
    const rl_key = mapKey(key);
    if (rl_key == .null) return false;
    return rl.isKeyDown(rl_key);
}

fn getKeyPressed(_: *anyopaque) ?types.Key {
    const key = rl.getKeyPressed();
    if (key == .null) return null;
    return mapRlKey(key);
}

fn getCharPressed(_: *anyopaque) u32 {
    return @intCast(rl.getCharPressed());
}

fn setMouseCursor(_: *anyopaque, cursor: types.CursorShape) void {
    const rl_cursor: rl.MouseCursor = switch (cursor) {
        .default, .arrow => .default,
        .ibeam => .ibeam,
        .crosshair => .crosshair,
        .pointing_hand => .pointing_hand,
        .resize_ew => .resize_ew,
        .resize_ns => .resize_ns,
        .resize_nwse => .resize_nwse,
        .resize_nesw => .resize_nesw,
        .resize_all => .resize_all,
        .not_allowed => .not_allowed,
    };
    rl.setMouseCursor(rl_cursor);
}

pub fn createInputBackend() InputBackend {
    return .{
        .context = undefined, // Raylib is global, no context needed
        .getMousePosition = getMousePosition,
        .getMouseWheelMove = getMouseWheelMove,
        .isMouseButtonDown = isMouseButtonDown,
        .isKeyDown = isKeyDown,
        .getKeyPressed = getKeyPressed,
        .getCharPressed = getCharPressed,
        .setMouseCursor = setMouseCursor,
    };
}

// ============================================================================
// Rendering & Measurement
// ============================================================================

fn toRlColor(color: cl.Color) rl.Color {
    return .{
        .r = @intFromFloat(color[0]),
        .g = @intFromFloat(color[1]),
        .b = @intFromFloat(color[2]),
        .a = @intFromFloat(color[3]),
    };
}

pub fn measureText(text: []const u8, config: *cl.TextElementConfig, _: void) cl.Dimensions {
    const font = rl.getFontDefault() catch return .{ .w = 0, .h = 0 };

    // Safety buffer for C-string conversion
    var buf: [1024]u8 = undefined;
    if (text.len >= buf.len - 1) return .{ .w = 0, .h = 0 };
    @memcpy(buf[0..text.len], text);
    buf[text.len] = 0;
    const c_text = buf[0..text.len :0];

    const size = rl.measureTextEx(font, c_text, @floatFromInt(config.font_size), 0);
    return .{ .w = size.x, .h = size.y };
}

pub fn render(commands: []cl.RenderCommand) void {
    for (commands) |cmd| {
        const bbox = cmd.bounding_box;
        switch (cmd.command_type) {
            .rectangle => {
                const config = cmd.render_data.rectangle;
                rl.drawRectangleRounded(.{ .x = bbox.x, .y = bbox.y, .width = bbox.width, .height = bbox.height }, config.corner_radius.top_left / @min(bbox.width, bbox.height), 8, toRlColor(config.background_color));
            },
            .text => {
                const config = cmd.render_data.text;
                const text_len = config.string_contents.length;
                const text_ptr = config.string_contents.chars;
                const text = text_ptr[0..@intCast(text_len)];

                var buf: [1024]u8 = undefined;
                if (text.len < buf.len - 1) {
                    @memcpy(buf[0..text.len], text);
                    buf[text.len] = 0;
                    const c_text = buf[0..text.len :0];

                    if (rl.getFontDefault()) |font| {
                        rl.drawTextEx(font, c_text, .{ .x = bbox.x, .y = bbox.y }, @floatFromInt(config.font_size), 0, toRlColor(config.text_color));
                    } else |_| {}
                }
            },
            .scissor_start => {
                rl.beginScissorMode(@intFromFloat(bbox.x), @intFromFloat(bbox.y), @intFromFloat(bbox.width), @intFromFloat(bbox.height));
            },
            .scissor_end => {
                rl.endScissorMode();
            },
            .border => {
                const config = cmd.render_data.border;
                rl.drawRectangleRoundedLines(.{ .x = bbox.x, .y = bbox.y, .width = bbox.width, .height = bbox.height }, config.corner_radius.top_left / @min(bbox.width, bbox.height), 8, toRlColor(config.color));
            },
            else => {},
        }
    }
}
