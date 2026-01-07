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
// Data Models
// ============================================================================

const Fruit = enum { Apple, Banana, Orange, Mango, Pineapple, Strawberry };

fn fruitLabel(f: Fruit) []const u8 {
    return switch (f) {
        .Apple => "Apple",
        .Banana => "Banana",
        .Orange => "Orange",
        .Mango => "Mango",
        .Pineapple => "Pineapple",
        .Strawberry => "Strawberry",
    };
}

// ============================================================================
// Application State
// ============================================================================

const AppState = struct {
    single_selection: ?usize = null,

    // Multi-select state
    // We'll use a boolean mask for simplicity as per the component design
    multi_selection: [6]bool = .{ false, false, false, false, false, false },

    // Constant data source
    fruits: [6]Fruit = .{ .Apple, .Banana, .Orange, .Mango, .Pineapple, .Strawberry },
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

const DropdownScreen = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, _: ?RouteArgs) !DropdownScreen {
        return DropdownScreen{
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *DropdownScreen) void {
        // No cleanup needed
    }

    pub fn render(_: *DropdownScreen) !void {
        const ui = adl.ui;
        const state = g_ctx.store.getCopy();

        cl.UI()(.{ .id = cl.ElementId.ID("Root"), .layout = .{
            .sizing = .grow,
            .direction = .top_to_bottom,
            .padding = .all(40),
            .child_gap = 40,
        }, .background_color = .{ 30, 30, 30, 255 } })({
            cl.text("Dropdown & Select Demo", .{ .font_size = 32, .color = .{ 255, 255, 255, 255 } });

            // 1. Single Select
            cl.UI()(.{ .layout = .{ .direction = .top_to_bottom, .child_gap = 10 } })({
                cl.text("Single Select", .{ .font_size = 24, .color = .{ 200, 200, 200, 255 } });

                if (state.single_selection) |idx| {
                    const label = std.fmt.allocPrint(g_ctx.ui.frame_allocator, "Selected: {s}", .{fruitLabel(state.fruits[idx])}) catch "";
                    cl.text(label, .{ .font_size = 16, .color = .{ 150, 255, 150, 255 } });
                } else {
                    cl.text("No selection", .{ .font_size = 16, .color = .{ 150, 150, 150, 255 } });
                }

                const FruitSelect = ui.Select(Fruit);
                if (try FruitSelect.render("fruit_select", .{
                    .items = &state.fruits,
                    .selected_index = state.single_selection,
                    .label_fn = fruitLabel,
                    .width = .fixed(250),
                    .placeholder = "Choose a fruit...",
                })) |new_idx| {
                    const guard = g_ctx.store.write();
                    defer guard.release();
                    guard.state.single_selection = new_idx;
                }
            });

            // 2. Multi Select
            cl.UI()(.{ .layout = .{ .direction = .top_to_bottom, .child_gap = 10 } })({
                cl.text("Multi Select", .{ .font_size = 24, .color = .{ 200, 200, 200, 255 } });

                // Show selected list
                var count: usize = 0;
                for (state.multi_selection) |sel| {
                    if (sel) count += 1;
                }
                const label = std.fmt.allocPrint(g_ctx.ui.frame_allocator, "{d} items selected", .{count}) catch "";
                cl.text(label, .{ .font_size = 16, .color = .{ 150, 255, 150, 255 } });

                const FruitMulti = ui.MultiSelect(Fruit);
                if (try FruitMulti.render("fruit_multi", .{
                    .items = &state.fruits,
                    .selected_mask = &state.multi_selection,
                    .label_fn = fruitLabel,
                    .width = .fixed(250),
                })) |toggled_index| {
                    const guard = g_ctx.store.write();
                    defer guard.release();
                    // Toggle boolean
                    guard.state.multi_selection[toggled_index] = !guard.state.multi_selection[toggled_index];
                }
            });

            // 3. Dropdown Menu
            cl.UI()(.{ .layout = .{ .direction = .top_to_bottom, .child_gap = 10 } })({
                cl.text("Dropdown Menu", .{ .font_size = 24, .color = .{ 200, 200, 200, 255 } });
                cl.text("Click to open menu", .{ .font_size = 16, .color = .{ 150, 150, 150, 255 } });

                const DM = ui.DropdownMenu;
                if (try DM.begin("demo_menu", .{ .label = "Options", .width = .fixed(200) })) |menu| {
                    defer menu.end();

                    if (menu.item("Profile", .{})) {
                        std.log.info("Menu: Profile selected", .{});
                    }
                    if (menu.item("Settings", .{ .shortcut = "Ctrl+S" })) {
                        std.log.info("Menu: Settings selected", .{});
                    }

                    menu.separator();

                    if (menu.item("Delete", .{ .destructive = true })) {
                        std.log.info("Menu: Delete selected", .{});
                    }
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
    rl.initWindow(800, 600, "ADL Dropdown Example");
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
    try router.register("/", DropdownScreen, null);

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
