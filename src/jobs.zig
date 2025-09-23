const std = @import("std");
const core = @import("core");
const zjobs = @import("zjobs");
const win32 = core.platform;

// This file contains all definitions for the application's background job system.

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Step 1: Define the results that jobs can produce.
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

const OpenProcessError = error{OpenProcessFailed};

pub const TaskResult = union(enum) {
    AttachProcess: struct {
        request_id: u64,
        result: union(enum) {
            Success: struct {
                handle: win32.HANDLE,
            },
            Failure: struct {
                reason: anyerror,
            },
        },
    },

    RefreshProcesses: struct {
        request_id: u64,
        result: union(enum) {
            Success: struct {
                processes: std.ArrayList(win32.ProcessInfo),
            },
            Failure: struct {
                reason: anyerror,
            },
        },
    },

    PopulateMemoryRegions: struct {
        request_id: u64,
        result: union(enum) {
            Success,
            Failure: struct {
                reason: anyerror,
            },
        },
    },
};

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Step 2: Define the concrete job structs that zjobs will execute.
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

pub const AttachProcessJob = struct {
    pid: win32.DWORD,
    request_id: u64,
    result_queue: *std.ArrayList(TaskResult),
    mutex: *std.Thread.Mutex,

    pub fn exec(self: *@This()) void {
        const handle: ?win32.HANDLE = win32.openProcess(self.pid);
        const result = if (handle) |h| TaskResult{ .AttachProcess = .{ .request_id = self.request_id, .result = .{ .Success = .{ .handle = h } } } } else TaskResult{ .AttachProcess = .{ .request_id = self.request_id, .result = .{ .Failure = .{ .reason = OpenProcessError.OpenProcessFailed } } } };

        self.mutex.lock();
        defer self.mutex.unlock();
        self.result_queue.append(result) catch |e| {
            std.log.err("Failed to push AttachProcess result to queue: {any}", .{e});
        };
    }
};

pub const RefreshProcessesJob = struct {
    request_id: u64,
    allocator: std.mem.Allocator,
    result_queue: *std.ArrayList(TaskResult),
    mutex: *std.Thread.Mutex,

    pub fn exec(self: *@This()) void {
        const processes = win32.getAllProcesses(self.allocator);
        const result = if (processes) |procs| TaskResult{
            .RefreshProcesses = .{
                .request_id = self.request_id,
                .result = .{
                    .Success = .{ .processes = procs },
                },
            },
        } else |err| TaskResult{
            .RefreshProcesses = .{
                .request_id = self.request_id,
                .result = .{
                    .Failure = .{ .reason = err },
                },
            },
        };

        self.mutex.lock();
        defer self.mutex.unlock();
        self.result_queue.append(result) catch |e| {
            std.log.err("Failed to push RefreshProcesses result to queue: {any}", .{e});
        };
    }
};

pub const PopulateMemoryRegionsJob = struct {
    request_id: u64,
    session: *core.engine.ScannerSession,
    result_queue: *std.ArrayList(TaskResult),
    mutex: *std.Thread.Mutex,

    pub fn exec(self: *@This()) void {
        self.session.populateMemoryRegions() catch |err| {
            const result = TaskResult{ .PopulateMemoryRegions = .{ .request_id = self.request_id, .result = .{ .Failure = .{ .reason = err } } } };
            self.mutex.lock();
            defer self.mutex.unlock();
            self.result_queue.append(result) catch |e| {
                std.log.err("Failed to push PopulateMemoryRegions result to queue: {any}", .{e});
            };
            return;
        };

        const result = TaskResult{ .PopulateMemoryRegions = .{ .request_id = self.request_id, .result = .Success } };
        self.mutex.lock();
        defer self.mutex.unlock();
        self.result_queue.append(result) catch |e| {
            std.log.err("Failed to push PopulateMemoryRegions result to queue: {any}", .{e});
        };
    }
};

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Step 3: Define a central runner for scheduling and handling jobs.
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

pub const JobRunner = struct {
    allocator: std.mem.Allocator,
    job_system: zjobs.JobQueue,
    result_queue: std.ArrayList(TaskResult),
    result_mutex: std.Thread.Mutex = .{},
    next_request_id: u64 = 1,

    pub fn init(allocator: std.mem.Allocator) !JobRunner {
        return .{
            .allocator = allocator,
            .job_system = zjobs.JobQueue(.{ .idle_sleep_ns = std.time.ns_per_ms * 10 }).init(),
            .result_queue = std.ArrayList(TaskResult).init(allocator),
        };
    }

    pub fn deinit(self: *JobRunner) void {
        self.job_system.deinit();
        self.result_queue.deinit();
    }

    pub fn start(self: *JobRunner) void {
        self.job_system.start(.{});
    }

    pub fn getResults(self: *JobRunner, out_results: *std.ArrayList(TaskResult)) void {
        self.result_mutex.lock();
        defer self.result_mutex.unlock();
        out_results.clearRetainingCapacity();
        out_results.appendSlice(self.result_queue.items) catch |err| {
            std.log.err("Failed to append results: {any}", .{err});
        };
        self.result_queue.clearRetainingCapacity();
    }

    fn nextId(self: *JobRunner) u64 {
        const id = self.next_request_id;
        self.next_request_id += 1;
        return id;
    }

    // --- Job Scheduling Functions ---

    pub fn scheduleAttachProcess(self: *JobRunner, pid: u32) u64 {
        const id = self.nextId();
        const job = AttachProcessJob{
            .pid = pid,
            .request_id = id,
            .result_queue = &self.result_queue,
            .mutex = &self.result_mutex,
        };
        _ = self.job_system.schedule(.none, job) catch |err| {
            std.log.err("Failed to schedule AttachProcessJob: {any}", .{err});
        };
        std.log.info("Scheduled job to attach to PID: {}", .{pid});
        return id;
    }

    pub fn scheduleRefreshProcesses(self: *JobRunner) u64 {
        const id = self.nextId();
        const job = RefreshProcessesJob{
            .request_id = id,
            .allocator = self.allocator,
            .result_queue = &self.result_queue,
            .mutex = &self.result_mutex,
        };
        _ = self.job_system.schedule(.none, job) catch |err| {
            std.log.err("Failed to schedule RefreshProcessesJob: {any}", .{err});
        };
        std.log.info("Scheduled job to refresh processes", .{});
        return id;
    }

    pub fn schedulePopulateMemoryRegions(self: *JobRunner, session: *core.engine.ScannerSession) u64 {
        const id = self.nextId();
        const job = PopulateMemoryRegionsJob{
            .request_id = id,
            .session = session,
            .result_queue = &self.result_queue,
            .mutex = &self.result_mutex,
        };
        _ = self.job_system.schedule(.none, job) catch |err| {
            std.log.err("Failed to schedule PopulateMemoryRegionsJob: {any}", .{err});
        };
        std.log.info("Scheduled job to populate memory regions", .{});
        return id;
    }
};
