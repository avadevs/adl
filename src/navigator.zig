/// The navigator is responsable to save a reference to each screen the developer wants
/// to be managed by the navigator. It provides methods to transition between these
/// screens, go back / forward and render the active screen.
/// The navigator is meant as the component that will manage the screen transitions.
const std = @import("std");

// pub fn Navigator(comptime Screen: type) type {
//     return struct {
//         const Self = @This();

//         //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//         // Public API: Configuration Structs & Enums
//         //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//         /// Defines an animation for presenting or dismissing a screen.
//         pub const Transition = struct {
//             style: Style = .push,
//             duration_ms: u32 = 250,

//             pub const Style = enum {
//                 none,
//                 /// Default: New screen slides from right, old slides to left.
//                 push,
//                 /// New screen slides up from the bottom.
//                 sheet,
//                 /// New screen fades in. Can be combined with other styles.
//                 fade,
//             };
//         };

//         /// Defines how a screen is presented in the navigation hierarchy.
//         pub const Presentation = enum {
//             /// Standard stack behavior. Pushes onto the main navigation stack.
//             push,
//             /// Presented modally on top of the current context. Has its own
//             /// internal navigation stack. Ideal for self-contained flows
//             /// like login or creating a new item.
//             modal,
//         };

//         /// Options for any navigation action that presents a new screen.
//         pub const PresentOptions = struct {
//             /// The animation to use when presenting the new screen.
//             transition: ?Transition = null,
//             /// The presentation style (e.g., push to stack or present as modal).
//             presentation: Presentation = .push,
//             /// If true, the screen's state will be preserved in a cache when it
//             /// is dismissed, allowing for instant navigation back to it later.
//             keep_alive: bool = false,
//         };

//         /// Options for any navigation action that dismisses a screen.
//         pub const DismissOptions = struct {
//             /// The animation to use when dismissing the screen.
//             transition: ?Transition = null,
//         };

//         /// A map of user-provided functions that the Navigator uses to manage
//         /// the lifecycle of each screen type.
//         pub const Handlers = struct {
//             /// Called to create the initial state for a screen.
//             init: *const fn (screen: Screen, allocator: std.mem.Allocator, app_services: *anyopaque) anyerror!ScreenInstance,
//             /// Called every frame to draw the screen's UI.
//             render: *const fn (state: *ScreenInstance, ui_context: *anyopaque) void,
//             /// Called when a screen is destroyed to free its resources.
//             deinit: *const fn (state: *ScreenInstance) void,
//             /// (Optional) Called when a screen that was pushed with on_result is popped.
//             on_result: ?*const fn (state: *ScreenInstance, result: *anyopaque) void = null,
//         };

//         //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//         // Public API: Methods
//         //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//         /// Initializes the Navigator.
//         ///
//         /// - allocator: The memory allocator for all internal operations.
//         /// - initial_screen: The Screen variant for the root of the navigation stack.
//         /// - handlers: A map of functions for managing screen lifecycles.
//         /// - app_services: An optional pointer to a user-defined context struct
//         ///   containing global services (like a JobRunner or Stores) that will be
//         ///   passed to each screen's init function.
//         pub fn init(
//             allocator: std.mem.Allocator,
//             initial_screen: Screen,
//             handlers: Handlers,
//             app_services: ?*anyopaque,
//         ) !Self {
//             var main_stack = std.ArrayList(ScreenInstance).init(allocator);
//             errdefer main_stack.deinit();

//             var self = Self{
//                 .allocator = allocator,
//                 .handlers = handlers,
//                 .app_services = app_services,
//                 .main_stack = main_stack,
//                 .modal_stacks = std.ArrayList(std.ArrayList(ScreenInstance)).init(allocator),
//                 .cache = std.AutoHashMap(u64, ScreenInstance).init(allocator),
//             };

//             const root_instance = try self.createScreenInstance(initial_screen, false);
//             try self.main_stack.append(root_instance);

//             return self;
//         }

//         /// Deinitializes the Navigator, ensuring all active and cached screens
//         /// are properly destroyed to prevent resource leaks.
//         pub fn deinit(self: *Self) void {
//             // Deinit all screens in the main stack
//             for (self.main_stack.items) |instance| {
//                 const deinit_fn = self.handlers.deinit.call(.{}, .{ .tag = instance.tag, .payload = &instance.state });
//                 deinit_fn(&instance.state);
//             }
//             self.main_stack.deinit();

//             // Deinit all screens in all modal stacks
//             for (self.modal_stacks.items) |*stack| {
//                 for (stack.items) |instance| {
//                     const deinit_fn = self.handlers.deinit.call(.{}, .{ .tag = instance.tag, .payload = &instance.state });
//                     deinit_fn(&instance.state);
//                 }
//                 stack.deinit();
//             }
//             self.modal_stacks.deinit();

//             // Deinit all cached screens
//             var it = self.cache.valueIterator();
//             while (it.next()) |instance| {
//                 const deinit_fn = self.handlers.deinit.call(.{}, .{ .tag = instance.tag, .payload = &instance.state });
//                 deinit_fn(&instance.state);
//             }
//             self.cache.deinit();
//         }

//         /// Updates the Navigator's internal state. Should be called once per frame.
//         /// This is primarily used to advance transition animation timers.
//         ///
//         /// - delta_time: The time elapsed since the last frame, in seconds.
//         pub fn update(self: *Self, delta_time: f32) void {
//             if (self.active_transition) |*transition| {
//                 transition.progress += delta_time / (transition.config.duration_ms / 1000.0);
//                 if (transition.progress >= 1.0) {
//                     transition.onComplete(self);
//                 }
//             }
//         }

//         /// Renders the currently active screen(s). During a transition, this function
//         /// will handle rendering both the incoming and outgoing screens.
//         ///
//         /// - ui_context: A pointer to the global UI context, passed down to the screen's render function.
//         pub fn render(self: *Self, ui_context: *anyopaque) void {
//             if (self.active_transition) |transition| {
//                 // During a transition, render both screens
//                 if (transition.from) |from_instance| {
//                     const render_fn = self.handlers.render.call(.{}, .{ .tag = from_instance.tag, .payload = &from_instance.state });
//                     render_fn(&from_instance.state, ui_context);
//                 }
//                 const to_instance = transition.to;
//                 const render_fn = self.handlers.render.call(.{}, .{ .tag = to_instance.tag, .payload = &to_instance.state });
//                 render_fn(&to_instance.state, ui_context);
//             } else {
//                 // Otherwise, just render the top-most screen of the active stack
//                 const active_stack = self.getActiveStack();
//                 if (active_stack.items.len > 0) {
//                     const instance = active_stack.items[active_stack.items.len - 1];
//                     const render_fn = self.handlers.render.call(.{}, .{ .tag = instance.tag, .payload = &instance.state });
//                     render_fn(&instance.state, ui_context);
//                 }
//             }
//         }

//         /// Pushes a new screen onto the current navigation stack.
//         pub fn push(self: *Self, screen: Screen, options: ?PresentOptions) !void {
//             const keep_alive = options.?.keep_alive orelse false;
//             const new_instance = try self.createScreenInstance(screen, keep_alive);

//             const active_stack = self.getActiveStack();
//             const old_instance = if (active_stack.items.len > 0) active_stack.items[active_stack.items.len - 1] else null;

//             try active_stack.append(new_instance);

//             if (options.?.transition) |transition_opts| {
//                 self.startTransition(old_instance, new_instance, transition_opts, .forward);
//             }
//         }

//         /// Pops the top-most screen from the current navigation stack.
//         ///
//         /// - result: An optional value to pass back to the previous screen's on_result handler.
//         pub fn pop(self: *Self, result: ?anyopaque, options: ?DismissOptions) void {
//             const active_stack = self.getActiveStack();
//             if (active_stack.items.len <= 1) {
//                 // Cannot pop the root screen
//                 return;
//             }

//             const popped_instance = active_stack.pop();
//             const new_top_instance = active_stack.items[active_stack.items.len - 1];

//             // Handle passing results back to the previous screen
//             if (self.handlers.on_result) |on_result_fn| {
//                 on_result_fn(&new_top_instance.state, result);
//             }

//             if (options.?.transition) |transition_opts| {
//                 self.startTransition(popped_instance, new_top_instance, transition_opts, .backward);
//             } else {
//                 // If no transition, deinit or cache immediately
//                 if (!popped_instance.keep_alive) {
//                     const deinit_fn = self.handlers.deinit.call(.{}, .{ .tag = popped_instance.tag, .payload = &popped_instance.state });
//                     deinit_fn(&popped_instance.state);
//                 } else {
//                     self.cache.put(popped_instance.id, popped_instance) catch |err| {
//                         std.log.err("Failed to cache screen: {any}", .{err});
//                     };
//                 }
//             }
//         }

//         /// Pops all screens from the current stack until only the root screen remains.
//         pub fn popToRoot(self: *Self, options: ?DismissOptions) void {
//             const active_stack = self.getActiveStack();
//             if (active_stack.items.len <= 1) return;

//             const old_top = active_stack.pop();
//             const new_top = active_stack.items[0];

//             // Deinit all screens between the new top and the old top
//             while (active_stack.items.len > 1) {
//                 const instance = active_stack.pop();
//                 const deinit_fn = self.handlers.deinit.call(.{}, .{ .tag = instance.tag, .payload = &instance.state });
//                 deinit_fn(&instance.state);
//             }

//             if (options.?.transition) |transition_opts| {
//                 self.startTransition(old_top, new_top, transition_opts, .backward);
//             }
//         }

//         /// Pops screens from the current stack until a specific screen instance is found.
//         ///
//         /// - screen_id: The unique ID of the screen to pop back to.
//         pub fn popTo(self: *Self, screen_id: u64, options: ?DismissOptions) void {
//             const active_stack = self.getActiveStack();
//             if (active_stack.items.len <= 1) return;

//             // Find the index of the target screen
//             var target_index: ?usize = null;
//             for (active_stack.items, 0..) |instance, i| {
//                 if (instance.id == screen_id) {
//                     target_index = i;
//                     break;
//                 }
//             }

//             if (target_index == null or target_index.? == active_stack.items.len - 1) {
//                 // Target not found or is already the top screen
//                 return;
//             }

//             const old_top = active_stack.pop();
//             const new_top = active_stack.items[target_index.?];

//             // Deinit all screens between the new top and the old top
//             while (active_stack.items.len - 1 > target_index.?) {
//                 const instance = active_stack.pop();
//                 const deinit_fn = self.handlers.deinit.call(.{}, .{ .tag = instance.tag, .payload = &instance.state });
//                 deinit_fn(&instance.state);
//             }

//             if (options.?.transition) |transition_opts| {
//                 self.startTransition(old_top, new_top, transition_opts, .backward);
//             }
//         }

//         /// Replaces the currently active screen with a new one without adding to the back stack.
//         pub fn replace(self: *Self, screen: Screen, options: ?PresentOptions) !void {
//             const active_stack = self.getActiveStack();
//             if (active_stack.items.len == 0) return;

//             const old_instance = active_stack.pop();
//             const new_instance = try self.createScreenInstance(screen, options.?.keep_alive orelse false);
//             try active_stack.append(new_instance);

//             if (options.?.transition) |transition_opts| {
//                 self.startTransition(old_instance, new_instance, transition_opts, .forward);
//             } else {
//                 // If no transition, deinit or cache immediately
//                 if (!old_instance.keep_alive) {
//                     const deinit_fn = self.handlers.deinit.call(.{}, .{ .tag = old_instance.tag, .payload = &old_instance.state });
//                     deinit_fn(&old_instance.state);
//                 } else {
//                     self.cache.put(old_instance.id, old_instance) catch |err| {
//                         std.log.err("Failed to cache screen: {any}", .{err});
//                     };
//                 }
//             }
//         }

//         /// Replaces the entire navigation stack with a new one. This is the core
//         /// function for programmatic navigation and deep linking.
//         ///
//         /// - screens: A slice of Screen variants that will become the new navigation stack.
//         pub fn setStack(self: *Self, screens: []const Screen, options: ?Transition) !void {
//             const active_stack = self.getActiveStack();
//             const old_top = if (active_stack.items.len > 0) active_stack.pop() else null;

//             // Deinit all old screens
//             for (active_stack.items) |instance| {
//                 const deinit_fn = self.handlers.deinit.call(.{}, .{ .tag = instance.tag, .payload = &instance.state });
//                 deinit_fn(&instance.state);
//             }
//             active_stack.clearRetainingCapacity();

//             // Create and add the new screens
//             for (screens) |screen| {
//                 const new_instance = try self.createScreenInstance(screen, false);
//                 try active_stack.append(new_instance);
//             }

//             const new_top = active_stack.items[active_stack.items.len - 1];

//             if (options) |transition_opts| {
//                 self.startTransition(old_top, new_top, transition_opts, .forward);
//             }
//         }

//         //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//         // Internal State (Private Fields)
//         //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//         allocator: std.mem.Allocator,
//         handlers: Handlers,
//         app_services: ?*anyopaque,

//         /// The unique ID to be assigned to the next created screen instance.
//         next_screen_id: u64 = 1,

//         /// The primary navigation stack for the main application flow.
//         main_stack: std.ArrayList(ScreenInstance),

//         /// A stack of modal stacks. Each time a modal is presented, a new
//         /// ArrayList is pushed onto this stack. This allows modals to have their
//         /// own independent navigation flows.
//         modal_stacks: std.ArrayList(std.ArrayList(ScreenInstance)),

//         /// A cache holding instances of screens that were marked with keep_alive.
//         /// The key is a hash of the screen type and its initialization parameters.
//         cache: std.AutoHashMap(u64, ScreenInstance),

//         /// State for managing the currently active transition.
//         active_transition: ?ActiveTransition = null,

//         //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//         // Internal Types (Private)
//         //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//         /// The actual state for a screen instance, managed internally by the Navigator.
//         const ScreenInstance = struct {
//             /// A unique identifier for this specific instance of a screen.
//             id: u64,
//             /// A pointer to the heap-allocated state of the screen. This is an anyopaque
//             /// pointer because the Navigator is generic; it uses the render and deinit
//             /// function pointers to interact with the state in a type-safe way.
//             state: *anyopaque,
//             /// The tag of the Screen union, used to look up the correct handler functions.
//             tag: std.meta.Tag(Screen),
//             /// Whether to cache this screen on pop.
//             keep_alive: bool,
//         };

//         /// Holds the state of an in-progress screen transition.
//         const ActiveTransition = struct {
//             /// The screen being navigated from.
//             from: ?ScreenInstance,
//             /// The screen being navigated to.
//             to: ScreenInstance,
//             /// The configuration for the transition animation.
//             config: Transition,
//             /// A timer that runs from 0.0 to 1.0 to track animation progress.
//             progress: f32 = 0.0,
//             /// The direction of the transition (presenting or dismissing).
//             direction: enum { forward, backward },

//             /// Called when the transition animation is complete. This is where
//             /// the from screen is actually deinitialized or moved to the cache.
//             fn onComplete(self: *ActiveTransition, nav: *Self) void {
//                 if (self.from) |old_screen| {
//                     if (!old_screen.keep_alive) {
//                         // Call the user's deinit function.
//                         const deinit_fn = nav.handlers.deinit.call(.{}, .{ .tag = old_screen.tag, .payload = &old_screen.state });
//                         deinit_fn(&old_screen.state);
//                     } else {
//                         // Move the old screen to the cache.
//                         nav.cache.put(old_screen.id, old_screen) catch |err| {
//                             std.log.err("Failed to cache screen: {any}", .{err});
//                         };
//                     }
//                 }
//                 nav.active_transition = null;
//             }
//         };

//         //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//         // Private Methods
//         //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//         /// Returns a pointer to the currently active navigation stack. This will be
//         /// the top-most stack in modal_stacks, or main_stack if no modals are presented.
//         fn getActiveStack(self: *Self) *std.ArrayList(ScreenInstance) {
//             if (self.modal_stacks.items.len > 0) {
//                 return &self.modal_stacks.items[self.modal_stacks.items.len - 1];
//             }
//             return &self.main_stack;
//         }

//         /// A factory function that safely creates and initializes a new ScreenInstance.
//         /// It looks up the correct init function from the handlers map.
//         fn createScreenInstance(self: *Self, screen: Screen, keep_alive: bool) !ScreenInstance {
//             const tag = @tagName(screen);
//             const init_fn = self.handlers.init.call(.{}, .{ .tag = tag, .payload = screen });
//             const state = try init_fn(screen, self.allocator, self.app_services);

//             const new_id = self.next_screen_id;
//             self.next_screen_id += 1;

//             return ScreenInstance{
//                 .id = new_id,
//                 .state = state,
//                 .tag = tag,
//                 .keep_alive = keep_alive,
//             };
//         }

//         /// Starts a new transition, moving the current screen to the from
//         /// field and the new screen to the to field of active_transition.
//         fn startTransition(self: *Self, from: ?ScreenInstance, to: ScreenInstance, config: Transition, direction: ActiveTransition.Direction) void {
//             self.active_transition = .{
//                 .from = from,
//                 .to = to,
//                 .config = config,
//                 .direction = direction,
//             };
//         }
//     };
// }

// // --- Test-only Helper Functions ---

// const TestScreen = union(enum) {
//     home: struct {},
//     detail: struct { id: u32 },
// };

// const TestScreenState = union(enum) {
//     home: struct {},
//     detail: struct { id: u32 },
// };

// const TestHandlers = Navigator(TestScreen).Handlers;

// // A context struct to hold shared state for the test handlers.
// const TestContext = struct {
//     active_screens: *std.ArrayList(u32),
// };

// fn testInit(screen: TestScreen, allocator: std.mem.Allocator, services: *anyopaque, active_screens: *std.ArrayList(u32)) !TestHandlers.ScreenInstance.State {
//     _ = allocator;
//     _ = services;
//     var state: TestScreenState = undefined;
//     switch (screen) {
//         .home => state = .{ .home = .{} },
//         .detail => |p| state = .{ .detail = .{ .id = p.id } },
//     }
//     if (state.detail) |s| {
//         try active_screens.append(s.id);
//     }
//     return state;
// }

// fn testRender(state: *TestHandlers.ScreenInstance.State, ui_ctx: *anyopaque) void {
//     _ = state;
//     _ = ui_ctx;
// }

// fn testDeinit(state: *TestHandlers.ScreenInstance.State, active_screens: *std.ArrayList(u32)) void {
//     if (state.detail) |s| {
//         for (active_screens.items, 0..) |id, i| {
//             if (id == s.id) {
//                 _ = active_screens.orderedRemove(i);
//                 return;
//             }
//         }
//     }
// }

// test "basic navigation: push and pop" {
//     const allocator = std.testing.allocator;

//     var active_screens = try std.ArrayList(u32).initCapacity(allocator, 8);
//     defer active_screens.deinit();

//     var test_context = TestContext{ .active_screens = &active_screens };

//     const AppServices = struct {};
//     var app_services = AppServices{};

//     const handlers = TestHandlers{
//         .init = struct {
//             ctx: *TestContext = &test_context,
//             fn init_wrapper(screen: TestScreen, alloc: std.mem.Allocator, services: *anyopaque) !TestHandlers.ScreenInstance.State {
//                 return testInit(screen, alloc, services, ctx);
//             }
//         }.init_wrapper,
//         .render = testRender,
//         .deinit = struct {
//             ctx: *TestContext = &test_context,
//             fn deinit_wrapper(state: *TestHandlers.ScreenInstance.State) void {
//                 testDeinit(state, ctx);
//             }
//         }.deinit_wrapper,
//     };

//     // 3. Initialize the Navigator
//     const AppNavigator = Navigator(TestScreen);
//     var nav = try AppNavigator.init(allocator, .{ .home = .{} }, handlers, &app_services);
//     defer nav.deinit();

//     try std.testing.expectEqual(1, nav.getActiveStack().items.len);
//     try std.testing.expectEqual(.home, nav.getActiveStack().items[0].tag);

//     // 4. Push a new screen
//     try nav.push(.{ .detail = .{ .id = 42 } }, null);

//     try std.testing.expectEqual(2, nav.getActiveStack().items.len);
//     const top_screen = nav.getActiveStack().items[1];
//     try std.testing.expectEqual(.detail, top_screen.tag);
//     try std.testing.expectEqual(@as(u32, 42), top_screen.state.detail.id);
//     try std.testing.expectEqual(1, active_screens.items.len);
//     try std.testing.expectEqual(@as(u32, 42), active_screens.items[0]);

//     // 5. Pop the screen
//     nav.pop(null, null);

//     try std.testing.expectEqual(1, nav.getActiveStack().items.len);
//     try std.testing.expectEqual(.home, nav.getActiveStack().items[0].tag);
//     try std.testing.expectEqual(0, active_screens.items.len); // Assert that the detail screen was deinitialized
// }
