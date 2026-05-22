const std = @import("std");

fn configuredPathOrDefault(b: *std.Build, provided: ?[]const u8, fallback: []const u8) []const u8 {
    const raw = provided orelse fallback;
    return if (std.fs.path.isAbsolute(raw)) raw else b.pathFromRoot(raw);
}

fn configuredRelativePathOrDefault(provided: ?[]const u8, fallback: []const u8) []const u8 {
    const raw = provided orelse fallback;
    if (std.fs.path.isAbsolute(raw)) {
        @panic("kiwi-root must be relative to extensions/jupyter-kiwi");
    }
    return raw;
}

fn pathExistsAbsolute(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

fn hasWorkspaceDependencyLayout(b: *std.Build, workspace_root: []const u8) bool {
    return pathExistsAbsolute(b.fmt("{s}/vendor/mlx-c", .{workspace_root}));
}

fn findImplementationKiwiRootRelative(b: *std.Build) ?[]const u8 {
    const implementations_rel = "../../implementations";
    var dir = std.fs.openDirAbsolute(b.pathFromRoot(implementations_rel), .{ .iterate = true }) catch return null;
    defer dir.close();

    var iterator = dir.iterate();
    while (true) {
        const maybe_entry = iterator.next() catch return null;
        const entry = maybe_entry orelse break;
        if (entry.kind != .directory) continue;

        const candidate_rel = b.fmt("{s}/{s}", .{ implementations_rel, entry.name });
        const candidate_abs = b.pathFromRoot(candidate_rel);
        if (pathExistsAbsolute(b.fmt("{s}/src/kiwi_bridge.zig", .{candidate_abs}))) {
            return candidate_rel;
        }
    }
    return null;
}

fn defaultKiwiRootRelative(b: *std.Build) []const u8 {
    if (pathExistsAbsolute(b.pathFromRoot("../../src/kiwi_bridge.zig"))) {
        return "../..";
    }
    return findImplementationKiwiRootRelative(b) orelse "../..";
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
                else => @panic("unsupported linux arch for kiwi-array-jupyter"),
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
    kiwi_root_rel: []const u8,
    mlx_prefix: []const u8,
    mlx_c_include: []const u8,
) void {
    const runtime_c = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.fmt("{s}/src/native/c.zig", .{kiwi_root_rel}) },
        .target = target,
        .optimize = optimize,
    });
    const runtime_mlx = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.fmt("{s}/src/native/mlx.zig", .{kiwi_root_rel}) },
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
        .files = &.{b.fmt("{s}/csrc/mlxc_mini.cpp", .{kiwi_root_rel})},
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

fn addHostSimdSources(
    b: *std.Build,
    root_module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    kiwi_root_rel: []const u8,
) void {
    switch (target.result.cpu.arch) {
        .aarch64 => root_module.addCSourceFiles(.{
            .files = &.{
                b.fmt("{s}/csrc/host_cpu.c", .{kiwi_root_rel}),
                b.fmt("{s}/csrc/host_sum.c", .{kiwi_root_rel}),
                b.fmt("{s}/csrc/host_sum_neon.c", .{kiwi_root_rel}),
                b.fmt("{s}/csrc/host_find.c", .{kiwi_root_rel}),
                b.fmt("{s}/csrc/host_find_neon.c", .{kiwi_root_rel}),
                b.fmt("{s}/csrc/host_compare.c", .{kiwi_root_rel}),
                b.fmt("{s}/csrc/host_compare_neon.c", .{kiwi_root_rel}),
                b.fmt("{s}/csrc/host_dyad.c", .{kiwi_root_rel}),
                b.fmt("{s}/csrc/host_dyad_neon.c", .{kiwi_root_rel}),
                b.fmt("{s}/csrc/host_blas.c", .{kiwi_root_rel}),
                b.fmt("{s}/csrc/host_mask_neon.c", .{kiwi_root_rel}),
                b.fmt("{s}/csrc/string_mask_neon.c", .{kiwi_root_rel}),
            },
            .flags = &.{ "-std=c11", "-fno-sanitize=undefined" },
            .language = .c,
        }),
        .x86_64 => {
            root_module.addCSourceFiles(.{
                .files = &.{
                    b.fmt("{s}/csrc/host_cpu.c", .{kiwi_root_rel}),
                    b.fmt("{s}/csrc/host_sum.c", .{kiwi_root_rel}),
                    b.fmt("{s}/csrc/host_sum_sse2.c", .{kiwi_root_rel}),
                    b.fmt("{s}/csrc/host_find.c", .{kiwi_root_rel}),
                    b.fmt("{s}/csrc/host_find_sse2.c", .{kiwi_root_rel}),
                    b.fmt("{s}/csrc/host_compare.c", .{kiwi_root_rel}),
                    b.fmt("{s}/csrc/host_compare_sse2.c", .{kiwi_root_rel}),
                    b.fmt("{s}/csrc/host_dyad.c", .{kiwi_root_rel}),
                    b.fmt("{s}/csrc/host_blas.c", .{kiwi_root_rel}),
                },
                .flags = &.{ "-std=c11", "-fno-sanitize=undefined" },
                .language = .c,
            });
            root_module.addCSourceFiles(.{
                .files = &.{
                    b.fmt("{s}/csrc/host_sum_avx2.c", .{kiwi_root_rel}),
                    b.fmt("{s}/csrc/host_find_avx2.c", .{kiwi_root_rel}),
                    b.fmt("{s}/csrc/host_compare_avx2.c", .{kiwi_root_rel}),
                },
                .flags = &.{ "-std=c11", "-fno-sanitize=undefined", "-mavx2" },
                .language = .c,
            });
            root_module.addCSourceFiles(.{
                .files = &.{
                    b.fmt("{s}/csrc/host_compare_sse41.c", .{kiwi_root_rel}),
                },
                .flags = &.{ "-std=c11", "-fno-sanitize=undefined", "-msse4.1" },
                .language = .c,
            });
            root_module.addCSourceFiles(.{
                .files = &.{
                    b.fmt("{s}/csrc/host_sum_avx512.c", .{kiwi_root_rel}),
                    b.fmt("{s}/csrc/host_find_avx512.c", .{kiwi_root_rel}),
                    b.fmt("{s}/csrc/host_compare_avx512.c", .{kiwi_root_rel}),
                },
                .flags = &.{ "-std=c11", "-fno-sanitize=undefined", "-mavx512f", "-mavx512bw", "-mevex512" },
                .language = .c,
            });
        },
        else => {},
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
    const workspace_root = b.pathFromRoot("../..");
    const kiwi_root_rel = configuredRelativePathOrDefault(
        b.option([]const u8, "kiwi-root", "Kiwi source root relative to extensions/jupyter-kiwi."),
        defaultKiwiRootRelative(b),
    );
    const kiwi_root = b.pathFromRoot(kiwi_root_rel);
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
        .root_source_file = .{ .cwd_relative = b.fmt("{s}/src/kiwi_bridge.zig", .{kiwi_root_rel}) },
        .target = target,
        .optimize = optimize,
    });
    addBuildOptions(bridge_module, build_options);
    addKiwiImports(b, bridge_module, target, optimize, kiwi_root_rel, mlx_prefix, mlx_c_include);
    addHostSimdSources(b, bridge_module, target, kiwi_root_rel);

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

    const test_step = b.step("test", "Run kiwi-array-jupyter bridge tests");
    test_step.dependOn(&test_run.step);
}
