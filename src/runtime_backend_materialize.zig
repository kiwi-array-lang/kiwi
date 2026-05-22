pub fn createHostDenseArrayFromBackendArray(
    comptime api: anytype,
    self: *api.Session,
    owner: api.HeapOwner,
    array: api.mlx.Array,
) api.KError!*api.HostDenseArray {
    var owned = array.clone() catch |err| return api.mapMlxError(err);
    defer owned.deinit();
    owned.eval() catch |err| return api.mapMlxError(err);

    const len = api.backendArrayElementCount(owned);
    return switch (owned.dtype()) {
        api.c.MLX_BOOL => blk: {
            const items = owned.readBools(self.allocator) catch |err| return api.mapMlxError(err);
            defer self.allocator.free(items);

            var asc = true;
            var dsc = true;
            var saw_zero = items.len == 0;
            var saw_one = false;
            if (items.len != 0) {
                if (items[0]) saw_one = true else saw_zero = true;
                var prev = items[0];
                for (items[1..]) |item| {
                    if (item) saw_one = true else saw_zero = true;
                    if (@intFromBool(prev) > @intFromBool(item)) asc = false;
                    if (@intFromBool(prev) < @intFromBool(item)) dsc = false;
                    prev = item;
                }
            }

            var out = try api.allocOwnedHostIntResult(self, owner, .bit, len);
            for (items, 0..) |item, idx| try api.hostIntResultSet(&out, idx, @intFromBool(item));
            const host = api.hostIntResultArrayPtr(&out);
            api.bitClearUnusedTail(host.storage.bit, host.logical_len);
            api.hostDenseSetFlags(host, api.host_dense_flag_normalized | api.orderFlagsFromMonotonic(asc, dsc));
            api.hostDenseSetCachedIntRange(host, .{
                .min = if (saw_zero) 0 else 1,
                .max = if (saw_one) 1 else 0,
            });
            break :blk host;
        },
        api.c.MLX_INT32 => blk: {
            const items = owned.readInts(self.allocator) catch |err| return api.mapMlxError(err);
            defer self.allocator.free(items);

            var values = try self.allocator.alloc(i64, items.len);
            defer self.allocator.free(values);
            for (items, 0..) |item, idx| values[idx] = item;

            const analysis = api.analyzeIntSlice(values);
            var out = try api.allocOwnedHostIntResult(self, owner, analysis.kind, len);
            for (values, 0..) |item, idx| try api.hostIntResultSet(&out, idx, item);
            const host = api.hostIntResultArrayPtr(&out);
            if (analysis.kind == .bit) api.bitClearUnusedTail(host.storage.bit, host.logical_len);
            api.hostDenseSetFlags(host, analysis.flags);
            api.hostDenseSetCachedIntRange(host, analysis.range);
            break :blk host;
        },
        api.c.MLX_UINT32 => blk: {
            const items = owned.readUInt32s(self.allocator) catch |err| return api.mapMlxError(err);
            defer self.allocator.free(items);

            var values = try self.allocator.alloc(i64, items.len);
            defer self.allocator.free(values);
            for (items, 0..) |item, idx| values[idx] = item;

            const analysis = api.analyzeIntSlice(values);
            var out = try api.allocOwnedHostIntResult(self, owner, analysis.kind, len);
            for (values, 0..) |item, idx| try api.hostIntResultSet(&out, idx, item);
            const host = api.hostIntResultArrayPtr(&out);
            if (analysis.kind == .bit) api.bitClearUnusedTail(host.storage.bit, host.logical_len);
            api.hostDenseSetFlags(host, analysis.flags);
            api.hostDenseSetCachedIntRange(host, analysis.range);
            break :blk host;
        },
        api.c.MLX_INT64 => blk: {
            const items = owned.readInt64s(self.allocator) catch |err| return api.mapMlxError(err);
            defer self.allocator.free(items);

            const analysis = api.analyzeIntSlice(items);
            var out = try api.allocOwnedHostIntResult(self, owner, analysis.kind, len);
            for (items, 0..) |item, idx| try api.hostIntResultSet(&out, idx, item);
            const host = api.hostIntResultArrayPtr(&out);
            if (analysis.kind == .bit) api.bitClearUnusedTail(host.storage.bit, host.logical_len);
            api.hostDenseSetFlags(host, analysis.flags);
            api.hostDenseSetCachedIntRange(host, analysis.range);
            break :blk host;
        },
        api.c.MLX_FLOAT16, api.c.MLX_FLOAT32, api.c.MLX_BFLOAT16 => blk: {
            const items = owned.readFloats(self.allocator) catch |err| return api.mapMlxError(err);
            defer self.allocator.free(items);

            const out = try api.allocOwnedHostFloat32Result(self, owner, len);
            @memcpy(out.items, items);
            const analysis = api.analyzeFloatSlice32(out.items);
            api.hostDenseSetFlags(out.array, analysis.flags);
            break :blk out.array;
        },
        api.c.MLX_FLOAT64 => blk: {
            const items = owned.readFloat64s(self.allocator) catch |err| return api.mapMlxError(err);
            defer self.allocator.free(items);

            const out = try api.allocOwnedHostFloatResult(self, owner, len);
            @memcpy(out.items, items);
            const analysis = api.analyzeFloatSlice(out.items);
            api.hostDenseSetFlags(out.array, analysis.flags);
            break :blk out.array;
        },
        else => error.Type,
    };
}

pub fn tryEnsureManagedBackendRealizationForHandle(
    comptime api: anytype,
    self: *api.Session,
    handle: *api.NumericArray,
) api.KError!?*api.BackendArray {
    if (handle.mlx) |array| {
        if (comptime api.enable_probe_instrumentation) self.debug_mlx_realization_reuse_count += 1;
        api.touchBackendAttachment(self, handle);
        return array;
    }
    if (handle.header.owner != .managed) return null;
    const had_host_attachment = handle.host != null;
    var materialized = if (api.numericArrayIsRangeIota(handle))
        try api.createBackendArrayFromRangeIota(self, handle)
    else if (api.numericArrayIsFlatSlice(handle))
        try api.createBackendArrayFromFlatSlice(self, handle)
    else if (api.numericArrayIsFlatConcat(handle))
        try api.createBackendArrayFromFlatConcat(self, handle)
    else if (api.numericArrayIsFlatSegments(handle))
        try api.createBackendArrayFromFlatSegments(self, handle)
    else if (api.numericArrayIsFirstAxisSlice(handle))
        try api.createBackendArrayFromFirstAxisSlice(self, handle)
    else if (api.numericArrayIsFirstAxisIndex(handle))
        try api.createBackendArrayFromFirstAxisIndex(self, handle)
    else if (api.numericArrayIsFirstAxisConcat(handle))
        try api.createBackendArrayFromFirstAxisConcat(self, handle)
    else if (api.numericArrayIsReshapeView(handle))
        try api.createBackendArrayFromReshapeView(self, handle)
    else if (api.numericArrayIsTransposeView(handle))
        try api.createBackendArrayFromTransposeView(self, handle)
    else blk: {
        const host = if (handle.host) |array|
            array
        else
            (try api.tryEnsureHostRealizationForHandle(self, handle) orelse return null);
        break :blk try api.createBackendArrayFromHostArray(self, host);
    };
    errdefer materialized.deinit();
    const owned = try api.allocManagedBackendPayload(self, materialized);
    materialized = api.mlx.Array.empty();
    if (comptime api.enable_probe_instrumentation) {
        self.debug_mlx_realization_count += 1;
        if (handle.structural != .materialized) {
            self.debug_structural_mlx_realization_count += 1;
            self.debug_numeric_structural_mlx_realization_counts[@intFromEnum(handle.structural)] += 1;
        }
        if (had_host_attachment) self.debug_mlx_promotion_count += 1;
    }
    handle.mlx = owned;
    api.syncNumericArrayChildren(handle);
    api.touchBackendAttachment(self, handle);
    if (handle.host != null) api.enforceDualResidentBudget(self, handle);
    return owned;
}

pub fn tryEnsureManagedBackendRealization(
    comptime api: anytype,
    self: *api.Session,
    value: api.Value,
) api.KError!?*api.BackendArray {
    const handle = api.mutableNumericHandle(value) orelse return null;
    return try api.tryEnsureManagedBackendRealizationForHandle(self, handle);
}
