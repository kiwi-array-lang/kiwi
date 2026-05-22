const std = @import("std");
const build_options = @import("build_options");
const runtime_device = @import("device.zig");
const repl_meta = @import("repl_meta.zig");
const runtime = @import("runtime.zig");
const syntax_tokens = @import("syntax_tokens.zig");

const page_size: usize = 64 * 1024;
const wasm_exports_accelerator_handles = build_options.wasm_exports_accelerator_handles;

var heap_offset: usize = 4096;
var session: ?runtime.Session = null;
var last_value: ?runtime.Value = null;
var last_array_info: ?runtime.WasmArrayInfo = null;
var last_rendered: ?[]u8 = null;
var last_display_mime: ?[]u8 = null;
var last_display_data: ?[]u8 = null;
var last_echo: bool = false;
var last_error_buf: [512]u8 = [_]u8{0} ** 512;
var last_error_len: u32 = 0;

fn alignForward(value: usize, alignment: usize) usize {
    return (value + alignment - 1) & ~(alignment - 1);
}

fn ensureCapacity(end: usize) bool {
    const current_pages = @wasmMemorySize(0);
    const current_bytes = current_pages * page_size;
    if (end <= current_bytes) return true;

    const missing = end - current_bytes;
    const grow_pages = (missing + page_size - 1) / page_size;
    return @wasmMemoryGrow(0, grow_pages) != -1;
}

fn bytesAt(ptr: u32, len: u32) []u8 {
    const base: usize = @intCast(ptr);
    const count: usize = @intCast(len);
    const many: [*]u8 = @ptrFromInt(base);
    return many[0..count];
}

fn syntaxTokensAt(ptr: u32, len: u32) []syntax_tokens.Token {
    const base: usize = @intCast(ptr);
    const count: usize = @intCast(len);
    const many: [*]syntax_tokens.Token = @ptrFromInt(base);
    return many[0..count];
}

fn setLastError(active: ?*runtime.Session, err: anyerror) void {
    @memset(&last_error_buf, 0);
    const text = if (active) |session_handle|
        session_handle.lastErrorText() orelse runtime.errorCode(err)
    else
        runtime.errorCode(err);
    const count = @min(text.len, last_error_buf.len);
    @memcpy(last_error_buf[0..count], text[0..count]);
    last_error_len = @intCast(count);
    if (active) |session_handle| session_handle.clearLastErrorText();
}

fn clearLastError() void {
    @memset(&last_error_buf, 0);
    last_error_len = 0;
}

fn clearLastRendered() void {
    if (last_rendered) |text| std.heap.wasm_allocator.free(text);
    last_rendered = null;
}

fn clearLastDisplay() void {
    if (last_display_mime) |mime| std.heap.wasm_allocator.free(mime);
    if (last_display_data) |data| std.heap.wasm_allocator.free(data);
    last_display_mime = null;
    last_display_data = null;
}

fn clearLastValue() void {
    clearLastRendered();
    clearLastDisplay();
    last_value = null;
    last_array_info = null;
    last_echo = false;
}

fn ensureLastArrayInfo() bool {
    if (comptime !wasm_exports_accelerator_handles) return false;
    if (last_array_info != null) return true;
    const active = &(session orelse return false);
    const value = last_value orelse return false;
    last_array_info = active.wasmAcceleratorArrayInfo(value) catch null;
    return last_array_info != null;
}

fn ensureLastRendered() i32 {
    if (last_rendered != null) return 0;
    const active = &(session orelse {
        setLastError(null, error.Name);
        return 1;
    });
    const value = last_value orelse {
        setLastError(active, error.Type);
        return 1;
    };
    last_rendered = active.renderValue(value) catch |err| {
        setLastError(active, err);
        return 1;
    };
    return 0;
}

fn ensureLastDisplay() bool {
    if (last_display_mime != null and last_display_data != null) return true;
    clearLastDisplay();

    const active = &(session orelse return false);
    const value = last_value orelse return false;
    const bundle = active.displayMimeBundleForValue(value) orelse return false;

    const mime = std.heap.wasm_allocator.dupe(u8, bundle.mime) catch |err| {
        setLastError(active, err);
        return false;
    };

    const data = std.heap.wasm_allocator.dupe(u8, bundle.data) catch |err| {
        std.heap.wasm_allocator.free(mime);
        setLastError(active, err);
        return false;
    };

    last_display_mime = mime;
    last_display_data = data;
    return true;
}

fn deviceFromInt(raw: u32) runtime_device.DevicePreference {
    return switch (raw) {
        1 => .cpu,
        2 => .gpu,
        else => .cpu,
    };
}

fn isIdentStart(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or ch == '_';
}

fn isIdentContinue(ch: u8) bool {
    return isIdentStart(ch) or (ch >= '0' and ch <= '9');
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

fn shouldEchoEvalLine(line: []const u8) bool {
    return !isTopLevelAssignment(line);
}

pub export fn kiwi_alloc_bytes(len: u32, alignment: u32) u32 {
    const requested: usize = @intCast(len);
    const align_to: usize = @max(@as(usize, 1), @as(usize, @intCast(alignment)));
    const base = alignForward(heap_offset, align_to);
    const end = base + requested;
    if (!ensureCapacity(end)) return 0;
    heap_offset = end;
    return @intCast(base);
}

pub export fn kiwi_reset_input_arena() void {
    heap_offset = 4096;
}

pub export fn kiwi_syntax_tokenize(ptr: u32, len: u32, out_ptr: u32, out_capacity: u32) u32 {
    if (ptr == 0 and len != 0) return 0;
    const source = if (len == 0) &[_]u8{} else bytesAt(ptr, len);
    var empty: [0]syntax_tokens.Token = .{};
    const output = if (out_ptr == 0 or out_capacity == 0)
        empty[0..]
    else
        syntaxTokensAt(out_ptr, out_capacity);
    var buffer = syntax_tokens.TokenBuffer{ .tokens = output };
    syntax_tokens.tokenize(source, &buffer);
    return std.math.cast(u32, buffer.total) orelse std.math.maxInt(u32);
}

pub export fn kiwi_init(device: u32) i32 {
    if (comptime wasm_exports_accelerator_handles) {
        if (device == 0xFFFF_FFFF) _ = kiwi_force_backend_surface();
    }
    clearLastValue();
    clearLastError();
    if (session) |*existing| {
        existing.deinit();
        session = null;
    }
    session = runtime.Session.initWithDevice(std.heap.wasm_allocator, deviceFromInt(device)) catch |err| {
        setLastError(null, err);
        return 1;
    };
    return 0;
}

pub export fn kiwi_deinit() void {
    clearLastValue();
    if (session) |*existing| {
        existing.deinit();
        session = null;
    }
    clearLastError();
}

pub export fn kiwi_eval(ptr: u32, len: u32) i32 {
    clearLastValue();
    clearLastError();
    const active = &(session orelse {
        setLastError(null, error.Name);
        return 1;
    });
    const source = bytesAt(ptr, len);
    if (repl_meta.command(source)) |command| {
        switch (command) {
            .exit => {
                last_echo = false;
                return 0;
            },
            .help => |text| {
                last_rendered = std.heap.wasm_allocator.dupe(u8, text) catch {
                    setLastError(active, error.OutOfMemory);
                    return 1;
                };
                last_echo = true;
                return 0;
            },
        }
    }
    const result = active.evalSource(source) catch |err| {
        setLastError(active, err);
        return 1;
    };
    last_echo = shouldEchoEvalLine(source);
    last_array_info = null;
    last_value = result;
    return 0;
}

pub export fn kiwi_last_error_ptr() u32 {
    return @intCast(@intFromPtr(&last_error_buf));
}

pub export fn kiwi_last_error_len() u32 {
    return last_error_len;
}

pub export fn kiwi_last_echo_value() u32 {
    return @intFromBool(last_echo);
}

pub export fn kiwi_last_kind() u32 {
    const value = last_value orelse return 0;
    return switch (value.tag()) {
        .int => 1,
        .float => 2,
        .bool => 3,
        .array => if (ensureLastArrayInfo()) 4 else 5,
        else => 5,
    };
}

pub export fn kiwi_last_int() i32 {
    const value = last_value orelse return 0;
    return switch (value.tag()) {
        .int => std.math.cast(i32, last_value.?.asInt()) orelse 0,
        .bool => if (last_value.?.asBool()) 1 else 0,
        else => 0,
    };
}

pub export fn kiwi_last_float() f32 {
    const value = last_value orelse return 0;
    return switch (value.tag()) {
        .float => @floatCast(value.asFloat()),
        .int => @floatFromInt(value.asInt()),
        .bool => if (value.asBool()) 1 else 0,
        else => 0,
    };
}

pub export fn kiwi_last_bool() u32 {
    const value = last_value orelse return 0;
    return switch (value.tag()) {
        .bool => @intFromBool(value.asBool()),
        .int => @intFromBool(value.asInt() != 0),
        .float => @intFromBool(value.asFloat() != 0),
        else => 0,
    };
}

pub export fn kiwi_last_array_handle() u32 {
    if (comptime !wasm_exports_accelerator_handles) return 0;
    return if (ensureLastArrayInfo()) last_array_info.?.handle else 0;
}

pub export fn kiwi_last_array_dtype() i32 {
    if (comptime !wasm_exports_accelerator_handles) return 0;
    return if (ensureLastArrayInfo()) last_array_info.?.dtype else 0;
}

pub export fn kiwi_last_array_ndim() u32 {
    if (comptime !wasm_exports_accelerator_handles) return 0;
    return if (ensureLastArrayInfo()) last_array_info.?.ndim else 0;
}

pub export fn kiwi_last_array_shape_dim(index: u32) i32 {
    if (comptime !wasm_exports_accelerator_handles) return 0;
    if (!ensureLastArrayInfo()) return 0;
    const info = last_array_info.?;
    if (index >= info.ndim) return 0;
    return info.shape[index];
}

pub export fn kiwi_last_array_size() u32 {
    if (comptime !wasm_exports_accelerator_handles) return 0;
    if (!ensureLastArrayInfo()) return 0;
    const info = last_array_info.?;
    var total: usize = 1;
    var idx: usize = 0;
    while (idx < info.ndim) : (idx += 1) total *= @intCast(info.shape[idx]);
    return @intCast(total);
}

pub export fn kiwi_render_last_value() i32 {
    return ensureLastRendered();
}

pub export fn kiwi_last_rendered_ptr() u32 {
    if (ensureLastRendered() != 0) return 0;
    return @intCast(@intFromPtr(last_rendered.?.ptr));
}

pub export fn kiwi_last_rendered_len() u32 {
    if (ensureLastRendered() != 0) return 0;
    return @intCast(last_rendered.?.len);
}

pub export fn kiwi_last_display_mime_ptr() u32 {
    if (!ensureLastDisplay()) return 0;
    return @intCast(@intFromPtr(last_display_mime.?.ptr));
}

pub export fn kiwi_last_display_mime_len() u32 {
    if (!ensureLastDisplay()) return 0;
    return @intCast(last_display_mime.?.len);
}

pub export fn kiwi_last_display_data_ptr() u32 {
    if (!ensureLastDisplay()) return 0;
    return @intCast(@intFromPtr(last_display_data.?.ptr));
}

pub export fn kiwi_last_display_data_len() u32 {
    if (!ensureLastDisplay()) return 0;
    return @intCast(last_display_data.?.len);
}

pub export fn kiwi_force_backend_surface() i32 {
    if (comptime !wasm_exports_accelerator_handles) return 1;
    var probe = runtime.Session.initWithDevice(std.heap.wasm_allocator, .gpu) catch return 1;
    defer probe.deinit();
    const value = probe.evalSource("x:(1 2;3 4);x.(+x)") catch return 2;
    return if ((probe.wasmAcceleratorArrayInfo(value) catch null) != null) 0 else 4;
}
