//! Job system with thread pools, futures, and event broadcasting.
//!
//! ## Quick Start
//!
//! ```zig
//! const Jobs = @import("jobs.zig").Jobs;
//!
//! // Initialize and start worker threads
//! var jobs = try Jobs.init(allocator, .{ .job_capacity = 256 });
//! try jobs.start();
//! defer jobs.deinit();
//!
//! // Schedule work
//! fn myWork(j: *Jobs, ctx: *anyopaque) JobOutcome {
//!     const value: *u32 = @ptrCast(@alignCast(ctx));
//!     value.* = 42;
//!     return .{ .completed = null };
//! }
//! const job_id = try jobs.schedule(&myWork, &my_value);
//! ```
//!
//! ## Event Subscription Patterns
//!
//! ### UI Event Loop (Non-blocking)
//! ```zig
//! const sub = try jobs.subscribe(.{ .key = .{ .kind = .completed } });
//! defer jobs.unsubscribe(sub);
//!
//! // In your main loop
//! while (running) {
//!     jobs.drain(sub, 16, &handleEvent, ctx); // up to 16 events per frame
//!     // ... render ...
//! }
//! ```
//!
//! ### Background Worker (Blocking)
//! ```zig
//! const sub = try jobs.subscribe(.{ .key = .{ .kind = .completed } });
//! defer jobs.unsubscribe(sub);
//!
//! while (jobs.waitAvailable(sub, null)) { // block until events arrive
//!     jobs.drain(sub, 100, &handleEvent, ctx); // process batch
//! }
//! ```
//!
//! ### Single Job Monitoring
//! ```zig
//! const job_id = try jobs.schedule(&work, ctx);
//! const sub = try jobs.subscribe(.{ .key = .{ .id = job_id } });
//! defer jobs.unsubscribe(sub);
//!
//! if (jobs.waitAvailable(sub, 5_000_000_000)) { // 5 second timeout
//!     jobs.drain(sub, 1, &handleEvent, ctx);
//! }
//! ```

const std = @import("std");
const mpmc_queue = @import("utility/mpmc_queue.zig");

pub const Id: type = usize;

// --- Core Types ---
pub const EventKind = enum { progress, completed, failed, cancelled };

pub const Event = struct {
    id: Id,
    kind: EventKind,
    payload: ?*anyopaque,
};

pub const EventKey = union(enum) {
    id: Id,
    kind: EventKind,
};

pub const JobOutcome = union(enum) {
    completed: ?*anyopaque,
    failed: ?*anyopaque,
    cancelled: void,
};

pub const JobFn = *const fn (*Jobs, *anyopaque) JobOutcome;

pub const Job = struct {
    id: Id,
    work: JobFn,
    ctx: *anyopaque,
};

/// The types that can be pushed onto the job queue.
/// - `job`: A job to execute.
/// - `stop`: A command to stop the worker threads.
pub const WorkItem = union(enum) {
    job: Job,
    stop: void,
};

// --- Options ---
pub const JobsOptions = struct {
    job_capacity: usize,
    blocking_capacity: usize = 256,
    thread_count: usize = 4,
    blocking_threads: usize = 2,
    subscriber_capacity_default: usize = 1024,
    // worker wait timeout; null means block indefinitely
    worker_wait_timeout_ns: ?u64 = null,
};

// --- Future(T) ---
/// Create a one-shot, generic Future type container.
/// - Thread-safe completion: first `complete` wins; subsequent calls are no-ops.
/// - Single waiter: only one thread may call `wait`; others should use subscribers or continuations.
/// - Continuations: install exactly once with `then`; scheduled back onto the CPU pool.
/// - Workers must not block; use `then` instead of `wait` from worker threads.
pub fn Future(comptime T: type) type {
    return struct {
        done: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
        cont_set: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
        waiter_set: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
        ready: std.Thread.Semaphore = .{ .permits = 0 },
        value: T = undefined,
        cont_fn: ?*const fn (*Jobs, T, *anyopaque) void = null,
        cont_ctx: ?*anyopaque = null,
    };
}

// --- Subscribers ---
/// Subscription options for broadcast events.
/// - `key`: subscribe by job `id` or by `EventKind` to receive matching events.
/// - `capacity`: bounded queue size per-subscriber; producers never block on publish.
/// - `lossless`: if true, we avoid dropping terminal events but may still drop progress on overflow.
///     This has the danger of waiting on emitting the event which could cause a deadlock.
/// - `drop_progress_first`: prefer dropping `.progress` events before terminal ones when full.
pub const SubscribeOpts = struct {
    key: EventKey,
    capacity: usize = 1024,
    lossless: bool = false,
    drop_progress_first: bool = true,
};

/// A per-consumer event queue and semaphore used for broadcast delivery.
/// - Each subscriber owns a bounded MPSC queue of `Event` and a semaphore `available`.
/// - Producers publish by `tryPush`ing into each matching queue and `post`ing the semaphore.
/// - Consumers can block on `waitAvailable` and then `drain` with a frame budget.
/// Notes:
/// - `lossless` and `drop_progress_first` govern overflow policy; workers never block on publish.
/// - Destroyed via `unsubscribe`; do not free manually.
pub const Subscriber = struct {
    key: EventKey,
    q: mpmc_queue.Queue(Event),
    available: std.Thread.Semaphore,
    lossless: bool,
    drop_progress_first: bool,
};

/// Internal registry mapping subscription keys to lists of `Subscriber` pointers.
/// - Split by-id and by-kind to avoid custom hashing/union key complications.
/// - Guarded by a mutex for safe concurrent modify/iterate during publish/subscribe.
/// - Only manages list storage; does not destroy `Subscriber` objects (that happens in `unsubscribe`).
const SubsRegistry = struct {
    // Split registry to avoid custom hash for union key
    by_id: std.AutoHashMapUnmanaged(Id, std.ArrayListUnmanaged(*Subscriber)) = .{},
    by_kind: [4]std.ArrayListUnmanaged(*Subscriber) = .{ .{}, .{}, .{}, .{} },
    mutex: std.Thread.Mutex = .{},

    /// Initialize registry fields. Currently a no-op; lists are zero-initialized.
    fn init(self: *SubsRegistry) void {
        _ = self; // nothing to do
    }

    /// Free list storage for by-id and by-kind registries.
    /// Note: Does not free `Subscriber` pointees; callers must destroy subscribers first.
    fn deinit(self: *SubsRegistry, alloc: std.mem.Allocator) void {
        var it = self.by_id.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(alloc);
        }
        self.by_id.deinit(alloc);
        for (&self.by_kind) |*lst| lst.deinit(alloc);
    }
};

// --- State Store ---
const TerminalState = struct {
    kind: EventKind,
    payload: ?*anyopaque,
};

// --- Jobs ---
pub const Jobs = struct {
    allocator: std.mem.Allocator,

    // CPU pool
    _job_q: mpmc_queue.Queue(WorkItem),
    _job_available: std.Thread.Semaphore = .{ .permits = 0 },
    _cpu_threads: []std.Thread = &[_]std.Thread{},

    // Blocking pool
    _block_q: mpmc_queue.Queue(WorkItem),
    _block_available: std.Thread.Semaphore = .{ .permits = 0 },
    _blk_threads: []std.Thread = &[_]std.Thread{},

    // Control
    /// A counter for generating unique job IDs.
    _id_counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    /// Worker wait timeout; null means block indefinitely
    _worker_wait_timeout_ns: ?u64 = null,

    // Broadcast subscribers
    _subs: SubsRegistry = .{},

    // Terminal states for late joiners
    _state: std.AutoHashMapUnmanaged(Id, TerminalState) = .{},
    _state_mutex: std.Thread.Mutex = .{},

    // --- Lifecycle ---
    /// Initialize the Jobs system.
    /// - Initializes bounded queues and semaphores, allocates thread arrays.
    /// - Call `start()` after init to spawn worker threads.
    /// Dangers:
    /// - Keep `opts.job_capacity` and `opts.blocking_capacity` reasonable; producers drop/push accordingly.
    /// - Must call `start()` to begin processing jobs.
    /// - Call `deinit` to stop and join threads.
    pub fn init(allocator: std.mem.Allocator, opts: JobsOptions) !Jobs {
        var jobs = Jobs{
            .allocator = allocator,
            ._job_q = try mpmc_queue.Queue(WorkItem).init(allocator, opts.job_capacity),
            ._block_q = try mpmc_queue.Queue(WorkItem).init(allocator, opts.blocking_capacity),
            ._worker_wait_timeout_ns = opts.worker_wait_timeout_ns,
        };

        // allocate thread arrays (but don't spawn yet)
        jobs._cpu_threads = try allocator.alloc(std.Thread, opts.thread_count);
        jobs._blk_threads = try allocator.alloc(std.Thread, opts.blocking_threads);

        return jobs;
    }

    /// Start worker threads.
    /// - Must be called after `init` and before scheduling jobs.
    pub fn start(self: *Jobs) !void {
        // spawn CPU threads
        var i: usize = 0;
        while (i < self._cpu_threads.len) : (i += 1) {
            self._cpu_threads[i] = try std.Thread.spawn(.{}, cpuWorker, .{ self, self._worker_wait_timeout_ns });
        }

        // spawn blocking threads
        i = 0;
        while (i < self._blk_threads.len) : (i += 1) {
            self._blk_threads[i] = try std.Thread.spawn(.{}, blockingWorker, .{ self, self._worker_wait_timeout_ns });
        }
    }

    /// Shut down the Jobs system.
    /// - Enqueues stop sentinels and posts semaphores to wake workers, then joins threads.
    /// - Frees queues, subscribers registry lists, and state store buffers.
    /// Note: Ensure external code has unsubscribed or destroyed any owned resources in job contexts.
    pub fn deinit(self: *Jobs) void {
        // enqueue stop sentinels and wake all workers
        var i: usize = 0;
        while (i < self._cpu_threads.len) : (i += 1) {
            self._job_q.push(.{ .stop = {} });
            self._job_available.post();
        }
        i = 0;
        while (i < self._blk_threads.len) : (i += 1) {
            self._block_q.push(.{ .stop = {} });
            self._block_available.post();
        }

        // join threads
        for (self._cpu_threads) |t| t.join();
        for (self._blk_threads) |t| t.join();

        self.allocator.free(self._cpu_threads);
        self.allocator.free(self._blk_threads);

        self._job_q.deinit();
        self._block_q.deinit();

        // free subscribers and state
        self._subs.deinit(self.allocator);
        var it = self._state.iterator();
        while (it.next()) |_| {}
        self._state.deinit(self.allocator);
    }

    // --- Scheduling ---
    /// Schedule a CPU job.
    /// - Returns a unique `Id` for the job.
    /// - The `ctx` pointer is opaque; you own its lifetime and must free it when appropriate.
    /// - The job function must return a `JobOutcome`; terminal events are auto-emitted by the worker.
    /// Dangers:
    /// - Do not perform blocking I/O in CPU jobs; use `scheduleBlocking` or the Future+then pattern.
    pub fn schedule(self: *Jobs, func: JobFn, ctx: *anyopaque) !Id {
        const id = self._id_counter.fetchAdd(1, .monotonic);
        self._job_q.push(.{ .job = .{ .id = id, .work = func, .ctx = ctx } });
        self._job_available.post();
        return id;
    }

    /// Schedule a blocking job.
    /// - For operations that may block (file I/O, OS APIs).
    /// - Runs on the blocking worker pool to avoid stalling CPU workers.
    /// Same lifetime caveats for `ctx` as `schedule`.
    pub fn scheduleBlocking(self: *Jobs, func: JobFn, ctx: *anyopaque) !Id {
        const id = self._id_counter.fetchAdd(1, .monotonic);
        self._block_q.push(.{ .job = .{ .id = id, .work = func, .ctx = ctx } });
        self._block_available.post();
        return id;
    }

    // --- Futures API (methods live on Jobs to access scheduler/allocator) ---
    /// Allocate and initialize a `Future(T)` instance.
    /// - Allocated with the `Jobs` allocator; free by `allocator.destroy(fut)` when done.
    /// Dangers:
    /// - Futures are one-shot; do not reuse after completion.
    pub fn makeFuture(self: *Jobs, comptime T: type) !*Future(T) {
        const f = try self.allocator.create(Future(T));
        f.* = .{};
        return f;
    }

    /// Register a continuation to run on the CPU pool when the future completes.
    /// - Exactly one continuation may be set; returns error if already set.
    /// - If the future is already complete, schedules immediately.
    /// Dangers:
    /// - Continuations run on CPU workers: they must not block. Chain blocking via `scheduleBlocking` + another future.
    pub fn then(self: *Jobs, comptime T: type, fut: *Future(T), cont: *const fn (*Jobs, T, *anyopaque) void, ctx: *anyopaque) !void {
        if (fut.cont_set.cmpxchgStrong(0, 1, .acquire, .monotonic)) |_| {
            return error.ContinuationAlreadySet;
        }
        fut.cont_fn = cont;
        fut.cont_ctx = ctx;
        if (fut.done.load(.acquire) == 1) {
            try self._scheduleContinuation(T, fut);
        }
    }

    /// Complete a future with a value.
    /// - Thread-safe; only the first call takes effect and returns true.
    /// - Wakes a waiter (if any) and schedules a continuation (if any).
    /// Dangers:
    /// - Do not access `fut.value` before the first successful completion.
    pub fn complete(self: *Jobs, comptime T: type, fut: *Future(T), value: T) bool {
        if (fut.done.cmpxchgStrong(0, 1, .release, .monotonic)) |_| {
            return false;
        }
        fut.value = value;
        fut.ready.post();
        if (fut.cont_set.load(.acquire) == 1) {
            _ = self._scheduleContinuation(T, fut) catch {};
        }
        return true;
    }

    /// Wait for a future to complete (non-worker threads only).
    /// - Blocks the calling thread until completion or timeout.
    /// - Only one waiter allowed; returns `error.AlreadyHasWaiter` otherwise.
    /// Returns: the completed value or `error.Timeout` if a timeout was provided and elapsed.
    /// Dangers:
    /// - Do NOT call from CPU worker threads; it would block a worker.
    pub fn wait(self: *Jobs, comptime T: type, fut: *Future(T), timeout_ns: ?u64) !T {
        _ = self;
        if (fut.done.load(.acquire) == 0) {
            if (fut.waiter_set.cmpxchgStrong(0, 1, .acquire, .monotonic)) |_| {
                return error.AlreadyHasWaiter;
            }
            if (timeout_ns) |ns| {
                if (!fut.ready.timedWait(ns)) return error.Timeout;
            } else {
                _ = fut.ready.wait();
            }
        }
        return fut.value;
    }

    fn _scheduleContinuation(self: *Jobs, comptime T: type, fut: *Future(T)) !void {
        const Runner = struct {
            fn run(j: *Jobs, ctx: *anyopaque) void {
                const f: *Future(T) = @ptrCast(@alignCast(ctx));
                const fnc = f.cont_fn.?;
                const c = f.cont_ctx.?;
                fnc(j, f.value, c);
            }
        };
        _ = try self.schedule(@ptrCast(&Runner.run), @ptrCast(fut));
    }

    // --- Subscribers API ---
    /// Create a subscriber for broadcast events.
    /// - Key can be by-id (subscribe to specific job) or by-kind (subscribe to event type).
    /// - Capacity is bounded; producers never block. Drop policy governs overflow handling.
    /// - Returns a pointer you must later pass to `unsubscribe`.
    ///
    /// Usage patterns:
    /// ```zig
    /// // Subscribe to all completed events
    /// const sub = try j.subscribe(.{ .key = .{ .kind = .completed } });
    /// defer j.unsubscribe(sub);
    ///
    /// // Subscribe to specific job by ID
    /// const job_id = try j.schedule(&work, ctx);
    /// const sub = try j.subscribe(.{ .key = .{ .id = job_id } });
    /// defer j.unsubscribe(sub);
    ///
    /// // Custom capacity and drop policy
    /// const sub = try j.subscribe(.{
    ///     .key = .{ .kind = .progress },
    ///     .capacity = 2048,
    ///     .drop_progress_first = true, // drop progress before terminal events
    /// });
    /// ```
    ///
    /// Dangers:
    /// - If queue fills, events are dropped per policy to avoid blocking workers.
    /// - Ensure `capacity` is sufficient for your event rate and drain frequency.
    pub fn subscribe(self: *Jobs, opts: SubscribeOpts) !*Subscriber {
        const cap = if (opts.capacity == 0) 1 else opts.capacity;
        const sub = try self.allocator.create(Subscriber);
        sub.* = .{
            .key = opts.key,
            .q = try mpmc_queue.Queue(Event).init(self.allocator, cap),
            .available = .{ .permits = 0 },
            .lossless = opts.lossless,
            .drop_progress_first = opts.drop_progress_first,
        };

        self._subs.mutex.lock();
        defer self._subs.mutex.unlock();
        switch (opts.key) {
            .id => |id| {
                var entry = try self._subs.by_id.getOrPut(self.allocator, id);
                if (!entry.found_existing) entry.value_ptr.* = .{};
                try entry.value_ptr.append(self.allocator, sub);
            },
            .kind => |k| {
                const idx: usize = @intFromEnum(k);
                try self._subs.by_kind[idx].append(self.allocator, sub);
            },
        }
        return sub;
    }

    /// Remove and destroy a subscriber.
    /// - Frees its queue and the subscriber object itself.
    /// Dangers:
    /// - Ensure no other threads are concurrently draining this subscriber.
    pub fn unsubscribe(self: *Jobs, s: *Subscriber) void {
        self._subs.mutex.lock();
        defer self._subs.mutex.unlock();
        switch (s.key) {
            .id => |id| {
                if (self._subs.by_id.getPtr(id)) |lst| {
                    removePtrFromList(self.allocator, lst, s);
                    if (lst.items.len == 0) {
                        _ = self._subs.by_id.remove(id);
                    }
                }
            },
            .kind => |k| {
                const idx: usize = @intFromEnum(k);
                removePtrFromList(self.allocator, &self._subs.by_kind[idx], s);
            },
        }
        s.q.deinit();
        self.allocator.destroy(s);
    }

    /// Non-blocking poll of a subscriber queue.
    /// - Returns an event if available, or null otherwise.
    /// - Use for quick checks without blocking.
    ///
    /// Usage patterns:
    /// ```zig
    /// // Check for events without waiting
    /// if (j.poll(sub)) |event| {
    ///     // handle event
    /// }
    /// ```
    pub fn poll(self: *Jobs, s: *Subscriber) ?Event {
        _ = self;
        var ev: Event = undefined;
        if (s.q.tryPop(&ev)) {
            return ev;
        }
        return null;
    }

    /// Wait for at least one event to become available for a subscriber.
    /// - Blocks on the subscriber semaphore until posted or timeout.
    /// - Returns: true if at least one event is available; false on timeout.
    /// - Pair with `drain()` after this returns true to process available events.
    ///
    /// Usage patterns:
    /// ```zig
    /// // Background worker: block until events arrive
    /// while (j.waitAvailable(sub, null)) { // null = wait indefinitely
    ///     j.drain(sub, 100, &handler, ctx); // process batch
    /// }
    ///
    /// // With timeout for periodic checks
    /// if (j.waitAvailable(sub, 50_000_000)) { // 50ms
    ///     j.drain(sub, 10, &handler, ctx);
    /// }
    /// ```
    pub fn waitAvailable(self: *Jobs, s: *Subscriber, timeout_ns: ?u64) bool {
        _ = self;
        if (timeout_ns) |ns| {
            s.available.timedWait(ns) catch return false;
            return true;
        } else {
            _ = s.available.wait();
            return true;
        }
    }

    /// Drain up to `max` events from a subscriber, invoking a callback per event.
    /// - Non-blocking: returns immediately if queue is empty.
    /// - Processes up to `max` events; stops early if queue becomes empty.
    /// - The `max` parameter serves as a budget control (useful for frame-based processing).
    ///
    /// Usage patterns:
    /// ```zig
    /// // UI event loop: process events within frame budget
    /// j.drain(sub, 16, &handler, ctx); // up to 16 events per frame
    ///
    /// // Process single event
    /// j.drain(sub, 1, &handler, ctx);
    ///
    /// // Process all available events (use large number)
    /// j.drain(sub, 1000, &handler, ctx);
    ///
    /// // Blocking pattern: wait then drain
    /// if (j.waitAvailable(sub, timeout)) {
    ///     j.drain(sub, 50, &handler, ctx); // at least 1 guaranteed
    /// }
    /// ```
    pub fn drain(self: *Jobs, s: *Subscriber, max: usize, cb: *const fn (Event, *anyopaque) void, ctx: *anyopaque) void {
        _ = self;
        var i: usize = 0;
        while (i < max) : (i += 1) {
            var ev: Event = undefined;
            if (s.q.tryPop(&ev)) {
                cb(ev, ctx);
            } else {
                break;
            }
        }
    }

    // --- Internal helpers ---
    fn _recordState(self: *Jobs, id: Id, kind: EventKind, payload: ?*anyopaque) void {
        self._state_mutex.lock();
        defer self._state_mutex.unlock();
        const gop = self._state.getOrPut(self.allocator, id) catch return;
        gop.value_ptr.* = .{ .kind = kind, .payload = payload };
    }

    pub fn publish(self: *Jobs, ev: Event) void {
        // by-kind
        self._subs.mutex.lock();
        var tmp_kind: ?std.ArrayListUnmanaged(*Subscriber) = null;
        var tmp_id: ?std.ArrayListUnmanaged(*Subscriber) = null;
        const kind_idx: usize = @intFromEnum(ev.kind);
        if (self._subs.by_kind[kind_idx].items.len > 0) {
            tmp_kind = .{};
            tmp_kind.?.appendSlice(self.allocator, self._subs.by_kind[kind_idx].items) catch {};
        }
        if (self._subs.by_id.get(ev.id)) |lst| {
            tmp_id = .{};
            tmp_id.?.appendSlice(self.allocator, lst.items) catch {};
        }
        self._subs.mutex.unlock();

        if (tmp_kind) |*lst| {
            for (lst.items) |sub| {
                deliverToSubscriber(sub, ev);
            }
            lst.deinit(self.allocator);
        }
        if (tmp_id) |*lst| {
            for (lst.items) |sub| {
                deliverToSubscriber(sub, ev);
            }
            lst.deinit(self.allocator);
        }
    }

    fn deliverToSubscriber(s: *Subscriber, ev: Event) void {
        // non-blocking: try push; drop on overflow per policy
        if (s.q.tryPush(ev)) {
            s.available.post();
        } else {
            if (!s.lossless and (s.drop_progress_first and ev.kind == .progress)) {
                // drop progress silently
            } else {
                // For lossless or terminal overflow, prefer keeping terminal events; no blocking
                // Drop newest
            }
        }
    }
};

fn removePtrFromList(alloc: std.mem.Allocator, lst: *std.ArrayListUnmanaged(*Subscriber), p: *Subscriber) void {
    var i: usize = 0;
    while (i < lst.items.len) : (i += 1) {
        if (lst.items[i] == p) {
            _ = lst.orderedRemove(i);
            break;
        }
    }
    _ = alloc; // no shrink here
}

fn cpuWorker(j: *Jobs, timeout_ns: ?u64) void {
    var item: WorkItem = undefined;
    loop: while (true) {
        if (j._job_q.tryPop(&item)) {
            switch (item) {
                .job => |job| {
                    const out = job.work(j, job.ctx);
                    // auto-emit terminal event and record state
                    switch (out) {
                        .completed => |p| {
                            j._recordState(job.id, .completed, p);
                            j.publish(.{ .id = job.id, .kind = .completed, .payload = p });
                        },
                        .failed => |p| {
                            j._recordState(job.id, .failed, p);
                            j.publish(.{ .id = job.id, .kind = .failed, .payload = p });
                        },
                        .cancelled => {
                            j._recordState(job.id, .cancelled, null);
                            j.publish(.{ .id = job.id, .kind = .cancelled, .payload = null });
                        },
                    }
                    continue;
                },
                .stop => break :loop,
            }
        }
        if (timeout_ns) |ns| {
            j._job_available.timedWait(ns) catch {};
        } else {
            _ = j._job_available.wait();
        }
    }
}

fn blockingWorker(j: *Jobs, timeout_ns: ?u64) void {
    var item: WorkItem = undefined;
    loop: while (true) {
        if (j._block_q.tryPop(&item)) {
            switch (item) {
                .job => |job| {
                    const out = job.work(j, job.ctx);
                    switch (out) {
                        .completed => |p| {
                            j._recordState(job.id, .completed, p);
                            j.publish(.{ .id = job.id, .kind = .completed, .payload = p });
                        },
                        .failed => |p| {
                            j._recordState(job.id, .failed, p);
                            j.publish(.{ .id = job.id, .kind = .failed, .payload = p });
                        },
                        .cancelled => {
                            j._recordState(job.id, .cancelled, null);
                            j.publish(.{ .id = job.id, .kind = .cancelled, .payload = null });
                        },
                    }
                    continue;
                },
                .stop => break :loop,
            }
        }
        if (timeout_ns) |ns| {
            j._block_available.timedWait(ns) catch {};
        } else {
            _ = j._block_available.wait();
        }
    }
}

// helper used by the file-level test below
fn test_job_work(jobs: *Jobs, ctx_ptr: *anyopaque) JobOutcome {
    _ = jobs;
    const ctx: *u32 = @ptrCast(@alignCast(ctx_ptr));
    if (ctx.* == 0) return .{ .failed = null };
    return .{ .completed = null };
}

// --- File-level test ---
test "jobs basic schedule and subscribe" {
    const alloc = std.testing.allocator;
    const opts = JobsOptions{
        .job_capacity = 8,
        .blocking_capacity = 4,
        .thread_count = 1,
        .blocking_threads = 1,
        .worker_wait_timeout_ns = 10_000_000, // 10ms polling to avoid semaphore race
    };
    var j = try Jobs.init(alloc, opts);
    defer j.deinit();

    try j.start();

    // Give threads time to start up
    std.Thread.sleep(5_000_000); // 5ms

    // subscribe to completed events by kind
    const sub = try j.subscribe(.{ .key = .{ .kind = .completed } });
    defer j.unsubscribe(sub);

    // schedule a job
    const ctx_ptr = try alloc.create(u32);
    defer alloc.destroy(ctx_ptr);
    ctx_ptr.* = 123;
    _ = try j.schedule(&test_job_work, ctx_ptr);

    // Wait for event to be available, then drain
    const ok = j.waitAvailable(sub, 500_000_000); // 500ms timeout
    try std.testing.expect(ok);

    var saw_completed: bool = false;
    const Handler = struct {
        fn handle(ev: Event, ctx: *anyopaque) void {
            if (ev.kind == .completed) {
                const flag: *bool = @ptrCast(@alignCast(ctx));
                flag.* = true;
            }
        }
    };
    j.drain(sub, 16, &Handler.handle, @ptrCast(@alignCast(&saw_completed)));

    // Ensure we saw a completed event
    try std.testing.expect(saw_completed);
}
