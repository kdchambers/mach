const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&testStep(b, optimize, target).step);
}

pub fn testStep(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.zig.CrossTarget) *std.build.RunStep {
    const main_tests = b.addTest(.{
        .name = "sysjs-tests",
        .kind = .test_exe,
        .root_source_file = .{ .path = sdkPath("/src/main.zig") },
        .target = target,
        .optimize = optimize,
    });
    return main_tests.run();
}

var cached_module: ?*std.build.Module = null;

pub fn module(b: *std.Build) *std.build.Module {
    if (cached_module == null) {
        cached_module = b.createModule(.{
            .source_file = .{ .path = sdkPath("/src/main.zig") },
        });
    }
    return cached_module.?;
}

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}
