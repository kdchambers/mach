const std = @import("std");
const builtin = @import("builtin");
const system_sdk = @import("libs/glfw/system_sdk.zig");
const glfw = @import("libs/glfw/build.zig");
const ecs = @import("libs/ecs/build.zig");
const freetype = @import("libs/freetype/build.zig");
const basisu = @import("libs/basisu/build.zig");
const sysjs = @import("libs/sysjs/build.zig");
const earcut = @import("libs/earcut/build.zig");
const gamemode = @import("libs/gamemode/build.zig");
const model3d = @import("libs/model3d/build.zig");
const dusk = @import("libs/dusk/build.zig");
const wasmserve = @import("tools/wasmserve/wasmserve.zig");
const gpu_dawn = @import("libs/gpu-dawn/sdk.zig").Sdk(.{
    .glfw_include_dir = sdkPath("/libs/glfw/upstream/glfw/include"),
    .system_sdk = system_sdk,
});
const gpu = @import("libs/gpu/sdk.zig").Sdk(.{
    .gpu_dawn = gpu_dawn,
});
const sysaudio = @import("libs/sysaudio/sdk.zig").Sdk(.{
    .system_sdk = system_sdk,
    .sysjs = sysjs,
});
const core = @import("libs/core/sdk.zig").Sdk(.{
    .gpu = gpu,
    .gpu_dawn = gpu_dawn,
    .glfw = glfw,
    .gamemode = gamemode,
    .wasmserve = wasmserve,
    .sysjs = sysjs,
});

pub fn module(b: *std.Build, target: std.zig.CrossTarget) *std.build.Module {
    return b.createModule(.{
        .source_file = .{ .path = sdkPath("/src/main.zig") },
        .dependencies = &.{
            .{ .name = "core", .module = core.module(b, target) },
            .{ .name = "ecs", .module = ecs.module(b) },
            .{ .name = "sysaudio", .module = sysaudio.module(b) },
            .{ .name = "earcut", .module = earcut.module(b) },
        },
    });
}

pub const Options = struct {
    core: core.Options = .{},
    sysaudio: sysaudio.Options = .{},
    freetype: freetype.Options = .{},
};

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const gpu_dawn_options = gpu_dawn.Options{
        .from_source = b.option(bool, "dawn-from-source", "Build Dawn from source") orelse false,
        .debug = b.option(bool, "dawn-debug", "Use a debug build of Dawn") orelse false,
    };
    const options = Options{ .core = .{ .gpu_dawn_options = gpu_dawn_options } };

    if (target.getCpuArch() != .wasm32) {
        const all_tests_step = b.step("test", "Run library tests");
        const core_test_step = b.step("test-core", "Run Core library tests");
        const ecs_test_step = b.step("test-ecs", "Run ECS library tests");
        const freetype_test_step = b.step("test-freetype", "Run Freetype library tests");
        const basisu_test_step = b.step("test-basisu", "Run Basis-Universal library tests");
        const sysaudio_test_step = b.step("test-sysaudio", "Run sysaudio library tests");
        const model3d_test_step = b.step("test-model3d", "Run Model3D library tests");
        const dusk_test_step = b.step("test-dusk", "Run Dusk library tests");
        const mach_test_step = b.step("test-mach", "Run Engine library tests");

        core_test_step.dependOn(&(try core.testStep(b, optimize, target)).step);
        freetype_test_step.dependOn(&freetype.testStep(b, optimize, target).step);
        ecs_test_step.dependOn(&ecs.testStep(b, optimize, target).step);
        basisu_test_step.dependOn(&basisu.testStep(b, optimize, target).step);
        sysaudio_test_step.dependOn(&sysaudio.testStep(b, optimize, target).step);
        model3d_test_step.dependOn(&model3d.testStep(b, optimize, target).step);
        dusk_test_step.dependOn(&dusk.testStep(b, optimize, target).step);
        mach_test_step.dependOn(&testStep(b, optimize, target).step);

        all_tests_step.dependOn(core_test_step);
        all_tests_step.dependOn(ecs_test_step);
        all_tests_step.dependOn(basisu_test_step);
        all_tests_step.dependOn(freetype_test_step);
        all_tests_step.dependOn(sysaudio_test_step);
        all_tests_step.dependOn(model3d_test_step);
        all_tests_step.dependOn(dusk_test_step);
        all_tests_step.dependOn(mach_test_step);

        const shaderexp_app = try App.init(
            b,
            .{
                .name = "shaderexp",
                .src = "shaderexp/main.zig",
                .target = target,
                .optimize = optimize,
            },
        );
        try shaderexp_app.link(options);
        shaderexp_app.install();

        const shaderexp_compile_step = b.step("shaderexp", "Compile shaderexp");
        shaderexp_compile_step.dependOn(&shaderexp_app.getInstallStep().?.step);

        const shaderexp_run_cmd = try shaderexp_app.run();
        shaderexp_run_cmd.dependOn(&shaderexp_app.getInstallStep().?.step);
        const shaderexp_run_step = b.step("run-shaderexp", "Run shaderexp");
        shaderexp_run_step.dependOn(shaderexp_run_cmd);
    }

    const compile_all = b.step("compile-all", "Compile Mach");
    compile_all.dependOn(b.getInstallStep());
}

fn testStep(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.zig.CrossTarget) *std.build.RunStep {
    const main_tests = b.addTest(.{
        .name = "mach-tests",
        .kind = .test_exe,
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    var iter = module(b, target).dependencies.iterator();
    while (iter.next()) |e| {
        main_tests.addModule(e.key_ptr.*, e.value_ptr.*);
    }
    main_tests.install();
    return main_tests.run();
}

pub const App = struct {
    const web_install_dir = std.build.InstallDir{ .custom = "www" };

    pub const InitError = error{OutOfMemory} || std.zig.system.NativeTargetInfo.DetectError;
    pub const LinkError = glfw.LinkError;
    pub const RunError = error{
        ParsingIpFailed,
    } || wasmserve.Error || std.fmt.ParseIntError;

    pub const Platform = enum {
        native,
        web,

        pub fn fromTarget(target: std.Target) Platform {
            if (target.cpu.arch == .wasm32) return .web;
            return .native;
        }
    };

    b: *std.Build,
    name: []const u8,
    step: *std.build.CompileStep,
    platform: Platform,
    res_dirs: ?[]const []const u8,
    watch_paths: ?[]const []const u8,
    use_freetype: ?[]const u8 = null,
    use_model3d: bool = false,

    pub fn init(
        b: *std.Build,
        options: struct {
            name: []const u8,
            src: []const u8,
            target: std.zig.CrossTarget,
            optimize: std.builtin.OptimizeMode,
            deps: ?[]const std.build.ModuleDependency = null,
            res_dirs: ?[]const []const u8 = null,
            watch_paths: ?[]const []const u8 = null,

            /// If set, freetype will be linked and can be imported using this name.
            // TODO(build-system): name is currently not used / always "freetype"
            use_freetype: ?[]const u8 = null,
            use_model3d: bool = false,
        },
    ) InitError!App {
        const target = (try std.zig.system.NativeTargetInfo.detect(options.target)).target;
        const platform = Platform.fromTarget(target);

        var deps = std.ArrayList(std.build.ModuleDependency).init(b.allocator);
        if (options.deps) |v| try deps.appendSlice(v);
        try deps.append(.{ .name = "mach", .module = module(b, options.target) });
        try deps.append(.{ .name = "gpu", .module = gpu.module(b) });
        try deps.append(.{ .name = "sysaudio", .module = sysaudio.module(b) });

        if (platform == .web)
            try deps.append(.{ .name = "sysjs", .module = sysjs.module(b) });

        if (options.use_freetype) |_| try deps.append(.{ .name = "freetype", .module = freetype.module(b) });

        const app_module = b.createModule(.{
            .source_file = .{ .path = options.src },
            .dependencies = try deps.toOwnedSlice(),
        });

        const step = blk: {
            if (platform == .web) {
                const lib = b.addSharedLibrary(.{
                    .name = options.name,
                    .root_source_file = .{ .path = sdkPath("/src/platform/wasm/entry.zig") },
                    .target = options.target,
                    .optimize = options.optimize,
                });
                lib.rdynamic = true;
                lib.addModule("sysjs", sysjs.module(b));
                break :blk lib;
            } else {
                const exe = b.addExecutable(.{
                    .name = options.name,
                    .root_source_file = .{ .path = sdkPath("/src/platform/native/entry.zig") },
                    .target = options.target,
                    .optimize = options.optimize,
                });
                break :blk exe;
            }
        };

        step.main_pkg_path = sdkPath("/src");
        step.addModule("gpu", gpu.module(b));
        step.addModule("app", app_module);

        return .{
            .b = b,
            .name = options.name,
            .step = step,
            .platform = platform,
            .res_dirs = options.res_dirs,
            .watch_paths = options.watch_paths,
            .use_freetype = options.use_freetype,
            .use_model3d = options.use_model3d,
        };
    }

    pub fn link(app: *const App, options: Options) LinkError!void {
        if (app.platform != .web) {
            try glfw.link(app.b, app.step, options.core.glfw_options);
            gpu.link(app.b, app.step, options.core.gpuOptions()) catch return error.FailedToLinkGPU;
            if (app.step.target.isLinux())
                gamemode.link(app.step);
        }

        sysaudio.link(app.b, app.step, options.sysaudio);
        if (app.use_freetype) |_| freetype.link(app.b, app.step, options.freetype);
        if (app.use_model3d) {
            model3d.link(app.b, app.step, app.step.target);
        }
    }

    pub fn install(app: *const App) void {
        app.step.install();

        // Install additional files (src/mach.js and template.html)
        // in case of wasm
        if (app.platform == .web) {
            // Set install directory to '{prefix}/www'
            app.getInstallStep().?.dest_dir = web_install_dir;

            inline for (.{ "/src/platform/wasm/mach.js", "/libs/sysjs/src/mach-sysjs.js" }) |js| {
                const install_js = app.b.addInstallFileWithDir(
                    .{ .path = sdkPath(js) },
                    web_install_dir,
                    std.fs.path.basename(js),
                );
                app.getInstallStep().?.step.dependOn(&install_js.step);
            }

            const html_generator = app.b.addExecutable(.{
                .name = "html-generator",
                .root_source_file = .{ .path = sdkPath("/tools/html-generator/main.zig") },
            });
            const run_html_generator = html_generator.run();
            run_html_generator.addArgs(&.{ "index.html", app.name });

            run_html_generator.cwd = app.b.getInstallPath(web_install_dir, "");
            app.getInstallStep().?.step.dependOn(&run_html_generator.step);
        }

        // Install resources
        if (app.res_dirs) |res_dirs| {
            for (res_dirs) |res| {
                const install_res = app.b.addInstallDirectory(.{
                    .source_dir = res,
                    .install_dir = app.getInstallStep().?.dest_dir,
                    .install_subdir = std.fs.path.basename(res),
                    .exclude_extensions = &.{},
                });
                app.getInstallStep().?.step.dependOn(&install_res.step);
            }
        }
    }

    pub fn run(app: *const App) RunError!*std.build.Step {
        if (app.platform == .web) {
            const address = std.process.getEnvVarOwned(app.b.allocator, "MACH_ADDRESS") catch try app.b.allocator.dupe(u8, "127.0.0.1");
            const port = std.process.getEnvVarOwned(app.b.allocator, "MACH_PORT") catch try app.b.allocator.dupe(u8, "8080");
            const address_parsed = std.net.Address.parseIp4(address, try std.fmt.parseInt(u16, port, 10)) catch return error.ParsingIpFailed;
            const serve_step = try wasmserve.serve(
                app.step,
                .{
                    .install_dir = web_install_dir,
                    .watch_paths = app.watch_paths,
                    .listen_address = address_parsed,
                },
            );
            return &serve_step.step;
        } else {
            return &app.step.run().step;
        }
    }

    pub fn getInstallStep(app: *const App) ?*std.build.InstallArtifactStep {
        return app.step.install_step;
    }
};

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}
