const std = @import("std");

pub fn renderBackendArray(
    comptime api: anytype,
    self: *api.Session,
    array: *const api.BackendArray,
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

    if (shape.len == 1) {
        return switch (owned.dtype()) {
            api.c.MLX_INT32, api.c.MLX_INT64, api.c.MLX_UINT32 => blk: {
                const items = try owned.readInts(self.allocator);
                defer self.allocator.free(items);
                var out = std.ArrayList(u8).empty;
                defer out.deinit(self.allocator);
                for (items, 0..) |item, idx| {
                    if (idx != 0) try out.append(self.allocator, ' ');
                    try out.writer(self.allocator).print("{d}", .{item});
                }
                break :blk try out.toOwnedSlice(self.allocator);
            },
            api.c.MLX_FLOAT16, api.c.MLX_FLOAT32, api.c.MLX_FLOAT64, api.c.MLX_BFLOAT16 => blk: {
                const items = try owned.readFloats(self.allocator);
                defer self.allocator.free(items);
                var out = std.ArrayList(u8).empty;
                defer out.deinit(self.allocator);
                for (items, 0..) |item, idx| {
                    if (idx != 0) try out.append(self.allocator, ' ');
                    const part = try api.formatFloat(self.allocator, item);
                    defer self.allocator.free(part);
                    try out.appendSlice(self.allocator, part);
                }
                break :blk try out.toOwnedSlice(self.allocator);
            },
            api.c.MLX_BOOL => blk: {
                const items = try owned.readBools(self.allocator);
                defer self.allocator.free(items);
                var out = std.ArrayList(u8).empty;
                defer out.deinit(self.allocator);
                for (items) |item| try out.append(self.allocator, if (item) '1' else '0');
                try out.append(self.allocator, 'b');
                break :blk try out.toOwnedSlice(self.allocator);
            },
            else => error.Type,
        };
    }

    if (shape.len == 2) {
        const rows: usize = @intCast(shape[0]);
        const cols: usize = @intCast(shape[1]);
        return switch (owned.dtype()) {
            api.c.MLX_BOOL => blk: {
                const items = try owned.readBools(self.allocator);
                defer self.allocator.free(items);
                var out = std.ArrayList(u8).empty;
                defer out.deinit(self.allocator);
                for (0..rows) |row| {
                    if (row != 0) try out.append(self.allocator, '\n');
                    const base = row * cols;
                    for (0..cols) |col| try out.append(self.allocator, if (items[base + col]) '1' else '0');
                    try out.append(self.allocator, 'b');
                }
                break :blk try out.toOwnedSlice(self.allocator);
            },
            api.c.MLX_INT32, api.c.MLX_INT64, api.c.MLX_UINT32 => blk: {
                const items = try owned.readInts(self.allocator);
                defer self.allocator.free(items);
                var out = std.ArrayList(u8).empty;
                defer out.deinit(self.allocator);
                for (0..rows) |row| {
                    if (row != 0) try out.append(self.allocator, '\n');
                    const base = row * cols;
                    for (0..cols) |col| {
                        if (col != 0) try out.append(self.allocator, ' ');
                        try out.writer(self.allocator).print("{d}", .{items[base + col]});
                    }
                }
                break :blk try out.toOwnedSlice(self.allocator);
            },
            api.c.MLX_FLOAT16, api.c.MLX_FLOAT32, api.c.MLX_FLOAT64, api.c.MLX_BFLOAT16 => blk: {
                const items = try owned.readFloats(self.allocator);
                defer self.allocator.free(items);
                var out = std.ArrayList(u8).empty;
                defer out.deinit(self.allocator);
                for (0..rows) |row| {
                    if (row != 0) try out.append(self.allocator, '\n');
                    const base = row * cols;
                    for (0..cols) |col| {
                        if (col != 0) try out.append(self.allocator, ' ');
                        const part = try api.formatFloat(self.allocator, items[base + col]);
                        defer self.allocator.free(part);
                        try out.appendSlice(self.allocator, part);
                    }
                }
                break :blk try out.toOwnedSlice(self.allocator);
            },
            else => error.Type,
        };
    }

    return std.fmt.allocPrint(self.allocator, "<array {d}d>", .{shape.len});
}
