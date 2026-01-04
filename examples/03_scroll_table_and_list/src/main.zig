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
const ui = adl.ui;

// Types
const Item = struct {
    id: usize,
    name: []const u8,
    score: u32,
    category: []const u8,
};

const AppState = struct {
    items: std.ArrayList(Item),
};

const GlobalContext = struct {
    router: *Router,
    store: *Store(AppState),
    ui: *UIContext,
};

var g_ctx: GlobalContext = undefined;

// Screen
const HomeScreen = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, _: ?RouteArgs) !HomeScreen {
        // Init some dummy data if empty
        var needs_init = false;
        {
            const guard = g_ctx.store.read();
            defer guard.release();
            if (guard.state.items.items.len == 0) {
                needs_init = true;
            }
        }

        if (needs_init) {
            var guard = g_ctx.store.write();
            defer guard.release();

            try guard.state.items.append(allocator, .{ .id = 1, .name = "Item Alpha", .score = 100, .category = "A" });
            try guard.state.items.append(allocator, .{ .id = 2, .name = "Item Beta", .score = 50, .category = "B" });
            try guard.state.items.append(allocator, .{ .id = 3, .name = "Item Gamma", .score = 75, .category = "A" });
            try guard.state.items.append(allocator, .{ .id = 4, .name = "Item Delta", .score = 25, .category = "C" });
            try guard.state.items.append(allocator, .{ .id = 5, .name = "Item Epsilon", .score = 90, .category = "B" });

            // Add more items to trigger scrolling
            var i: usize = 6;
            while (i <= 50) : (i += 1) {
                const cat = if (i % 3 == 0) "A" else if (i % 3 == 1) "B" else "C";
                const score = (i * 13) % 100;
                // Use the allocator passed to init (which is persistent)
                const name = try std.fmt.allocPrint(allocator, "Item {}", .{i});
                try guard.state.items.append(allocator, .{ .id = i, .name = name, .score = @intCast(score), .category = cat });
            }
        }
        return HomeScreen{ .allocator = allocator };
    }

    pub fn deinit(self: *HomeScreen) void {
        _ = self;
    }

    pub fn render(self: *HomeScreen) void {
        const state_guard = g_ctx.store.read();
        defer state_guard.release();
        const items = state_guard.state.items.items;

        cl.UI()(.{ .id = cl.ElementId.ID("MainContainer"), .layout = .{ .direction = .top_to_bottom, .sizing = .grow, .padding = .all(20), .child_gap = 20 }, .background_color = .{ 30, 30, 30, 255 } })({
            cl.text("Scroll Table & List Example", .{ .font_size = 32, .color = .{ 200, 200, 200, 255 } });

            cl.UI()(.{ .layout = .{ .direction = .left_to_right, .sizing = .grow, .child_gap = 20 } })({
                // --- LEFT: Scroll List ---
                cl.UI()(.{ .layout = .{ .direction = .top_to_bottom, .sizing = .{ .w = .fixed(250), .h = .grow }, .child_gap = 10 } })({
                    cl.text("Simple List", .{ .font_size = 24, .color = .{ 180, 180, 180, 255 } });

                    var walker = ui.scrollList.begin("my_list", items.len, .{ .item_height = 30 });
                    defer ui.scrollList.end(walker);

                    var iter = walker.iterator();
                    while (iter.next()) |i| {
                        if (walker.row(i)) {
                            std.log.info("List Clicked: {}", .{items[i].id});
                        }
                        defer walker.endRow();
                        cl.text(items[i].name, .{ .font_size = 20, .color = .{ 255, 255, 255, 255 } });
                    }
                });

                // --- RIGHT: Scroll Table ---
                cl.UI()(.{ .layout = .{ .direction = .top_to_bottom, .sizing = .{ .w = .grow, .h = .grow }, .child_gap = 10 } })({
                    cl.text("Sortable Table", .{ .font_size = 24, .color = .{ 180, 180, 180, 255 } });

                    const columns = &[_]ui.scrollTable.Column{
                        .{ .name = "ID", .width = 60 },
                        .{ .name = "Name", .width = 200 },
                        .{ .name = "Score", .width = 100 },
                        .{ .name = "Category", .width = 120 },
                    };

                    var walker = ui.scrollTable.begin("my_table", items.len, columns, .{ .row_height = 30 });
                    defer ui.scrollTable.end(walker);

                    walker.header();

                    // --- SORTING LOGIC ---
                    var sorted_indices = std.ArrayList(usize).initCapacity(self.allocator, items.len) catch unreachable;
                    defer sorted_indices.deinit(self.allocator);

                    for (items, 0..) |_, i| sorted_indices.appendAssumeCapacity(i);

                    if (walker.state.sort_column_index) |col_idx| {
                        const SortContext = struct {
                            items: []const Item,
                            col_idx: usize,
                            asc: bool,

                            pub fn lessThan(ctx: @This(), a_idx: usize, b_idx: usize) bool {
                                const a = ctx.items[a_idx];
                                const b = ctx.items[b_idx];
                                const lhs = if (ctx.asc) a else b;
                                const rhs = if (ctx.asc) b else a;

                                return switch (ctx.col_idx) {
                                    0 => lhs.id < rhs.id,
                                    1 => std.mem.order(u8, lhs.name, rhs.name) == .lt,
                                    2 => lhs.score < rhs.score,
                                    3 => std.mem.order(u8, lhs.category, rhs.category) == .lt,
                                    else => false,
                                };
                            }
                        };
                        const sort_ctx = SortContext{
                            .items = items,
                            .col_idx = col_idx,
                            .asc = walker.state.sort_direction == .asc,
                        };
                        std.sort.block(usize, sorted_indices.items, sort_ctx, SortContext.lessThan);
                    }
                    // ---------------------

                    var iter = walker.iterator();
                    defer iter.deinit();

                    while (iter.next()) |i| {
                        const data_idx = sorted_indices.items[i];
                        const item = items[data_idx];

                        if (walker.row(i)) {
                            std.log.info("Table Clicked: {}", .{item.id});
                        }
                        defer walker.endRow();

                        const id_str = std.fmt.allocPrint(g_ctx.ui.frame_allocator, "{}", .{item.id}) catch "err";
                        walker.textCell(id_str);
                        walker.textCell(item.name);
                        const score_str = std.fmt.allocPrint(g_ctx.ui.frame_allocator, "{}", .{item.score}) catch "err";
                        walker.textCell(score_str);
                        walker.textCell(item.category);
                    }
                });
            });
        });
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const backend = adl_rl.createInputBackend();
    const theme = Theme.init();

    var ui_ctx = try UIContext.init(allocator, &theme, adl_rl.measureText, backend);
    defer ui_ctx.deinit();

    var router = try Router.init(allocator, .{});
    defer router.deinit(&ui_ctx);
    try router.register("/", HomeScreen, null);

    var store = Store(AppState).init(allocator, .{
        .items = try std.ArrayList(Item).initCapacity(allocator, 16),
    });
    defer {
        // Simple cleanup for example
        var list = store.state.items;
        for (list.items) |item| {
            // If names were allocated with 'allocator' in init, we should free them.
            // But 'allocator' is passed to HomeScreen.init, which uses it.
            // We can just rely on GPA for leak check or clean up if we had access to the same allocator.
            // Since 'allocator' here is the same gpa, we can free.
            if (item.id > 5) allocator.free(item.name);
        }
        list.deinit(allocator);
        store.deinit();
    }

    const min_memory_size = cl.minMemorySize();
    const memory = try allocator.alloc(u8, min_memory_size);
    defer allocator.free(memory);

    const arena = cl.createArenaWithCapacityAndMemory(memory);
    _ = cl.initialize(arena, .{ .w = 800, .h = 600 }, .{});
    cl.setMeasureTextFunction(void, {}, adl_rl.measureText);

    g_ctx = .{
        .router = &router,
        .store = &store,
        .ui = &ui_ctx,
    };

    var frame_arena = std.heap.ArenaAllocator.init(allocator);
    defer frame_arena.deinit();

    rl.setConfigFlags(rl.ConfigFlags{ .window_resizable = true, .msaa_4x_hint = true });
    rl.initWindow(800, 600, "ADL Table Example");
    rl.setTargetFPS(60);
    defer rl.closeWindow();

    try router.navigate(&ui_ctx, "/");

    while (!rl.windowShouldClose()) {
        const delta_time = rl.getFrameTime();
        std.log.debug("Frame start", .{});
        _ = frame_arena.reset(.retain_capacity);
        ui_ctx.frame_allocator = frame_arena.allocator();

        const screen_width = @as(f32, @floatFromInt(rl.getScreenWidth()));
        const screen_height = @as(f32, @floatFromInt(rl.getScreenHeight()));
        cl.setLayoutDimensions(.{ .w = screen_width, .h = screen_height });

        const mouse_pos = rl.getMousePosition();
        cl.setPointerState(.{ .x = mouse_pos.x, .y = mouse_pos.y }, rl.isMouseButtonDown(.left));
        const wheel_delta = rl.getMouseWheelMoveV();
        cl.updateScrollContainers(false, .{ .x = wheel_delta.x, .y = wheel_delta.y }, delta_time);

        ui_ctx.beginFrame(delta_time);

        cl.beginLayout();
        std.log.debug("Begin Layout", .{});
        cl.UI()(.{ .id = cl.ElementId.ID("Root"), .layout = .{ .sizing = .grow, .direction = .top_to_bottom }, .background_color = .{ 30, 30, 30, 255 } })({
            router.render(&ui_ctx);
        });
        std.log.debug("End Layout Start", .{});
        const commands = cl.endLayout();
        std.log.debug("End Layout Finish", .{});

        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);
        adl_rl.render(commands);
        rl.endDrawing();
    }
}
