const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. The Core ADL Module (No Raylib dependency)
    const adl_mod = b.addModule("adl", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Zclay is required for core ADL
    const zclay_dep = b.dependency("zclay", .{
        .target = target,
        .optimize = optimize,
    });
    adl_mod.addImport("zclay", zclay_dep.module("zclay"));

    // 2. The Raylib Backend Module (Optional for users)
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib_mod = raylib_dep.module("raylib");
    // const raylib_artifact = raylib_dep.artifact("raylib");

    const backend_mod = b.addModule("adl_raylib", .{
        .root_source_file = b.path("src/backends/raylib_backend.zig"),
        .target = target,
        .optimize = optimize,
    });
    backend_mod.addImport("adl", adl_mod);
    backend_mod.addImport("raylib", raylib_mod);
    backend_mod.addImport("zclay", zclay_dep.module("zclay"));

    // 3. Static Library
    const lib = b.addLibrary(.{
        .name = "adl",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/root.zig"),
        }),
    });
    lib.root_module.addImport("zclay", zclay_dep.module("zclay"));
    lib.linkLibC();
    b.installArtifact(lib);

    // 4. Tests
    const mod_tests = b.addTest(.{
        .root_module = adl_mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
