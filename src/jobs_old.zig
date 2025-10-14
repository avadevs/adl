const std = @import("std");
const zjobs = @import("zjobs");

/// A typed completion callback invoked on the main thread during `pump()`.
/// The payload `result` is owned by the runner and valid for the duration of the callback.
/// If you need to keep it, copy it inside the callback.
pub fn Completion(comptime T: type) type {
    return struct {
        ctx: ?*anyopaque = null,
        call: *const fn (ctx: ?*anyopaque, request_id: u64, result: T) void,
    };
}

/// A typed error callback invoked on the main thread during `pump()`.
pub const ErrorCallback = struct {
    ctx: ?*anyopaque = null,
    call: *const fn (ctx: ?*anyopaque, request_id: u64, err: anyerror) void,
};

const ErasedDeliver = struct {
    ctx: *anyopaque,
    call: *const fn (ctx: *anyopaque, request_id: u64, payload: *anyopaque) void,
    deinit_ctx: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,
};

/// Internal event type queued by worker threads and delivered on `pump()`.
const JobEvent = union(enum) {
    Completed: struct {
        request_id: u64,
        payload: *anyopaque,
        deinit_payload: *const fn (payload: *anyopaque, allocator: std.mem.Allocator) void,
        deliver: ?ErasedDeliver,
    },
    Failed: struct {
        request_id: u64,
        err: anyerror,
        on_error: ?ErrorCallback,
    },
    Cancelled: struct {
        request_id: u64,
    },
};

/// JobRunner executes background jobs using zjobs and delivers results via callbacks.
///
/// Typical usage in an immediate-mode UI:
/// - Initialize once with an allocator and call `start()`
/// - Schedule jobs with `schedule(...)` providing typed completion/error callbacks
/// - Call `pump()` once per frame to deliver queued events on the main thread
/// - Optionally cancel with `cancel(id)`
pub fn JobRunnerType(comptime Cfg: zjobs.QueueConfig) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        job_system: zjobs.JobQueue(Cfg),
        result_mutex: std.Thread.Mutex = .{},
        result_queue: std.ArrayList(JobEvent),
        next_request_id: u64 = 1,
        cancelled: std.AutoHashMap(u64, bool),

        /// Creates a new JobRunner. Call `start()` to begin processing.
        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .allocator = allocator,
                .job_system = zjobs.JobQueue(Cfg).init(),
                .result_queue = try std.ArrayList(JobEvent).initCapacity(allocator, 128),
                .cancelled = std.AutoHashMap(u64, bool).init(allocator), // u64 is the request id
            };
        }

        /// Frees resources. Ensure no external references to callbacks remain.
        pub fn deinit(self: *Self) void {
            self.job_system.deinit();
            self.result_queue.deinit();
            self.cancelled.deinit();
        }

        /// Starts worker threads in the underlying job system.
        pub fn start(self: *Self) void {
            self.job_system.start(.{});
        }

        /// Delivers all queued job events on the main thread.
        /// Call exactly once per frame in immediate-mode UIs.
        pub fn pump(self: *Self) !void {
            var tmp = try std.ArrayList(JobEvent).initCapacity(self.allocator, self.result_queue.items.len);
            defer tmp.deinit();

            self.result_mutex.lock();
            defer self.result_mutex.unlock();

            tmp.appendSlice(self.result_queue.items) catch |err| {
                std.log.err("Failed to move job events: {any}", .{err});
                self.result_queue.clearRetainingCapacity();
            };

            for (tmp.items) |ev| switch (ev) {
                .Completed => |c| {
                    if (c.deliver) |d| {
                        d.call(d.ctx, c.request_id, c.payload);
                        c.deinit_payload(c.payload, self.allocator);
                        d.deinit_ctx(d.ctx, self.allocator);
                    } else {
                        c.deinit_payload(c.payload, self.allocator);
                    }
                },
                .Failed => |f| {
                    if (f.on_error) |h| h.call(h.ctx, f.request_id, f.err);
                },
                .Cancelled => |_| {},
            };
        }

        /// Marks a job as cancelled. Cooperative; the job should check and bail early.
        pub fn cancel(self: *Self, request_id: u64) bool {
            self.result_mutex.lock();
            defer self.result_mutex.unlock();
            const gop = self.cancelled.getOrPut(self.allocator, request_id) catch return false;
            if (!gop.found_existing) {
                gop.value_ptr.* = true;
                return true;
            }
            return false;
        }

        fn nextId(self: *Self) u64 {
            const id = self.next_request_id;
            self.next_request_id += 1;
            return id;
        }

        /// Schedules a job function for execution.
        /// `job_fn` must have type `fn(allocator: std.mem.Allocator, args: A) anyerror!T`.
        /// Results are delivered via `on_complete` during `pump()`.
        pub fn schedule(self: *Self, comptime T: type, job_fn: anytype, args: anytype, on_complete: ?Completion(T), on_error: ?ErrorCallback) u64 {
            const A = @TypeOf(args);
            const Fn = *const fn (std.mem.Allocator, A) anyerror!T;
            const typed_fn: Fn = job_fn;

            const id = self.nextId();
            const deliver = makeDeliver(T, self.allocator, on_complete);

            const Wrapper = JobWrapper(Self, T, A);
            const job = Wrapper{
                .runner = self,
                .allocator = self.allocator,
                .request_id = id,
                .job_fn = typed_fn,
                .args = args,
                .on_error = on_error,
                .deliver = deliver,
            };

            _ = self.job_system.schedule(.none, job) catch |err| {
                std.log.err("Failed to schedule job: {any}", .{err});
            };
            return id;
        }
    };
}

/// Default JobRunner with a sensible idle sleep
pub const JobRunner = JobRunnerType(.{ .idle_sleep_ns = std.time.ns_per_ms * 10 });

fn JobWrapper(comptime Runner: type, comptime T: type, comptime A: type) type {
    return struct {
        const Self = @This();
        runner: *Runner,
        allocator: std.mem.Allocator,
        request_id: u64,
        job_fn: *const fn (std.mem.Allocator, A) anyerror!T,
        args: A,
        on_error: ?ErrorCallback,
        deliver: ?ErasedDeliver,

        pub fn exec(self: *Self) void {
            // Check cancellation before doing work
            if (self.runner.cancelled.contains(self.request_id)) {
                self.runner.result_mutex.lock();
                defer self.runner.result_mutex.unlock();
                self.runner.result_queue.append(JobEvent{ .Cancelled = .{ .request_id = self.request_id } }) catch |e| {
                    std.log.err("Failed to append cancelled event: {any}", .{e});
                };
                return;
            }

            const ok = self.job_fn(self.allocator, self.args) catch |err| {
                self.runner.result_mutex.lock();
                defer self.runner.result_mutex.unlock();
                self.runner.result_queue.append(JobEvent{ .Failed = .{ .request_id = self.request_id, .err = err, .on_error = self.on_error } }) catch |e| {
                    std.log.err("Failed to append failed event: {any}", .{e});
                };
                return;
            };

            self.runner.result_mutex.lock();
            defer self.runner.result_mutex.unlock();

            // If cancelled after completion, report as cancelled
            if (self.runner.cancelled.contains(self.request_id)) {
                self.runner.result_queue.append(JobEvent{ .Cancelled = .{ .request_id = self.request_id } }) catch |e| {
                    std.log.err("Failed to append cancelled event: {any}", .{e});
                };
                return;
            }

            const payload_ptr = self.allocator.create(T) catch |alloc_err| {
                std.log.err("Failed to allocate result payload: {any}", .{alloc_err});
                return;
            };
            payload_ptr.* = ok;
            const deinit_payload = deinitPayloadFn(T);
            self.runner.result_queue.append(JobEvent{ .Completed = .{ .request_id = self.request_id, .payload = payload_ptr, .deinit_payload = deinit_payload, .deliver = self.deliver } }) catch |e| {
                std.log.err("Failed to append completed event: {any}", .{e});
            };
        }
    };
}

fn makeDeliver(comptime T: type, allocator: std.mem.Allocator, cb: ?Completion(T)) ?ErasedDeliver {
    if (cb == null) return null;
    const DeliverT = struct {
        ctx: ?*anyopaque,
        user_call: *const fn (ctx: ?*anyopaque, request_id: u64, result: T) void,
    };
    const deliver_ctx = allocator.create(DeliverT) catch return null;
    deliver_ctx.* = .{ .ctx = cb.?.ctx, .user_call = cb.?.call };

    const Ctx = DeliverT;
    const call_erased = struct {
        fn f(ctx_ptr: *anyopaque, request_id: u64, payload_ptr: *anyopaque) void {
            const self: *Ctx = @ptrCast(@alignCast(ctx_ptr));
            const val: *T = @ptrCast(@alignCast(payload_ptr));
            self.user_call(self.ctx, request_id, val.*);
        }
    }.f;
    const deinit_ctx = struct {
        fn f(ctx_ptr: *anyopaque, a: std.mem.Allocator) void {
            const self: *Ctx = @ptrCast(@alignCast(ctx_ptr));
            a.destroy(self);
        }
    }.f;

    return ErasedDeliver{ .ctx = deliver_ctx, .call = call_erased, .deinit_ctx = deinit_ctx };
}

fn deinitPayloadFn(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) void {
    const Impl = struct {
        fn f(payload: *anyopaque, a: std.mem.Allocator) void {
            const p: *T = @ptrCast(@alignCast(payload));
            a.destroy(p);
        }
    };
    return Impl.f;
}

// --- Tests ---
var g_done_called: bool = false;
var g_done_sum: u64 = 0;
var g_error_called: bool = false;

fn testCompute(_: std.mem.Allocator, args: struct { n: u64 }) anyerror!u64 {
    var s: u64 = 0;
    var i: u64 = 0;
    while (i <= args.n) : (i += 1) s += i;
    return s;
}

fn testOnDone(_: ?*anyopaque, _id: u64, sum: u64) void {
    _ = _id;
    g_done_called = true;
    g_done_sum = sum;
}

fn testOnError(_: ?*anyopaque, _id: u64, _err: anyerror) void {
    _ = _id;
    _ = _err;
    g_error_called = true;
}

test "jobs: schedule + pump + callback" {
    const allocator = std.testing.allocator;
    var runner = try JobRunner.init(allocator);
    defer runner.deinit();
    runner.start();

    g_done_called = false;
    g_error_called = false;
    g_done_sum = 0;

    _ = runner.schedule(u64, &testCompute, .{ .n = 10 }, .{ .ctx = null, .call = testOnDone }, .{ .ctx = null, .call = testOnError });

    var tries: usize = 0;
    while (tries < 200 and !g_done_called and !g_error_called) : (tries += 1) {
        std.time.sleep(1_000_0); // 0.01 ms
        runner.pump();
    }

    try std.testing.expect(g_done_called);
    try std.testing.expect(!g_error_called);
    try std.testing.expectEqual(@as(u64, 55), g_done_sum);
}
