const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const strip = b.option(bool, "strip", "Strip debug info from the output binary");

    const bdwgc = b.dependency("bdwgc", .{
        .target = target,
        .optimize = optimize,
        .BUILD_SHARED_LIBS = false,
    });

    const bdwgc_artifact = bdwgc.artifact("gc");

    const ffi = b.dependency("ffi", .{
        .target = target,
        .optimize = optimize,
    });

    const ffi_artifact = ffi.artifact("ffi");

    const exe = b.addExecutable(.{
        .name = "syphon",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });

    const exe_options = b.addOptions();

    exe_options.addOption([]const u8, "version", "0.1.0");

    exe.root_module.addOptions("build_options", exe_options);

    exe.addIncludePath(bdwgc.path("include"));
    exe.linkLibrary(bdwgc_artifact);

    exe.linkLibrary(ffi_artifact);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_check = b.addExecutable(.{
        .name = "syphon",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_check.root_module.addOptions("build_options", exe_options);

    exe_check.addIncludePath(bdwgc.path("include"));
    exe_check.linkLibrary(bdwgc_artifact);

    exe_check.linkLibrary(ffi_artifact);

    const check_step = b.step("check", "Checks if the app can compile");
    check_step.dependOn(&exe_check.step);
}
