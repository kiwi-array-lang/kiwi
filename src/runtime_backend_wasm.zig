pub fn wasmAcceleratorArrayInfo(
    comptime api: anytype,
    self: *api.Session,
    value: api.Value,
) api.KError!?api.WasmArrayInfo {
    if (comptime api.mlx.backend_kind != .webgpu) return null;
    const payload = try api.wasmAcceleratorPayload(self, value) orelse return null;

    var info = api.WasmArrayInfo{
        .handle = payload.array.handle,
        .dtype = payload.array.dtype(),
        .ndim = @intCast(payload.array.ndim()),
    };
    for (payload.array.shape(), 0..) |dim, idx| info.shape[idx] = dim;
    return info;
}
