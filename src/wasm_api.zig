const std = @import("std");
const runtime_device = @import("device.zig");
const runtime = @import("runtime.zig");

const page_size: usize = 64 * 1024;

var heap_offset: usize = 4096;
var session: ?runtime.Session = null;
var last_value: ?runtime.Value = null;
var last_array_info: ?runtime.WasmArrayInfo = null;
var last_rendered: ?[]u8 = null;
var last_echo: bool = false;
var last_error_buf: [16]u8 = [_]u8{0} ** 16;
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

fn setLastError(err: anyerror) void {
    @memset(&last_error_buf, 0);
    const text = runtime.errorCode(err);
    const count = @min(text.len, last_error_buf.len);
    @memcpy(last_error_buf[0..count], text[0..count]);
    last_error_len = @intCast(count);
}

fn clearLastError() void {
    @memset(&last_error_buf, 0);
    last_error_len = 0;
}

fn clearLastRendered() void {
    if (last_rendered) |text| std.heap.wasm_allocator.free(text);
    last_rendered = null;
}

fn clearLastValue() void {
    clearLastRendered();
    last_value = null;
    last_array_info = null;
    last_echo = false;
}

fn ensureLastArrayInfo() bool {
    if (last_array_info != null) return true;
    const active = &(session orelse return false);
    const value = last_value orelse return false;
    last_array_info = active.wasmAcceleratorArrayInfo(value) catch null;
    return last_array_info != null;
}

fn ensureLastRendered() i32 {
    if (last_rendered != null) return 0;
    const active = &(session orelse {
        setLastError(error.Name);
        return 1;
    });
    const value = last_value orelse {
        setLastError(error.Type);
        return 1;
    };
    last_rendered = active.renderValue(value) catch |err| {
        setLastError(err);
        return 1;
    };
    return 0;
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

pub export fn kiwi_init(device: u32) i32 {
    if (device == 0xFFFF_FFFF) _ = kiwi_force_backend_surface();
    clearLastValue();
    clearLastError();
    if (session) |*existing| {
        existing.deinit();
        session = null;
    }
    session = runtime.Session.initWithDevice(std.heap.wasm_allocator, deviceFromInt(device)) catch |err| {
        setLastError(err);
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
        setLastError(error.Name);
        return 1;
    });
    const source = bytesAt(ptr, len);
    const result = active.evalSource(source) catch |err| {
        setLastError(err);
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
    return if (ensureLastArrayInfo()) last_array_info.?.handle else 0;
}

pub export fn kiwi_last_array_dtype() i32 {
    return if (ensureLastArrayInfo()) last_array_info.?.dtype else 0;
}

pub export fn kiwi_last_array_ndim() u32 {
    return if (ensureLastArrayInfo()) last_array_info.?.ndim else 0;
}

pub export fn kiwi_last_array_shape_dim(index: u32) i32 {
    if (!ensureLastArrayInfo()) return 0;
    const info = last_array_info.?;
    if (index >= info.ndim) return 0;
    return info.shape[index];
}

pub export fn kiwi_last_array_size() u32 {
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

pub export fn kiwi_force_backend_surface() i32 {
    var probe = runtime.Session.initWithDevice(std.heap.wasm_allocator, .gpu) catch return 1;
    defer probe.deinit();
    const value = probe.evalSource("x:(1 2;3 4);x.(+x)") catch return 2;
    return if ((probe.wasmAcceleratorArrayInfo(value) catch null) != null) 0 else 4;
}
