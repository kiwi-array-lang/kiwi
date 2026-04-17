const zig_builtin = @import("builtin");
const std = @import("std");

pub const Dtype = enum {
    bool,
    u8,
    u16,
    u32,
    u64,
    i8,
    i16,
    i32,
    i64,
    f16,
    f32,
    f64,
    bf16,
    complex64,
    f8_e4m3,

    pub fn byteSize(self: Dtype) u64 {
        return switch (self) {
            .bool, .u8, .i8, .f8_e4m3 => 1,
            .u16, .i16, .f16, .bf16 => 2,
            .u32, .i32, .f32 => 4,
            .u64, .i64, .f64, .complex64 => 8,
        };
    }
};

pub const TensorEntry = struct {
    name: []u8,
    dtype: Dtype,
    shape: []i32,
    absolute_offset: u64,
    byte_len: u64,
};

pub const ParsedFile = struct {
    entries: []TensorEntry,

    pub fn deinit(self: *ParsedFile, allocator: std.mem.Allocator) void {
        for (self.entries) |entry| {
            allocator.free(entry.name);
            allocator.free(entry.shape);
        }
        allocator.free(self.entries);
        self.* = .{ .entries = &.{} };
    }
};

pub const Error = error{
    InvalidHeader,
    InvalidMetadata,
    InvalidTensorEntry,
    UnsupportedDtype,
    UnsupportedShape,
    UnsupportedTarget,
};

pub const ParseFileHeaderError = if (zig_builtin.target.cpu.arch == .wasm32)
    Error || std.mem.Allocator.Error
else
    Error || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError || std.fs.File.StatError;

fn openPathForRead(path: []const u8) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) return std.fs.openFileAbsolute(path, .{});
    return std.fs.cwd().openFile(path, .{});
}

pub fn parseFileHeader(allocator: std.mem.Allocator, path: []const u8) ParseFileHeaderError!ParsedFile {
    if (comptime zig_builtin.target.cpu.arch == .wasm32) {
        return error.UnsupportedTarget;
    }

    const file = try openPathForRead(path);
    defer file.close();

    const file_size = (try file.stat()).size;

    var header_len_buf: [8]u8 = undefined;
    if (try file.readAll(&header_len_buf) != header_len_buf.len) return error.InvalidHeader;
    const header_len = std.mem.readInt(u64, &header_len_buf, .little);
    if (header_len == 0 or header_len >= max_json_header_len) return error.InvalidHeader;

    const payload_offset = std.math.add(u64, 8, header_len) catch return error.InvalidHeader;
    if (payload_offset > file_size) return error.InvalidHeader;

    const header_bytes = try allocator.alloc(u8, header_len);
    defer allocator.free(header_bytes);
    if (try file.readAll(header_bytes) != header_bytes.len) return error.InvalidHeader;

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, header_bytes, .{}) catch return error.InvalidMetadata;
    defer parsed.deinit();

    const metadata = switch (parsed.value) {
        .object => |object| object,
        else => return error.InvalidMetadata,
    };

    var entries = std.ArrayList(TensorEntry).empty;
    defer {
        for (entries.items) |entry| {
            allocator.free(entry.name);
            allocator.free(entry.shape);
        }
        entries.deinit(allocator);
    }

    var it = metadata.iterator();
    while (it.next()) |item| {
        const name = item.key_ptr.*;
        const value = item.value_ptr.*;

        if (std.mem.eql(u8, name, "__metadata__")) {
            switch (value) {
                .object, .null => {},
                else => return error.InvalidMetadata,
            }
            continue;
        }

        try entries.append(allocator, try parseTensorEntry(allocator, name, value, payload_offset, file_size));
    }

    const owned = try entries.toOwnedSlice(allocator);
    std.sort.block(TensorEntry, owned, {}, struct {
        fn lessThan(_: void, left: TensorEntry, right: TensorEntry) bool {
            return std.mem.order(u8, left.name, right.name) == .lt;
        }
    }.lessThan);
    return .{ .entries = owned };
}

const max_json_header_len: u64 = 100_000_000;

fn parseTensorEntry(
    allocator: std.mem.Allocator,
    name: []const u8,
    value: std.json.Value,
    payload_offset: u64,
    file_size: u64,
) (Error || std.mem.Allocator.Error)!TensorEntry {
    const object = switch (value) {
        .object => |object| object,
        else => return error.InvalidTensorEntry,
    };

    const dtype_value = object.get("dtype") orelse return error.InvalidTensorEntry;
    const shape_value = object.get("shape") orelse return error.InvalidTensorEntry;
    const offsets_value = object.get("data_offsets") orelse return error.InvalidTensorEntry;

    const dtype_name = switch (dtype_value) {
        .string => |text| text,
        else => return error.InvalidTensorEntry,
    };
    const dtype = parseDtype(dtype_name) orelse return error.UnsupportedDtype;

    const shape = try parseShape(allocator, shape_value);
    errdefer allocator.free(shape);

    const elem_count = try shapeElementCount(shape);
    const byte_len = std.math.mul(u64, elem_count, dtype.byteSize()) catch return error.InvalidTensorEntry;

    const offsets = switch (offsets_value) {
        .array => |array| array.items,
        else => return error.InvalidTensorEntry,
    };
    if (offsets.len != 2) return error.InvalidTensorEntry;

    const relative_start = try jsonU64(offsets[0]);
    const relative_end = try jsonU64(offsets[1]);
    if (relative_end < relative_start) return error.InvalidTensorEntry;
    if (relative_end - relative_start != byte_len) return error.InvalidTensorEntry;

    const absolute_offset = std.math.add(u64, payload_offset, relative_start) catch return error.InvalidTensorEntry;
    const absolute_end = std.math.add(u64, payload_offset, relative_end) catch return error.InvalidTensorEntry;
    if (absolute_end > file_size) return error.InvalidTensorEntry;

    return .{
        .name = try allocator.dupe(u8, name),
        .dtype = dtype,
        .shape = shape,
        .absolute_offset = absolute_offset,
        .byte_len = byte_len,
    };
}

fn parseShape(allocator: std.mem.Allocator, value: std.json.Value) (Error || std.mem.Allocator.Error)![]i32 {
    const items = switch (value) {
        .array => |array| array.items,
        else => return error.InvalidTensorEntry,
    };

    const shape = try allocator.alloc(i32, items.len);
    errdefer allocator.free(shape);

    for (items, 0..) |item, idx| {
        const dim = try jsonU64(item);
        if (dim > std.math.maxInt(i32)) return error.UnsupportedShape;
        shape[idx] = @intCast(dim);
    }
    return shape;
}

fn shapeElementCount(shape: []const i32) Error!u64 {
    var out: u64 = 1;
    for (shape) |dim| {
        out = std.math.mul(u64, out, @intCast(dim)) catch return error.InvalidTensorEntry;
    }
    return out;
}

fn jsonU64(value: std.json.Value) Error!u64 {
    return switch (value) {
        .integer => |integer| blk: {
            if (integer < 0) return error.InvalidTensorEntry;
            break :blk @intCast(integer);
        },
        else => error.InvalidTensorEntry,
    };
}

fn parseDtype(text: []const u8) ?Dtype {
    if (std.mem.eql(u8, text, "BOOL")) return .bool;
    if (std.mem.eql(u8, text, "U8")) return .u8;
    if (std.mem.eql(u8, text, "U16")) return .u16;
    if (std.mem.eql(u8, text, "U32")) return .u32;
    if (std.mem.eql(u8, text, "U64")) return .u64;
    if (std.mem.eql(u8, text, "I8")) return .i8;
    if (std.mem.eql(u8, text, "I16")) return .i16;
    if (std.mem.eql(u8, text, "I32")) return .i32;
    if (std.mem.eql(u8, text, "I64")) return .i64;
    if (std.mem.eql(u8, text, "F16")) return .f16;
    if (std.mem.eql(u8, text, "F32")) return .f32;
    if (std.mem.eql(u8, text, "F64")) return .f64;
    if (std.mem.eql(u8, text, "BF16")) return .bf16;
    if (std.mem.eql(u8, text, "C64")) return .complex64;
    if (std.mem.eql(u8, text, "F8_E4M3")) return .f8_e4m3;
    return null;
}
