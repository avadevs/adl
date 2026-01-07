const std = @import("std");
const adl = @import("adl");
const adl_rl = @import("adl_raylib");
const cl = adl.clay;
const rl = @import("raylib");

const Router = adl.router.Router;
const RouteArgs = adl.router.RouteArgs;
const Store = adl.store.Store;
const UIContext = adl.ui.context.UIContext;
const Theme = adl.ui.theme.THEME;

// ============================================================================
// Application State
// ============================================================================

const AppState = struct {
    opacity: f32 = 0.5,
    volume: f32 = 25.0,
    rating: f32 = 5.0,
    read_only_val: f32 = 0.75,
};

// Global context to allow screens to access systems.
const GlobalContext = struct {
    router: *Router,
    store: *Store(AppState),
    ui: *UIContext,
};

var g_ctx: GlobalContext = undefined;

// ============================================================================
// Screens
// ============================================================================

const SliderScreen = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, _: ?RouteArgs) !SliderScreen {
        return SliderScreen{
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *SliderScreen) void {
        // No cleanup needed
    }

    pub fn render(_: *SliderScreen) !void {
        const ui = adl.ui;
        const state = g_ctx.store.getCopy();

        cl.UI()(.{ .id = cl.ElementId.ID("Root"), .layout = .{
            .sizing = .grow,
            .direction = .top_to_bottom,
            .padding = .all(40),
            .child_gap = 20,
        }, .background_color = .{ 30, 30, 30, 255 } })({
            cl.text("Slider Component Demo", .{ .font_size = 32, .color = .{ 255, 255, 255, 255 } });

            // 1. Basic Opacity Slider (0.0 - 1.0)
            cl.UI()(.{ .layout = .{ .direction = .top_to_bottom, .child_gap = 8 } })({
                const label = std.fmt.allocPrint(g_ctx.ui.frame_allocator, "Opacity: {d:.2}", .{state.opacity}) catch "err";
                cl.text(label, .{ .font_size = 18, .color = .{ 200, 200, 200, 255 } });

                var op = state.opacity;
                if (try ui.slider("slider_opacity", &op, .{ .min = 0.0, .max = 1.0 })) {
                    const guard = g_ctx.store.write();
                    defer guard.release();
                    guard.state.opacity = op;
                }
            });

            // 2. Volume Slider (0 - 100)
            cl.UI()(.{ .layout = .{ .direction = .top_to_bottom, .child_gap = 8 } })({
                const label = std.fmt.allocPrint(g_ctx.ui.frame_allocator, "Volume: {d:.0}%", .{state.volume}) catch "err";
                cl.text(label, .{ .font_size = 18, .color = .{ 200, 200, 200, 255 } });

                var vol = state.volume;
                if (try ui.slider("slider_volume", &vol, .{ .min = 0, .max = 100 })) {
                    const guard = g_ctx.store.write();
                    defer guard.release();
                    guard.state.volume = vol;
                }
            });

            // 3. Stepped Slider (Rating 1-10)
            cl.UI()(.{ .layout = .{ .direction = .top_to_bottom, .child_gap = 8 } })({
                const label = std.fmt.allocPrint(g_ctx.ui.frame_allocator, "Rating: {d:.0}/10", .{state.rating}) catch "err";
                cl.text(label, .{ .font_size = 18, .color = .{ 200, 200, 200, 255 } });

                var rat = state.rating;
                if (try ui.slider("slider_rating", &rat, .{ .min = 1, .max = 10, .step = 1 })) {
                    const guard = g_ctx.store.write();
                    defer guard.release();
                    guard.state.rating = rat;
                }
            });

            // 4. Disabled Slider
            cl.UI()(.{ .layout = .{ .direction = .top_to_bottom, .child_gap = 8 } })({
                cl.text("Disabled (Read Only)", .{ .font_size = 18, .color = .{ 150, 150, 150, 255 } });

                var ro = state.read_only_val;
                _ = try ui.slider("slider_disabled", &ro, .{ .disabled = true });
            });

            // 5. Custom Width
            cl.UI()(.{ .layout = .{ .direction = .top_to_bottom, .child_gap = 8 } })({
                cl.text("Custom Width (Fixed 200px)", .{ .font_size = 18, .color = .{ 200, 200, 200, 255 } });

                var op = state.opacity;
                if (try ui.slider("slider_width", &op, .{ .width = .fixed(200) })) {
                    const guard = g_ctx.store.write();
                    defer guard.release();
                    guard.state.opacity = op;
                }
            });
        });
    }
};

// ============================================================================
// Main
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Init Raylib
    rl.setConfigFlags(rl.ConfigFlags{ .window_resizable = true, .msaa_4x_hint = true, .window_highdpi = true });
    rl.initWindow(800, 600, "ADL Slider Example");
    rl.setTargetFPS(60);
    defer rl.closeWindow();

    // Create rendering backend
    const backend = adl_rl.createInputBackend();

    // Init UI
    const theme = Theme.init();
    var ui_ctx = try UIContext.init(allocator, &theme, adl_rl.measureText, backend);
    defer ui_ctx.deinit();

    // Init Router
    var router = try Router.init(allocator, .{});
    defer router.deinit(&ui_ctx);
    try router.register("/", SliderScreen, null);

    // Init Store
    var store = Store(AppState).init(allocator, .{});
    defer store.deinit();

    // Init Clay
    const min_memory_size = cl.minMemorySize();
    const memory = try allocator.alloc(u8, min_memory_size);
    defer allocator.free(memory);

    const arena = cl.createArenaWithCapacityAndMemory(memory);
    _ = cl.initialize(arena, .{ .w = 800, .h = 600 }, .{});
    cl.setMeasureTextFunction(void, {}, adl_rl.measureText);

    // Setup global context
    g_ctx = .{
        .router = &router,
        .store = &store,
        .ui = &ui_ctx,
    };

    // Frame Allocator
    var frame_arena = std.heap.ArenaAllocator.init(allocator);
    defer frame_arena.deinit();

    // Set implicit scale factor from OS
    const scale = rl.getWindowScaleDPI();
    adl_rl.scale_factor = scale.x;

    // Navigate to home
    try router.navigate(&ui_ctx, "/");

    while (!rl.windowShouldClose()) {
        const delta_time = rl.getFrameTime();

        // Reset Frame Allocator
        _ = frame_arena.reset(.retain_capacity);
        ui_ctx.frame_allocator = frame_arena.allocator();

        // Update Layout Dimensions
        const screen_width = @as(f32, @floatFromInt(rl.getScreenWidth()));
        const screen_height = @as(f32, @floatFromInt(rl.getScreenHeight()));
        cl.setLayoutDimensions(.{ .w = screen_width / adl_rl.scale_factor, .h = screen_height / adl_rl.scale_factor });

        // Update Inputs
        const mouse_pos = adl_rl.getScaledMousePosition();
        cl.setPointerState(.{ .x = mouse_pos.x, .y = mouse_pos.y }, rl.isMouseButtonDown(.left));
        cl.updateScrollContainers(false, .{ .x = 0, .y = 0 }, delta_time);

        // Begin Frame
        ui_ctx.beginFrame(delta_time);

        // --- Clay Layout Phase ---
        cl.beginLayout();

        router.render(&ui_ctx) catch |err| {
            std.log.err("Render error: {}", .{err});
        };

        const commands = cl.endLayout();
        // -------------------------

        // --- Raylib Render Phase ---
        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);

        adl_rl.render(commands);

        rl.endDrawing();
        // ---------------------------
    }
}
