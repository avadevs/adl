/// The jobs module is making the creation and management of asynchronous work easier.
/// Jobs are created by the developer and will then be executed by one thread.
/// Threads will spawn based on the provided configuration.
///
/// You can think of jobs as the input to the job system.
/// Events on the other hand are the output of the job system and are usually created
/// during the execution of a scheduled job.
///
/// Both Jobs and Events have a unique ID to identify them later on.
/// You can try to cancel a job but cancellation is cooperative so you need to
/// check for cancellation during the execution of the job.
///
/// Jobs and Events will have their own multi producer multi consumer (mpmc) queue
/// to ensure we provide maximum flexiblity to you as the developer.
/// This means that you can schedule jobs from your regular code and also from other jobs
/// (synchronous and asynchronous job handling).
/// This allows us to create events (the output of the system) directly from the jobs,
/// which means we don't have to go through a single-threaded job "executor" to collect the results of
/// each job to then create events.
/// You can then consume the events from all threads because the queue allows multiple consumers.
///
const std = @import("std");
const mpmc_queue = @import("mpmc_queue.zig");

pub const Id: type = usize;

//--- Options ---
pub const JobsOptions = struct {
    job_capacity: usize,
    thread_count: usize = std.Thread.getCpuCount() - 1 catch 1,
};

//--- Job ---
pub const JobFn = *const fn (*Jobs, *anyopaque) void;

/// A job is the input to the job system. It declares
/// the work that you want to have done on your thread pool.
pub const Job = struct {
    id: Id,
    work: JobFn,
};

//--- Event ---
pub const EventKind = enum {
    progress,
    completed,
    failed,
    cancelled,
};

/// An event is the output of the job system. It is created by the job system
/// when the job is completed.
/// You can react to events that get emitted by the job system.
/// You can bind to the event by type of event or by the id of the event.
pub const Event = struct {
    id: Id,
    kind: EventKind,
    payload: ?*anyopaque,
};

/// This struct holds the queue that is responsible for holding the jobs.
/// You can schedule jobs by pushing the jobs into the queue.
/// The jobs are executed by the thred pool that is created by the job system.
pub const Jobs = struct {
    allocator: std.mem.Allocator,
    _queue: mpmc_queue.Queue(null),
    _threads: std.Thread.Pool,
    _id_counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    pub fn init(allocator: std.mem.Allocator, options: JobsOptions) !Jobs {
        var jobs = Jobs{
            .allocator = allocator,
            ._queue = try mpmc_queue.Queue(null).init(allocator, options.job_capacity),
        };

        jobs._threads.init(.{ .allocator = allocator, .n_jobs = options.thread_count }) catch |err| {
            std.log.err("Failed to initialize threads: {any}", .{err});
            return error.FailedToInitializeThreads;
        };

        return jobs;
    }

    pub fn deinit(self: *Jobs) void {
        self._queue.deinit();
        self._threads.deinit();
    }

    /// Adds a job to the queue. This will block until the job is added.
    /// Returns the id of the job that was added.
    pub fn addJob(self: *Jobs) !usize {
        const id = self._id_counter.fetchAdd(1, .monotonic);

        self._queue.push(null);

        return id;
    }

    /// Tries to add a job to the queue.
    /// Returns the id of the job that was added.
    pub fn tryAddJob(self: *Jobs) !usize {
        return self._queue.tryPush(null);
    }
};
