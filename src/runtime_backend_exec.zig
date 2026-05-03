const std = @import("std");

fn mlxDtypeIsFloat(comptime api: anytype, dtype: api.c.mlx_dtype) bool {
    return dtype == api.c.MLX_FLOAT16 or
        dtype == api.c.MLX_FLOAT32 or
        dtype == api.c.MLX_FLOAT64 or
        dtype == api.c.MLX_BFLOAT16;
}

fn castMlxBoolArrayTo(
    comptime api: anytype,
    self: *api.Session,
    array: *api.mlx.Array,
    target_dtype: api.c.mlx_dtype,
) api.KError!void {
    if (array.dtype() != api.c.MLX_BOOL) return;
    const ctx = try api.backendContext(self);
    const casted = api.mlx.Array.cast(ctx.*, array.*, target_dtype) catch |err| return api.mapMlxError(err);
    array.deinit();
    array.* = casted;
}

fn scalarLikeBackendArray(comptime api: anytype, array: api.mlx.Array) bool {
    return array.ndim() == 0 or (array.ndim() == 1 and array.shape()[0] == 1);
}

fn preserveFloatArrayDtypeWithScalar(
    comptime api: anytype,
    self: *api.Session,
    left_arr: *api.mlx.Array,
    right_arr: *api.mlx.Array,
) api.KError!void {
    const left_scalar = scalarLikeBackendArray(api, left_arr.*);
    const right_scalar = scalarLikeBackendArray(api, right_arr.*);
    if (left_scalar == right_scalar) return;

    const target_dtype = if (left_scalar) right_arr.dtype() else left_arr.dtype();
    if (!mlxDtypeIsFloat(api, target_dtype)) return;

    const source = if (left_scalar) left_arr else right_arr;
    if (source.dtype() == target_dtype) return;

    const ctx = try api.backendContext(self);
    const casted = api.mlx.Array.cast(ctx.*, source.*, target_dtype) catch |err| return api.mapMlxError(err);
    source.deinit();
    source.* = casted;
}

fn sliceMlxAxis0Range(
    comptime api: anytype,
    self: *api.Session,
    value: api.mlx.Array,
    start: usize,
    count: usize,
) api.KError!api.mlx.Array {
    const ndim = value.ndim();
    if (ndim == 0) return error.Type;
    var start_buf: [api.numeric_array_max_rank]i32 = [_]i32{0} ** api.numeric_array_max_rank;
    var stop_buf: [api.numeric_array_max_rank]i32 = [_]i32{0} ** api.numeric_array_max_rank;
    var stride_buf: [api.numeric_array_max_rank]i32 = [_]i32{1} ** api.numeric_array_max_rank;
    const shape = value.shape();
    for (0..ndim) |idx| stop_buf[idx] = shape[idx];
    start_buf[0] = std.math.cast(i32, start) orelse return error.Unsupported;
    stop_buf[0] = std.math.cast(i32, start + count) orelse return error.Unsupported;
    return api.mlx.Array.slice(
        (try api.backendContext(self)).*,
        value,
        start_buf[0..ndim],
        stop_buf[0..ndim],
        stride_buf[0..ndim],
    ) catch |err| return api.mapMlxError(err);
}

fn backendTensor(
    comptime api: anytype,
    self: *api.Session,
    value: api.Value,
) api.KError!api.mlx.Array {
    if (api.valueNumericHandle(value)) |handle| {
        if (api.numericArrayIsTransposeView(handle)) {
            const source = api.numericArrayTransposeSource(handle) orelse return error.Type;
            var source_arr = try backendTensor(api, self, source);
            defer source_arr.deinit();
            const ctx = try api.backendContext(self);
            return api.mlx.Array.transpose(ctx.*, source_arr) catch |err| return api.mapMlxError(err);
        }
        if (api.numericArrayIsReshapeView(handle)) {
            const source = api.numericArrayReshapeSource(handle) orelse return error.Type;
            var source_arr = try backendTensor(api, self, source);
            defer source_arr.deinit();
            const ctx = try api.backendContext(self);
            return api.mlx.Array.reshape(ctx.*, source_arr, handle.shape[0..handle.rank]) catch |err| return api.mapMlxError(err);
        }
        if (api.numericArrayIsFirstAxisSlice(handle)) {
            const source = api.numericArrayFirstAxisSliceSource(handle) orelse return error.Type;
            const start = api.numericArrayFirstAxisSliceRowStart(handle) orelse return error.Type;
            const step = api.numericArrayFirstAxisSliceRowStep(handle) orelse return error.Type;
            const row_count: usize = @intCast(handle.shape[0]);

            var source_arr = try backendTensor(api, self, source);
            defer source_arr.deinit();
            if (source_arr.ndim() == 0) return error.Type;

            if (step == 1) {
                return try sliceMlxAxis0Range(api, self, source_arr, start, row_count);
            }

            const idx_dims = [_]i32{std.math.cast(i32, row_count) orelse return error.Unsupported};
            const indices_buf = try self.allocator.alloc(i32, row_count);
            defer self.allocator.free(indices_buf);
            for (0..row_count) |row| {
                const row_idx_i64 = @as(i64, @intCast(start)) + @as(i64, @intCast(row)) * @as(i64, step);
                if (row_idx_i64 < 0) return error.Type;
                indices_buf[row] = std.math.cast(i32, row_idx_i64) orelse return error.Unsupported;
            }
            var indices = api.mlx.Array.fromIntSlice(indices_buf, &idx_dims);
            defer indices.deinit();
            const ctx = try api.backendContext(self);
            return api.mlx.Array.takeAxis(ctx.*, source_arr, indices, 0) catch |err| return api.mapMlxError(err);
        }
        if (api.numericArrayIsFirstAxisIndex(handle)) {
            const source = api.numericArrayFirstAxisIndexSource(handle) orelse return error.Type;
            const row_indices = api.numericArrayFirstAxisIndexRows(handle) orelse return error.Type;
            const row_count: usize = @intCast(handle.shape[0]);

            var source_arr = try backendTensor(api, self, source);
            defer source_arr.deinit();
            if (source_arr.ndim() == 0) return error.Type;

            const idx_dims = [_]i32{std.math.cast(i32, row_count) orelse return error.Unsupported};
            const indices_buf = try self.allocator.alloc(i32, row_count);
            defer self.allocator.free(indices_buf);
            for (0..row_count) |row| {
                const row_i64 = try api.numericIntAt(row_indices, row);
                if (row_i64 < 0) return error.Type;
                indices_buf[row] = std.math.cast(i32, row_i64) orelse return error.Unsupported;
            }
            var indices = api.mlx.Array.fromIntSlice(indices_buf, &idx_dims);
            defer indices.deinit();
            const ctx = try api.backendContext(self);
            return api.mlx.Array.takeAxis(ctx.*, source_arr, indices, 0) catch |err| return api.mapMlxError(err);
        }
    }
    return try api.materializeBackendArray(self, value);
}

fn dotTensor(
    comptime api: anytype,
    self: *api.Session,
    value: api.Value,
) api.KError!api.mlx.Array {
    var arr = try backendTensor(api, self, value);
    errdefer arr.deinit();
    if (arr.ndim() == 0) return error.Type;
    if (arr.dtype() != api.c.MLX_FLOAT16 and
        arr.dtype() != api.c.MLX_BFLOAT16 and
        arr.dtype() != api.c.MLX_FLOAT32 and
        arr.dtype() != api.c.MLX_FLOAT64)
    {
        const ctx = try api.backendContext(self);
        const casted = api.mlx.Array.cast(ctx.*, arr, api.c.MLX_FLOAT32) catch |err| return api.mapMlxError(err);
        arr.deinit();
        arr = casted;
    }
    return arr;
}

pub fn tryFastBackendMatrixRowFoldEachDerived(
    comptime api: anytype,
    self: *api.Session,
    base: api.Value,
    args: []const api.Value,
) api.KError!?api.Value {
    if (comptime !api.runtime_has_mlx) return null;
    if (args.len != 1) return null;

    const op: api.BuiltinId = if (api.isDerivedBuiltinClosure(base, .fold, .add))
        .add
    else if (api.isDerivedBuiltinClosure(base, .fold, .mul))
        .mul
    else if (api.isDerivedBuiltinClosure(base, .fold, .minimum))
        .minimum
    else if (api.isDerivedBuiltinClosure(base, .fold, .maximum))
        .maximum
    else
        return null;

    return try tryFastBackendMatrixRowFoldBuiltin(api, self, op, args[0]);
}

pub fn tryFastBackendMatrixRowFoldBuiltin(
    comptime api: anytype,
    self: *api.Session,
    op: api.BuiltinId,
    matrix: api.Value,
) api.KError!?api.Value {
    if (comptime !api.runtime_has_mlx) return null;
    switch (op) {
        .add, .mul, .minimum, .maximum => {},
        else => return null,
    }

    const shape = api.valueNumericMatrixShape(matrix) orelse return null;
    if (shape.rows == 0 or shape.cols == 0) return null;

    const has_backend_residency = api.isBackendArrayValue(matrix) or api.hasBackendRealization(matrix);
    const planned_backend: api.DenseExecBackend = switch (self.dense_backend_override) {
        .host => return null,
        .mlx => .mlx,
        .auto => if (has_backend_residency) .mlx else return null,
    };
    const actual_backend = api.actualDenseBackend(self, true, planned_backend);
    if (actual_backend != .mlx) return null;

    var arr = try backendTensor(api, self, matrix);
    defer arr.deinit();
    if (arr.ndim() != 2) return null;
    try castMlxBoolArrayTo(api, self, &arr, api.c.MLX_INT32);

    const ctx = try api.backendContext(self);
    var transposed = api.mlx.Array.transpose(ctx.*, arr) catch |err| return api.mapMlxError(err);
    defer transposed.deinit();

    const out = switch (op) {
        .add => api.mlx.Array.sumAxis0(ctx.*, transposed) catch |err| return api.mapMlxError(err),
        .mul => api.mlx.Array.prodAxis0(ctx.*, transposed) catch |err| return api.mapMlxError(err),
        .minimum => api.mlx.Array.minAxis0(ctx.*, transposed) catch |err| return api.mapMlxError(err),
        .maximum => api.mlx.Array.maxAxis0(ctx.*, transposed) catch |err| return api.mapMlxError(err),
        else => return null,
    };
    api.noteDensePlanDecision(
        self,
        .reduce,
        planned_backend,
        actual_backend,
        if (has_backend_residency) .already_backend_resident else .large_problem,
    );
    return try api.wrapManagedBackendArray(self, out);
}

fn tryFastBackendReduceUnary(
    comptime api: anytype,
    self: *api.Session,
    op: api.BuiltinId,
    args: []const api.Value,
) api.KError!?api.Value {
    if (args.len != 1) return null;
    const vector = args[0];
    if (api.planDenseReduceScanBackend(self, false, vector) != .mlx) return null;

    var arr = try backendTensor(api, self, vector);
    defer arr.deinit();
    if (arr.ndim() == 0) return null;
    if (@as(usize, @intCast(arr.shape()[0])) == 0) {
        return switch (op) {
            .mul => null,
            else => error.Type,
        };
    }
    try castMlxBoolArrayTo(api, self, &arr, api.c.MLX_INT32);

    const ctx = try api.backendContext(self);
    const out = switch (op) {
        .add => api.mlx.Array.sumAxis0(ctx.*, arr) catch |err| return api.mapMlxError(err),
        .mul => api.mlx.Array.prodAxis0(ctx.*, arr) catch |err| return api.mapMlxError(err),
        .minimum => api.mlx.Array.minAxis0(ctx.*, arr) catch |err| return api.mapMlxError(err),
        .maximum => api.mlx.Array.maxAxis0(ctx.*, arr) catch |err| return api.mapMlxError(err),
        else => return null,
    };
    return try api.wrapManagedBackendArray(self, out);
}

fn tryFastBackendAddFoldScan(
    comptime api: anytype,
    self: *api.Session,
    args: []const api.Value,
    collect: bool,
) api.KError!?api.Value {
    if (args.len != 1) return null;
    const vector = args[0];
    if (api.planDenseReduceScanBackend(self, collect, vector) != .mlx) return null;

    var arr = try backendTensor(api, self, vector);
    defer arr.deinit();
    if (arr.ndim() == 0) return null;
    if (@as(usize, @intCast(arr.shape()[0])) == 0) return null;
    try castMlxBoolArrayTo(api, self, &arr, api.c.MLX_INT32);

    const ctx = try api.backendContext(self);
    const out = if (collect)
        api.mlx.Array.cumsum0Inclusive(ctx.*, arr) catch |err| return api.mapMlxError(err)
    else
        api.mlx.Array.sumAxis0(ctx.*, arr) catch |err| return api.mapMlxError(err);
    return try api.wrapManagedBackendArray(self, out);
}

fn tryFastBackendSubFold(
    comptime api: anytype,
    self: *api.Session,
    args: []const api.Value,
) api.KError!?api.Value {
    if (args.len == 0 or args.len > 2) return null;
    const vector = args[args.len - 1];
    if (api.planDenseReduceScanBackend(self, false, vector) != .mlx) return null;

    var arr = try backendTensor(api, self, vector);
    defer arr.deinit();
    if (arr.ndim() == 0) return null;
    const outer_len: usize = @intCast(arr.shape()[0]);
    if (args.len == 1 and outer_len == 0) return error.Type;
    if (outer_len <= 1) return null;

    try castMlxBoolArrayTo(api, self, &arr, api.c.MLX_INT32);

    const ctx = try api.backendContext(self);
    const reduced = if (args.len == 2) blk: {
        var total = api.mlx.Array.sumAxis0(ctx.*, arr) catch |err| return api.mapMlxError(err);
        errdefer total.deinit();
        var seed = try backendTensor(api, self, args[0]);
        defer seed.deinit();
        try castMlxBoolArrayTo(api, self, &seed, api.c.MLX_INT32);
        break :blk api.mlx.Array.sub(ctx.*, seed, total) catch |err| return api.mapMlxError(err);
    } else blk: {
        var head = try sliceMlxAxis0Range(api, self, arr, 0, 1);
        defer head.deinit();
        var tail = try sliceMlxAxis0Range(api, self, arr, 1, outer_len - 1);
        defer tail.deinit();
        var first = api.mlx.Array.sumAxis0(ctx.*, head) catch |err| return api.mapMlxError(err);
        errdefer first.deinit();
        var rest = api.mlx.Array.sumAxis0(ctx.*, tail) catch |err| return api.mapMlxError(err);
        errdefer rest.deinit();
        break :blk api.mlx.Array.sub(ctx.*, first, rest) catch |err| return api.mapMlxError(err);
    };
    return try api.wrapManagedBackendArray(self, reduced);
}

pub fn tryFastBackendFoldDerived(
    comptime api: anytype,
    self: *api.Session,
    base: api.Value,
    args: []const api.Value,
    collect: bool,
) api.KError!?api.Value {
    if (base.tag() != .builtin) return null;
    return switch (base.asBuiltin()) {
        .add => try tryFastBackendAddFoldScan(api, self, args, collect),
        .sub => if (!collect) try tryFastBackendSubFold(api, self, args) else null,
        .mul, .minimum, .maximum => if (!collect) try tryFastBackendReduceUnary(api, self, base.asBuiltin(), args) else null,
        else => null,
    };
}

pub fn tryFastBackendNumericVectorFindValue(
    comptime api: anytype,
    self: *api.Session,
    left: api.Value,
    right: api.Value,
) api.KError!?api.Value {
    if (comptime !api.runtime_has_mlx) return null;
    if (api.valueNumericMode(left) == null or api.valueNumericMatrixShape(left) != null) return null;
    const left_len = api.numericFlatLen(left) orelse return null;
    const query_len = api.numericRowQueryLen(right) orelse return null;

    const has_backend_residency = api.isBackendArrayValue(left) or
        api.isBackendArrayValue(right) or
        api.hasBackendRealization(left) or
        api.hasBackendRealization(right);
    if (!has_backend_residency) return null;

    var left_arr = try backendTensor(api, self, left);
    defer left_arr.deinit();
    if (left_arr.ndim() != 1) return null;

    var right_arr = try backendTensor(api, self, right);
    defer right_arr.deinit();
    if (query_len == 1) {
        if (right_arr.ndim() > 1) return null;
        if (right_arr.ndim() == 1) {
            const shape = right_arr.shape();
            if (shape.len != 1 or shape[0] != 1) return error.Type;
        }
        const ctx = try api.backendContext(self);
        var mask = api.mlx.Array.equal(ctx.*, left_arr, right_arr) catch |err| return api.mapMlxError(err);
        defer mask.deinit();

        var indices = api.mlx.Array.boolWhereIndices(ctx.*, mask) catch |err| return api.mapMlxError(err);
        defer indices.deinit();
        if (indices.ndim() != 1) return error.Type;
        const match_count: usize = @intCast(indices.shape()[0]);
        if (match_count == 0) return try api.intValue(self, @intCast(left_len));

        var first = try sliceMlxAxis0Range(api, self, indices, 0, 1);
        defer first.deinit();
        const first_items = first.readInts(self.allocator) catch |err| return api.mapMlxError(err);
        defer self.allocator.free(first_items);
        if (first_items.len != 1) return error.Internal;
        return try api.intValue(self, first_items[0]);
    }

    const query_len_i32 = std.math.cast(i32, query_len) orelse return error.Unsupported;
    if (query_len == 0) {
        const dims = [_]i32{query_len_i32};
        const empty = api.mlx.Array.fromIntSlice(&[_]i32{}, &dims);
        return try api.wrapManagedBackendArray(self, empty);
    }
    const miss_index = std.math.cast(i32, left_len) orelse return error.Unsupported;
    if (left_len == 0) {
        const miss_items = try self.allocator.alloc(i32, query_len);
        defer self.allocator.free(miss_items);
        @memset(miss_items, miss_index);
        const dims = [_]i32{query_len_i32};
        const misses = api.mlx.Array.fromIntSlice(miss_items, &dims);
        return try api.wrapManagedBackendArray(self, misses);
    }

    const left_len_i32 = std.math.cast(i32, left_len) orelse return error.Unsupported;
    const ctx = try api.backendContext(self);
    var left_col = api.mlx.Array.reshape(ctx.*, left_arr, &[_]i32{ left_len_i32, 1 }) catch |err| return api.mapMlxError(err);
    defer left_col.deinit();

    var right_row = blk: {
        switch (right_arr.ndim()) {
            1 => break :blk api.mlx.Array.reshape(ctx.*, right_arr, &[_]i32{ 1, query_len_i32 }) catch |err| return api.mapMlxError(err),
            2 => {
                const shape = right_arr.shape();
                if (shape.len != 2 or shape[0] != 1 or shape[1] != query_len_i32) return error.Type;
                break :blk right_arr.clone() catch |err| return api.mapMlxError(err);
            },
            else => return error.Type,
        }
    };
    defer right_row.deinit();

    var mask = api.mlx.Array.equal(ctx.*, left_col, right_row) catch |err| return api.mapMlxError(err);
    defer mask.deinit();

    var row_indices = api.mlx.Array.arangeStop(ctx.*, left_len_i32) catch |err| return api.mapMlxError(err);
    defer row_indices.deinit();
    var row_index_col = api.mlx.Array.reshape(ctx.*, row_indices, &[_]i32{ left_len_i32, 1 }) catch |err| return api.mapMlxError(err);
    defer row_index_col.deinit();
    const miss_value = api.mlx.Array.fromInt(miss_index);
    var selected = api.mlx.Array.where(ctx.*, mask, row_index_col, miss_value) catch |err| return api.mapMlxError(err);
    defer selected.deinit();

    const first = api.mlx.Array.minAxis0(ctx.*, selected) catch |err| return api.mapMlxError(err);
    return try api.wrapManagedBackendArray(self, first);
}

pub fn tryFastBackendArgmaxValue(
    comptime api: anytype,
    self: *api.Session,
    value: api.Value,
) api.KError!?api.Value {
    if (comptime !api.runtime_has_mlx) return null;
    if (api.valueNumericMode(value) == null or api.valueNumericMatrixShape(value) != null) return null;
    const len = api.numericFlatLen(value) orelse return null;
    if (len == 0) return error.Type;
    if (len == 1) return try api.intValue(self, 0);

    const has_backend_residency = api.isBackendArrayValue(value) or api.hasBackendRealization(value);
    if (!has_backend_residency) return null;

    const materialize_start_ns: u64 = if (comptime api.enable_probe_instrumentation)
        @intCast(std.time.nanoTimestamp())
    else
        0;
    var arr = try backendTensor(api, self, value);
    defer arr.deinit();
    if (arr.ndim() != 1) return null;
    const kernel_start_ns: u64 = if (comptime api.enable_probe_instrumentation)
        @intCast(std.time.nanoTimestamp())
    else
        0;

    const ctx = try api.backendContext(self);
    var out = api.mlx.Array.argmax(ctx.*, arr) catch |err| return api.mapMlxError(err);
    defer out.deinit();

    const idx = out.intItem() catch |err| return api.mapMlxError(err);
    if (comptime api.enable_probe_instrumentation) {
        const finish_ns: u64 = @intCast(std.time.nanoTimestamp());
        self.debug_backend_argmax_fast_count += 1;
        self.debug_backend_argmax_materialize_ns +%= kernel_start_ns - materialize_start_ns;
        self.debug_backend_argmax_kernel_ns +%= finish_ns - kernel_start_ns;
    }
    return try api.intValue(self, idx);
}

pub fn transposeBackendMatrixValue(
    comptime api: anytype,
    self: *api.Session,
    value: api.Value,
) api.KError!api.Value {
    var input = try backendTensor(api, self, value);
    defer input.deinit();
    const ctx = try api.backendContext(self);
    const out = api.mlx.Array.transpose(ctx.*, input) catch |err| return api.mapMlxError(err);
    return try api.wrapManagedBackendArray(self, out);
}

pub fn transposeBackendSwapAxesValue(
    comptime api: anytype,
    self: *api.Session,
    value: api.Value,
    axis1: i32,
    axis2: i32,
) api.KError!api.Value {
    var input = try backendTensor(api, self, value);
    defer input.deinit();
    const ctx = try api.backendContext(self);
    const out = api.mlx.Array.swapAxes(ctx.*, input, axis1, axis2) catch |err| return api.mapMlxError(err);
    return try api.wrapManagedBackendArray(self, out);
}

pub fn applyBackendMatmulValues(
    comptime api: anytype,
    self: *api.Session,
    left: api.Value,
    right: api.Value,
) api.KError!api.Value {
    var left_arr = try dotTensor(api, self, left);
    defer left_arr.deinit();
    var right_arr = try dotTensor(api, self, right);
    defer right_arr.deinit();

    const ctx = try api.backendContext(self);
    const out = api.mlx.Array.matmul(ctx.*, left_arr, right_arr) catch |err| return api.mapMlxError(err);
    return try api.wrapManagedBackendArray(self, out);
}

pub fn applyBackendArrayMonad(
    comptime api: anytype,
    self: *api.Session,
    op: api.BuiltinId,
    value: api.Value,
) api.KError!api.Value {
    var input = try backendTensor(api, self, value);
    errdefer input.deinit();
    if (op == .add) return try api.wrapManagedBackendArray(self, input);
    defer input.deinit();

    const out = switch (op) {
        .add => unreachable,
        .sub => blk: {
            try castMlxBoolArrayTo(api, self, &input, api.c.MLX_INT32);
            const ctx = try api.backendContext(self);
            break :blk api.mlx.Array.negate(ctx.*, input) catch |err| return api.mapMlxError(err);
        },
        .div => blk: {
            try castMlxBoolArrayTo(api, self, &input, api.c.MLX_FLOAT32);
            const ctx = try api.backendContext(self);
            break :blk api.mlx.Array.sqrt(ctx.*, input) catch |err| return api.mapMlxError(err);
        },
        .mul => return error.Unsupported,
        .exp => blk: {
            try castMlxBoolArrayTo(api, self, &input, api.c.MLX_FLOAT32);
            const ctx = try api.backendContext(self);
            break :blk api.mlx.Array.exp(ctx.*, input) catch |err| return api.mapMlxError(err);
        },
        .log => blk: {
            try castMlxBoolArrayTo(api, self, &input, api.c.MLX_FLOAT32);
            const ctx = try api.backendContext(self);
            break :blk api.mlx.Array.log(ctx.*, input) catch |err| return api.mapMlxError(err);
        },
        .sin => blk: {
            try castMlxBoolArrayTo(api, self, &input, api.c.MLX_FLOAT32);
            const ctx = try api.backendContext(self);
            break :blk api.mlx.Array.sin(ctx.*, input) catch |err| return api.mapMlxError(err);
        },
        .cos => blk: {
            try castMlxBoolArrayTo(api, self, &input, api.c.MLX_FLOAT32);
            const ctx = try api.backendContext(self);
            break :blk api.mlx.Array.cos(ctx.*, input) catch |err| return api.mapMlxError(err);
        },
        .tanh => blk: {
            try castMlxBoolArrayTo(api, self, &input, api.c.MLX_FLOAT32);
            const ctx = try api.backendContext(self);
            break :blk api.mlx.Array.tanh(ctx.*, input) catch |err| return api.mapMlxError(err);
        },
        .sigmoid => blk: {
            try castMlxBoolArrayTo(api, self, &input, api.c.MLX_FLOAT32);
            const ctx = try api.backendContext(self);
            break :blk api.mlx.Array.sigmoid(ctx.*, input) catch |err| return api.mapMlxError(err);
        },
        else => return error.Unsupported,
    };
    return try api.wrapManagedBackendArray(self, out);
}

pub fn applyBackendArrayDyad(
    comptime api: anytype,
    self: *api.Session,
    op: api.BuiltinId,
    left: api.Value,
    right: api.Value,
) api.KError!api.Value {
    var left_arr = try backendTensor(api, self, left);
    defer left_arr.deinit();
    var right_arr = try backendTensor(api, self, right);
    defer right_arr.deinit();

    const use_float = op == .div or mlxDtypeIsFloat(api, left_arr.dtype()) or mlxDtypeIsFloat(api, right_arr.dtype());
    try castMlxBoolArrayTo(api, self, &left_arr, if (use_float) api.c.MLX_FLOAT32 else api.c.MLX_INT32);
    try castMlxBoolArrayTo(api, self, &right_arr, if (use_float) api.c.MLX_FLOAT32 else api.c.MLX_INT32);
    try preserveFloatArrayDtypeWithScalar(api, self, &left_arr, &right_arr);

    const ctx = try api.backendContext(self);
    if (api.rowwiseMatrixVectorDyad(left, right)) |rowwise| {
        if (rowwise.matrix_on_left) {
            const reshaped = api.mlx.Array.reshape(ctx.*, right_arr, &[_]i32{ @intCast(rowwise.rows), 1 }) catch |err| return api.mapMlxError(err);
            right_arr.deinit();
            right_arr = reshaped;
        } else {
            const reshaped = api.mlx.Array.reshape(ctx.*, left_arr, &[_]i32{ @intCast(rowwise.rows), 1 }) catch |err| return api.mapMlxError(err);
            left_arr.deinit();
            left_arr = reshaped;
        }
    }

    const out = switch (op) {
        .add => api.mlx.Array.add(ctx.*, left_arr, right_arr) catch |err| return api.mapMlxError(err),
        .sub => api.mlx.Array.sub(ctx.*, left_arr, right_arr) catch |err| return api.mapMlxError(err),
        .mul => api.mlx.Array.mul(ctx.*, left_arr, right_arr) catch |err| return api.mapMlxError(err),
        .div => api.mlx.Array.div(ctx.*, left_arr, right_arr) catch |err| return api.mapMlxError(err),
        .pow => api.mlx.Array.power(ctx.*, left_arr, right_arr) catch |err| return api.mapMlxError(err),
        .minimum => api.mlx.Array.minimum(ctx.*, left_arr, right_arr) catch |err| return api.mapMlxError(err),
        .maximum => api.mlx.Array.maximum(ctx.*, left_arr, right_arr) catch |err| return api.mapMlxError(err),
        .less => api.mlx.Array.less(ctx.*, left_arr, right_arr) catch |err| return api.mapMlxError(err),
        .more => api.mlx.Array.greater(ctx.*, left_arr, right_arr) catch |err| return api.mapMlxError(err),
        .equal => api.mlx.Array.equal(ctx.*, left_arr, right_arr) catch |err| return api.mapMlxError(err),
        else => return error.Unsupported,
    };
    return try api.wrapManagedBackendArray(self, out);
}
