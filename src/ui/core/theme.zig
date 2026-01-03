const cl = @import("zclay");

pub const THEME = struct {
    color_base_100: cl.Color,
    color_base_200: cl.Color,
    color_base_300: cl.Color,
    color_base_content: cl.Color,
    color_primary: cl.Color,
    color_primary_content: cl.Color,
    color_second: cl.Color,
    color_second_content: cl.Color,
    color_accent: cl.Color,
    color_accent_content: cl.Color,
    color_neutral: cl.Color,
    color_neutral_content: cl.Color,
    color_info: cl.Color,
    color_info_content: cl.Color,
    color_success: cl.Color,
    color_success_content: cl.Color,
    color_warning: cl.Color,
    color_warning_content: cl.Color,
    color_error: cl.Color,
    color_error_content: cl.Color,
    radius_selector: u16,
    radius_field: f32,
    radius_box: f32,
    size_selector: u16,
    size_field: u16,
    border: u16,
    depth: u16,
    noise: u16,

    pub fn init() THEME {
        return .{
            .color_base_100 = .{ 32, 32, 32, 255 },
            .color_base_200 = .{ 28, 28, 28, 255 },
            .color_base_300 = .{ 24, 24, 24, 255 },
            .color_base_content = .{ 205, 205, 205, 255 },
            .color_primary = .{ 28, 78, 128, 255 },
            .color_primary_content = .{ 208, 218, 229, 255 },
            .color_second = .{ 124, 144, 154, 255 },
            .color_second_content = .{ 5, 7, 8, 255 },
            .color_accent = .{ 234, 105, 71, 255 },
            .color_accent_content = .{ 19, 4, 2, 255 },
            .color_neutral = .{ 35, 40, 46, 255 },
            .color_neutral_content = .{ 206, 207, 208, 255 },
            .color_info = .{ 2, 145, 213, 255 },
            .color_info_content = .{ 0, 7, 16, 255 },
            .color_success = .{ 107, 177, 135, 255 },
            .color_success_content = .{ 4, 11, 7, 255 },
            .color_warning = .{ 219, 174, 90, 255 },
            .color_warning_content = .{ 17, 11, 3, 255 },
            .color_error = .{ 172, 62, 49, 255 },
            .color_error_content = .{ 242, 216, 212, 255 },
            .radius_selector = 0,
            .radius_field = 4,
            .radius_box = 4,
            .size_selector = 4,
            .size_field = 4,
            .border = 2,
            .depth = 0,
            .noise = 0,
        };
    }
};

pub const ThemeOverrides = struct {
    color_base_100: ?cl.Color = null,
    color_base_200: ?cl.Color = null,
    color_base_300: ?cl.Color = null,
    color_base_content: ?cl.Color = null,
    color_primary: ?cl.Color = null,
    color_primary_content: ?cl.Color = null,
    color_second: ?cl.Color = null,
    color_second_content: ?cl.Color = null,
    color_accent: ?cl.Color = null,
    color_accent_content: ?cl.Color = null,
    color_neutral: ?cl.Color = null,
    color_neutral_content: ?cl.Color = null,
    color_info: ?cl.Color = null,
    color_info_content: ?cl.Color = null,
    color_success: ?cl.Color = null,
    color_success_content: ?cl.Color = null,
    color_warning: ?cl.Color = null,
    color_warning_content: ?cl.Color = null,
    color_error: ?cl.Color = null,
    color_error_content: ?cl.Color = null,
    radius_selector: ?u16 = null,
    radius_field: ?f32 = null,
    radius_box: ?f32 = null,
    size_selector: ?u16 = null,
    size_field: ?u16 = null,
    border: ?u16 = null,
    depth: ?u16 = null,
    noise: ?u16 = null,
};

pub fn merge(base: THEME, overrides: ?ThemeOverrides) THEME {
    const ov = overrides orelse return base;
    var new = base;
    if (ov.color_base_100) |c| new.color_base_100 = c;
    if (ov.color_base_200) |c| new.color_base_200 = c;
    if (ov.color_base_300) |c| new.color_base_300 = c;
    if (ov.color_base_content) |c| new.color_base_content = c;
    if (ov.color_primary) |c| new.color_primary = c;
    if (ov.color_primary_content) |c| new.color_primary_content = c;
    if (ov.color_second) |c| new.color_second = c;
    if (ov.color_second_content) |c| new.color_second_content = c;
    if (ov.color_accent) |c| new.color_accent = c;
    if (ov.color_accent_content) |c| new.color_accent_content = c;
    if (ov.color_neutral) |c| new.color_neutral = c;
    if (ov.color_neutral_content) |c| new.color_neutral_content = c;
    if (ov.color_info) |c| new.color_info = c;
    if (ov.color_info_content) |c| new.color_info_content = c;
    if (ov.color_success) |c| new.color_success = c;
    if (ov.color_success_content) |c| new.color_success_content = c;
    if (ov.color_warning) |c| new.color_warning = c;
    if (ov.color_warning_content) |c| new.color_warning_content = c;
    if (ov.color_error) |c| new.color_error = c;
    if (ov.color_error_content) |c| new.color_error_content = c;
    if (ov.radius_selector) |v| new.radius_selector = v;
    if (ov.radius_field) |v| new.radius_field = v;
    if (ov.radius_box) |v| new.radius_box = v;
    if (ov.size_selector) |v| new.size_selector = v;
    if (ov.size_field) |v| new.size_field = v;
    if (ov.border) |v| new.border = v;
    if (ov.depth) |v| new.depth = v;
    if (ov.noise) |v| new.noise = v;
    return new;
}
