const std = @import("std");

const RuntimeBackend = enum {
    mlx,
    host,
};

const MlxBackend = enum {
    auto,
    cpu,
    metal,
    cuda,
};

const MlxLinkage = enum {
    auto,
    static,
    dynamic,
};

const wasm_base_export_symbols = &.{
    "kiwi_alloc_bytes",
    "kiwi_reset_input_arena",
    "kiwi_init",
    "kiwi_deinit",
    "kiwi_eval",
    "kiwi_last_error_ptr",
    "kiwi_last_error_len",
    "kiwi_last_echo_value",
    "kiwi_last_kind",
    "kiwi_last_int",
    "kiwi_last_float",
    "kiwi_last_bool",
    "kiwi_render_last_value",
    "kiwi_last_rendered_ptr",
    "kiwi_last_rendered_len",
    "kiwi_last_display_mime_ptr",
    "kiwi_last_display_mime_len",
    "kiwi_last_display_data_ptr",
    "kiwi_last_display_data_len",
    "kiwi_syntax_tokenize",
};

const wasm_webgpu_export_symbols = &.{
    "kiwi_alloc_bytes",
    "kiwi_reset_input_arena",
    "kiwi_init",
    "kiwi_deinit",
    "kiwi_eval",
    "kiwi_last_error_ptr",
    "kiwi_last_error_len",
    "kiwi_last_echo_value",
    "kiwi_last_kind",
    "kiwi_last_int",
    "kiwi_last_float",
    "kiwi_last_bool",
    "kiwi_last_array_handle",
    "kiwi_last_array_dtype",
    "kiwi_last_array_ndim",
    "kiwi_last_array_shape_dim",
    "kiwi_last_array_size",
    "kiwi_render_last_value",
    "kiwi_last_rendered_ptr",
    "kiwi_last_rendered_len",
    "kiwi_last_display_mime_ptr",
    "kiwi_last_display_mime_len",
    "kiwi_last_display_data_ptr",
    "kiwi_last_display_data_len",
    "kiwi_force_backend_surface",
    "kiwi_syntax_tokenize",
};

fn addWasmBuildOptions(
    options: *std.Build.Step.Options,
    runtime_has_mlx: bool,
    wasm_exports_accelerator_handles: bool,
) void {
    options.addOption(bool, "enable_probe_instrumentation", false);
    options.addOption(bool, "enable_sampling_profile", false);
    options.addOption(bool, "enable_string_instrumentation", false);
    options.addOption([]const u8, "cli_invocation", "kiwi");
    options.addOption(bool, "enable_bench_cli", false);
    options.addOption(bool, "runtime_has_mlx", runtime_has_mlx);
    options.addOption(bool, "runtime_has_duckdb", false);
    options.addOption(bool, "duckdb_external", false);
    options.addOption(bool, "wasm_exports_accelerator_handles", wasm_exports_accelerator_handles);
}

fn addBuildOptions(root_module: *std.Build.Module, options: *std.Build.Step.Options) void {
    root_module.addOptions("build_options", options);
}

fn parseEnumOption(
    comptime T: type,
    option_name: []const u8,
    raw: ?[]const u8,
    default_value: T,
) T {
    const text = raw orelse return default_value;
    return std.meta.stringToEnum(T, text) orelse {
        std.debug.print("invalid -D{s} value: {s}\n", .{ option_name, text });
        std.process.exit(1);
    };
}

fn resolveBuildPath(b: *std.Build, raw: []const u8) []const u8 {
    return if (std.fs.path.isAbsolute(raw)) raw else b.pathFromRoot(raw);
}

fn configuredPathOrDefault(b: *std.Build, provided: ?[]const u8, fallback: []const u8) []const u8 {
    return resolveBuildPath(b, provided orelse fallback);
}

fn pathExistsAbsolute(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

fn targetMatchesHost(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == b.graph.host.result.os.tag and
        target.result.cpu.arch == b.graph.host.result.cpu.arch;
}

fn resolveInstallPrefixSubdir(b: *std.Build, prefix: []const u8, subdir: []const u8) []const u8 {
    const candidate = b.fmt("{s}/{s}", .{ prefix, subdir });
    return if (pathExistsAbsolute(candidate)) candidate else prefix;
}

fn cppFlags(target: std.Build.ResolvedTarget) []const []const u8 {
    return if (target.result.os.tag == .linux)
        &.{ "-std=c++20", "-stdlib=libstdc++" }
    else
        &.{"-std=c++20"};
}

fn addRelocatableMlxRPath(root_module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    switch (target.result.os.tag) {
        .linux => root_module.addRPathSpecial("$ORIGIN/../lib"),
        .macos, .ios, .watchos, .tvos, .visionos => root_module.addRPathSpecial("@loader_path/../lib"),
        else => {},
    }
}

fn isAppleTarget(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.os.tag) {
        .macos, .ios, .watchos, .tvos, .visionos => true,
        else => false,
    };
}

fn addAppleFrameworkPath(step: anytype, apple_sdk: ?[]const u8) void {
    if (apple_sdk) |sdk| {
        step.root_module.addFrameworkPath(.{
            .cwd_relative = step.step.owner.fmt("{s}/System/Library/Frameworks", .{sdk}),
        });
    }
}

fn linkAppleAccelerate(step: anytype, target: std.Build.ResolvedTarget, apple_sdk: ?[]const u8) void {
    if (!isAppleTarget(target)) return;
    addAppleFrameworkPath(step, apple_sdk);
    step.root_module.linkFramework("Accelerate", .{});
}

fn mlxRuntimeLibDir(b: *std.Build, mlx_prefix: []const u8) []const u8 {
    return b.fmt("{s}/lib", .{mlx_prefix});
}

fn mlxSharedLibraryName(target: std.Build.ResolvedTarget) ?[]const u8 {
    return switch (target.result.os.tag) {
        .linux => "libmlx.so",
        .macos, .ios, .watchos, .tvos, .visionos => "libmlx.dylib",
        else => null,
    };
}

fn installMlxRuntimeFile(b: *std.Build, lib_dir: []const u8, name: []const u8) void {
    const path = b.fmt("{s}/{s}", .{ lib_dir, name });
    if (!pathExistsAbsolute(path)) return;
    b.getInstallStep().dependOn(&b.addInstallLibFile(.{ .cwd_relative = path }, name).step);
}

fn installExternalMlx(
    b: *std.Build,
    runtime_backend: RuntimeBackend,
    target: std.Build.ResolvedTarget,
    mlx_prefix: []const u8,
) void {
    if (runtime_backend != .mlx) return;
    const lib_dir = mlxRuntimeLibDir(b, mlx_prefix);
    const lib_name = mlxSharedLibraryName(target) orelse return;
    installMlxRuntimeFile(b, lib_dir, lib_name);
    switch (target.result.os.tag) {
        .macos, .ios, .watchos, .tvos, .visionos => {
            installMlxRuntimeFile(b, lib_dir, "libjaccl.dylib");
            installMlxRuntimeFile(b, lib_dir, "mlx.metallib");
        },
        else => {},
    }
}

fn configureRunMlxLibraryPath(
    run: *std.Build.Step.Run,
    target: std.Build.ResolvedTarget,
    mlx_prefix: []const u8,
) void {
    const lib_dir = mlxRuntimeLibDir(run.step.owner, mlx_prefix);
    switch (target.result.os.tag) {
        .linux => run.setEnvironmentVariable("LD_LIBRARY_PATH", lib_dir),
        .macos, .ios, .watchos, .tvos, .visionos => run.setEnvironmentVariable("DYLD_LIBRARY_PATH", lib_dir),
        else => {},
    }
}

fn addNativeMlxImports(
    b: *std.Build,
    root_module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    mlx_c_include: []const u8,
    mlx_prefix: []const u8,
    mlxc_mini_bridge: ?[]const u8,
) void {
    const legacy_c = b.createModule(.{
        .root_source_file = b.path("src/native/c.zig"),
        .target = target,
        .optimize = optimize,
    });
    const legacy_mlx = b.createModule(.{
        .root_source_file = b.path("src/native/mlx.zig"),
        .target = target,
        .optimize = optimize,
    });
    legacy_mlx.addImport("c.zig", legacy_c);
    legacy_c.addIncludePath(.{ .cwd_relative = mlx_c_include });
    legacy_c.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{mlx_prefix}) });
    legacy_mlx.addIncludePath(.{ .cwd_relative = mlx_c_include });
    legacy_mlx.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{mlx_prefix}) });
    root_module.addImport("kiwi_runtime_c", legacy_c);
    root_module.addImport("kiwi_runtime_mlx", legacy_mlx);
    root_module.addIncludePath(.{ .cwd_relative = mlx_c_include });
    root_module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{mlx_prefix}) });
    root_module.addLibraryPath(.{ .cwd_relative = mlxRuntimeLibDir(b, mlx_prefix) });
    addRelocatableMlxRPath(root_module, target);
    if (mlxc_mini_bridge == null) {
        root_module.addCSourceFiles(.{
            .files = &.{"csrc/mlxc_mini.cpp"},
            .flags = cppFlags(target),
            .language = .cpp,
        });
    }
}

fn addHostOnlyImports(
    b: *std.Build,
    root_module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const runtime_c = b.createModule(.{
        .root_source_file = b.path("src/native/c.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_module.addImport("kiwi_runtime_c", runtime_c);
}

fn addHostSimdSources(root_module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    switch (target.result.cpu.arch) {
        .aarch64 => root_module.addCSourceFiles(.{
            .files = &.{
                "csrc/host_cpu.c",
                "csrc/host_sum.c",
                "csrc/host_sum_neon.c",
                "csrc/host_find.c",
                "csrc/host_find_neon.c",
                "csrc/host_compare.c",
                "csrc/host_compare_neon.c",
                "csrc/host_dyad.c",
                "csrc/host_dyad_neon.c",
                "csrc/host_blas.c",
                "csrc/host_mask_neon.c",
                "csrc/string_mask_neon.c",
            },
            .flags = &.{ "-std=c11", "-fno-sanitize=undefined" },
            .language = .c,
        }),
        .x86_64 => {
            root_module.addCSourceFiles(.{
                .files = &.{
                    "csrc/host_cpu.c",
                    "csrc/host_sum.c",
                    "csrc/host_sum_sse2.c",
                    "csrc/host_find.c",
                    "csrc/host_find_sse2.c",
                    "csrc/host_compare.c",
                    "csrc/host_compare_sse2.c",
                    "csrc/host_dyad.c",
                    "csrc/host_blas.c",
                },
                .flags = &.{ "-std=c11", "-fno-sanitize=undefined" },
                .language = .c,
            });
            root_module.addCSourceFiles(.{
                .files = &.{
                    "csrc/host_sum_avx2.c",
                    "csrc/host_find_avx2.c",
                    "csrc/host_compare_avx2.c",
                },
                .flags = &.{ "-std=c11", "-fno-sanitize=undefined", "-mavx2" },
                .language = .c,
            });
            root_module.addCSourceFiles(.{
                .files = &.{
                    "csrc/host_compare_sse41.c",
                },
                .flags = &.{ "-std=c11", "-fno-sanitize=undefined", "-msse4.1" },
                .language = .c,
            });
            root_module.addCSourceFiles(.{
                .files = &.{
                    "csrc/host_sum_avx512.c",
                    "csrc/host_find_avx512.c",
                    "csrc/host_compare_avx512.c",
                },
                .flags = &.{ "-std=c11", "-fno-sanitize=undefined", "-mavx512f", "-mavx512bw", "-mevex512" },
                .language = .c,
            });
        },
        else => {},
    }
}

fn addRuntimeImports(
    b: *std.Build,
    root_module: *std.Build.Module,
    runtime_backend: RuntimeBackend,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    mlx_c_include: []const u8,
    mlx_prefix: []const u8,
    mlxc_mini_bridge: ?[]const u8,
) void {
    switch (runtime_backend) {
        .mlx => addNativeMlxImports(b, root_module, target, optimize, mlx_c_include, mlx_prefix, mlxc_mini_bridge),
        .host => addHostOnlyImports(b, root_module, target, optimize),
    }
    addHostSimdSources(root_module, target);
}

fn addDuckDbImports(
    b: *std.Build,
    root_module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    duckdb_prefix: ?[]const u8,
    add_absolute_rpath: bool,
) void {
    if (target.result.cpu.arch == .wasm32) return;
    const prefix = duckdb_prefix orelse {
        std.debug.print("DuckDB dependency not found. Run scripts/bootstrap_duckdb.sh or pass -Dduckdb-prefix=<prefix>.\n", .{});
        std.process.exit(1);
    };
    const include_path = resolveInstallPrefixSubdir(b, prefix, "include");
    const library_path = resolveInstallPrefixSubdir(b, prefix, "lib");
    root_module.addIncludePath(.{ .cwd_relative = include_path });
    root_module.addLibraryPath(.{ .cwd_relative = library_path });
    if (add_absolute_rpath) root_module.addRPath(.{ .cwd_relative = library_path });
    addRelocatableMlxRPath(root_module, target);
}

fn duckdbSharedLibraryName(target: std.Build.ResolvedTarget) ?[]const u8 {
    return switch (target.result.os.tag) {
        .linux => "libduckdb.so",
        .macos, .ios, .watchos, .tvos, .visionos => "libduckdb.dylib",
        else => null,
    };
}

fn installExternalDuckDb(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    duckdb_prefix: ?[]const u8,
) void {
    const prefix = duckdb_prefix orelse return;
    const lib_name = duckdbSharedLibraryName(target) orelse return;
    const library_path = resolveInstallPrefixSubdir(b, prefix, "lib");
    const lib_path = b.fmt("{s}/{s}", .{ library_path, lib_name });
    if (!pathExistsAbsolute(lib_path)) return;
    b.getInstallStep().dependOn(&b.addInstallLibFile(.{ .cwd_relative = lib_path }, lib_name).step);
}

fn configureRunLibraryPath(
    run: *std.Build.Step.Run,
    runtime_backend: RuntimeBackend,
    target: std.Build.ResolvedTarget,
    mlx_prefix: []const u8,
) void {
    if (runtime_backend != .mlx) return;
    configureRunMlxLibraryPath(run, target, mlx_prefix);
}

fn linkDuckDb(
    step: anytype,
    target: std.Build.ResolvedTarget,
    duckdb_prefix: ?[]const u8,
    add_absolute_rpath: bool,
) void {
    if (target.result.cpu.arch == .wasm32) return;
    if (duckdb_prefix) |prefix| {
        const library_path = resolveInstallPrefixSubdir(step.step.owner, prefix, "lib");
        step.root_module.addLibraryPath(.{ .cwd_relative = library_path });
        if (add_absolute_rpath) step.root_module.addRPath(.{ .cwd_relative = library_path });
        addRelocatableMlxRPath(step.root_module, target);
        step.root_module.linkSystemLibrary("duckdb", .{});
    }
}

fn linkMlxDeps(
    step: anytype,
    runtime_backend: RuntimeBackend,
    target: std.Build.ResolvedTarget,
    mlx_backend: MlxBackend,
    mlx_linkage: MlxLinkage,
    mlxc_mini_bridge: ?[]const u8,
    apple_sdk: ?[]const u8,
) void {
    if (runtime_backend != .mlx) return;
    const mlx_link_opts: std.Build.Module.LinkSystemLibraryOptions = switch (mlx_linkage) {
        .auto => .{},
        .static => .{
            .preferred_link_mode = .static,
            .search_strategy = .mode_first,
        },
        .dynamic => .{
            .preferred_link_mode = .dynamic,
            .search_strategy = .mode_first,
        },
    };
    if (mlxc_mini_bridge) |bridge_name| {
        step.root_module.linkSystemLibrary(bridge_name, .{});
    }
    if (mlx_linkage == .auto)
        step.root_module.linkSystemLibrary("mlx", .{})
    else
        step.linkSystemLibrary2("mlx", mlx_link_opts);
    step.root_module.linkSystemLibrary("c", .{});
    switch (target.result.os.tag) {
        .linux => step.root_module.linkSystemLibrary("stdc++", .{}),
        else => step.root_module.linkSystemLibrary("c++", .{}),
    }
    if (isAppleTarget(target)) {
        linkAppleAccelerate(step, target, apple_sdk);
        switch (mlx_backend) {
            .metal, .auto => {
                step.root_module.linkFramework("Metal", .{});
                step.root_module.linkFramework("Foundation", .{});
                step.root_module.linkFramework("QuartzCore", .{});
            },
            .cpu, .cuda => {},
        }
    }
}

fn linkHostDeps(
    step: anytype,
    runtime_backend: RuntimeBackend,
    target: std.Build.ResolvedTarget,
    apple_sdk: ?[]const u8,
) void {
    if (target.result.cpu.arch == .wasm32) return;
    if (runtime_backend != .host) return;
    step.root_module.linkSystemLibrary("c", .{});
    linkAppleAccelerate(step, target, apple_sdk);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const public_export = pathExistsAbsolute(b.pathFromRoot("PUBLIC_EXPORT"));
    const has_bench_sources = pathExistsAbsolute(b.pathFromRoot("src/bench_internal.zig")) and
        pathExistsAbsolute(b.pathFromRoot("src/bench_test_internal.zig"));
    const has_test_sources = pathExistsAbsolute(b.pathFromRoot("src/tests.zig"));
    const public_cli = b.option(bool, "public-cli", "Build the standalone CLI install surface (bin/kiwi only by default).") orelse public_export;
    const runtime_backend = parseEnumOption(
        RuntimeBackend,
        "runtime-backend",
        b.option([]const u8, "runtime-backend", "Backend implementation to compile against: mlx or host."),
        .mlx,
    );
    const mlx_backend = parseEnumOption(
        MlxBackend,
        "mlx-backend",
        b.option([]const u8, "mlx-backend", "Native MLX backend shape: auto, cpu, metal, or cuda."),
        .auto,
    );
    const mlx_linkage = parseEnumOption(
        MlxLinkage,
        "mlx-linkage",
        b.option([]const u8, "mlx-linkage", "Preferred MLX link mode: auto, static, or dynamic."),
        .auto,
    );
    const cli_name = b.option([]const u8, "cli-name", "Installed CLI executable name.") orelse if (public_cli) "kiwi" else "kiwi-zig";
    const install_sdk = b.option(bool, "install-sdk", "Install bridge libs and headers.") orelse !public_cli;
    _ = b.option(bool, "install-probes", "Deprecated compatibility option; standalone probe executables are no longer built.");
    const mlx_prefix = configuredPathOrDefault(
        b,
        b.option([]const u8, "mlx-prefix", "Installed MLX prefix to link against. Defaults to .deps/mlx."),
        ".deps/mlx",
    );
    const mlx_c_include = configuredPathOrDefault(
        b,
        b.option([]const u8, "mlx-c-include", "Path to the MLX C headers directory. Defaults to .deps/mlx-c."),
        ".deps/mlx-c",
    );
    const mlxc_mini_bridge = b.option([]const u8, "mlxc-mini-bridge", "Link an external MLX helper bridge library instead of compiling csrc/mlxc_mini.cpp.");
    const apple_sdk = b.option([]const u8, "apple-sdk", "Apple SDK root used to locate system frameworks for targeted macOS builds.");
    const duckdb_prefix_option = b.option([]const u8, "duckdb-prefix", "External DuckDB install prefix. If unset, prefer .deps/duckdb when present. When set, prefer an install root that contains include/ and lib/.");
    const default_duckdb_prefix = b.pathFromRoot(".deps/duckdb");
    const duckdb_prefix = if (duckdb_prefix_option) |raw|
        resolveBuildPath(b, raw)
    else if (targetMatchesHost(b, target) and pathExistsAbsolute(default_duckdb_prefix))
        default_duckdb_prefix
    else
        null;
    const raw_strip_symbols = b.option(bool, "strip", "Strip debug info from compiled artifacts.");
    const strip_symbols = raw_strip_symbols orelse false;
    const wasm_strip_symbols = b.option(bool, "wasm-strip", "Strip debug info from wasm artifacts. Defaults to true.") orelse raw_strip_symbols orelse true;
    const strip_instrumentation = b.option(bool, "strip-instrumentation", "Compile out profile/probe/string instrumentation for stripped performance builds.") orelse false;
    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_probe_instrumentation", !strip_instrumentation);
    build_options.addOption(bool, "enable_sampling_profile", !strip_instrumentation);
    build_options.addOption(bool, "enable_string_instrumentation", optimize == .Debug and !strip_instrumentation);
    build_options.addOption([]const u8, "cli_invocation", cli_name);
    build_options.addOption(bool, "enable_bench_cli", !public_cli and has_bench_sources);
    build_options.addOption(bool, "runtime_has_mlx", runtime_backend == .mlx);
    build_options.addOption(bool, "runtime_has_duckdb", target.result.cpu.arch != .wasm32);
    build_options.addOption(bool, "duckdb_external", duckdb_prefix != null);
    build_options.addOption(bool, "wasm_exports_accelerator_handles", false);
    const wasm_webgpu_build_options = b.addOptions();
    addWasmBuildOptions(wasm_webgpu_build_options, true, true);
    const wasm_host_min_build_options = b.addOptions();
    addWasmBuildOptions(wasm_host_min_build_options, false, false);

    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip_symbols,
    });
    addBuildOptions(module, build_options);
    addRuntimeImports(b, module, runtime_backend, target, optimize, mlx_c_include, mlx_prefix, mlxc_mini_bridge);
    addDuckDbImports(b, module, target, duckdb_prefix, !public_cli);

    const exe = b.addExecutable(.{
        .name = cli_name,
        .root_module = module,
    });
    exe.each_lib_rpath = false;
    linkMlxDeps(exe, runtime_backend, target, mlx_backend, mlx_linkage, mlxc_mini_bridge, apple_sdk);
    linkHostDeps(exe, runtime_backend, target, apple_sdk);
    linkDuckDb(exe, target, duckdb_prefix, !public_cli);
    b.installArtifact(exe);
    installExternalMlx(b, runtime_backend, target, mlx_prefix);
    installExternalDuckDb(b, target, duckdb_prefix);

    const run_cmd = b.addRunArtifact(exe);
    configureRunLibraryPath(run_cmd, runtime_backend, target, mlx_prefix);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", b.fmt("Run {s}", .{cli_name}));
    run_step.dependOn(&run_cmd.step);

    if (install_sdk) {
        const bridge_module = b.createModule(.{
            .root_source_file = b.path("src/kiwi_bridge.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip_symbols,
        });
        addBuildOptions(bridge_module, build_options);
        addRuntimeImports(b, bridge_module, runtime_backend, target, optimize, mlx_c_include, mlx_prefix, mlxc_mini_bridge);
        addDuckDbImports(b, bridge_module, target, duckdb_prefix, !public_cli);

        const bridge_shared = b.addLibrary(.{
            .linkage = .dynamic,
            .name = "kiwi_bridge",
            .root_module = bridge_module,
        });
        bridge_shared.each_lib_rpath = false;
        linkMlxDeps(bridge_shared, runtime_backend, target, mlx_backend, mlx_linkage, mlxc_mini_bridge, apple_sdk);
        linkHostDeps(bridge_shared, runtime_backend, target, apple_sdk);
        linkDuckDb(bridge_shared, target, duckdb_prefix, !public_cli);
        b.installArtifact(bridge_shared);
        bridge_shared.installHeader(b.path("bridge/include/kiwi_bridge.h"), "kiwi_bridge.h");
        bridge_shared.installHeader(b.path("bridge/include/module.modulemap"), "module.modulemap");

        const bridge_static = b.addLibrary(.{
            .linkage = .static,
            .name = "kiwi_bridge",
            .root_module = bridge_module,
        });
        b.installArtifact(bridge_static);
    }

    if (has_test_sources) {
        const test_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip_symbols,
        });
        addBuildOptions(test_module, build_options);
        addRuntimeImports(b, test_module, runtime_backend, target, optimize, mlx_c_include, mlx_prefix, mlxc_mini_bridge);
        addDuckDbImports(b, test_module, target, duckdb_prefix, !public_cli);

        const tests = b.addTest(.{
            .root_module = test_module,
        });
        tests.each_lib_rpath = false;
        linkMlxDeps(tests, runtime_backend, target, mlx_backend, mlx_linkage, mlxc_mini_bridge, apple_sdk);
        linkHostDeps(tests, runtime_backend, target, apple_sdk);
        linkDuckDb(tests, target, duckdb_prefix, !public_cli);
        const test_run = b.addRunArtifact(tests);
        configureRunLibraryPath(test_run, runtime_backend, target, mlx_prefix);
        const test_step = b.step("test", "Run kiwi-zig tests");
        test_step.dependOn(&test_run.step);
    }

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_module = b.createModule(.{
        .root_source_file = b.path("src/wasm_api.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .strip = wasm_strip_symbols,
    });
    addBuildOptions(wasm_module, wasm_webgpu_build_options);
    wasm_module.export_symbol_names = wasm_webgpu_export_symbols;

    const wasm_exe = b.addExecutable(.{
        .name = "kiwi_wasm_module",
        .root_module = wasm_module,
    });
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;

    const wasm_cmd = b.addSystemCommand(&.{ "bash", "scripts/build_kiwi_wasm_module.sh" });
    wasm_cmd.setCwd(b.path("."));
    wasm_cmd.addFileArg(wasm_exe.getEmittedBin());
    wasm_cmd.addArg("web/kiwi_wasm_module.wasm");

    const wasm_webgpu_step = b.step("wasm-webgpu", "Build the Kiwi wasm module for the WebGPU-capable web target");
    wasm_webgpu_step.dependOn(&wasm_cmd.step);

    const wasm_host_min_module = b.createModule(.{
        .root_source_file = b.path("src/wasm_api.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .strip = wasm_strip_symbols,
    });
    addBuildOptions(wasm_host_min_module, wasm_host_min_build_options);
    wasm_host_min_module.export_symbol_names = wasm_base_export_symbols;

    const wasm_host_min_exe = b.addExecutable(.{
        .name = "kiwi_wasm_module_host_min",
        .root_module = wasm_host_min_module,
    });
    wasm_host_min_exe.entry = .disabled;
    wasm_host_min_exe.rdynamic = true;

    const wasm_host_min_cmd = b.addSystemCommand(&.{ "bash", "scripts/build_kiwi_wasm_module.sh" });
    wasm_host_min_cmd.setCwd(b.path("."));
    wasm_host_min_cmd.addFileArg(wasm_host_min_exe.getEmittedBin());
    wasm_host_min_cmd.addArg("web/kiwi_wasm_module_host_min.wasm");

    const wasm_host_min_step = b.step("wasm-host-min", "Build the minimal host-only Kiwi wasm module");
    wasm_host_min_step.dependOn(&wasm_host_min_cmd.step);

    const wasm_step = b.step("wasm", "Build the Kiwi wasm module for the web target");
    wasm_step.dependOn(&wasm_cmd.step);
}
