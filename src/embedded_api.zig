const std = @import("std");
const runtime = @import("runtime.zig");

pub const panic = std.debug.no_panic;

const heap_bytes: usize = 64 * 1024;
const f64_fraction_bits: u64 = 52;
const f64_exponent_bias: u64 = 1023;
const f64_fraction_mask: u64 = (1 << f64_fraction_bits) - 1;

var configured_heap_ptr: ?[*]u8 = null;
var configured_heap_len: usize = 0;
export var kiwi_embedded_panic_return_address: usize = 0;
export var kiwi_embedded_probe_stage: usize = 0;

fn embeddedPanic(_: []const u8, return_address: ?usize) noreturn {
    kiwi_embedded_panic_return_address = return_address orelse 0;
    @trap();
}

pub export fn kiwi_embedded_heap_bytes() usize {
    return heap_bytes;
}

pub export fn kiwi_embedded_set_heap(heap_ptr: [*]u8, heap_len: usize) isize {
    if (heap_len < heap_bytes) return -1;
    configured_heap_ptr = heap_ptr;
    configured_heap_len = heap_len;
    return 0;
}

pub export fn kiwi_embedded_session_bytes() usize {
    return @sizeOf(runtime.Session);
}

fn initFixedBufferAllocator() ?std.heap.FixedBufferAllocator {
    const heap_ptr = configured_heap_ptr orelse return null;
    return std.heap.FixedBufferAllocator.init(heap_ptr[0..configured_heap_len]);
}

pub export fn kiwi_embedded_probe_session_alloc_only() isize {
    kiwi_embedded_probe_stage = 1;
    var fixed = initFixedBufferAllocator() orelse return -5;
    const allocator = fixed.allocator();

    kiwi_embedded_probe_stage = 2;
    const session = allocator.create(runtime.Session) catch return -1;
    kiwi_embedded_probe_stage = 3;
    allocator.destroy(session);
    kiwi_embedded_probe_stage = 100;
    return 0;
}

pub export fn kiwi_embedded_probe_session_init_no_deinit() isize {
    kiwi_embedded_probe_stage = 5;
    var fixed = initFixedBufferAllocator() orelse return -5;
    const allocator = fixed.allocator();

    kiwi_embedded_probe_stage = 6;
    const session = allocator.create(runtime.Session) catch return -1;
    kiwi_embedded_probe_stage = 7;
    session.initInPlace(allocator) catch {
        allocator.destroy(session);
        return -1;
    };
    kiwi_embedded_probe_stage = 100;
    return 0;
}

pub export fn kiwi_embedded_probe_session_init() isize {
    kiwi_embedded_probe_stage = 1;
    var fixed = initFixedBufferAllocator() orelse return -5;
    const allocator = fixed.allocator();

    kiwi_embedded_probe_stage = 2;
    const session = allocator.create(runtime.Session) catch return -1;
    kiwi_embedded_probe_stage = 3;
    session.initInPlace(allocator) catch {
        allocator.destroy(session);
        return -1;
    };
    kiwi_embedded_probe_stage = 4;
    session.deinit();
    allocator.destroy(session);
    kiwi_embedded_probe_stage = 100;
    return 0;
}

pub export fn kiwi_embedded_probe_parse(source_ptr: [*]const u8, source_len: usize) isize {
    kiwi_embedded_probe_stage = 10;
    var fixed = initFixedBufferAllocator() orelse return -5;
    const allocator = fixed.allocator();

    kiwi_embedded_probe_stage = 11;
    const session = allocator.create(runtime.Session) catch return -1;
    kiwi_embedded_probe_stage = 12;
    session.initInPlace(allocator) catch {
        allocator.destroy(session);
        return -1;
    };
    defer {
        session.deinit();
        allocator.destroy(session);
    }

    kiwi_embedded_probe_stage = 13;
    const source = source_ptr[0..source_len];
    session.parseOnly(source) catch return -2;
    kiwi_embedded_probe_stage = 100;
    return 0;
}

pub export fn kiwi_embedded_probe_eval(source_ptr: [*]const u8, source_len: usize) isize {
    kiwi_embedded_probe_stage = 20;
    var fixed = initFixedBufferAllocator() orelse return -5;
    const allocator = fixed.allocator();

    kiwi_embedded_probe_stage = 21;
    const session = allocator.create(runtime.Session) catch return -1;
    kiwi_embedded_probe_stage = 22;
    session.initInPlace(allocator) catch {
        allocator.destroy(session);
        return -1;
    };

    kiwi_embedded_probe_stage = 23;
    const source = source_ptr[0..source_len];
    _ = session.evalSource(source) catch return -2;
    kiwi_embedded_probe_stage = 24;
    session.deinit();
    kiwi_embedded_probe_stage = 25;
    allocator.destroy(session);
    kiwi_embedded_probe_stage = 100;
    return 0;
}

pub export fn kiwi_embedded_probe_eval_no_deinit(source_ptr: [*]const u8, source_len: usize) isize {
    kiwi_embedded_probe_stage = 50;
    var fixed = initFixedBufferAllocator() orelse return -5;
    const allocator = fixed.allocator();

    kiwi_embedded_probe_stage = 51;
    const session = allocator.create(runtime.Session) catch return -1;
    kiwi_embedded_probe_stage = 52;
    session.initInPlace(allocator) catch {
        allocator.destroy(session);
        return -1;
    };

    kiwi_embedded_probe_stage = 53;
    const source = source_ptr[0..source_len];
    _ = session.evalSource(source) catch return -2;
    kiwi_embedded_probe_stage = 100;
    return 0;
}

pub export fn kiwi_embedded_probe_eval_render(
    source_ptr: [*]const u8,
    source_len: usize,
    output_ptr: [*]u8,
    output_capacity: usize,
) isize {
    kiwi_embedded_probe_stage = 30;
    var fixed = initFixedBufferAllocator() orelse return -5;
    const allocator = fixed.allocator();

    kiwi_embedded_probe_stage = 31;
    const session = allocator.create(runtime.Session) catch return -1;
    kiwi_embedded_probe_stage = 32;
    session.initInPlace(allocator) catch {
        allocator.destroy(session);
        return -1;
    };

    kiwi_embedded_probe_stage = 33;
    const source = source_ptr[0..source_len];
    const value = session.evalSource(source) catch return -2;
    kiwi_embedded_probe_stage = 34;
    const text = session.renderValue(value) catch return -3;

    kiwi_embedded_probe_stage = 35;
    if (text.len > output_capacity) return -4;
    @memcpy(output_ptr[0..text.len], text);
    kiwi_embedded_probe_stage = 36;
    allocator.free(text);
    kiwi_embedded_probe_stage = 37;
    session.deinit();
    kiwi_embedded_probe_stage = 38;
    allocator.destroy(session);
    kiwi_embedded_probe_stage = 100;
    return @intCast(text.len);
}

pub export fn kiwi_embedded_probe_eval_render_no_cleanup(
    source_ptr: [*]const u8,
    source_len: usize,
    output_ptr: [*]u8,
    output_capacity: usize,
) isize {
    kiwi_embedded_probe_stage = 60;
    var fixed = initFixedBufferAllocator() orelse return -5;
    const allocator = fixed.allocator();

    kiwi_embedded_probe_stage = 61;
    const session = allocator.create(runtime.Session) catch return -1;
    kiwi_embedded_probe_stage = 62;
    session.initInPlace(allocator) catch return -1;

    kiwi_embedded_probe_stage = 63;
    const source = source_ptr[0..source_len];
    const value = session.evalSource(source) catch return -2;
    kiwi_embedded_probe_stage = 64;
    const text = session.renderValue(value) catch return -3;

    kiwi_embedded_probe_stage = 65;
    if (text.len > output_capacity) return -4;
    @memcpy(output_ptr[0..text.len], text);
    kiwi_embedded_probe_stage = 100;
    return @intCast(text.len);
}

pub export fn kiwi_embedded_eval_once(
    source_ptr: [*]const u8,
    source_len: usize,
    output_ptr: [*]u8,
    output_capacity: usize,
) isize {
    kiwi_embedded_probe_stage = 40;
    var fixed = initFixedBufferAllocator() orelse return -5;
    const allocator = fixed.allocator();

    kiwi_embedded_probe_stage = 41;
    const session = allocator.create(runtime.Session) catch return -1;
    kiwi_embedded_probe_stage = 42;
    session.initInPlace(allocator) catch {
        allocator.destroy(session);
        return -1;
    };
    defer {
        session.deinit();
        allocator.destroy(session);
    }

    kiwi_embedded_probe_stage = 43;
    const source = source_ptr[0..source_len];
    const value = session.evalSource(source) catch return -2;
    kiwi_embedded_probe_stage = 44;
    const text = session.renderValue(value) catch return -3;
    defer allocator.free(text);

    kiwi_embedded_probe_stage = 45;
    if (text.len > output_capacity) return -4;
    @memcpy(output_ptr[0..text.len], text);
    kiwi_embedded_probe_stage = 100;
    return @intCast(text.len);
}

// Zig emits this compiler-rt helper for riscv32, but ESP-IDF's libgcc does not
// provide it. Keep a local implementation in the embedded archive for ESP links.
pub export fn __floatuntidf(value: u128) f64 {
    const words: *const [4]u32 = @ptrCast(@alignCast(&value));
    const lo = (@as(u64, words[1]) << 32) | @as(u64, words[0]);
    const hi = (@as(u64, words[3]) << 32) | @as(u64, words[2]);

    if (hi == 0 and lo == 0) return 0.0;

    const top_bit: u7 = if (hi != 0)
        64 + @as(u7, @intCast(63 - @clz(hi)))
    else
        @as(u7, @intCast(63 - @clz(lo)));

    if (top_bit <= f64_fraction_bits) return @floatFromInt(lo);

    var exponent = @as(u64, top_bit) + f64_exponent_bias;
    const shift: u7 = @intCast(@as(u64, top_bit) - f64_fraction_bits);
    var mantissa = shiftRight128ToU64(hi, lo, shift);
    if (bit128(hi, lo, shift - 1) and (lowerBitsNonZero128(hi, lo, shift - 1) or (mantissa & 1) != 0)) {
        mantissa += 1;
        if (mantissa == (1 << (f64_fraction_bits + 1))) {
            mantissa >>= 1;
            exponent += 1;
        }
    }

    const bits = (exponent << f64_fraction_bits) | (mantissa & f64_fraction_mask);
    return @bitCast(bits);
}

fn shiftRight128ToU64(hi: u64, lo: u64, shift: u7) u64 {
    if (shift == 0) return lo;
    if (shift < 64) return (lo >> @intCast(shift)) | (hi << @intCast(64 - shift));
    if (shift == 64) return hi;
    return hi >> @intCast(shift - 64);
}

fn bit128(hi: u64, lo: u64, index: u7) bool {
    if (index < 64) return ((lo >> @intCast(index)) & 1) != 0;
    return ((hi >> @intCast(index - 64)) & 1) != 0;
}

fn lowerBitsNonZero128(hi: u64, lo: u64, bit_count: u7) bool {
    if (bit_count == 0) return false;
    if (bit_count < 64) return (lo & ((@as(u64, 1) << @intCast(bit_count)) - 1)) != 0;
    if (bit_count == 64) return lo != 0;
    return lo != 0 or (hi & ((@as(u64, 1) << @intCast(bit_count - 64)) - 1)) != 0;
}
