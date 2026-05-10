const std = @import("std");
const build_options = @import("build_options");
const runtime_device = @import("device.zig");
const profile = @import("profile.zig");
const probe = @import("probe.zig");
const repl_meta = @import("repl_meta.zig");
const repl_input = @import("repl_input.zig");
const runtime = @import("runtime.zig");
const version = @import("version.zig");

const cli_invocation = if (@hasDecl(build_options, "cli_invocation")) build_options.cli_invocation else "kiwi-zig";
pub const enable_bench_cli = if (@hasDecl(build_options, "enable_bench_cli")) build_options.enable_bench_cli else true;
const enable_probe_cli = runtime.enable_probe_instrumentation;
const enable_profile_cli = runtime.enable_sampling_profile;
const enable_debug_cli = enable_bench_cli;

const bench_tools = if (enable_bench_cli) @import("bench_internal.zig") else struct {
    pub const BackendMode = enum {
        auto,
        host,
        mlx_cpu,
        mlx_gpu,
    };

    pub const BenchTiming = struct {};
    pub const BenchSampleProfile = struct {
        use_calibration: bool,
        warmup_samples: usize,
        measured_samples: usize,
    };
    pub const DenseAutodiffAuditRow = struct {};
    pub const default_target_batch_ms = 30.0;
    pub const default_vector_size: usize = 100_000;
    pub const default_matmul_size: usize = 64;

    pub fn runBenchCli(
        _: std.mem.Allocator,
        _: runtime_device.DevicePreference,
        _: BackendMode,
        _: []const u8,
        _: f64,
        _: usize,
        _: usize,
    ) !void {
        return error.InvalidArgument;
    }

    pub fn benchmarkNamedCase(_: std.mem.Allocator, _: []const u8) !?@This().BenchTiming {
        return null;
    }

    pub fn benchmarkNamedCaseWithTarget(
        _: std.mem.Allocator,
        _: runtime_device.DevicePreference,
        _: []const u8,
        _: f64,
        _: usize,
        _: usize,
    ) !?@This().BenchTiming {
        return null;
    }

    pub fn denseAutodiffAudit(_: std.mem.Allocator) ![]@This().DenseAutodiffAuditRow {
        return error.InvalidArgument;
    }

    pub fn sampleProfileForCase(_: []const u8) @This().BenchSampleProfile {
        return .{
            .use_calibration = true,
            .warmup_samples = 1,
            .measured_samples = 7,
        };
    }

    pub fn isDefaultBenchSuiteCase(_: []const u8) bool {
        return true;
    }

    pub fn auditDenseAutodiffCli(_: std.mem.Allocator) !void {
        return error.InvalidArgument;
    }

    pub fn auditFindLookupCli(_: std.mem.Allocator, _: f64, _: usize) !void {
        return error.InvalidArgument;
    }

    pub fn resolveVectorSize(_: []const u8, requested_size: usize) usize {
        return requested_size;
    }

    pub fn isRealisticStringBenchCase(_: []const u8) bool {
        return false;
    }
};

pub const BenchTiming = bench_tools.BenchTiming;
pub const BenchSampleProfile = bench_tools.BenchSampleProfile;
pub const DenseAutodiffAuditRow = bench_tools.DenseAutodiffAuditRow;

const TimingRequest = struct {
    loops: usize,
    expr: []const u8,
};

const ParsedLine = union(enum) {
    skip,
    eval: []const u8,
    timing: TimingRequest,
    meta: repl_meta.Command,
};

pub const ExecInput = union(enum) {
    expr: []const u8,
    path: []const u8,
    stdin,
};

pub const ExecRequest = struct {
    input: ExecInput,
    interactive: bool,
    argv: []const []const u8 = &.{},
};

pub const BenchRequest = struct {
    case_name: []const u8,
};

pub const ProbeRequest = struct {
    input: ExecInput,
    setup_sources: []const []const u8 = &.{},
    setup_files: []const []const u8 = &.{},
    json_stdout: bool = false,
    json_out: ?[]const u8 = null,

    pub fn deinit(self: *const ProbeRequest, allocator: std.mem.Allocator) void {
        if (self.setup_sources.len != 0) allocator.free(self.setup_sources);
        if (self.setup_files.len != 0) allocator.free(self.setup_files);
    }
};

pub const ProfileRequest = struct {
    input: ExecInput,
    sample_hz: usize = profile.default_sample_hz,
    json_stdout: bool = false,
    json_out: ?[]const u8 = null,
};

pub const DebugRequest = enum {
    audit_dense_autodiff,
    find_lookup_stages,
    layout,
};

pub const CliRequest = union(enum) {
    repl,
    version,
    exec: ExecRequest,
    bench: BenchRequest,
    probe: ProbeRequest,
    profile: ProfileRequest,
    debug: DebugRequest,
};

pub const CliOptions = struct {
    request: CliRequest,
    device: runtime_device.DevicePreference = .cpu,
    backend_mode: BenchBackendMode = .auto,
    target_batch_ms: f64 = bench_tools.default_target_batch_ms,
    vector_size: usize = bench_tools.default_vector_size,
    matmul_size: usize = bench_tools.default_matmul_size,

    pub fn deinit(self: *const CliOptions, allocator: std.mem.Allocator) void {
        switch (self.request) {
            .probe => |request| request.deinit(allocator),
            else => {},
        }
    }
};

pub const BenchBackendMode = enum {
    auto,
    host,
    mlx_cpu,
    mlx_gpu,

    fn parse(text: []const u8) ?BenchBackendMode {
        if (std.mem.eql(u8, text, "auto")) return .auto;
        if (std.mem.eql(u8, text, "host")) return .host;
        if (std.mem.eql(u8, text, "mlx_cpu")) return .mlx_cpu;
        if (std.mem.eql(u8, text, "mlx_gpu")) return .mlx_gpu;
        return null;
    }

    pub fn label(self: BenchBackendMode) []const u8 {
        return switch (self) {
            .auto => "auto",
            .host => "host",
            .mlx_cpu => "mlx_cpu",
            .mlx_gpu => "mlx_gpu",
        };
    }
};

fn toBenchBackendMode(mode: BenchBackendMode) bench_tools.BackendMode {
    return switch (mode) {
        .auto => .auto,
        .host => .host,
        .mlx_cpu => .mlx_cpu,
        .mlx_gpu => .mlx_gpu,
    };
}

pub fn main() void {
    run() catch |err| switch (err) {
        error.InvalidArgument, error.ScriptFailed => std.process.exit(1),
        else => std.debug.panic("{s}", .{@errorName(err)}),
    };
}

fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const parsed = try parseCliArgs(allocator, args[1..]);
    defer parsed.deinit(allocator);
    const device = effectiveDevicePreference(parsed.device, parsed.backend_mode);

    switch (parsed.request) {
        .repl => try repl(allocator, device, parsed.backend_mode),
        .version => try std.fs.File.stdout().deprecatedWriter().print("{s}\n", .{version.string}),
        .exec => |request| try executeRequest(allocator, device, parsed.backend_mode, request),
        .bench => |request| {
            if (comptime enable_bench_cli) {
                try bench_tools.runBenchCli(allocator, device, toBenchBackendMode(parsed.backend_mode), request.case_name, parsed.target_batch_ms, parsed.vector_size, parsed.matmul_size);
            } else {
                return invalidArgument();
            }
        },
        .probe => |request| try executeProbeRequest(allocator, device, parsed.backend_mode, request),
        .profile => |request| try executeProfileRequest(allocator, device, parsed.backend_mode, request),
        .debug => |request| switch (request) {
            .audit_dense_autodiff => {
                if (!enable_debug_cli) return invalidArgument();
                try bench_tools.auditDenseAutodiffCli(allocator);
            },
            .find_lookup_stages => {
                if (!enable_debug_cli) return invalidArgument();
                try bench_tools.auditFindLookupCli(allocator, parsed.target_batch_ms, parsed.vector_size);
            },
            .layout => {
                if (!enable_debug_cli) return invalidArgument();
                try printLayoutDebug();
            },
        },
    }
}

fn printLayoutDebug() !void {
    const facts = runtime.debugRuntimeLayoutFacts();
    const writer = std.fs.File.stdout().deprecatedWriter();
    try writer.print(
        "value size={d} align={d}\n" ++
            "heap_header size={d} align={d}\n" ++
            "host_text size={d} align={d}\n" ++
            "host_string_view size={d} align={d}\n" ++
            "host_string_list size={d} align={d}\n" ++
            "host_dense_array size={d} align={d}\n" ++
            "host_boxed_array size={d} align={d}\n" ++
            "backend_array size={d} align={d}\n" ++
            "numeric_array size={d} align={d}\n",
        .{
            facts.value_size,
            facts.value_align,
            facts.heap_header_size,
            facts.heap_header_align,
            facts.host_text_size,
            facts.host_text_align,
            facts.host_string_view_size,
            facts.host_string_view_align,
            facts.host_string_list_size,
            facts.host_string_list_align,
            facts.host_dense_array_size,
            facts.host_dense_array_align,
            facts.host_boxed_array_size,
            facts.host_boxed_array_align,
            facts.backend_array_size,
            facts.backend_array_align,
            facts.numeric_array_size,
            facts.numeric_array_align,
        },
    );
}

pub fn parseCliArgs(allocator: std.mem.Allocator, args: []const []const u8) !CliOptions {
    var options = CliOptions{ .request = .repl };
    var mode: enum { auto, exec, bench, probe, profile, debug } = .auto;
    var exec_input: ?ExecInput = null;
    var exec_argv: []const []const u8 = &.{};
    var interactive = false;
    var bench_case: ?[]const u8 = null;
    var probe_input: ?ExecInput = null;
    var probe_setup_sources = std.ArrayList([]const u8).empty;
    defer probe_setup_sources.deinit(allocator);
    var probe_setup_files = std.ArrayList([]const u8).empty;
    defer probe_setup_files.deinit(allocator);
    var probe_json_stdout = false;
    var probe_json_out: ?[]const u8 = null;
    var profile_input: ?ExecInput = null;
    var profile_sample_hz: usize = profile.default_sample_hz;
    var profile_json_stdout = false;
    var profile_json_out: ?[]const u8 = null;
    var debug_request: ?DebugRequest = null;

    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];

        if (mode == .exec and exec_input != null) {
            exec_argv = args[idx..];
            break;
        }

        if (std.mem.eql(u8, arg, "--version")) {
            if (mode != .auto or exec_input != null) return invalidArgument();
            options.request = .version;
            return options;
        }
        if (std.mem.eql(u8, arg, "--device")) {
            idx += 1;
            if (idx >= args.len) return invalidArgument();
            options.device = runtime_device.DevicePreference.parse(args[idx]) orelse return invalidArgument();
            continue;
        }
        if (std.mem.eql(u8, arg, "--backend")) {
            idx += 1;
            if (idx >= args.len) return invalidArgument();
            options.backend_mode = BenchBackendMode.parse(args[idx]) orelse return invalidArgument();
            continue;
        }
        if (std.mem.eql(u8, arg, "--target-batch-ms")) {
            if (!enable_bench_cli) return invalidArgument();
            idx += 1;
            if (idx >= args.len) return invalidArgument();
            options.target_batch_ms = try std.fmt.parseFloat(f64, args[idx]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--size")) {
            if (!enable_bench_cli) return invalidArgument();
            idx += 1;
            if (idx >= args.len) return invalidArgument();
            options.vector_size = try std.fmt.parseUnsigned(usize, args[idx], 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "--matmul-size")) {
            if (!enable_bench_cli) return invalidArgument();
            idx += 1;
            if (idx >= args.len) return invalidArgument();
            options.matmul_size = try std.fmt.parseUnsigned(usize, args[idx], 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "-i")) {
            if (mode == .bench or mode == .probe or mode == .profile or mode == .debug) return invalidArgument();
            interactive = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--json")) {
            switch (mode) {
                .probe => probe_json_stdout = true,
                .profile => profile_json_stdout = true,
                else => return invalidArgument(),
            }
            continue;
        }
        if (std.mem.eql(u8, arg, "--json-out")) {
            idx += 1;
            if (idx >= args.len) return invalidArgument();
            switch (mode) {
                .probe => probe_json_out = args[idx],
                .profile => profile_json_out = args[idx],
                else => return invalidArgument(),
            }
            continue;
        }
        if (std.mem.eql(u8, arg, "--setup")) {
            if (mode != .probe) return invalidArgument();
            idx += 1;
            if (idx >= args.len) return invalidArgument();
            try probe_setup_sources.append(allocator, args[idx]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--setup-file")) {
            if (mode != .probe) return invalidArgument();
            idx += 1;
            if (idx >= args.len) return invalidArgument();
            try probe_setup_files.append(allocator, args[idx]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--hz")) {
            if (mode != .profile) return invalidArgument();
            idx += 1;
            if (idx >= args.len) return invalidArgument();
            profile_sample_hz = try std.fmt.parseUnsigned(usize, args[idx], 10);
            if (profile_sample_hz == 0) return invalidArgument();
            continue;
        }
        if (std.mem.eql(u8, arg, "-e")) {
            if (mode == .bench or mode == .debug or exec_input != null) return invalidArgument();
            idx += 1;
            if (idx >= args.len) return invalidArgument();
            switch (mode) {
                .auto, .exec => {
                    if (exec_input != null) return invalidArgument();
                    exec_input = .{ .expr = args[idx] };
                    if (mode == .auto) mode = .exec;
                },
                .probe => {
                    if (probe_input != null) return invalidArgument();
                    probe_input = .{ .expr = args[idx] };
                },
                .profile => {
                    if (profile_input != null) return invalidArgument();
                    profile_input = .{ .expr = args[idx] };
                },
                .bench, .debug => return invalidArgument(),
            }
            continue;
        }

        if (mode == .auto and exec_input == null) {
            if (std.mem.eql(u8, arg, "bench")) {
                if (!enable_bench_cli) return invalidArgument();
                mode = .bench;
                continue;
            }
            if (std.mem.eql(u8, arg, "probe")) {
                if (!enable_probe_cli) return invalidArgument();
                mode = .probe;
                continue;
            }
            if (std.mem.eql(u8, arg, "profile")) {
                if (!enable_profile_cli) return invalidArgument();
                mode = .profile;
                continue;
            }
            if (std.mem.eql(u8, arg, "debug")) {
                if (!enable_debug_cli) return invalidArgument();
                mode = .debug;
                continue;
            }
        }

        switch (mode) {
            .auto => {
                exec_input = if (std.mem.eql(u8, arg, "-")) .stdin else .{ .path = arg };
                mode = .exec;
            },
            .exec => {
                if (exec_input != null) return invalidArgument();
                exec_input = if (std.mem.eql(u8, arg, "-")) .stdin else .{ .path = arg };
            },
            .bench => {
                if (bench_case != null) return invalidArgument();
                bench_case = arg;
            },
            .probe => {
                if (probe_input != null) return invalidArgument();
                probe_input = if (std.mem.eql(u8, arg, "-")) .stdin else .{ .path = arg };
            },
            .profile => {
                if (profile_input != null) return invalidArgument();
                profile_input = if (std.mem.eql(u8, arg, "-")) .stdin else .{ .path = arg };
            },
            .debug => {
                if (debug_request != null) return invalidArgument();
                if (std.mem.eql(u8, arg, "audit-dense-autodiff")) {
                    debug_request = .audit_dense_autodiff;
                } else if (std.mem.eql(u8, arg, "find-lookup-stages")) {
                    debug_request = .find_lookup_stages;
                } else if (std.mem.eql(u8, arg, "layout")) {
                    debug_request = .layout;
                } else {
                    return invalidArgument();
                }
            },
        }
    }

    options.request = switch (mode) {
        .auto => if (exec_input) |input|
            .{ .exec = .{ .input = input, .interactive = interactive, .argv = exec_argv } }
        else
            .repl,
        .exec => .{ .exec = .{ .input = exec_input orelse return invalidArgument(), .interactive = interactive, .argv = exec_argv } },
        .bench => .{ .bench = .{ .case_name = bench_case orelse return invalidArgument() } },
        .probe => .{ .probe = .{
            .input = probe_input orelse return invalidArgument(),
            .setup_sources = try probe_setup_sources.toOwnedSlice(allocator),
            .setup_files = try probe_setup_files.toOwnedSlice(allocator),
            .json_stdout = probe_json_stdout,
            .json_out = probe_json_out,
        } },
        .profile => .{ .profile = .{
            .input = profile_input orelse return invalidArgument(),
            .sample_hz = profile_sample_hz,
            .json_stdout = profile_json_stdout,
            .json_out = profile_json_out,
        } },
        .debug => .{ .debug = debug_request orelse return invalidArgument() },
    };
    return options;
}

fn usage() !void {
    const stderr = std.fs.File.stderr().deprecatedWriter();
    try stderr.print(
        "{s} {s}\n\nusage:\n  {s}\n  {s} --version\n  {s} [--device cpu|gpu] [--backend auto|host|mlx_cpu|mlx_gpu] [-i] [-e source | file.k | -] [args...]\n",
        .{
            cli_invocation,
            version.string,
            cli_invocation,
            cli_invocation,
            cli_invocation,
        },
    );
    if (comptime enable_bench_cli) {
        try stderr.print(
            "  {s} bench [--device cpu|gpu] [--backend auto|host|mlx_cpu|mlx_gpu] [--target-batch-ms N] [--size N] [--matmul-size N] case  (case: name, all, all-full, or stress)\n",
            .{cli_invocation},
        );
    }
    if (comptime enable_probe_cli) {
        try stderr.print(
            "  {s} probe [--device cpu|gpu] [--backend auto|host|mlx_cpu|mlx_gpu] [--setup source] [--setup-file path.k] [--json] [--json-out path] [-e source | file.k | -]\n",
            .{cli_invocation},
        );
    }
    if (comptime enable_profile_cli) {
        try stderr.print(
            "  {s} profile [--device cpu|gpu] [--backend auto|host|mlx_cpu|mlx_gpu] [--hz N] [--json] [--json-out path] [-e source | file.k | -]\n",
            .{cli_invocation},
        );
    }
    if (comptime enable_debug_cli) {
        try stderr.print(
            "  {s} debug audit-dense-autodiff\n  {s} debug [--target-batch-ms N] [--size N] find-lookup-stages\n  {s} debug layout\n",
            .{ cli_invocation, cli_invocation, cli_invocation },
        );
    }
    return error.InvalidArgument;
}

fn invalidArgument() error{InvalidArgument} {
    usage() catch {};
    return error.InvalidArgument;
}

pub fn denseAutodiffAudit(allocator: std.mem.Allocator) ![]DenseAutodiffAuditRow {
    return try bench_tools.denseAutodiffAudit(allocator);
}

fn effectiveDevicePreference(device: runtime_device.DevicePreference, backend_mode: BenchBackendMode) runtime_device.DevicePreference {
    return switch (backend_mode) {
        .mlx_cpu => .cpu,
        .mlx_gpu => .gpu,
        else => device,
    };
}

fn configureDenseBackendMode(session: *runtime.Session, backend_mode: BenchBackendMode) void {
    session.setDenseBackendOverride(switch (backend_mode) {
        .auto => .auto,
        .host => .host,
        .mlx_cpu, .mlx_gpu => .mlx,
    });
}

fn mlxBackendLabel(device: runtime_device.DevicePreference) []const u8 {
    return switch (device) {
        .cpu => "mlx_cpu",
        .gpu => "mlx_gpu",
        .auto => "mlx_auto",
    };
}

fn backendLabelFromSessionPath(path: []const u8, device: runtime_device.DevicePreference) []const u8 {
    return if (std.mem.eql(u8, path, "mlx")) mlxBackendLabel(device) else path;
}

fn actualBackendLabel(session: *runtime.Session, device: runtime_device.DevicePreference, fallback_path: []const u8) []const u8 {
    if (session.lastDenseExecBackend()) |backend| {
        return if (std.mem.eql(u8, backend, "mlx")) mlxBackendLabel(device) else backend;
    }
    if (session.lastDenseAutodiffExecPath()) |backend| {
        return if (std.mem.eql(u8, backend, "mlx")) mlxBackendLabel(device) else backend;
    }
    return backendLabelFromSessionPath(fallback_path, device);
}

fn plannerBackendLabel(session: *runtime.Session, device: runtime_device.DevicePreference) []const u8 {
    if (session.lastDensePlanBackend()) |backend| {
        return if (std.mem.eql(u8, backend, "mlx")) mlxBackendLabel(device) else backend;
    }
    return "none";
}

fn plannerRegionLabel(session: *runtime.Session) []const u8 {
    return session.lastDensePlanRegion() orelse "none";
}

fn plannerReasonLabel(session: *runtime.Session) []const u8 {
    return session.lastDensePlanReason() orelse "none";
}

fn denseRegionLabel(kind: runtime.DenseRegionKind) []const u8 {
    return switch (kind) {
        .numeric_dyad => "numeric_dyad",
        .compare_mask => "compare_mask",
        .reduce => "reduce",
        .scan => "scan",
        .matmul => "matmul",
        .transpose => "transpose",
        .dense_autodiff => "dense_autodiff",
    };
}

fn denseBackendLabel(backend: runtime.DenseExecBackend, device: runtime_device.DevicePreference) []const u8 {
    return switch (backend) {
        .host => "host",
        .mlx => mlxBackendLabel(device),
    };
}

fn denseCountSummary(session: *runtime.Session, device: runtime_device.DevicePreference, comptime use_exec_counts: bool, buffer: []u8) []const u8 {
    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();
    var first = true;
    const kinds = [_]runtime.DenseRegionKind{
        .numeric_dyad,
        .compare_mask,
        .reduce,
        .scan,
        .matmul,
        .transpose,
        .dense_autodiff,
    };
    const backends = [_]runtime.DenseExecBackend{ .host, .mlx };
    for (kinds) |kind| {
        for (backends) |backend| {
            const count = if (use_exec_counts)
                session.debugDenseExecCount(kind, backend)
            else
                session.debugDensePlanCount(kind, backend);
            if (count == 0) continue;
            if (!first) writer.writeByte(',') catch return "overflow";
            writer.print("{s}:{s}={d}", .{
                denseRegionLabel(kind),
                denseBackendLabel(backend, device),
                count,
            }) catch return "overflow";
            first = false;
        }
    }
    return if (first) "none" else stream.getWritten();
}

fn emitBackendReport(session: *runtime.Session, device: runtime_device.DevicePreference, backend_mode: BenchBackendMode, writer: anytype) !void {
    if (comptime !runtime.enable_probe_instrumentation) {
        try writer.print(
            "#backend-report backend_request={s} instrumentation=stripped\n",
            .{backend_mode.label()},
        );
        return;
    }
    const path = if (session.lastDenseAutodiffExecPath() != null)
        session.lastDenseAutodiffExecPath().?
    else if (session.lastDenseExecBackend() != null)
        session.lastDenseExecBackend().?
    else if (session.debugBackendRealizationCount() != 0 and session.debugHostReadbackCount() == 0)
        "mlx"
    else
        "host";
    var planner_summary_buf: [256]u8 = undefined;
    var exec_summary_buf: [256]u8 = undefined;
    try writer.print(
        "#backend-report backend_request={s} actual_backend={s} planner_region={s} planner_backend={s} planner_reason={s} planner_overridden={s} planner_summary={s} exec_summary={s}\n",
        .{
            backend_mode.label(),
            actualBackendLabel(session, device, path),
            plannerRegionLabel(session),
            plannerBackendLabel(session, device),
            plannerReasonLabel(session),
            if (session.lastDensePlanOverridden()) "1" else "0",
            denseCountSummary(session, device, false, planner_summary_buf[0..]),
            denseCountSummary(session, device, true, exec_summary_buf[0..]),
        },
    );
}

fn repl(allocator: std.mem.Allocator, device: runtime_device.DevicePreference, backend_mode: BenchBackendMode) !void {
    var session = try runtime.Session.initWithDevice(allocator, device);
    defer session.deinit();
    configureDenseBackendMode(&session, backend_mode);
    try replSession(&session, allocator);
}

fn replSession(session: *runtime.Session, allocator: std.mem.Allocator) !void {
    var input = try repl_input.ReplInput.init(allocator);
    defer input.deinit();

    const stdout = std.fs.File.stdout().deprecatedWriter();
    const stderr = std.fs.File.stderr().deprecatedWriter();

    while (true) {
        const line = (try input.readLine(" ")) orelse return;
        defer allocator.free(line);

        if (sanitizeLine(line) != null) try input.rememberLine(line);

        const parsed = parseLine(line) catch |err| {
            try writeRuntimeError(null, stderr, err);
            continue;
        };
        switch (parsed) {
            .skip => continue,
            .eval => |trimmed| {
                const value = session.evalSource(trimmed) catch |err| {
                    try writeRuntimeError(session, stderr, err);
                    continue;
                };
                if (!shouldEchoEvalLine(trimmed)) continue;
                const text = try session.renderValue(value);
                defer allocator.free(text);
                try stdout.print("{s}\n", .{text});
            },
            .meta => |command| switch (command) {
                .exit => return,
                .help => |text| try stdout.print("{s}\n", .{text}),
            },
            .timing => |request| {
                const text = evalTiming(session, allocator, request) catch |err| {
                    try writeRuntimeError(session, stderr, err);
                    continue;
                };
                defer allocator.free(text);
                try stdout.print("{s}\n", .{text});
            },
        }
    }
}

fn executeRequest(allocator: std.mem.Allocator, device: runtime_device.DevicePreference, backend_mode: BenchBackendMode, request: ExecRequest) !void {
    var session = try runtime.Session.initWithDevice(allocator, device);
    defer session.deinit();
    configureDenseBackendMode(&session, backend_mode);
    try session.setGlobalHostStringList("x", request.argv);

    const exec_result = switch (request.input) {
        .expr => |source| execBufferedSource(&session, allocator, "<expr>", source, device, backend_mode),
        .path => |path| execPathSource(&session, allocator, path, device, backend_mode),
        .stdin => execStdinSource(&session, allocator, device, backend_mode),
    };
    exec_result catch |err| {
        if (!request.interactive or err != error.ScriptFailed) return err;
    };

    if (request.interactive) try replSession(&session, allocator);
}

fn executeProbeRequest(allocator: std.mem.Allocator, device: runtime_device.DevicePreference, backend_mode: BenchBackendMode, request: ProbeRequest) !void {
    if (!runtime.enable_probe_instrumentation) {
        try std.fs.File.stderr().deprecatedWriter().writeAll("probe is unavailable in stripped builds\n");
        return error.InvalidArgument;
    }
    const result = try collectProbeRequestResult(allocator, device, backend_mode, request);

    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (request.json_stdout or request.json_out != null) {
        const out = try probe.allocJsonString(allocator, result);
        defer allocator.free(out);

        if (request.json_stdout) {
            try stdout.print("{s}\n", .{out});
        } else {
            try probe.writeProbeResultText(stdout, result);
        }

        if (request.json_out) |path| {
            try std.fs.cwd().writeFile(.{ .sub_path = path, .data = out });
        }
        return;
    }

    try probe.writeProbeResultText(stdout, result);
}

fn executeProfileRequest(allocator: std.mem.Allocator, device: runtime_device.DevicePreference, backend_mode: BenchBackendMode, request: ProfileRequest) !void {
    if (!runtime.enable_sampling_profile) {
        try std.fs.File.stderr().deprecatedWriter().writeAll("profile is unavailable in stripped builds\n");
        return error.InvalidArgument;
    }
    const result = try collectProfileRequestResult(allocator, device, backend_mode, request);
    defer result.deinit(allocator);

    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (request.json_stdout or request.json_out != null) {
        const out = try probe.allocJsonString(allocator, result);
        defer allocator.free(out);

        if (request.json_stdout) {
            try stdout.print("{s}\n", .{out});
        } else {
            try profile.writeProfileResultText(stdout, result);
        }

        if (request.json_out) |path| {
            try std.fs.cwd().writeFile(.{ .sub_path = path, .data = out });
        }
        return;
    }

    try profile.writeProfileResultText(stdout, result);
}

pub fn collectProbeRequestResult(allocator: std.mem.Allocator, device: runtime_device.DevicePreference, backend_mode: BenchBackendMode, request: ProbeRequest) !probe.ProbeResult {
    var session = try runtime.Session.initWithDevice(allocator, device);
    defer session.deinit();
    configureDenseBackendMode(&session, backend_mode);

    const name = execInputLabel(request.input);

    for (request.setup_sources) |source| {
        execSourceQuiet(&session, "<probe-setup>", source) catch |err| {
            return probe.collectProbeResult(&session, name, @errorName(err));
        };
    }

    for (request.setup_files) |path| {
        const source = try readSourceFromFile(allocator, path);
        defer allocator.free(source);

        execSourceQuiet(&session, path, source) catch |err| {
            return probe.collectProbeResult(&session, name, @errorName(err));
        };
    }

    session.resetDebugStructuralExecutionCounters();
    session.setDebugProbeActive(true);
    defer session.setDebugProbeActive(false);
    switch (request.input) {
        .expr => |source| {
            execSourceQuiet(&session, "<expr>", source) catch |err| {
                return probe.collectProbeResult(&session, name, @errorName(err));
            };
        },
        .path => |path| {
            const source = try readSourceFromFile(allocator, path);
            defer allocator.free(source);

            execSourceQuiet(&session, path, source) catch |err| {
                return probe.collectProbeResult(&session, name, @errorName(err));
            };
        },
        .stdin => {
            const source = try readSourceFromStdin(allocator);
            defer allocator.free(source);

            execSourceQuiet(&session, "-", source) catch |err| {
                return probe.collectProbeResult(&session, name, @errorName(err));
            };
        },
    }

    return probe.collectProbeResult(&session, name, null);
}

pub fn collectProfileRequestResult(allocator: std.mem.Allocator, device: runtime_device.DevicePreference, backend_mode: BenchBackendMode, request: ProfileRequest) !profile.ProfileResult {
    var session = try runtime.Session.initWithDevice(allocator, device);
    defer session.deinit();
    configureDenseBackendMode(&session, backend_mode);

    var sampler = profile.Collector.init(allocator, &session, request.sample_hz);
    try sampler.start();
    defer sampler.cancel();

    const started_ns = monotonicNanos();
    var err_name: ?[]const u8 = null;
    const null_writer = std.io.null_writer;

    switch (request.input) {
        .expr => |source| {
            execSource(&session, "<expr>", source, null_writer, null_writer) catch |err| {
                err_name = @errorName(err);
            };
        },
        .path => |path| {
            const source = try readSourceFromFile(allocator, path);
            defer allocator.free(source);

            execSource(&session, path, source, null_writer, null_writer) catch |err| {
                err_name = @errorName(err);
            };
        },
        .stdin => {
            const source = try readSourceFromStdin(allocator);
            defer allocator.free(source);

            execSource(&session, "-", source, null_writer, null_writer) catch |err| {
                err_name = @errorName(err);
            };
        },
    }

    return try sampler.finish(execInputLabel(request.input), err_name, monotonicNanos() - started_ns);
}

fn execInputLabel(input: ExecInput) []const u8 {
    return switch (input) {
        .expr => "<expr>",
        .path => |path| path,
        .stdin => "-",
    };
}

fn readSourceFromFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, max_source_bytes);
}

fn readSourceFromStdin(allocator: std.mem.Allocator) ![]u8 {
    return try std.fs.File.stdin().readToEndAlloc(allocator, max_source_bytes);
}

fn execPathSource(session: *runtime.Session, allocator: std.mem.Allocator, path: []const u8, device: runtime_device.DevicePreference, backend_mode: BenchBackendMode) !void {
    const source = try readSourceFromFile(allocator, path);
    defer allocator.free(source);

    try execBufferedSource(session, allocator, path, source, device, backend_mode);
}

fn execStdinSource(session: *runtime.Session, allocator: std.mem.Allocator, device: runtime_device.DevicePreference, backend_mode: BenchBackendMode) !void {
    const source = try readSourceFromStdin(allocator);
    defer allocator.free(source);
    try execBufferedSource(session, allocator, "-", source, device, backend_mode);
}

fn execBufferedSource(session: *runtime.Session, allocator: std.mem.Allocator, path: []const u8, source: []const u8, device: runtime_device.DevicePreference, backend_mode: BenchBackendMode) !void {
    try execSource(session, path, source, std.fs.File.stdout().deprecatedWriter(), std.fs.File.stderr().deprecatedWriter());
    if (std.process.getEnvVarOwned(allocator, "KIWI_BENCH_BACKEND_REPORT")) |flag| {
        defer allocator.free(flag);
        if (flag.len != 0 and !std.mem.eql(u8, flag, "0")) {
            try emitBackendReport(session, device, backend_mode, std.fs.File.stderr().deprecatedWriter());
        }
    } else |_| {}
}

fn writeRuntimeError(session: ?*runtime.Session, writer: anytype, err: anyerror) !void {
    try writer.print("!{s}\n", .{runtime.errorCode(err)});
    const active = session orelse return;
    const detail = active.lastErrorText() orelse return;
    defer active.clearLastErrorText();
    try writer.print("{s}\n", .{detail});
}

fn writeRuntimeErrorAt(session: ?*runtime.Session, writer: anytype, path: []const u8, line_no: usize, err: anyerror) !void {
    try writer.print("{s}:{d}: !{s}\n", .{ path, line_no, runtime.errorCode(err) });
    const active = session orelse return;
    const detail = active.lastErrorText() orelse return;
    defer active.clearLastErrorText();
    try writer.print("{s}:{d}: {s}\n", .{ path, line_no, detail });
}

pub fn execSource(session: *runtime.Session, path: []const u8, source: []const u8, out_writer: anytype, err_writer: anytype) !void {
    if (sanitizeScript(session.allocator, source)) |cleaned| {
        defer session.allocator.free(cleaned);

        const value = session.evalSource(cleaned) catch {
            // Fall back to line-by-line execution so script errors still get a useful line number.
            return execSourceLineByLine(session, path, source, out_writer, err_writer);
        };
        const text = try session.renderValue(value);
        defer session.allocator.free(text);
        try out_writer.print("{s}\n", .{text});
        return;
    }

    return execSourceLineByLine(session, path, source, out_writer, err_writer);
}

fn execSourceQuiet(session: *runtime.Session, path: []const u8, source: []const u8) !void {
    if (sanitizeScript(session.allocator, source)) |cleaned| {
        defer session.allocator.free(cleaned);

        const value = session.evalSource(cleaned) catch {
            return execSourceLineByLineQuiet(session, path, source);
        };
        try session.forceValue(value);
        return;
    }

    return execSourceLineByLineQuiet(session, path, source);
}

fn execSourceLineByLine(session: *runtime.Session, path: []const u8, source: []const u8, out_writer: anytype, err_writer: anytype) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var line_no: usize = 0;
    var statement_start_line: usize = 0;
    var pending = std.ArrayList(u8).empty;
    defer pending.deinit(session.allocator);
    var depth = ScriptDepth{};

    while (lines.next()) |raw| {
        line_no += 1;
        const line = sanitizeLine(raw) orelse continue;
        if (pending.items.len == 0) {
            statement_start_line = line_no;
            depth = .{};
        } else {
            try pending.append(session.allocator, '\n');
        }
        try pending.appendSlice(session.allocator, line);
        if (!updateScriptDepth(line, &depth)) {
            try writeRuntimeErrorAt(null, err_writer, path, line_no, error.Parse);
            return error.ScriptFailed;
        }
        if (!depth.isZero()) continue;

        const statement_text = pending.items;
        const parsed = parseLine(statement_text) catch |err| {
            try writeRuntimeErrorAt(null, err_writer, path, statement_start_line, err);
            return error.ScriptFailed;
        };
        switch (parsed) {
            .skip => {},
            .eval => |clean| {
                const value = session.evalSource(clean) catch |err| {
                    try writeRuntimeErrorAt(session, err_writer, path, statement_start_line, err);
                    return error.ScriptFailed;
                };
                if (shouldEchoEvalLine(clean)) {
                    const text = try session.renderValue(value);
                    defer session.allocator.free(text);
                    try out_writer.print("{s}\n", .{text});
                }
            },
            .meta => |command| switch (command) {
                .exit => return,
                .help => |text| try out_writer.print("{s}\n", .{text}),
            },
            .timing => |request| {
                const text = evalTiming(session, session.allocator, request) catch |err| {
                    try writeRuntimeErrorAt(session, err_writer, path, statement_start_line, err);
                    return error.ScriptFailed;
                };
                defer session.allocator.free(text);
                try out_writer.print("{s}\n", .{text});
            },
        }
        pending.clearRetainingCapacity();
    }

    if (pending.items.len != 0) {
        try writeRuntimeErrorAt(null, err_writer, path, statement_start_line, error.Parse);
        return error.ScriptFailed;
    }
}

fn execSourceLineByLineQuiet(session: *runtime.Session, path: []const u8, source: []const u8) !void {
    _ = path;
    var lines = std.mem.splitScalar(u8, source, '\n');
    var pending = std.ArrayList(u8).empty;
    defer pending.deinit(session.allocator);
    var depth = ScriptDepth{};

    while (lines.next()) |raw| {
        const line = sanitizeLine(raw) orelse continue;
        if (pending.items.len == 0) {
            depth = .{};
        } else {
            try pending.append(session.allocator, '\n');
        }
        try pending.appendSlice(session.allocator, line);
        if (!updateScriptDepth(line, &depth)) return error.Parse;
        if (!depth.isZero()) continue;

        const parsed = try parseLine(pending.items);
        switch (parsed) {
            .skip => {},
            .eval => |clean| {
                const value = try session.evalSource(clean);
                if (shouldEchoEvalLine(clean)) try session.forceValue(value);
            },
            .meta => |command| switch (command) {
                .exit => return,
                .help => {},
            },
            .timing => |request| {
                _ = try runTimingRequest(session, request);
            },
        }
        pending.clearRetainingCapacity();
    }

    if (pending.items.len != 0) return error.Parse;
}

fn sanitizeScript(allocator: std.mem.Allocator, source: []const u8) ?[]u8 {
    var lines = std.mem.tokenizeAny(u8, source, "\n");
    var cleaned = std.ArrayList(u8).empty;
    defer cleaned.deinit(allocator);
    var saw_eval = false;
    var statement_count: usize = 0;
    var depth = ScriptDepth{};

    while (lines.next()) |raw| {
        const line = sanitizeLine(raw) orelse continue;
        if (std.mem.startsWith(u8, line, "\\t")) return null;
        if (saw_eval) cleaned.append(allocator, '\n') catch return null;
        cleaned.appendSlice(allocator, line) catch return null;
        saw_eval = true;
        if (!updateScriptDepth(line, &depth)) return null;
        if (depth.isZero()) statement_count += 1;
    }

    if (!saw_eval or statement_count != 1 or !depth.isZero()) return null;
    return cleaned.toOwnedSlice(allocator) catch null;
}

const ScriptDepth = struct {
    paren: usize = 0,
    bracket: usize = 0,
    brace: usize = 0,

    fn isZero(self: ScriptDepth) bool {
        return self.paren == 0 and self.bracket == 0 and self.brace == 0;
    }
};

fn updateScriptDepth(line: []const u8, depth: *ScriptDepth) bool {
    var idx: usize = 0;
    while (idx < line.len) : (idx += 1) {
        switch (line[idx]) {
            '"' => {
                idx += 1;
                while (idx < line.len and line[idx] != '"') : (idx += 1) {}
                if (idx >= line.len) return false;
            },
            '(' => depth.paren += 1,
            ')' => {
                if (depth.paren == 0) return false;
                depth.paren -= 1;
            },
            '[' => depth.bracket += 1,
            ']' => {
                if (depth.bracket == 0) return false;
                depth.bracket -= 1;
            },
            '{' => depth.brace += 1,
            '}' => {
                if (depth.brace == 0) return false;
                depth.brace -= 1;
            },
            else => {},
        }
    }
    return true;
}

fn shouldEchoEvalLine(line: []const u8) bool {
    return !isTopLevelAssignment(line);
}

fn isTopLevelAssignment(line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len == 0 or !isIdentStart(trimmed[0])) return false;

    var idx: usize = 0;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var brace_depth: usize = 0;
    while (idx < trimmed.len) : (idx += 1) {
        switch (trimmed[idx]) {
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth != 0) paren_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth != 0) bracket_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth != 0) brace_depth -= 1;
            },
            ':' => {
                if (paren_depth != 0 or bracket_depth != 0 or brace_depth != 0) continue;
                if (idx == 0) return false;
                const lhs = std.mem.trimRight(u8, trimmed[0..idx], " \t");
                if (lhs.len == 0) return false;
                var ident_idx: usize = 0;
                while (ident_idx < lhs.len and isIdentContinue(lhs[ident_idx])) : (ident_idx += 1) {}
                return ident_idx == lhs.len;
            },
            else => {},
        }
    }
    return false;
}

fn isIdentStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_';
}

fn isIdentContinue(ch: u8) bool {
    return isIdentStart(ch) or std.ascii.isDigit(ch);
}

fn parseLine(raw: []const u8) !ParsedLine {
    const maybe_line = sanitizeLine(raw);
    const line = maybe_line orelse return .skip;
    if (repl_meta.command(line)) |command| return .{ .meta = command };
    if (!std.mem.startsWith(u8, line, "\\t")) return .{ .eval = line };

    var expr = line[2..];
    var loops: usize = 1;
    if (expr.len > 0 and expr[0] == ':') {
        expr = expr[1..];
        const digits_len = countLeadingDigits(expr);
        if (digits_len == 0) return error.Parse;
        loops = std.fmt.parseUnsigned(usize, expr[0..digits_len], 10) catch return error.Parse;
        if (loops == 0) return error.Parse;
        expr = expr[digits_len..];
    }

    expr = std.mem.trimLeft(u8, expr, " \t");
    if (expr.len == 0) return error.Parse;
    return .{ .timing = .{ .loops = loops, .expr = expr } };
}

fn sanitizeLine(raw: []const u8) ?[]const u8 {
    const line = std.mem.trim(u8, raw, " \t\r");
    if (line.len == 0) return null;
    if (line[0] == '/') return null;

    var idx: usize = 0;
    while (idx < line.len) : (idx += 1) {
        if (line[idx] == '/' and idx > 0 and std.ascii.isWhitespace(line[idx - 1])) {
            const trimmed = std.mem.trimRight(u8, line[0..idx], " \t");
            if (trimmed.len == 0) return null;
            return trimmed;
        }
    }
    return line;
}

fn countLeadingDigits(text: []const u8) usize {
    var idx: usize = 0;
    while (idx < text.len and std.ascii.isDigit(text[idx])) : (idx += 1) {}
    return idx;
}

fn evalTiming(session: *runtime.Session, allocator: std.mem.Allocator, request: TimingRequest) ![]u8 {
    const elapsed_ns = try runTimingRequest(session, request);
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_ms;
    const rounded_ms: u64 = @intFromFloat(@round(elapsed_ms));
    return try std.fmt.allocPrint(allocator, "{d}", .{rounded_ms});
}

fn runTimingRequest(session: *runtime.Session, request: TimingRequest) !u64 {
    const started = monotonicNanos();
    var idx: usize = 0;
    while (idx < request.loops) : (idx += 1) {
        const value = try session.evalSource(request.expr);
        try session.forceValue(value);
    }
    return monotonicNanos() - started;
}

fn monotonicNanos() u64 {
    return @intCast(std.time.nanoTimestamp());
}

const max_source_bytes = 1 << 20;

pub fn benchmarkNamedCase(allocator: std.mem.Allocator, case_name: []const u8) !?BenchTiming {
    return try bench_tools.benchmarkNamedCase(allocator, case_name);
}

pub fn benchmarkNamedCaseWithTarget(
    allocator: std.mem.Allocator,
    device: runtime_device.DevicePreference,
    case_name: []const u8,
    target_batch_ms: f64,
    vector_size: usize,
    matmul_size: usize,
) !?BenchTiming {
    return try bench_tools.benchmarkNamedCaseWithTarget(allocator, device, case_name, target_batch_ms, vector_size, matmul_size);
}

pub fn defaultVectorSizeForTesting() usize {
    return bench_tools.default_vector_size;
}

pub fn resolveVectorSizeForTesting(case_name: []const u8, requested_size: usize) usize {
    return bench_tools.resolveVectorSize(case_name, requested_size);
}

pub fn resolveMatmulSizeForTesting(case_name: []const u8, requested_size: usize) usize {
    return bench_tools.resolveMatmulSize(case_name, requested_size);
}

pub fn isRealisticStringBenchCaseForTesting(case_name: []const u8) bool {
    return bench_tools.isRealisticStringBenchCase(case_name);
}

pub fn benchmarkSampleProfileForTesting(case_name: []const u8) BenchSampleProfile {
    return bench_tools.sampleProfileForCase(case_name);
}

pub fn isDefaultBenchSuiteCaseForTesting(case_name: []const u8) bool {
    return bench_tools.isDefaultBenchSuiteCase(case_name);
}
