const std = @import("std");

fn configuredPathOrDefault(b: *std.Build, provided: ?[]const u8, fallback: []const u8) []const u8 {
    const raw = provided orelse fallback;
    return if (std.fs.path.isAbsolute(raw)) raw else b.pathFromRoot(raw);
}

fn pathExistsAbsolute(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

fn hasWorkspaceDependencyLayout(b: *std.Build, workspace_root: []const u8) bool {
    return pathExistsAbsolute(b.fmt("{s}/vendor/mlx-c", .{workspace_root}));
}

fn defaultMlxPrefix(b: *std.Build, target: std.Build.ResolvedTarget, kiwi_root: []const u8, workspace_root: []const u8) []const u8 {
    if (!hasWorkspaceDependencyLayout(b, workspace_root)) {
        return b.fmt("{s}/.deps/mlx", .{kiwi_root});
    }
    return switch (target.result.os.tag) {
        .linux => b.fmt("{s}/.artifacts/mlx/linux-{s}-install", .{
            workspace_root,
            switch (target.result.cpu.arch) {
                .aarch64 => "aarch64",
                .x86_64 => "x86_64",
                else => @panic("unsupported linux arch for kiwilang-jupyter-kernel"),
            },
        }),
        else => b.fmt("{s}/.artifacts/mlx/macos-default-install", .{workspace_root}),
    };
}

fn defaultMlxCInclude(b: *std.Build, kiwi_root: []const u8, workspace_root: []const u8) []const u8 {
    if (!hasWorkspaceDependencyLayout(b, workspace_root)) {
        return b.fmt("{s}/.deps/mlx-c", .{kiwi_root});
    }
    return b.fmt("{s}/vendor/mlx-c", .{workspace_root});
}

fn addBuildOptions(root_module: *std.Build.Module, options: *std.Build.Step.Options) void {
    root_module.addOptions("build_options", options);
}

fn cppFlags(target: std.Build.ResolvedTarget) []const []const u8 {
    return if (target.result.os.tag == .linux)
        &.{ "-std=c++20", "-stdlib=libstdc++" }
    else
        &.{"-std=c++20"};
}

fn addKiwiImports(
    b: *std.Build,
    root_module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    kiwi_root: []const u8,
    mlx_prefix: []const u8,
    mlx_c_include: []const u8,
) void {
    const runtime_c = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.fmt("{s}/src/native/c.zig", .{kiwi_root}) },
        .target = target,
        .optimize = optimize,
    });
    const runtime_mlx = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.fmt("{s}/src/native/mlx.zig", .{kiwi_root}) },
        .target = target,
        .optimize = optimize,
    });
    runtime_mlx.addImport("c.zig", runtime_c);
    runtime_c.addIncludePath(.{ .cwd_relative = mlx_c_include });
    runtime_c.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{mlx_prefix}) });
    runtime_mlx.addIncludePath(.{ .cwd_relative = mlx_c_include });
    runtime_mlx.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{mlx_prefix}) });

    root_module.addImport("kiwi_runtime_c", runtime_c);
    root_module.addImport("kiwi_runtime_mlx", runtime_mlx);
    root_module.addIncludePath(.{ .cwd_relative = mlx_c_include });
    root_module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{mlx_prefix}) });
    root_module.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{mlx_prefix}) });
    root_module.addRPath(.{ .cwd_relative = b.fmt("{s}/lib", .{mlx_prefix}) });
    root_module.addCSourceFiles(.{
        .files = &.{"../../csrc/mlxc_mini.cpp"},
        .flags = cppFlags(target),
        .language = .cpp,
    });
}

fn linkMlxDeps(step: anytype, target: std.Build.ResolvedTarget) void {
    step.root_module.linkSystemLibrary("mlx", .{});
    step.root_module.linkSystemLibrary("c", .{});

    switch (target.result.os.tag) {
        .linux => step.root_module.linkSystemLibrary("stdc++", .{}),
        else => step.root_module.linkSystemLibrary("c++", .{}),
    }

    if (target.result.os.tag == .macos) {
        step.root_module.linkFramework("Accelerate", .{});
        step.root_module.linkFramework("Metal", .{});
        step.root_module.linkFramework("Foundation", .{});
        step.root_module.linkFramework("QuartzCore", .{});
    }
}

fn configureRunLibraryPath(run: *std.Build.Step.Run, target: std.Build.ResolvedTarget, mlx_prefix: []const u8) void {
    const lib_dir = run.step.owner.fmt("{s}/lib", .{mlx_prefix});
    switch (target.result.os.tag) {
        .linux => run.setEnvironmentVariable("LD_LIBRARY_PATH", lib_dir),
        .macos, .ios, .watchos, .tvos, .visionos => run.setEnvironmentVariable("DYLD_LIBRARY_PATH", lib_dir),
        else => {},
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const kiwi_root = b.pathFromRoot("../..");
    const workspace_root = b.pathFromRoot("../../../..");
    const mlx_prefix = configuredPathOrDefault(
        b,
        b.option([]const u8, "mlx-prefix", "Installed MLX prefix to link against."),
        defaultMlxPrefix(b, target, kiwi_root, workspace_root),
    );
    const mlx_c_include = configuredPathOrDefault(
        b,
        b.option([]const u8, "mlx-c-include", "Path to the MLX C headers directory."),
        defaultMlxCInclude(b, kiwi_root, workspace_root),
    );

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_probe_instrumentation", false);
    build_options.addOption(bool, "enable_sampling_profile", false);
    build_options.addOption(bool, "enable_string_instrumentation", false);
    build_options.addOption([]const u8, "cli_invocation", "kiwi");
    build_options.addOption(bool, "enable_bench_cli", false);
    build_options.addOption(bool, "runtime_has_mlx", true);
    build_options.addOption(bool, "runtime_has_duckdb", false);
    build_options.addOption(bool, "duckdb_external", false);
    build_options.addOption(bool, "wasm_exports_accelerator_handles", false);

    const bridge_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.fmt("{s}/src/kiwi_bridge.zig", .{kiwi_root}) },
        .target = target,
        .optimize = optimize,
    });
    addBuildOptions(bridge_module, build_options);
    addKiwiImports(b, bridge_module, target, optimize, kiwi_root, mlx_prefix, mlx_c_include);

    const test_module = b.createModule(.{
        .root_source_file = b.path("zig-src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("kiwi_bridge", bridge_module);

    const tests = b.addTest(.{
        .root_module = test_module,
    });
    linkMlxDeps(tests, target);

    const test_run = b.addRunArtifact(tests);
    configureRunLibraryPath(test_run, target, mlx_prefix);

    const test_step = b.step("test", "Run kiwilang-jupyter-kernel bridge tests");
    test_step.dependOn(&test_run.step);
}
