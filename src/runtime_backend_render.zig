const std = @import("std");

const PrototypeKind = enum(u8) {
    int,
    float,
};

fn shapeDim(dim: i32) anyerror!usize {
    if (dim < 0) return error.Internal;
    return @intCast(dim);
}

fn shapeElementCount(shape: []const i32) anyerror!usize {
    var total: usize = 1;
    for (shape) |dim| {
        total = std.math.mul(usize, total, try shapeDim(dim)) catch return error.Unsupported;
    }
    return total;
}

fn appendPrototypeFlatVector(allocator: std.mem.Allocator, out: *std.ArrayList(u8), len: usize, kind: PrototypeKind) !void {
    if (len == 0) {
        try out.appendSlice(allocator, if (kind == .float) "0#0.0" else "!0");
        return;
    }
    if (len == 1) try out.append(allocator, ',');
    for (0..len) |idx| {
        if (idx != 0) try out.append(allocator, ' ');
        try out.appendSlice(allocator, if (kind == .float) "0.0" else "0");
    }
}

fn appendPrototypeShape(allocator: std.mem.Allocator, out: *std.ArrayList(u8), shape: []const i32, kind: PrototypeKind) anyerror!void {
    if (shape.len <= 1) {
        const len: usize = if (shape.len == 0) 1 else try shapeDim(shape[0]);
        try appendPrototypeFlatVector(allocator, out, len, kind);
        return;
    }

    const first = try shapeDim(shape[0]);
    if (first == 0) {
        try out.appendSlice(allocator, "0#,");
        try appendPrototypeShape(allocator, out, shape[1..], kind);
        return;
    }
    if (first == 1) {
        try out.append(allocator, ',');
        try appendPrototypeShape(allocator, out, shape[1..], kind);
        return;
    }

    try out.append(allocator, '(');
    for (0..first) |idx| {
        if (idx != 0) try out.append(allocator, ';');
        try appendPrototypeShape(allocator, out, shape[1..], kind);
    }
    try out.append(allocator, ')');
}

fn appendFlatIntVector(allocator: std.mem.Allocator, out: *std.ArrayList(u8), items: []const i32, base: usize, len: usize) anyerror!void {
    if (len == 0) {
        try out.appendSlice(allocator, "!0");
        return;
    }
    if (base + len > items.len) return error.Internal;
    if (len == 1) try out.append(allocator, ',');
    for (0..len) |idx| {
        if (idx != 0) try out.append(allocator, ' ');
        try out.writer(allocator).print("{d}", .{items[base + idx]});
    }
}

fn appendFlatFloatVector(
    comptime api: anytype,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    items: []const f32,
    base: usize,
    len: usize,
) anyerror!void {
    if (len == 0) {
        try out.appendSlice(allocator, "0#0.0");
        return;
    }
    if (base + len > items.len) return error.Internal;
    if (len == 1) try out.append(allocator, ',');
    for (0..len) |idx| {
        if (idx != 0) try out.append(allocator, ' ');
        const part = try api.formatFloat(allocator, items[base + idx]);
        defer allocator.free(part);
        try out.appendSlice(allocator, part);
    }
}

fn appendFlatBoolLiteralVector(allocator: std.mem.Allocator, out: *std.ArrayList(u8), items: []const bool, base: usize, len: usize) anyerror!void {
    if (len == 0) {
        try out.appendSlice(allocator, "!0");
        return;
    }
    if (base + len > items.len) return error.Internal;
    if (len == 1) try out.append(allocator, ',');
    for (0..len) |idx| try out.append(allocator, if (items[base + idx]) '1' else '0');
    try out.append(allocator, 'b');
}

fn appendFlatBoolNumericVector(allocator: std.mem.Allocator, out: *std.ArrayList(u8), items: []const bool, base: usize, len: usize) anyerror!void {
    if (len == 0) {
        try out.appendSlice(allocator, "!0");
        return;
    }
    if (base + len > items.len) return error.Internal;
    if (len == 1) try out.append(allocator, ',');
    for (0..len) |idx| {
        if (idx != 0) try out.append(allocator, ' ');
        try out.writer(allocator).print("{d}", .{@intFromBool(items[base + idx])});
    }
}

fn appendShape(
    comptime Item: type,
    comptime appendFlatVector: anytype,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    items: []const Item,
    shape: []const i32,
    base: usize,
    top_level: bool,
    prototype_kind: PrototypeKind,
) anyerror!void {
    if (shape.len <= 1) {
        const len: usize = if (shape.len == 0) 1 else try shapeDim(shape[0]);
        try appendFlatVector(allocator, out, items, base, len);
        return;
    }

    const first = try shapeDim(shape[0]);
    if (first == 0) {
        try out.appendSlice(allocator, "0#,");
        try appendPrototypeShape(allocator, out, shape[1..], prototype_kind);
        return;
    }
    if (first == 1) {
        try out.append(allocator, ',');
        try appendShape(Item, appendFlatVector, allocator, out, items, shape[1..], base, false, prototype_kind);
        return;
    }

    const block_len = try shapeElementCount(shape[1..]);
    try out.append(allocator, '(');
    for (0..first) |idx| {
        if (idx != 0) {
            if (top_level) {
                try out.appendSlice(allocator, "\n ");
            } else {
                try out.append(allocator, ';');
            }
        }
        try appendShape(Item, appendFlatVector, allocator, out, items, shape[1..], base + idx * block_len, false, prototype_kind);
    }
    try out.append(allocator, ')');
}

fn renderIntItems(self: anytype, shape: []const i32, items: []const i32, top_level: bool) anyerror![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(self.allocator);
    try appendShape(i32, appendFlatIntVector, self.allocator, &out, items, shape, 0, top_level, .int);
    return try out.toOwnedSlice(self.allocator);
}

fn renderFloatItems(comptime api: anytype, self: *api.Session, shape: []const i32, items: []const f32, top_level: bool) anyerror![]u8 {
    const appendFlat = struct {
        fn append(allocator: std.mem.Allocator, out: *std.ArrayList(u8), values: []const f32, base: usize, len: usize) anyerror!void {
            try appendFlatFloatVector(api, allocator, out, values, base, len);
        }
    }.append;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(self.allocator);
    try appendShape(f32, appendFlat, self.allocator, &out, items, shape, 0, top_level, .float);
    return try out.toOwnedSlice(self.allocator);
}

fn renderBoolItems(self: anytype, shape: []const i32, items: []const bool, top_level: bool) anyerror![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(self.allocator);
    if (shape.len == 1) {
        try appendFlatBoolLiteralVector(self.allocator, &out, items, 0, try shapeDim(shape[0]));
    } else {
        try appendShape(bool, appendFlatBoolNumericVector, self.allocator, &out, items, shape, 0, top_level, .int);
    }
    return try out.toOwnedSlice(self.allocator);
}

pub fn renderBackendArray(
    comptime api: anytype,
    self: *api.Session,
    array: *const api.BackendArray,
    top_level: bool,
) anyerror![]u8 {
    var owned = try array.array.clone();
    defer owned.deinit();
    try owned.eval();
    if (owned.ndim() == 0) {
        return switch (owned.dtype()) {
            api.c.MLX_BOOL => self.allocator.dupe(u8, if (try owned.boolItem()) "1b" else "0b"),
            api.c.MLX_INT32, api.c.MLX_INT64, api.c.MLX_UINT32 => std.fmt.allocPrint(self.allocator, "{d}", .{try owned.intItem()}),
            api.c.MLX_FLOAT16, api.c.MLX_FLOAT32, api.c.MLX_FLOAT64, api.c.MLX_BFLOAT16 => api.formatFloat(self.allocator, try owned.floatItem()),
            else => error.Type,
        };
    }

    const shape = try self.allocator.alloc(i32, owned.ndim());
    defer self.allocator.free(shape);
    for (owned.shape(), 0..) |dim, idx| shape[idx] = @intCast(dim);

    return switch (owned.dtype()) {
        api.c.MLX_INT32, api.c.MLX_INT64, api.c.MLX_UINT32 => blk: {
            const items = try owned.readInts(self.allocator);
            defer self.allocator.free(items);
            break :blk try renderIntItems(self, shape, items, top_level);
        },
        api.c.MLX_FLOAT16, api.c.MLX_FLOAT32, api.c.MLX_FLOAT64, api.c.MLX_BFLOAT16 => blk: {
            const items = try owned.readFloats(self.allocator);
            defer self.allocator.free(items);
            break :blk try renderFloatItems(api, self, shape, items, top_level);
        },
        api.c.MLX_BOOL => blk: {
            const items = try owned.readBools(self.allocator);
            defer self.allocator.free(items);
            break :blk try renderBoolItems(self, shape, items, top_level);
        },
        else => error.Type,
    };
}
