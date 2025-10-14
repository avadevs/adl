## Jobs System (Updated Design)

### Goals
- Simple, predictable behavior for immediate-mode apps (30–144 FPS).
- High utilization: CPU workers never block.
- First-class targeted waits without an event loop.
- Coordinator-free broadcast delivery to subscribers.

### Components
- CPU Pool (N threads): executes non-blocking jobs only.
- Blocking Pool (M threads, small): executes known blocking calls (file I/O, OS APIs).
- Job Queue: `mpmc_queue.Queue(Job)` feeding the CPU pool.
- Blocking Queue: `mpmc_queue.Queue(Job)` feeding the blocking pool.
- Futures (targeted waits): one-shot completion, usable from any thread; workers use continuations, non-workers may block.
- Subscribers: per-subscriber `mpsc_queue.Queue(Event)` with a counting semaphore for blocking waits without spinning.
- Wait Registry: maps keys (id and/or kind) to futures/continuations.
- Job State Store: id → state for immediate late-join resolution.

### Data Types
- Id: `usize`.
- EventKind: `{ progress, completed, failed, cancelled }`.
- Event: `{ id: Id, kind: EventKind, payload: ?*anyopaque }`.
- JobFn: `*const fn (*Jobs, *anyopaque) void`.
- Future(T): one-shot result; single-completion, single-waiter or continuation; thread-safe post.

### Concurrency Rules
- CPU workers must not block; use continuations (`then`) for waits.
- Non-worker threads may block on futures or subscriber semaphores.
- Broadcast is coordinator-free: producers fan-out directly into per-subscriber MPSC queues.
- Futures are for targeted waits; events are for broadcast.
- Backpressure handled per subscriber: capacity + drop policy; never block workers on publish.

### Blocking Call Pattern
- Wrapper `scheduleBlocking`: submit a closure to the Blocking Pool.
- For workers needing a blocking operation:
  1) Create a future.
  2) Submit blocking work to Blocking Pool that completes the future.
  3) Register `then(fut, continuation)` which enqueues the continuation job to CPU Pool on completion.
  4) Return from the worker job immediately.
- For non-workers: you may `wait(fut, timeout_ns)` directly.

### Subscriber Queues (Broadcast)
- Each subscriber has a bounded `mpsc_queue.Queue(Event)` and a `std.Thread.Semaphore available`.
- On successful enqueue: `available.post()`.
- Consumers call `available.timedWait(ns)` to sleep until there is at least one event, then drain up to a budget.
- Drop policy on overflow: drop `progress` first, keep terminal events; optionally drop oldest progress.

### API (Sketch)
```zig
pub const Jobs = struct {
    // lifecycle
    pub fn init(alloc: std.mem.Allocator, opts: JobsOptions) !Jobs;
    pub fn deinit(self: *Jobs) void;

    // scheduling
    pub fn schedule(self: *Jobs, func: JobFn, ctx: *anyopaque) !Id;          // CPU pool
    pub fn scheduleBlocking(self: *Jobs, func: JobFn, ctx: *anyopaque) !Id;  // Blocking pool

    // futures (targeted waits)
    pub fn makeFuture(self: *Jobs, comptime T: type) !*Future(T);
    pub fn complete(self: *Jobs, fut: *Future(T), value: T) void; // thread-safe
    pub fn then(self: *Jobs, fut: *Future(T), cont: *const fn(*Jobs, T, *anyopaque) void, ctx: *anyopaque) void; // worker-safe
    pub fn wait(self: *Jobs, fut: *Future(T), timeout_ns: ?u64) !T; // non-worker threads only

    // events (broadcast)
    pub const SubscribeOpts = struct {
        key: EventKey,
        capacity: usize = 1024,
        lossless: bool = false,
        drop_progress_first: bool = true,
    };
    pub fn subscribe(self: *Jobs, opts: SubscribeOpts) !*Subscriber;
    pub fn unsubscribe(self: *Jobs, s: *Subscriber) void;
    pub fn poll(self: *Jobs, s: *Subscriber) ?Event; // non-blocking
    pub fn waitAvailable(self: *Jobs, s: *Subscriber, timeout_ns: ?u64) bool; // semaphore wait
    pub fn drain(self: *Jobs, s: *Subscriber, max: usize, cb: *const fn (Event, *anyopaque) void, ctx: *anyopaque) void;
};
```

### Flows
1) CPU Job → Completion → Broadcast and/or Future
```
CPU worker
  do work
  if progress: enqueue to matching subscribers; post semaphore
  on completion: complete future (if any), emit terminal event to subscribers
```

2) Worker awaiting a blocking operation
```
CPU worker
  fut = makeFuture(T)
  scheduleBlocking(blocking_fn)
  then(fut, continuation) // schedules continuation job when done
  return // free CPU worker

Blocking pool thread
  val = blocking_fn()
  complete(fut, val)
```

3) Subscriber consumption without busy-wait
```
consumer thread
  if waitAvailable(sub, 1ms): // blocks on semaphore
      drain(sub, 256, handle, ctx) // budgeted per frame
```

### Policies
- Worker threads never block. Any potentially blocking path uses Future+then or scheduleBlocking.
- Broadcast queues are bounded; drop policy keeps terminal events.
- Futures are one-shot; completion is idempotent (first completion wins).
- Job state store enables immediate resolution for wait-by-id without registration.

### Rationale
- Avoids a central event loop; uses minimal OS primitives (semaphores) and two pools.
- Keeps CPU workers hot: no blocking, continuations re-enter the pool on readiness.
- Broadcast is predictable and per-consumer; targeted waits are explicit via futures.


