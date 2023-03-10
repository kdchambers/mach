const std = @import("std");

pub fn Sdk(comptime deps: anytype) type {
    return struct {
        pub const Options = struct {
            glfw_options: deps.glfw.Options = .{},
            gpu_dawn_options: deps.gpu_dawn.Options = .{},

            pub fn gpuOptions(options: Options) deps.gpu.Options {
                return .{
                    .gpu_dawn_options = options.gpu_dawn_options,
                };
            }
        };

        pub fn module(b: *std.Build, target: std.zig.CrossTarget) *std.build.Module {
            const dependencies: []std.build.ModuleDependency = blk: {
                if (target.isLinux()) {
                    break :blk &[_]std.build.ModuleDependency{
                        .{ .name = "gpu", .module = deps.gpu.module(b) },
                        .{ .name = "glfw", .module = deps.glfw.module(b) },
                        .{ .name = "gamemode", .module = deps.gamemode.module(b) },
                    };
                }
                const native_target = (std.zig.system.NativeTargetInfo.detect(target) catch unreachable).target;
                if (native_target.cpu.arch == .wasm32) {
                    break :blk &[_]std.build.ModuleDependency{
                        .{ .name = "gpu", .module = deps.gpu.module(b) },
                        .{ .name = "sysjs", .module = deps.sysjs.module(b) },
                    };
                }
                break :blk &[_]std.build.ModuleDependency{
                    .{ .name = "glfw", .module = deps.glfw.module(b) },
                    .{ .name = "gpu", .module = deps.gpu.module(b) },
                };
            };
            return b.createModule(.{
                .source_file = .{ .path = sdkPath("/src/main.zig") },
                .dependencies = dependencies,
            });
        }

        pub fn testStep(
            b: *std.Build,
            optimize: std.builtin.OptimizeMode,
            target: std.zig.CrossTarget,
        ) !*std.build.RunStep {
            const main_tests = b.addTest(.{
                .name = "core-tests",
                .kind = .test_exe,
                .root_source_file = .{ .path = sdkPath("/src/main.zig") },
                .target = target,
                .optimize = optimize,
            });
            var iter = module(b, target).dependencies.iterator();
            while (iter.next()) |e| {
                main_tests.addModule(e.key_ptr.*, e.value_ptr.*);
            }
            try deps.glfw.link(b, main_tests, .{});
            if (target.isLinux()) {
                deps.gamemode.link(main_tests);
            }
            main_tests.addIncludePath(sdkPath("/include"));
            main_tests.install();
            return main_tests.run();
        }

        pub fn buildSharedLib(
            b: *std.Build,
            optimize: std.builtin.OptimizeMode,
            target: std.zig.CrossTarget,
            options: Options,
        ) !*std.build.CompileStep {
            // TODO(build): this should use the App abstraction instead of being built manually
            std.debug.assert(false);
            const lib = b.addSharedLibrary(.{
                .name = "machcore",
                .root_source_file = .{ .path = "src/platform/libmachcore.zig" },
                .target = target,
                .optimize = optimize,
            });
            lib.main_pkg_path = "src/";
            const app_module = b.createModule(.{
                .source_file = .{ .path = "src/platform/libmachcore.zig" },
            });
            lib.addModule("app", app_module);
            lib.addModule("glfw", deps.glfw.module(b));
            lib.addModule("gpu", deps.gpu.module(b));
            if (target.isLinux()) {
                lib.addModule("gamemode", deps.gamemode.module(b));
                deps.gamemode.link(lib);
            }
            try deps.glfw.link(b, lib, options.glfw_options);
            try deps.gpu.link(b, lib, options.gpuOptions());
            return lib;
        }

        fn sdkPath(comptime suffix: []const u8) []const u8 {
            if (suffix[0] != '/') @compileError("suffix must be an absolute path");
            return comptime blk: {
                const root_dir = std.fs.path.dirname(@src().file) orelse ".";
                break :blk root_dir ++ suffix;
            };
        }
    };
}
