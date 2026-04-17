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
    "kiwi_force_backend_surface",
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

fn mlxRuntimeLibDir(b: *std.Build, mlx_prefix: []const u8) []const u8 {
    return b.fmt("{s}/lib", .{mlx_prefix});
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
}

fn addDuckDbImports(
    b: *std.Build,
    root_module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    repo_root: []const u8,
    duckdb_prefix: ?[]const u8,
) void {
    if (target.result.cpu.arch == .wasm32) return;
    if (duckdb_prefix) |prefix| {
        const include_path = resolveInstallPrefixSubdir(b, prefix, "include");
        const library_path = resolveInstallPrefixSubdir(b, prefix, "lib");
        root_module.addIncludePath(.{ .cwd_relative = include_path });
        root_module.addLibraryPath(.{ .cwd_relative = library_path });
        root_module.addRPath(.{ .cwd_relative = library_path });
        addRelocatableMlxRPath(root_module, target);
        return;
    }

    root_module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/vendor/duckdb-src", .{repo_root}) });
    root_module.addCSourceFiles(.{
        .files = &.{"../../vendor/duckdb-src/duckdb.cpp"},
        .flags = &.{ "-std=c++17", "-Wno-error=date-time" },
        .language = .cpp,
    });
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
) void {
    if (target.result.cpu.arch == .wasm32) return;
    if (duckdb_prefix) |prefix| {
        const library_path = resolveInstallPrefixSubdir(step.step.owner, prefix, "lib");
        step.root_module.addLibraryPath(.{ .cwd_relative = library_path });
        step.root_module.addRPath(.{ .cwd_relative = library_path });
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
    if (target.result.os.tag == .macos) {
        step.root_module.linkFramework("Accelerate", .{});
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
) void {
    if (target.result.cpu.arch == .wasm32) return;
    if (runtime_backend != .host) return;
    step.root_module.linkSystemLibrary("c", .{});
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const repo_root = b.pathFromRoot("../..");
    const public_export = pathExistsAbsolute(b.pathFromRoot("PUBLIC_EXPORT"));
    const has_probe_sources = pathExistsAbsolute(b.pathFromRoot("src/counter_probe.zig")) and
        pathExistsAbsolute(b.pathFromRoot("src/string_perf_probe.zig")) and
        pathExistsAbsolute(b.pathFromRoot("src/realistic_string_perf_probe.zig"));
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
    const install_probes = b.option(bool, "install-probes", "Install internal probe executables.") orelse (!public_cli and has_probe_sources);
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
    const duckdb_prefix_option = b.option([]const u8, "duckdb-prefix", "External DuckDB install prefix. If unset, prefer .deps/duckdb when present, otherwise use the vendored source amalgamation. When set, prefer an install root that contains include/ and lib/.");
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
    addDuckDbImports(b, module, target, repo_root, duckdb_prefix);

    const exe = b.addExecutable(.{
        .name = cli_name,
        .root_module = module,
    });
    exe.each_lib_rpath = false;
    linkMlxDeps(exe, runtime_backend, target, mlx_backend, mlx_linkage, mlxc_mini_bridge);
    linkHostDeps(exe, runtime_backend, target);
    linkDuckDb(exe, target, duckdb_prefix);
    b.installArtifact(exe);
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
        addDuckDbImports(b, bridge_module, target, repo_root, duckdb_prefix);

        const bridge_shared = b.addLibrary(.{
            .linkage = .dynamic,
            .name = "kiwi_bridge",
            .root_module = bridge_module,
        });
        bridge_shared.each_lib_rpath = false;
        linkMlxDeps(bridge_shared, runtime_backend, target, mlx_backend, mlx_linkage, mlxc_mini_bridge);
        linkHostDeps(bridge_shared, runtime_backend, target);
        linkDuckDb(bridge_shared, target, duckdb_prefix);
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

    if (install_probes) {
        const counter_probe_module = b.createModule(.{
            .root_source_file = b.path("src/counter_probe.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip_symbols,
        });
        addBuildOptions(counter_probe_module, build_options);
        addRuntimeImports(b, counter_probe_module, runtime_backend, target, optimize, mlx_c_include, mlx_prefix, mlxc_mini_bridge);
        addDuckDbImports(b, counter_probe_module, target, repo_root, duckdb_prefix);

        const counter_probe = b.addExecutable(.{
            .name = "kiwi-zig-counter-probe",
            .root_module = counter_probe_module,
        });
        counter_probe.each_lib_rpath = false;
        linkMlxDeps(counter_probe, runtime_backend, target, mlx_backend, mlx_linkage, mlxc_mini_bridge);
        linkHostDeps(counter_probe, runtime_backend, target);
        linkDuckDb(counter_probe, target, duckdb_prefix);
        b.installArtifact(counter_probe);

        const counter_probe_run = b.addRunArtifact(counter_probe);
        configureRunLibraryPath(counter_probe_run, runtime_backend, target, mlx_prefix);
        if (b.args) |args| counter_probe_run.addArgs(args);
        const counter_probe_step = b.step("counter-probe", "Run kiwi-zig counter probe");
        counter_probe_step.dependOn(&counter_probe_run.step);

        const string_perf_probe_module = b.createModule(.{
            .root_source_file = b.path("src/string_perf_probe.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip_symbols,
        });
        addBuildOptions(string_perf_probe_module, build_options);
        addRuntimeImports(b, string_perf_probe_module, runtime_backend, target, optimize, mlx_c_include, mlx_prefix, mlxc_mini_bridge);
        addDuckDbImports(b, string_perf_probe_module, target, repo_root, duckdb_prefix);

        const string_perf_probe = b.addExecutable(.{
            .name = "kiwi-zig-string-perf-probe",
            .root_module = string_perf_probe_module,
        });
        string_perf_probe.each_lib_rpath = false;
        linkMlxDeps(string_perf_probe, runtime_backend, target, mlx_backend, mlx_linkage, mlxc_mini_bridge);
        linkHostDeps(string_perf_probe, runtime_backend, target);
        linkDuckDb(string_perf_probe, target, duckdb_prefix);
        b.installArtifact(string_perf_probe);

        const string_perf_probe_run = b.addRunArtifact(string_perf_probe);
        configureRunLibraryPath(string_perf_probe_run, runtime_backend, target, mlx_prefix);
        if (b.args) |args| string_perf_probe_run.addArgs(args);
        const string_perf_probe_step = b.step("string-perf-probe", "Run kiwi-zig string perf probe");
        string_perf_probe_step.dependOn(&string_perf_probe_run.step);

        const realistic_string_perf_probe_module = b.createModule(.{
            .root_source_file = b.path("src/realistic_string_perf_probe.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip_symbols,
        });
        addBuildOptions(realistic_string_perf_probe_module, build_options);
        addRuntimeImports(b, realistic_string_perf_probe_module, runtime_backend, target, optimize, mlx_c_include, mlx_prefix, mlxc_mini_bridge);
        addDuckDbImports(b, realistic_string_perf_probe_module, target, repo_root, duckdb_prefix);

        const realistic_string_perf_probe = b.addExecutable(.{
            .name = "kiwi-zig-realistic-string-perf-probe",
            .root_module = realistic_string_perf_probe_module,
        });
        realistic_string_perf_probe.each_lib_rpath = false;
        linkMlxDeps(realistic_string_perf_probe, runtime_backend, target, mlx_backend, mlx_linkage, mlxc_mini_bridge);
        linkHostDeps(realistic_string_perf_probe, runtime_backend, target);
        linkDuckDb(realistic_string_perf_probe, target, duckdb_prefix);
        b.installArtifact(realistic_string_perf_probe);

        const realistic_string_perf_probe_run = b.addRunArtifact(realistic_string_perf_probe);
        configureRunLibraryPath(realistic_string_perf_probe_run, runtime_backend, target, mlx_prefix);
        if (b.args) |args| realistic_string_perf_probe_run.addArgs(args);
        const realistic_string_perf_probe_step = b.step("realistic-string-perf-probe", "Run kiwi-zig realistic string perf probe");
        realistic_string_perf_probe_step.dependOn(&realistic_string_perf_probe_run.step);
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
        addDuckDbImports(b, test_module, target, repo_root, duckdb_prefix);

        const tests = b.addTest(.{
            .root_module = test_module,
        });
        tests.each_lib_rpath = false;
        linkMlxDeps(tests, runtime_backend, target, mlx_backend, mlx_linkage, mlxc_mini_bridge);
        linkHostDeps(tests, runtime_backend, target);
        linkDuckDb(tests, target, duckdb_prefix);
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
