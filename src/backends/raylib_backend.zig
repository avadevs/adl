const std = @import("std");
const rl = @import("raylib");
const cl = @import("zclay");
const adl = @import("adl");

const types = adl.ui.types;
const InputBackend = adl.ui.input.InputBackend;

// ============================================================================
// Input Backend Implementation
// ============================================================================

// Global font storage for the backend
pub var fonts: [16]?rl.Font = @splat(null);

fn getMousePosition(_: *anyopaque) types.Vector2 {
    const pos = rl.getMousePosition();
    return .{ .x = pos.x, .y = pos.y };
}

fn getMouseWheelMove(_: *anyopaque) types.Vector2 {
    const wheel = rl.getMouseWheelMoveV();
    return .{ .x = wheel.x, .y = wheel.y };
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
    return switch (key) {
        .space => .space,
        .escape => .escape,
        .enter => .enter,
        .tab => .tab,
        .backspace => .backspace,
        .insert => .insert,
        .delete => .delete,
        .right => .right,
        .left => .left,
        .down => .down,
        .up => .up,
        .page_up => .page_up,
        .page_down => .page_down,
        .home => .home,
        .end => .end,
        .caps_lock => .caps_lock,
        .scroll_lock => .scroll_lock,
        .num_lock => .num_lock,
        .print_screen => .print_screen,
        .pause => .pause,
        .f1 => .f1,
        .f2 => .f2,
        .f3 => .f3,
        .f4 => .f4,
        .f5 => .f5,
        .f6 => .f6,
        .f7 => .f7,
        .f8 => .f8,
        .f9 => .f9,
        .f10 => .f10,
        .f11 => .f11,
        .f12 => .f12,
        .left_shift => .left_shift,
        .left_control => .left_control,
        .left_alt => .left_alt,
        .left_super => .left_super,
        .right_shift => .right_shift,
        .right_control => .right_control,
        .right_alt => .right_alt,
        .right_super => .right_super,
        .kb_menu => .kb_menu,
        .left_bracket => .left_bracket,
        .backslash => .backslash,
        .right_bracket => .right_bracket,
        .grave => .grave,
        .kp_0 => .kp_0,
        .kp_1 => .kp_1,
        .kp_2 => .kp_2,
        .kp_3 => .kp_3,
        .kp_4 => .kp_4,
        .kp_5 => .kp_5,
        .kp_6 => .kp_6,
        .kp_7 => .kp_7,
        .kp_8 => .kp_8,
        .kp_9 => .kp_9,
        .kp_decimal => .kp_decimal,
        .kp_divide => .kp_divide,
        .kp_multiply => .kp_multiply,
        .kp_subtract => .kp_subtract,
        .kp_add => .kp_add,
        .kp_enter => .kp_enter,
        .kp_equal => .kp_equal,
        .apostrophe => .apostrophe,
        .comma => .comma,
        .minus => .minus,
        .period => .period,
        .slash => .slash,
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
        .semicolon => .semicolon,
        .equal => .equal,
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
        else => .null,
    };
}

fn mapRlKey(key: rl.KeyboardKey) types.Key {
    return switch (key) {
        .space => .space,
        .escape => .escape,
        .enter => .enter,
        .tab => .tab,
        .backspace => .backspace,
        .insert => .insert,
        .delete => .delete,
        .right => .right,
        .left => .left,
        .down => .down,
        .up => .up,
        .page_up => .page_up,
        .page_down => .page_down,
        .home => .home,
        .end => .end,
        .caps_lock => .caps_lock,
        .scroll_lock => .scroll_lock,
        .num_lock => .num_lock,
        .print_screen => .print_screen,
        .pause => .pause,
        .f1 => .f1,
        .f2 => .f2,
        .f3 => .f3,
        .f4 => .f4,
        .f5 => .f5,
        .f6 => .f6,
        .f7 => .f7,
        .f8 => .f8,
        .f9 => .f9,
        .f10 => .f10,
        .f11 => .f11,
        .f12 => .f12,
        .left_shift => .left_shift,
        .left_control => .left_control,
        .left_alt => .left_alt,
        .left_super => .left_super,
        .right_shift => .right_shift,
        .right_control => .right_control,
        .right_alt => .right_alt,
        .right_super => .right_super,
        .kb_menu => .kb_menu,
        .left_bracket => .left_bracket,
        .backslash => .backslash,
        .right_bracket => .right_bracket,
        .grave => .grave,
        .kp_0 => .kp_0,
        .kp_1 => .kp_1,
        .kp_2 => .kp_2,
        .kp_3 => .kp_3,
        .kp_4 => .kp_4,
        .kp_5 => .kp_5,
        .kp_6 => .kp_6,
        .kp_7 => .kp_7,
        .kp_8 => .kp_8,
        .kp_9 => .kp_9,
        .kp_decimal => .kp_decimal,
        .kp_divide => .kp_divide,
        .kp_multiply => .kp_multiply,
        .kp_subtract => .kp_subtract,
        .kp_add => .kp_add,
        .kp_enter => .kp_enter,
        .kp_equal => .kp_equal,
        .apostrophe => .apostrophe,
        .comma => .comma,
        .minus => .minus,
        .period => .period,
        .slash => .slash,
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
        .semicolon => .semicolon,
        .equal => .equal,
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
    const font = fonts[config.font_id] orelse rl.getFontDefault() catch return .{ .w = 0, .h = 0 };

    // Safety buffer for C-string conversion (increased to 8KB)
    var buf: [8192]u8 = undefined;
    if (text.len >= buf.len - 1) return .{ .w = 0, .h = 0 };
    @memcpy(buf[0..text.len], text);
    buf[text.len] = 0;
    const c_text = buf[0..text.len :0];

    const size = rl.measureTextEx(font, c_text, @floatFromInt(config.font_size), @floatFromInt(config.letter_spacing));
    return .{ .w = size.x, .h = size.y };
}

pub fn render(commands: []cl.RenderCommand) void {
    for (commands) |cmd| {
        const bbox = cmd.bounding_box;
        switch (cmd.command_type) {
            .rectangle => {
                const config = cmd.render_data.rectangle;
                if (config.corner_radius.top_left > 0) {
                    rl.drawRectangleRounded(.{ .x = bbox.x, .y = bbox.y, .width = bbox.width, .height = bbox.height }, config.corner_radius.top_left / @min(bbox.width, bbox.height), 8, toRlColor(config.background_color));
                } else {
                    rl.drawRectangle(
                        @intFromFloat(bbox.x),
                        @intFromFloat(bbox.y),
                        @intFromFloat(bbox.width),
                        @intFromFloat(bbox.height),
                        toRlColor(config.background_color),
                    );
                }
            },
            .text => {
                const config = cmd.render_data.text;
                const text_len = config.string_contents.length;
                const text_ptr = config.string_contents.chars;
                const text = text_ptr[0..@intCast(text_len)];

                var buf: [8192]u8 = undefined;
                if (text.len < buf.len - 1) {
                    @memcpy(buf[0..text.len], text);
                    buf[text.len] = 0;
                    const c_text = buf[0..text.len :0];

                    const font = fonts[config.font_id] orelse rl.getFontDefault() catch continue;
                    rl.drawTextEx(font, c_text, .{ .x = bbox.x, .y = bbox.y }, @floatFromInt(config.font_size), @floatFromInt(config.letter_spacing), toRlColor(config.text_color));
                }
            },
            .image => {
                const config = cmd.render_data.image;
                var tint = config.background_color;
                if (std.mem.eql(f32, &tint, &.{ 0, 0, 0, 0 })) {
                    tint = .{ 255, 255, 255, 255 };
                }

                if (config.image_data) |data| {
                    const image_texture: *const rl.Texture2D = @ptrCast(@alignCast(data));
                    rl.drawTextureEx(
                        image_texture.*,
                        rl.Vector2{ .x = bbox.x, .y = bbox.y },
                        0,
                        bbox.width / @as(f32, @floatFromInt(image_texture.width)),
                        toRlColor(tint),
                    );
                }
            },
            .scissor_start => {
                rl.beginScissorMode(@intFromFloat(@round(bbox.x)), @intFromFloat(@round(bbox.y)), @intFromFloat(@round(bbox.width)), @intFromFloat(@round(bbox.height)));
            },
            .scissor_end => {
                rl.endScissorMode();
            },
            .border => {
                const config = cmd.render_data.border;
                const color = toRlColor(config.color);
                const corners = config.corner_radius;

                // Helper to draw a rectangle
                const drawRect = struct {
                    fn draw(x: f32, y: f32, w: f32, h: f32, c: rl.Color) void {
                        rl.drawRectangle(@intFromFloat(@round(x)), @intFromFloat(@round(y)), @intFromFloat(@round(w)), @intFromFloat(@round(h)), c);
                    }
                }.draw;

                // Left
                if (config.width.left > 0) {
                    drawRect(
                        bbox.x,
                        bbox.y + corners.top_left,
                        @floatFromInt(config.width.left),
                        bbox.height - corners.top_left - corners.bottom_left,
                        color,
                    );
                }

                // Right
                if (config.width.right > 0) {
                    drawRect(
                        bbox.x + bbox.width - @as(f32, @floatFromInt(config.width.right)),
                        bbox.y + corners.top_right,
                        @floatFromInt(config.width.right),
                        bbox.height - corners.top_right - corners.bottom_right,
                        color,
                    );
                }

                // Top
                if (config.width.top > 0) {
                    drawRect(
                        bbox.x + corners.top_left,
                        bbox.y,
                        bbox.width - corners.top_left - corners.top_right,
                        @floatFromInt(config.width.top),
                        color,
                    );
                }

                // Bottom
                if (config.width.bottom > 0) {
                    drawRect(
                        bbox.x + corners.bottom_left,
                        bbox.y + bbox.height - @as(f32, @floatFromInt(config.width.bottom)),
                        bbox.width - corners.bottom_left - corners.bottom_right,
                        @floatFromInt(config.width.bottom),
                        color,
                    );
                }

                // Helper to draw a corner ring
                const drawCorner = struct {
                    fn draw(center: rl.Vector2, innerRadius: f32, outerRadius: f32, startAngle: f32, endAngle: f32, c: rl.Color) void {
                        if (outerRadius <= 0) return;
                        rl.drawRing(center, innerRadius, outerRadius, startAngle, endAngle, 10, c);
                    }
                }.draw;

                // Top Left
                if (corners.top_left > 0) {
                    drawCorner(
                        rl.Vector2{ .x = bbox.x + corners.top_left, .y = bbox.y + corners.top_left },
                        corners.top_left - @as(f32, @floatFromInt(config.width.top)),
                        corners.top_left,
                        180,
                        270,
                        color,
                    );
                }

                // Top Right
                if (corners.top_right > 0) {
                    drawCorner(
                        rl.Vector2{ .x = bbox.x + bbox.width - corners.top_right, .y = bbox.y + corners.top_right },
                        corners.top_right - @as(f32, @floatFromInt(config.width.top)),
                        corners.top_right,
                        270,
                        360,
                        color,
                    );
                }

                // Bottom Left
                if (corners.bottom_left > 0) {
                    drawCorner(
                        rl.Vector2{ .x = bbox.x + corners.bottom_left, .y = bbox.y + bbox.height - corners.bottom_left },
                        corners.bottom_left - @as(f32, @floatFromInt(config.width.bottom)),
                        corners.bottom_left,
                        90,
                        180,
                        color,
                    );
                }

                // Bottom Right
                if (corners.bottom_right > 0) {
                    drawCorner(
                        rl.Vector2{ .x = bbox.x + bbox.width - corners.bottom_right, .y = bbox.y + bbox.height - corners.bottom_right },
                        corners.bottom_right - @as(f32, @floatFromInt(config.width.bottom)),
                        corners.bottom_right,
                        0.1,
                        90,
                        color,
                    );
                }
            },
            else => {},
        }
    }
}
