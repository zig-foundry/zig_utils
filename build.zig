const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Public library module that other packages can import as `@import("zig_utils")`.
    const mod = b.addModule("zig_utils", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Executable module for the CLI or demo runner.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig_utils", .module = mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "zig_utils",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // Run step (`zig build run -- <args>`)
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test step (`zig build test`)
    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{ .root_module = exe_mod });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run all library and executable tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Check step (`zig build check`)
    // Checks if the code compiles without emitting binaries. Used by LSPs for fast diagnostics.
    const exe_check = b.addExecutable(.{
        .name = "zig_utils",
        .root_module = exe_mod,
    });

    const check_step = b.step("check", "Check if the library and app compile");
    check_step.dependOn(&mod_tests.step);
    check_step.dependOn(&exe_check.step);

    // Docs step (`zig build docs`)
    // Builds HTML documentation and puts it in `zig-out/docs`.
    const docs_obj = b.addObject(.{
        .name = "zig_utils",
        .root_module = mod,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Build HTML documentation into zig-out/docs");
    docs_step.dependOn(&install_docs.step);
}
