const std = @import("std");
const adl = @import("adl");
const adl_rl = @import("adl_raylib");
const cl = adl.clay;
const rl = @import("raylib");

const Jobs = adl.jobs.Jobs;
const JobsOptions = adl.jobs.JobsOptions;
const JobOutcome = adl.jobs.JobOutcome;

const Router = adl.router.Router;
const RouteArgs = adl.router.RouteArgs;

const Store = adl.store.Store;
const UIContext = adl.ui.context.UIContext;
const Theme = adl.ui.theme.THEME;

// ============================================================================
// Application State
// ============================================================================

const AppState = struct {
    counter: u32 = 0,
    last_job_result: u32 = 0,
    loading: bool = false,
};

// Global context to allow screens to access systems.
const GlobalContext = struct {
    jobs: *Jobs,
    router: *Router,
    store: *Store(AppState),
    ui: *UIContext,
};

var g_ctx: GlobalContext = undefined;

// ============================================================================
// Jobs
// ============================================================================

const JobData = struct {
    value: u32,
    store: *Store(AppState),
};

fn simulationJob(jobs: *Jobs, ctx_ptr: *anyopaque) JobOutcome {
    const data: *JobData = @ptrCast(@alignCast(ctx_ptr));
    defer jobs.allocator.destroy(data); // Clean up context

    // Simulate work
    std.Thread.sleep(1000 * 1000 * 1000); // 1000ms

    // Update store
    {
        const guard = data.store.write();
        defer guard.release();
        guard.state.last_job_result = data.value * 2;
        guard.state.loading = false;
    }

    return .{ .completed = null };
}

// ============================================================================
// Screens
// ============================================================================

const HomeScreen = struct {
    allocator: std.mem.Allocator,
    text_buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, _: ?RouteArgs) !HomeScreen {
        return HomeScreen{
            .allocator = allocator,
            .text_buffer = try std.ArrayList(u8).initCapacity(allocator, 32),
        };
    }

    pub fn deinit(self: *HomeScreen) void {
        self.text_buffer.deinit(self.allocator);
    }

    pub fn render(self: *HomeScreen) !void {
        const ui = adl.ui;

        // Access state safely
        const state = g_ctx.store.getCopy();

        cl.UI()(.{ .id = cl.ElementId.ID("MainContainer"), .layout = .{ .direction = .top_to_bottom, .sizing = .grow, .padding = .all(20), .child_gap = 10, .child_alignment = .{ .x = .center, .y = .center } } })({
            cl.text("ADL Basic Example", .{ .font_size = 32, .color = .{ 200, 200, 200, 255 } });

            cl.text(std.fmt.allocPrint(g_ctx.ui.frame_allocator, "Counter: {}", .{state.counter}) catch "Counter: ?", .{ .font_size = 24, .color = .{ 150, 150, 150, 255 } });

            cl.text(std.fmt.allocPrint(g_ctx.ui.frame_allocator, "Last Job Result: {}", .{state.last_job_result}) catch "Result: ?", .{ .font_size = 24, .color = .{ 150, 150, 150, 255 } });

            // Example: Textbox
            try ui.textbox("my_input", &self.text_buffer, .{
                .placeholder = "Enter number to add...",
            });

            // Example: Scroll Area
            try ui.scrollArea("scroll_area", .{ .content_height = 200 }, struct {
                fn render() void {
                    cl.text("I am inside a scroll area!", .{ .font_size = 20, .color = .{ 255, 255, 255, 255 } });
                    cl.text("Me too!", .{ .font_size = 20, .color = .{ 200, 200, 200, 255 } });
                    cl.text("Me three!", .{ .font_size = 20, .color = .{ 150, 150, 150, 255 } });
                    cl.text("Me four!", .{ .font_size = 20, .color = .{ 100, 100, 100, 255 } });
                    cl.text("Me five!", .{ .font_size = 20, .color = .{ 50, 50, 50, 255 } });
                    cl.text("Me six!", .{ .font_size = 20, .color = .{ 100, 100, 100, 255 } });
                    cl.text("Me seven!", .{ .font_size = 20, .color = .{ 150, 150, 150, 255 } });
                    cl.text("Me eight!", .{ .font_size = 20, .color = .{ 200, 200, 200, 255 } });
                }
            }.render);

            // Render buttons normally
            if (try ui.button("btn_inc", .{ .text = "Increment Counter", .variant = .primary })) {
                {
                    const guard = g_ctx.store.write();
                    defer guard.release();
                    guard.state.counter += 1;
                }
                std.log.info("Button clicked! Counter: {}", .{state.counter});
            }

            if (try ui.button("btn_job", .{ .text = if (state.loading) "Processing..." else "Run Background Job", .is_disabled = state.loading, .variant = .accent })) {
                // Parse input
                const input_val = std.fmt.parseInt(u32, self.text_buffer.items, 10) catch 0;

                // Schedule a job
                const job_data = g_ctx.jobs.allocator.create(JobData) catch return;
                job_data.* = .{ .value = state.counter + input_val, .store = g_ctx.store };
                {
                    const guard = g_ctx.store.write();
                    defer guard.release();
                    guard.state.loading = true;
                }
                _ = g_ctx.jobs.schedule(simulationJob, job_data) catch |err| {
                    std.log.err("Failed to schedule job: {}", .{err});
                };
            }
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

    // 1. Init Jobs
    var jobs = try Jobs.init(allocator, .{
        .job_capacity = 64,
        .thread_count = 2,
    });
    try jobs.start();
    defer jobs.deinit();

    // Create rendering backend
    const backend = adl_rl.createInputBackend();

    // 2. Init UI
    const theme = Theme.init();

    var ui_ctx = try UIContext.init(allocator, &theme, adl_rl.measureText, backend);
    defer ui_ctx.deinit();

    // 3. Init Router
    var router = try Router.init(allocator, .{});
    defer router.deinit(&ui_ctx);
    try router.register("/", HomeScreen, null);

    // 3. Init Store
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
        .jobs = &jobs,
        .router = &router,
        .store = &store,
        .ui = &ui_ctx,
    };

    // Frame Allocator
    var frame_arena = std.heap.ArenaAllocator.init(allocator);
    defer frame_arena.deinit();

    // Init Raylib
    rl.setConfigFlags(rl.ConfigFlags{ .window_resizable = true, .msaa_4x_hint = true });
    rl.initWindow(800, 600, "ADL Basic Example");
    rl.setTargetFPS(60);
    defer rl.closeWindow();

    std.log.info("System initialized. Starting loop...", .{});

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
        cl.setLayoutDimensions(.{ .w = screen_width, .h = screen_height });

        // Update Inputs
        const mouse_pos = rl.getMousePosition();
        cl.setPointerState(.{ .x = mouse_pos.x, .y = mouse_pos.y }, rl.isMouseButtonDown(.left));

        const wheel_delta = rl.getMouseWheelMoveV();
        cl.updateScrollContainers(false, .{ .x = wheel_delta.x, .y = wheel_delta.y }, delta_time);

        // Begin Frame
        ui_ctx.beginFrame(delta_time);

        // --- Clay Layout Phase ---
        cl.beginLayout();
        cl.UI()(.{ .id = cl.ElementId.ID("Root"), .layout = .{ .sizing = .grow, .direction = .top_to_bottom }, .background_color = .{ 30, 30, 30, 255 } })({
            router.render(&ui_ctx) catch |err| {
                std.log.err("Render error: {}", .{err});
            };
        });
        const commands = cl.endLayout();
        // -------------------------

        // --- Raylib Render Phase ---
        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);

        adl_rl.render(commands);

        rl.endDrawing();
        // ---------------------------
    }

    std.log.info("Example completed successfully.", .{});
}
