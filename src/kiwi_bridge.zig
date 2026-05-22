const builtin = @import("builtin");
const std = @import("std");
const runtime_device = @import("device.zig");
const repl_meta = @import("repl_meta.zig");
const runtime = @import("runtime.zig");
const syntax_tokens = @import("syntax_tokens.zig");

pub const debug = if (builtin.target.os.tag == .ios or builtin.target.os.tag == .watchos)
    struct {
        pub const SelfInfo = void;
    }
else
    struct {};

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

pub const kiwi_device_preference_e = enum(c_int) {
    auto = 0,
    cpu = 1,
    gpu = 2,
};

pub const kiwi_status_e = enum(c_int) {
    ok = 0,
    parse = 1,
    type = 2,
    name = 3,
    domain = 4,
    rank = 5,
    nyi = 6,
    length = 7,
    index = 8,
    mlx = 9,
    device = 10,
    @"error" = 11,
    oom = 12,
};

pub const kiwi_autograd_path_e = enum(c_int) {
    none = 0,
    mlx = 1,
    finite_difference = 2,
};

pub const kiwi_eval_result_s = extern struct {
    status: kiwi_status_e,
    echoed: bool,
    autograd_path: kiwi_autograd_path_e,
    text_ptr: ?[*]u8,
    text_len: usize,
    display_mime_ptr: ?[*]u8,
    display_mime_len: usize,
    display_data_ptr: ?[*]u8,
    display_data_len: usize,
};

pub const kiwi_syntax_token_kind_e = syntax_tokens.TokenKind;
pub const kiwi_syntax_token_s = syntax_tokens.Token;

pub const kiwi_session = struct {
    allocator: std.mem.Allocator = std.heap.smp_allocator,
    session: runtime.Session,

    pub fn create(device: kiwi_device_preference_e) !*kiwi_session {
        const handle = try std.heap.c_allocator.create(kiwi_session);
        errdefer std.heap.c_allocator.destroy(handle);

        handle.* = .{
            .session = undefined,
        };
        handle.session = try runtime.Session.initWithDevice(handle.allocator, devicePreference(device));
        return handle;
    }

    pub fn destroy(self: *kiwi_session) void {
        self.session.deinit();
        std.heap.c_allocator.destroy(self);
    }

    pub fn evalOwned(self: *kiwi_session, source: []const u8) EvalOwned {
        const parsed = parseLine(source) catch |err| {
            return .{
                .status = statusFromError(err),
                .echoed = false,
                .autograd_path = .none,
                .text = null,
            };
        };
        return switch (parsed) {
            .skip => .{
                .status = .ok,
                .echoed = false,
                .autograd_path = .none,
                .text = null,
            },
            .timing => |request| blk: {
                const rendered = evalTiming(&self.session, std.heap.c_allocator, request) catch |err| {
                    break :blk errorEvalOwned(&self.session, err);
                };
                break :blk .{
                    .status = .ok,
                    .echoed = true,
                    .autograd_path = autogradPathFromRuntime(&self.session),
                    .text = rendered,
                };
            },
            .meta => |command| blk: {
                switch (command) {
                    .exit => break :blk .{
                        .status = .ok,
                        .echoed = false,
                        .autograd_path = .none,
                        .text = null,
                    },
                    .help => |text| {
                        const rendered = std.heap.c_allocator.dupe(u8, text) catch break :blk .{
                            .status = .oom,
                            .echoed = false,
                            .autograd_path = .none,
                            .text = null,
                        };
                        break :blk .{
                            .status = .ok,
                            .echoed = true,
                            .autograd_path = autogradPathFromRuntime(&self.session),
                            .text = rendered,
                        };
                    },
                }
            },
            .eval => |expr| blk: {
                const value = self.session.evalSource(expr) catch |err| {
                    break :blk errorEvalOwned(&self.session, err);
                };

                var owned = EvalOwned{
                    .status = .ok,
                    .echoed = shouldEchoEvalLine(expr),
                    .autograd_path = autogradPathFromRuntime(&self.session),
                    .text = null,
                };
                if (!owned.echoed) break :blk owned;

                const rendered = self.session.renderValue(value) catch |err| {
                    break :blk errorEvalOwned(&self.session, err);
                };
                defer self.session.allocator.free(rendered);

                owned.text = std.heap.c_allocator.dupe(u8, rendered) catch {
                    owned.status = .oom;
                    owned.echoed = false;
                    owned.autograd_path = .none;
                    break :blk owned;
                };
                if (displayPayloadForValue(&self.session, value)) |display| {
                    owned.display_mime = display.mime;
                    owned.display_data = display.data;
                }
                break :blk owned;
            },
        };
    }

    pub fn setGlobalFloatArray(self: *kiwi_session, name: []const u8, data: []const f32, dims: []const i32) kiwi_status_e {
        self.session.setGlobalHostFloatArray(name, data, dims) catch |err| return statusFromError(err);
        return .ok;
    }

    pub fn setGlobalMlxFloatArray(self: *kiwi_session, name: []const u8, data: []const f32, dims: []const i32) kiwi_status_e {
        self.session.setGlobalMlxFloatArray(name, data, dims) catch |err| return statusFromError(err);
        return .ok;
    }

    pub fn setGlobalIntArray(self: *kiwi_session, name: []const u8, data: []const i32, dims: []const i32) kiwi_status_e {
        self.session.setGlobalHostIntArray(name, data, dims) catch |err| return statusFromError(err);
        return .ok;
    }

    pub fn setGlobalBoolArray(self: *kiwi_session, name: []const u8, data: []const bool, dims: []const i32) kiwi_status_e {
        self.session.setGlobalHostBoolArray(name, data, dims) catch |err| return statusFromError(err);
        return .ok;
    }
};

pub const EvalOwned = struct {
    status: kiwi_status_e,
    echoed: bool,
    autograd_path: kiwi_autograd_path_e,
    text: ?[]u8,
    display_mime: ?[]u8 = null,
    display_data: ?[]u8 = null,

    pub fn intoC(self: *EvalOwned) kiwi_eval_result_s {
        const text = self.text;
        const display_mime = self.display_mime;
        const display_data = self.display_data;
        self.text = null;
        self.display_mime = null;
        self.display_data = null;
        return .{
            .status = self.status,
            .echoed = self.echoed,
            .autograd_path = self.autograd_path,
            .text_ptr = if (text) |buf| buf.ptr else null,
            .text_len = if (text) |buf| buf.len else 0,
            .display_mime_ptr = if (display_mime) |buf| buf.ptr else null,
            .display_mime_len = if (display_mime) |buf| buf.len else 0,
            .display_data_ptr = if (display_data) |buf| buf.ptr else null,
            .display_data_len = if (display_data) |buf| buf.len else 0,
        };
    }
};

const DisplayPayloadOwned = struct {
    mime: []u8,
    data: []u8,
};

fn displayPayloadForValue(session: *runtime.Session, value: runtime.Value) ?DisplayPayloadOwned {
    const bundle = session.displayMimeBundleForValue(value) orelse return null;
    const mime = std.heap.c_allocator.dupe(u8, bundle.mime) catch return null;
    const data = std.heap.c_allocator.dupe(u8, bundle.data) catch {
        std.heap.c_allocator.free(mime);
        return null;
    };
    return .{ .mime = mime, .data = data };
}

fn diagnosticTextOwned(session: *runtime.Session) ?[]u8 {
    const detail = session.lastErrorText() orelse return null;
    defer session.clearLastErrorText();
    return std.heap.c_allocator.dupe(u8, detail) catch null;
}

fn errorEvalOwned(session: *runtime.Session, err: anyerror) EvalOwned {
    return .{
        .status = statusFromError(err),
        .echoed = false,
        .autograd_path = .none,
        .text = diagnosticTextOwned(session),
    };
}

pub fn statusName(status: kiwi_status_e) [*:0]const u8 {
    return switch (status) {
        .ok => "ok",
        .parse => "parse",
        .type => "type",
        .name => "name",
        .domain => "domain",
        .rank => "rank",
        .nyi => "nyi",
        .length => "length",
        .index => "index",
        .mlx => "mlx",
        .device => "device",
        .@"error" => "error",
        .oom => "oom",
    };
}

fn devicePreference(device: kiwi_device_preference_e) runtime_device.DevicePreference {
    return switch (device) {
        .auto => .auto,
        .cpu => .cpu,
        .gpu => .gpu,
    };
}

fn statusFromError(err: anyerror) kiwi_status_e {
    return switch (err) {
        error.Parse => .parse,
        error.Name => .name,
        error.Type => .type,
        error.Arity => .type,
        error.Unsupported => .nyi,
        error.OutOfMemory => .oom,
        else => .@"error",
    };
}

fn autogradPathFromRuntime(session: *runtime.Session) kiwi_autograd_path_e {
    return if (session.lastDenseAutodiffExecPath()) |path|
        if (std.mem.eql(u8, path, "mlx")) .mlx else .finite_difference
    else
        .none;
}

fn elementCount(dims: []const i32) runtime.KError!usize {
    var count: usize = 1;
    for (dims) |dim| {
        if (dim < 0) return error.Type;
        count *= @as(usize, @intCast(dim));
    }
    return count;
}

fn nameSlice(name: ?[*]const u8, name_len: usize) ?[]const u8 {
    const ptr = name orelse return null;
    return ptr[0..name_len];
}

fn dimsSlice(dims: ?[*]const i32, ndim: usize) ?[]const i32 {
    if (ndim == 0) return &.{};
    const ptr = dims orelse return null;
    return ptr[0..ndim];
}

fn parseLine(raw: []const u8) !ParsedLine {
    const line = sanitizeLine(raw) orelse return .skip;
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

fn shouldEchoEvalLine(line: []const u8) bool {
    return !isTopLevelAssignment(line);
}

fn isTopLevelAssignment(line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    return isSingleTopLevelAssignment(lastTopLevelStatementSlice(trimmed));
}

fn lastTopLevelStatementSlice(trimmed: []const u8) []const u8 {
    var idx: usize = 0;
    var segment_start: usize = 0;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var brace_depth: usize = 0;
    while (idx < trimmed.len) : (idx += 1) {
        switch (trimmed[idx]) {
            '"' => {
                idx += 1;
                while (idx < trimmed.len and trimmed[idx] != '"') : (idx += 1) {}
                if (idx >= trimmed.len) break;
            },
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
            ';' => {
                if (paren_depth == 0 and bracket_depth == 0 and brace_depth == 0) segment_start = idx + 1;
            },
            else => {},
        }
    }
    return std.mem.trim(u8, trimmed[segment_start..], " \t\r");
}

fn isSingleTopLevelAssignment(trimmed: []const u8) bool {
    if (trimmed.len == 0 or !isIdentStart(trimmed[0])) return false;

    var idx: usize = 0;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var brace_depth: usize = 0;
    while (idx < trimmed.len) : (idx += 1) {
        switch (trimmed[idx]) {
            '"' => {
                idx += 1;
                while (idx < trimmed.len and trimmed[idx] != '"') : (idx += 1) {}
                if (idx >= trimmed.len) break;
            },
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

fn evalTiming(session: *runtime.Session, allocator: std.mem.Allocator, request: TimingRequest) ![]u8 {
    session.clearLastErrorText();
    const code = try session.compile(request.expr);

    const started = monotonicNanos();
    var idx: usize = 0;
    while (idx < request.loops) : (idx += 1) {
        const value = try session.evalCode(code);
        try session.forceValue(value);
    }
    const elapsed_ns = monotonicNanos() - started;
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_ms;
    const rounded_ms: u64 = @intFromFloat(@round(elapsed_ms));
    return try std.fmt.allocPrint(allocator, "{d}", .{rounded_ms});
}

fn monotonicNanos() u64 {
    return @intCast(std.time.nanoTimestamp());
}

pub export fn kiwi_session_create(device: kiwi_device_preference_e) ?*kiwi_session {
    return kiwi_session.create(device) catch null;
}

pub export fn kiwi_session_destroy(session: ?*kiwi_session) void {
    if (session) |handle| handle.destroy();
}

pub export fn kiwi_session_eval(session: ?*kiwi_session, source: ?[*]const u8, source_len: usize) kiwi_eval_result_s {
    const handle = session orelse return .{
        .status = .@"error",
        .echoed = false,
        .autograd_path = .none,
        .text_ptr = null,
        .text_len = 0,
        .display_mime_ptr = null,
        .display_mime_len = 0,
        .display_data_ptr = null,
        .display_data_len = 0,
    };
    const ptr = source orelse return .{
        .status = .parse,
        .echoed = false,
        .autograd_path = .none,
        .text_ptr = null,
        .text_len = 0,
        .display_mime_ptr = null,
        .display_mime_len = 0,
        .display_data_ptr = null,
        .display_data_len = 0,
    };
    var result = handle.evalOwned(ptr[0..source_len]);
    return result.intoC();
}

pub export fn kiwi_syntax_tokenize(
    source: ?[*]const u8,
    source_len: usize,
    out_tokens: ?[*]kiwi_syntax_token_s,
    out_capacity: usize,
) usize {
    const ptr = source orelse return 0;
    const source_buf = ptr[0..source_len];
    var empty: [0]kiwi_syntax_token_s = .{};
    const output = if (out_tokens) |out| out[0..out_capacity] else empty[0..];
    var buffer = syntax_tokens.TokenBuffer{ .tokens = output };
    syntax_tokens.tokenize(source_buf, &buffer);
    return buffer.total;
}

pub export fn kiwi_session_set_global_float_array(
    session: ?*kiwi_session,
    name: ?[*]const u8,
    name_len: usize,
    data: ?[*]const f32,
    dims: ?[*]const i32,
    ndim: usize,
) kiwi_status_e {
    const handle = session orelse return .@"error";
    const name_buf = nameSlice(name, name_len) orelse return .name;
    const dims_buf = dimsSlice(dims, ndim) orelse return .rank;
    const count = elementCount(dims_buf) catch |err| return statusFromError(err);
    const data_buf: []const f32 = if (count == 0) &.{} else (data orelse return .type)[0..count];
    return handle.setGlobalFloatArray(name_buf, data_buf, dims_buf);
}

pub export fn kiwi_session_set_global_mlx_float_array(
    session: ?*kiwi_session,
    name: ?[*]const u8,
    name_len: usize,
    data: ?[*]const f32,
    dims: ?[*]const i32,
    ndim: usize,
) kiwi_status_e {
    const handle = session orelse return .@"error";
    const name_buf = nameSlice(name, name_len) orelse return .name;
    const dims_buf = dimsSlice(dims, ndim) orelse return .rank;
    const count = elementCount(dims_buf) catch |err| return statusFromError(err);
    const data_buf: []const f32 = if (count == 0) &.{} else (data orelse return .type)[0..count];
    return handle.setGlobalMlxFloatArray(name_buf, data_buf, dims_buf);
}

pub export fn kiwi_session_set_global_int_array(
    session: ?*kiwi_session,
    name: ?[*]const u8,
    name_len: usize,
    data: ?[*]const i32,
    dims: ?[*]const i32,
    ndim: usize,
) kiwi_status_e {
    const handle = session orelse return .@"error";
    const name_buf = nameSlice(name, name_len) orelse return .name;
    const dims_buf = dimsSlice(dims, ndim) orelse return .rank;
    const count = elementCount(dims_buf) catch |err| return statusFromError(err);
    const data_buf: []const i32 = if (count == 0) &.{} else (data orelse return .type)[0..count];
    return handle.setGlobalIntArray(name_buf, data_buf, dims_buf);
}

pub export fn kiwi_session_set_global_bool_array(
    session: ?*kiwi_session,
    name: ?[*]const u8,
    name_len: usize,
    data: ?[*]const bool,
    dims: ?[*]const i32,
    ndim: usize,
) kiwi_status_e {
    const handle = session orelse return .@"error";
    const name_buf = nameSlice(name, name_len) orelse return .name;
    const dims_buf = dimsSlice(dims, ndim) orelse return .rank;
    const count = elementCount(dims_buf) catch |err| return statusFromError(err);
    const data_buf: []const bool = if (count == 0) &.{} else (data orelse return .type)[0..count];
    return handle.setGlobalBoolArray(name_buf, data_buf, dims_buf);
}

pub export fn kiwi_eval_result_free(result: kiwi_eval_result_s) void {
    if (result.text_ptr) |ptr| {
        std.heap.c_allocator.free(ptr[0..result.text_len]);
    }
    if (result.display_mime_ptr) |ptr| {
        std.heap.c_allocator.free(ptr[0..result.display_mime_len]);
    }
    if (result.display_data_ptr) |ptr| {
        std.heap.c_allocator.free(ptr[0..result.display_data_len]);
    }
}

pub export fn kiwi_status_name(status: kiwi_status_e) [*:0]const u8 {
    return statusName(status);
}
