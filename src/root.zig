//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const mpmc_queue = @import("utility/mpmc_queue.zig");
const ui = @import("ui/ui.zig");
const jobs = @import("jobs.zig");
const router = @import("router.zig");
const store = @import("store.zig");

test {
    _ = @import("ui/ui.zig");
    _ = @import("jobs.zig");
    _ = @import("router.zig");
    _ = @import("store.zig");
    _ = @import("utility/mpmc_queue.zig");
}
