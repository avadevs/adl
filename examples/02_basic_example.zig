const std = @import("std");
const adl = @import("adl");
const cl = @import("zclay");
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
    const UpdateCtx = struct {
        val: u32,
        fn update(self: @This(), state: *AppState) void {
            state.last_job_result = self.val;
            state.loading = false;
        }
    };

    data.store.updateWith(UpdateCtx{ .val = data.value * 2 }, UpdateCtx.update);

    return .{ .completed = null };
}

// ============================================================================
// Screens
// ============================================================================

const HomeScreen = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, _: ?RouteArgs) !HomeScreen {
        return HomeScreen{
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *HomeScreen) void {}

    pub fn render(_: *HomeScreen) void {
        const ui = g_ctx.ui;

        // Access state safely
        const state = g_ctx.store.getCopy();

        cl.UI()(.{ .id = cl.ElementId.localID("MainContainer"), .layout = .{ .direction = .top_to_bottom, .sizing = .grow, .padding = .all(20), .child_gap = 10, .child_alignment = .{ .x = .center, .y = .center } } })({
            cl.text("ADL Basic Example", .{ .font_size = 32, .color = .{ 200, 200, 200, 255 } });

            cl.text(std.fmt.allocPrint(g_ctx.ui.frame_allocator, "Counter: {}", .{state.counter}) catch "Counter: ?", .{ .font_size = 24, .color = .{ 150, 150, 150, 255 } });

            cl.text(std.fmt.allocPrint(g_ctx.ui.frame_allocator, "Last Job Result: {}", .{state.last_job_result}) catch "Result: ?", .{ .font_size = 24, .color = .{ 150, 150, 150, 255 } });

            // Example: Render a button (logically)
            if (adl.ui.button.render(ui, cl.ElementId.localID("btn_inc"), .{ .text = "Increment Counter", .variant = .primary })) {
                const IncCtx = struct {
                    fn update(_: @This(), s: *AppState) void {
                        s.counter += 1;
                    }
                };
                g_ctx.store.updateWith(IncCtx{}, IncCtx.update);
                std.log.info("Button clicked! Counter: {}", .{state.counter});
            }

            if (adl.ui.button.render(ui, cl.ElementId.localID("btn_job"), .{ .text = if (state.loading) "Processing..." else "Run Background Job", .is_disabled = state.loading, .variant = .accent })) {
                // Schedule a job
                const job_data = g_ctx.jobs.allocator.create(JobData) catch return;
                job_data.* = .{ .value = state.counter, .store = g_ctx.store };

                // Set loading state
                const LoadCtx = struct {
                    fn update(_: @This(), s: *AppState) void {
                        s.loading = true;
                    }
                };
                g_ctx.store.updateWith(LoadCtx{}, LoadCtx.update);

                _ = g_ctx.jobs.schedule(simulationJob, job_data) catch |err| {
                    std.log.err("Failed to schedule job: {}", .{err});
                };
            }
        });
    }
};

// ============================================================================
// Raylib Integration
// ============================================================================

fn toRlColor(color: cl.Color) rl.Color {
    return .{
        .r = @intFromFloat(color[0]),
        .g = @intFromFloat(color[1]),
        .b = @intFromFloat(color[2]),
        .a = @intFromFloat(color[3]),
    };
}

fn raylibMeasureText(text: []const u8, config: *cl.TextElementConfig, _: void) cl.Dimensions {
    const font = rl.getFontDefault() catch return .{ .w = 0, .h = 0 };
    // Raylib expects a null-terminated string.
    // We'll use a small buffer on stack for short strings, or alloc for long ones.
    // Ideally we'd use an allocator passed in context, but for this signature we don't have it easily.
    // However, text measurement is frequent.
    // Let's assume text is relatively short for UI labels.
    var buf: [1024]u8 = undefined;
    if (text.len >= buf.len - 1) return .{ .w = 0, .h = 0 }; // Truncate or fail if too long
    @memcpy(buf[0..text.len], text);
    buf[text.len] = 0;
    const c_text = buf[0..text.len :0];

    const size = rl.measureTextEx(font, c_text, @floatFromInt(config.font_size), 0);
    return .{ .w = size.x, .h = size.y };
}

fn clayRaylibRender(commands: []cl.RenderCommand) void {
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
                // Simple border implementation
                const config = cmd.render_data.border;
                // Note: This version of raylib wrapper might not support line thickness in DrawRectangleRoundedLines
                rl.drawRectangleRoundedLines(.{ .x = bbox.x, .y = bbox.y, .width = bbox.width, .height = bbox.height }, config.corner_radius.top_left / @min(bbox.width, bbox.height), 8, toRlColor(config.color));
            },
            else => {},
        }
    }
}

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

    // 2. Init Router
    var router = try Router.init(allocator, .{});
    defer router.deinit();

    try router.register("/", HomeScreen, null);

    // 3. Init Store
    var store = Store(AppState).init(allocator, .{});
    defer store.deinit();

    // 4. Init UI
    const theme = Theme.init();
    var ui_ctx = try UIContext.init(allocator, &theme, raylibMeasureText);
    defer ui_ctx.deinit();

    // Init Clay
    const min_memory_size = cl.minMemorySize();
    const memory = try allocator.alloc(u8, min_memory_size);
    defer allocator.free(memory);

    const arena = cl.createArenaWithCapacityAndMemory(memory);
    _ = cl.initialize(arena, .{ .w = 800, .h = 600 }, .{});
    cl.setMeasureTextFunction(void, {}, raylibMeasureText);

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
    try router.navigate("/");

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
            router.render();
        });
        const commands = cl.endLayout();
        // -------------------------

        // --- Raylib Render Phase ---
        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);

        clayRaylibRender(commands);

        rl.endDrawing();
        // ---------------------------
    }

    std.log.info("Example completed successfully.", .{});
}
