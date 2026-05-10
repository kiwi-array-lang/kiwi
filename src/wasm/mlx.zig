const std = @import("std");
const c = @import("c.zig").c;

pub const backend_kind = .wasm_bridge;
pub const supports_full_ops = false;

pub const Error = error{
    MlxFailure,
    InvalidDevice,
    UnsupportedType,
};

pub const DevicePreference = enum {
    auto,
    cpu,
    gpu,

    pub fn parse(text: []const u8) ?DevicePreference {
        if (std.mem.eql(u8, text, "auto")) return .auto;
        if (std.mem.eql(u8, text, "cpu")) return .cpu;
        if (std.mem.eql(u8, text, "gpu")) return .gpu;
        return null;
    }

    pub fn label(self: DevicePreference) []const u8 {
        return switch (self) {
            .auto => "auto",
            .cpu => "cpu",
            .gpu => "gpu",
        };
    }
};

pub const NamedArray = struct {
    name: []u8,
    array: Array,
};

pub const HotGradKind = enum(c_int) {
    square = 1,
    cube = 2,
    sumsq = 3,
};

const AxisOp = enum(c_int) {
    add = 0,
    mul = 1,
    min = 2,
    max = 3,
};

pub const LoweredProgramTag = enum(u8) {
    param = 1,
    constant = 2,
    stack = 3,
    monad = 4,
    dyad = 5,
    reduce_builtin = 6,
    reduce_seeded_builtin = 7,
    scan_builtin = 8,
    scan_seeded_builtin = 9,
    index = 10,
    select = 11,
};

pub const LoweredProgramInstr = extern struct {
    tag: u8,
    op: u8,
    reserved: u16 = 0,
    a: u32,
    b: u32,
    c: u32,
};

pub fn check(code: i32) Error!void {
    if (code != 0) return error.MlxFailure;
}

extern "bridge" fn kiwi_bridge_context_init(preference: i32) i32;
extern "bridge" fn kiwi_bridge_context_deinit() void;
extern "bridge" fn kiwi_bridge_array_ndim(handle: u32) u32;
extern "bridge" fn kiwi_bridge_array_shape_dim(handle: u32, index: u32) i32;
extern "bridge" fn kiwi_bridge_array_clone(handle: u32) u32;
extern "bridge" fn kiwi_bridge_array_release(handle: u32) void;
extern "bridge" fn kiwi_bridge_array_eval(handle: u32) i32;
extern "bridge" fn kiwi_bridge_scalar_bool(value: u32) u32;
extern "bridge" fn kiwi_bridge_scalar_i32(value: i32) u32;
extern "bridge" fn kiwi_bridge_scalar_f32(value: f32) u32;
extern "bridge" fn kiwi_bridge_array_bool(data_ptr: u32, dims_ptr: u32, ndim: u32) u32;
extern "bridge" fn kiwi_bridge_array_i32(data_ptr: u32, dims_ptr: u32, ndim: u32) u32;
extern "bridge" fn kiwi_bridge_array_f32(data_ptr: u32, dims_ptr: u32, ndim: u32) u32;
extern "bridge" fn kiwi_bridge_item_bool(handle: u32) i32;
extern "bridge" fn kiwi_bridge_item_i32(handle: u32) i32;
extern "bridge" fn kiwi_bridge_item_f32(handle: u32) f32;
extern "bridge" fn kiwi_bridge_read_bool(handle: u32, out_ptr: u32) i32;
extern "bridge" fn kiwi_bridge_read_i32(handle: u32, out_ptr: u32) i32;
extern "bridge" fn kiwi_bridge_read_f32(handle: u32, out_ptr: u32) i32;
extern "bridge" fn kiwi_bridge_add(left: u32, right: u32) u32;
extern "bridge" fn kiwi_bridge_sub(left: u32, right: u32) u32;
extern "bridge" fn kiwi_bridge_mul(left: u32, right: u32) u32;
extern "bridge" fn kiwi_bridge_div(left: u32, right: u32) u32;
extern "bridge" fn kiwi_bridge_minimum(left: u32, right: u32) u32;
extern "bridge" fn kiwi_bridge_maximum(left: u32, right: u32) u32;
extern "bridge" fn kiwi_bridge_remainder(left: u32, right: u32) u32;
extern "bridge" fn kiwi_bridge_less(left: u32, right: u32) u32;
extern "bridge" fn kiwi_bridge_greater(left: u32, right: u32) u32;
extern "bridge" fn kiwi_bridge_equal(left: u32, right: u32) u32;
extern "bridge" fn kiwi_bridge_power(left: u32, right: u32) u32;
extern "bridge" fn kiwi_bridge_logical_not(value: u32) u32;
extern "bridge" fn kiwi_bridge_negate(value: u32) u32;
extern "bridge" fn kiwi_bridge_exp(value: u32) u32;
extern "bridge" fn kiwi_bridge_log(value: u32) u32;
extern "bridge" fn kiwi_bridge_tanh(value: u32) u32;
extern "bridge" fn kiwi_bridge_sigmoid(value: u32) u32;
extern "bridge" fn kiwi_bridge_sin(value: u32) u32;
extern "bridge" fn kiwi_bridge_cos(value: u32) u32;
extern "bridge" fn kiwi_bridge_floor(value: u32) u32;
extern "bridge" fn kiwi_bridge_cast(value: u32, dtype: i32) u32;
extern "bridge" fn kiwi_bridge_bool_where_indices(value: u32) u32;
extern "bridge" fn kiwi_bridge_arange_stop(stop: i32) u32;
extern "bridge" fn kiwi_bridge_arange(start: f64, stop: f64, step: f64, dtype: i32) u32;
extern "bridge" fn kiwi_bridge_transpose(value: u32) u32;
extern "bridge" fn kiwi_bridge_matmul(left: u32, right: u32) u32;
extern "bridge" fn kiwi_bridge_sum_all(value: u32) u32;
extern "bridge" fn kiwi_bridge_reduce_axis0(value: u32, op: i32) u32;
extern "bridge" fn kiwi_bridge_cumsum0_inclusive(value: u32) u32;
extern "bridge" fn kiwi_bridge_scan_axis0_inclusive(value: u32, op: i32) u32;
extern "bridge" fn kiwi_bridge_argsort(value: u32) u32;
extern "bridge" fn kiwi_bridge_reverse0(value: u32) u32;
extern "bridge" fn kiwi_bridge_slice(value: u32, start_ptr: u32, stop_ptr: u32, strides_ptr: u32, ndim: u32) u32;
extern "bridge" fn kiwi_bridge_take(value: u32, indices: u32) u32;
extern "bridge" fn kiwi_bridge_take_axis(value: u32, indices: u32, axis: i32) u32;
extern "bridge" fn kiwi_bridge_zeros(dims_ptr: u32, ndim: u32, dtype: i32) u32;
extern "bridge" fn kiwi_bridge_reshape_1d(value: u32, dim0: i32) u32;
extern "bridge" fn kiwi_bridge_reshape_2d(value: u32, dim0: i32, dim1: i32) u32;
extern "bridge" fn kiwi_bridge_concat(handles_ptr: u32, count: u32) u32;
extern "bridge" fn kiwi_bridge_stack(handles_ptr: u32, count: u32) u32;

const MaxRank = 4;
const BridgeReadFn = *const fn (u32, u32) callconv(.c) i32;

fn unsupported() Error {
    return error.MlxFailure;
}

fn product(dims: []const i32) usize {
    var total: usize = 1;
    for (dims) |dim| total *= @intCast(dim);
    return total;
}

fn ptrAsU32(ptr: anytype) u32 {
    return @intCast(@intFromPtr(ptr));
}

pub const Context = struct {
    resolved: DevicePreference,

    pub fn init(preference: DevicePreference) Error!Context {
        try check(kiwi_bridge_context_init(@intFromEnum(preference)));
        return .{ .resolved = switch (preference) {
            .auto, .gpu => .gpu,
            .cpu => .cpu,
        } };
    }

    pub fn deinit(self: *Context) void {
        _ = self;
        kiwi_bridge_context_deinit();
    }
};

pub const Array = struct {
    handle: u32,
    dtype_tag: c.mlx_dtype,
    ndim_value: u8,
    size_value: usize,
    shape_storage: [MaxRank]i32 = .{ 0, 0, 0, 0 },

    fn init(handle: u32, dtype_tag: c.mlx_dtype, dims: []const i32) Error!Array {
        if (handle == 0) return error.MlxFailure;
        if (dims.len > MaxRank) return error.MlxFailure;
        var out = Array{
            .handle = handle,
            .dtype_tag = dtype_tag,
            .ndim_value = @intCast(dims.len),
            .size_value = if (dims.len == 0) 1 else product(dims),
        };
        for (dims, 0..) |dim, idx| out.shape_storage[idx] = dim;
        return out;
    }

    fn initFromHandle(handle: u32, dtype_tag: c.mlx_dtype) Error!Array {
        if (handle == 0) return error.MlxFailure;
        const rank: usize = @intCast(kiwi_bridge_array_ndim(handle));
        if (rank > MaxRank) return error.MlxFailure;
        var out = Array{
            .handle = handle,
            .dtype_tag = dtype_tag,
            .ndim_value = @intCast(rank),
            .size_value = if (rank == 0) 1 else 1,
        };
        var idx: usize = 0;
        while (idx < rank) : (idx += 1) {
            const dim = kiwi_bridge_array_shape_dim(handle, @intCast(idx));
            out.shape_storage[idx] = dim;
            out.size_value *= @intCast(dim);
        }
        return out;
    }

    fn unaryResult(handle: u32, source: Array, target_dtype: ?c.mlx_dtype) Error!Array {
        return initFromHandle(handle, target_dtype orelse source.dtype_tag);
    }

    fn binaryResult(handle: u32, left: Array, right: Array, dtype_tag: c.mlx_dtype) Error!Array {
        _ = left;
        _ = right;
        return initFromHandle(handle, dtype_tag);
    }

    fn readSlice(self: Array, allocator: std.mem.Allocator, comptime T: type, bridge: BridgeReadFn) (Error || std.mem.Allocator.Error)![]T {
        const out = try allocator.alloc(T, self.size());
        errdefer allocator.free(out);
        try check(bridge(self.handle, ptrAsU32(out.ptr)));
        return out;
    }

    pub fn empty() Array {
        return .{
            .handle = 0,
            .dtype_tag = c.MLX_FLOAT32,
            .ndim_value = 0,
            .size_value = 0,
        };
    }

    pub fn clone(self: Array) Error!Array {
        if (self.handle == 0) return empty();
        return initFromHandle(kiwi_bridge_array_clone(self.handle), self.dtype_tag);
    }

    pub fn deinit(self: *Array) void {
        if (self.handle != 0) kiwi_bridge_array_release(self.handle);
        self.* = empty();
    }

    pub fn isValid(self: Array) bool {
        return self.handle != 0;
    }

    pub fn fromBool(value: bool) Array {
        return init(kiwi_bridge_scalar_bool(@intFromBool(value)), c.MLX_BOOL, &.{}) catch unreachable;
    }

    pub fn fromInt(value: i32) Array {
        return init(kiwi_bridge_scalar_i32(value), c.MLX_INT32, &.{}) catch unreachable;
    }

    pub fn fromFloat(value: f32) Array {
        return init(kiwi_bridge_scalar_f32(value), c.MLX_FLOAT32, &.{}) catch unreachable;
    }

    pub fn fromBoolSlice(data: []const bool, dims: []const i32) Array {
        return init(kiwi_bridge_array_bool(ptrAsU32(data.ptr), ptrAsU32(dims.ptr), @intCast(dims.len)), c.MLX_BOOL, dims) catch unreachable;
    }

    pub fn fromBoolSliceChecked(data: []const bool, dims: []const i32) Error!Array {
        return init(kiwi_bridge_array_bool(ptrAsU32(data.ptr), ptrAsU32(dims.ptr), @intCast(dims.len)), c.MLX_BOOL, dims);
    }

    pub fn fromIntSlice(data: []const i32, dims: []const i32) Array {
        return init(kiwi_bridge_array_i32(ptrAsU32(data.ptr), ptrAsU32(dims.ptr), @intCast(dims.len)), c.MLX_INT32, dims) catch unreachable;
    }

    pub fn fromIntSliceChecked(data: []const i32, dims: []const i32) Error!Array {
        return init(kiwi_bridge_array_i32(ptrAsU32(data.ptr), ptrAsU32(dims.ptr), @intCast(dims.len)), c.MLX_INT32, dims);
    }

    pub fn fromFloatSlice(data: []const f32, dims: []const i32) Array {
        return init(kiwi_bridge_array_f32(ptrAsU32(data.ptr), ptrAsU32(dims.ptr), @intCast(dims.len)), c.MLX_FLOAT32, dims) catch unreachable;
    }

    pub fn fromFloatSliceChecked(data: []const f32, dims: []const i32) Error!Array {
        return init(kiwi_bridge_array_f32(ptrAsU32(data.ptr), ptrAsU32(dims.ptr), @intCast(dims.len)), c.MLX_FLOAT32, dims);
    }

    pub fn ndim(self: *const Array) usize {
        return self.ndim_value;
    }

    pub fn size(self: *const Array) usize {
        return self.size_value;
    }

    pub fn shape(self: *const Array) []const i32 {
        return self.shape_storage[0..self.ndim_value];
    }

    pub fn dtype(self: *const Array) c.mlx_dtype {
        return self.dtype_tag;
    }

    pub fn isScalar(self: *const Array) bool {
        return self.ndim() == 0;
    }

    pub fn eval(self: Array) Error!void {
        try check(kiwi_bridge_array_eval(self.handle));
    }

    pub fn boolItem(self: Array) Error!bool {
        return kiwi_bridge_item_bool(self.handle) != 0;
    }

    pub fn intItem(self: Array) Error!i64 {
        return kiwi_bridge_item_i32(self.handle);
    }

    pub fn floatItem(self: Array) Error!f64 {
        return kiwi_bridge_item_f32(self.handle);
    }

    pub fn readBools(self: Array, allocator: std.mem.Allocator) (Error || std.mem.Allocator.Error)![]bool {
        return self.readSlice(allocator, bool, kiwi_bridge_read_bool);
    }

    pub fn readInts(self: Array, allocator: std.mem.Allocator) (Error || std.mem.Allocator.Error)![]i32 {
        return self.readSlice(allocator, i32, kiwi_bridge_read_i32);
    }

    pub fn readFloats(self: Array, allocator: std.mem.Allocator) (Error || std.mem.Allocator.Error)![]f32 {
        return self.readSlice(allocator, f32, kiwi_bridge_read_f32);
    }

    pub fn add(ctx: Context, left: Array, right: Array) Error!Array {
        _ = ctx;
        return binaryResult(kiwi_bridge_add(left.handle, right.handle), left, right, if (left.dtype() == c.MLX_FLOAT32 or right.dtype() == c.MLX_FLOAT32) c.MLX_FLOAT32 else c.MLX_INT32);
    }

    pub fn sub(ctx: Context, left: Array, right: Array) Error!Array {
        _ = ctx;
        return binaryResult(kiwi_bridge_sub(left.handle, right.handle), left, right, if (left.dtype() == c.MLX_FLOAT32 or right.dtype() == c.MLX_FLOAT32) c.MLX_FLOAT32 else c.MLX_INT32);
    }

    pub fn mul(ctx: Context, left: Array, right: Array) Error!Array {
        _ = ctx;
        return binaryResult(kiwi_bridge_mul(left.handle, right.handle), left, right, if (left.dtype() == c.MLX_FLOAT32 or right.dtype() == c.MLX_FLOAT32) c.MLX_FLOAT32 else c.MLX_INT32);
    }

    pub fn div(ctx: Context, left: Array, right: Array) Error!Array {
        _ = ctx;
        return binaryResult(kiwi_bridge_div(left.handle, right.handle), left, right, c.MLX_FLOAT32);
    }

    pub fn power(ctx: Context, left: Array, right: Array) Error!Array {
        _ = ctx;
        return binaryResult(kiwi_bridge_power(left.handle, right.handle), left, right, if (left.dtype() == c.MLX_FLOAT32 or right.dtype() == c.MLX_FLOAT32) c.MLX_FLOAT32 else c.MLX_INT32);
    }

    pub fn minimum(ctx: Context, left: Array, right: Array) Error!Array {
        _ = ctx;
        return binaryResult(kiwi_bridge_minimum(left.handle, right.handle), left, right, if (left.dtype() == c.MLX_FLOAT32 or right.dtype() == c.MLX_FLOAT32) c.MLX_FLOAT32 else if (left.dtype() == c.MLX_BOOL and right.dtype() == c.MLX_BOOL) c.MLX_BOOL else c.MLX_INT32);
    }

    pub fn maximum(ctx: Context, left: Array, right: Array) Error!Array {
        _ = ctx;
        return binaryResult(kiwi_bridge_maximum(left.handle, right.handle), left, right, if (left.dtype() == c.MLX_FLOAT32 or right.dtype() == c.MLX_FLOAT32) c.MLX_FLOAT32 else if (left.dtype() == c.MLX_BOOL and right.dtype() == c.MLX_BOOL) c.MLX_BOOL else c.MLX_INT32);
    }

    pub fn logicalAnd(ctx: Context, left: Array, right: Array) Error!Array {
        return minimum(ctx, left, right);
    }

    pub fn logicalOr(ctx: Context, left: Array, right: Array) Error!Array {
        return maximum(ctx, left, right);
    }

    pub fn remainder(ctx: Context, left: Array, right: Array) Error!Array {
        _ = ctx;
        return binaryResult(kiwi_bridge_remainder(left.handle, right.handle), left, right, if (left.dtype() == c.MLX_FLOAT32 or right.dtype() == c.MLX_FLOAT32) c.MLX_FLOAT32 else c.MLX_INT32);
    }

    pub fn less(ctx: Context, left: Array, right: Array) Error!Array {
        _ = ctx;
        return binaryResult(kiwi_bridge_less(left.handle, right.handle), left, right, c.MLX_BOOL);
    }

    pub fn greater(ctx: Context, left: Array, right: Array) Error!Array {
        _ = ctx;
        return binaryResult(kiwi_bridge_greater(left.handle, right.handle), left, right, c.MLX_BOOL);
    }

    pub fn equal(ctx: Context, left: Array, right: Array) Error!Array {
        _ = ctx;
        return binaryResult(kiwi_bridge_equal(left.handle, right.handle), left, right, c.MLX_BOOL);
    }

    pub fn logicalNot(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return unaryResult(kiwi_bridge_logical_not(value.handle), value, c.MLX_BOOL);
    }

    pub fn negate(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return unaryResult(kiwi_bridge_negate(value.handle), value, null);
    }

    pub fn exp(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return unaryResult(kiwi_bridge_exp(value.handle), value, c.MLX_FLOAT32);
    }

    pub fn log(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return unaryResult(kiwi_bridge_log(value.handle), value, c.MLX_FLOAT32);
    }

    pub fn tanh(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return unaryResult(kiwi_bridge_tanh(value.handle), value, c.MLX_FLOAT32);
    }

    pub fn sigmoid(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return unaryResult(kiwi_bridge_sigmoid(value.handle), value, c.MLX_FLOAT32);
    }

    pub fn sin(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return unaryResult(kiwi_bridge_sin(value.handle), value, c.MLX_FLOAT32);
    }

    pub fn cos(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return unaryResult(kiwi_bridge_cos(value.handle), value, c.MLX_FLOAT32);
    }

    pub fn sqrt(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        _ = value;
        return unsupported();
    }

    pub fn floor(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return unaryResult(kiwi_bridge_floor(value.handle), value, value.dtype());
    }

    pub fn cast(ctx: Context, value: Array, target_dtype: c.mlx_dtype) Error!Array {
        _ = ctx;
        return unaryResult(kiwi_bridge_cast(value.handle, target_dtype), value, target_dtype);
    }

    pub fn arangeStop(ctx: Context, stop: i32) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_arange_stop(stop), c.MLX_INT32);
    }

    pub fn arange(ctx: Context, start: f64, stop: f64, step: f64, target_dtype: c.mlx_dtype) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_arange(start, stop, step, target_dtype), target_dtype);
    }

    pub fn transpose(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        if (value.ndim() != 2) return error.MlxFailure;
        return initFromHandle(kiwi_bridge_transpose(value.handle), value.dtype());
    }

    pub fn swapAxes(ctx: Context, value: Array, axis1: i32, axis2: i32) Error!Array {
        if (axis1 == axis2) return value.clone();

        const rank_i32: i32 = @intCast(value.ndim());
        if (rank_i32 <= 1) return value.clone();

        const norm_axis1 = if (axis1 < 0) axis1 + rank_i32 else axis1;
        const norm_axis2 = if (axis2 < 0) axis2 + rank_i32 else axis2;
        if (norm_axis1 < 0 or norm_axis1 >= rank_i32) return error.MlxFailure;
        if (norm_axis2 < 0 or norm_axis2 >= rank_i32) return error.MlxFailure;

        if (rank_i32 == 2 and ((norm_axis1 == 0 and norm_axis2 == 1) or (norm_axis1 == 1 and norm_axis2 == 0))) {
            return transpose(ctx, value);
        }

        // The wasm bridge only exposes a plain 2D transpose today.
        return error.MlxFailure;
    }

    pub fn copy(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return value.clone();
    }

    pub fn matmul(ctx: Context, left: Array, right: Array) Error!Array {
        _ = ctx;
        if (left.ndim() != 2 or right.ndim() != 2) return error.MlxFailure;
        if (left.shape()[1] != right.shape()[0]) return error.MlxFailure;
        return initFromHandle(kiwi_bridge_matmul(left.handle, right.handle), c.MLX_FLOAT32);
    }

    pub fn sumAll(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_sum_all(value.handle), if (value.dtype() == c.MLX_BOOL) c.MLX_INT32 else value.dtype());
    }

    pub fn sumAxis0(ctx: Context, value: Array) Error!Array {
        return sumAll(ctx, value);
    }

    pub fn prodAll(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_reduce_axis0(value.handle, @intFromEnum(AxisOp.mul)), if (value.dtype() == c.MLX_BOOL) c.MLX_INT32 else value.dtype());
    }

    pub fn prodAxis0(ctx: Context, value: Array) Error!Array {
        return prodAll(ctx, value);
    }

    pub fn minAll(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_reduce_axis0(value.handle, @intFromEnum(AxisOp.min)), value.dtype());
    }

    pub fn minAxis0(ctx: Context, value: Array) Error!Array {
        return minAll(ctx, value);
    }

    pub fn maxAll(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_reduce_axis0(value.handle, @intFromEnum(AxisOp.max)), value.dtype());
    }

    pub fn maxAxis0(ctx: Context, value: Array) Error!Array {
        return maxAll(ctx, value);
    }

    pub fn cumsum0(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        _ = value;
        return unsupported();
    }

    pub fn cumsum0Inclusive(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_cumsum0_inclusive(value.handle), if (value.dtype() == c.MLX_BOOL) c.MLX_INT32 else value.dtype());
    }

    pub fn cumsum0ReverseInclusive(ctx: Context, value: Array) Error!Array {
        var reversed = try reverse0(ctx, value);
        defer reversed.deinit();
        var suffix = try cumsum0Inclusive(ctx, reversed);
        defer suffix.deinit();
        return reverse0(ctx, suffix);
    }

    pub fn cumprod0Inclusive(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_scan_axis0_inclusive(value.handle, @intFromEnum(AxisOp.mul)), if (value.dtype() == c.MLX_BOOL) c.MLX_INT32 else value.dtype());
    }

    pub fn cummin0Inclusive(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_scan_axis0_inclusive(value.handle, @intFromEnum(AxisOp.min)), value.dtype());
    }

    pub fn cummax0Inclusive(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_scan_axis0_inclusive(value.handle, @intFromEnum(AxisOp.max)), value.dtype());
    }

    pub fn argsort(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_argsort(value.handle), c.MLX_INT32);
    }

    pub fn argmax(ctx: Context, value: Array) Error!Array {
        if (value.ndim() != 1 or value.size() == 0) return error.MlxFailure;
        var sorted = try argsort(ctx, value);
        defer sorted.deinit();
        const items = sorted.readInts(std.heap.wasm_allocator) catch return error.MlxFailure;
        defer std.heap.wasm_allocator.free(items);
        if (items.len == 0) return error.MlxFailure;
        return fromInt(items[items.len - 1]);
    }

    pub fn where(ctx: Context, cond: Array, left: Array, right: Array) Error!Array {
        _ = ctx;
        _ = cond;
        _ = left;
        _ = right;
        return unsupported();
    }

    pub fn boolWhereIndices(ctx: Context, mask: Array) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_bool_where_indices(mask.handle), c.MLX_INT32);
    }

    pub fn reshape(ctx: Context, value: Array, dims: []const i32) Error!Array {
        _ = ctx;
        if (product(dims) != value.size()) return error.MlxFailure;
        return switch (dims.len) {
            1 => initFromHandle(kiwi_bridge_reshape_1d(value.handle, dims[0]), value.dtype()),
            2 => initFromHandle(kiwi_bridge_reshape_2d(value.handle, dims[0], dims[1]), value.dtype()),
            else => error.MlxFailure,
        };
    }

    pub fn slice(ctx: Context, value: Array, start: []const i32, stop: []const i32, strides: []const i32) Error!Array {
        _ = ctx;
        if (start.len != value.ndim() or stop.len != value.ndim() or strides.len != value.ndim()) return error.MlxFailure;
        return initFromHandle(
            kiwi_bridge_slice(
                value.handle,
                ptrAsU32(start.ptr),
                ptrAsU32(stop.ptr),
                ptrAsU32(strides.ptr),
                @intCast(start.len),
            ),
            value.dtype(),
        );
    }

    pub fn take(ctx: Context, value: Array, indices: Array) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_take(value.handle, indices.handle), value.dtype());
    }

    pub fn takeAxis(ctx: Context, value: Array, indices: Array, axis: i32) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_take_axis(value.handle, indices.handle, axis), value.dtype());
    }

    pub fn zeros(ctx: Context, dims: []const i32, target_dtype: c.mlx_dtype) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_zeros(ptrAsU32(dims.ptr), @intCast(dims.len), target_dtype), target_dtype);
    }

    pub fn concat(ctx: Context, arrays: []const Array) Error!Array {
        _ = ctx;
        if (arrays.len < 2) return error.MlxFailure;
        var handles: [32]u32 = undefined;
        if (arrays.len > handles.len) return error.MlxFailure;
        for (arrays, 0..) |arr, idx| handles[idx] = arr.handle;
        return initFromHandle(kiwi_bridge_concat(ptrAsU32(&handles[0]), @intCast(arrays.len)), arrays[0].dtype());
    }

    pub fn stack(ctx: Context, arrays: []const Array) Error!Array {
        _ = ctx;
        if (arrays.len < 2) return error.MlxFailure;
        var handles: [32]u32 = undefined;
        if (arrays.len > handles.len) return error.MlxFailure;
        for (arrays, 0..) |arr, idx| handles[idx] = arr.handle;
        return initFromHandle(kiwi_bridge_stack(ptrAsU32(&handles[0]), @intCast(arrays.len)), arrays[0].dtype());
    }

    pub fn reverse0(ctx: Context, value: Array) Error!Array {
        _ = ctx;
        return initFromHandle(kiwi_bridge_reverse0(value.handle), value.dtype());
    }

    pub fn hotValueAndGrad(input: Array, kind: HotGradKind) Error!struct { value: Array, grad: Array } {
        _ = input;
        _ = kind;
        return unsupported();
    }

    pub fn loweredValueAndGrad(
        program: []const LoweredProgramInstr,
        refs: []const u32,
        consts: []const Array,
        inputs: []const Array,
        root: u32,
        argnum: u32,
    ) (Error || std.mem.Allocator.Error)!struct { value: Array, grad: Array } {
        _ = program;
        _ = refs;
        _ = consts;
        _ = inputs;
        _ = root;
        _ = argnum;
        return unsupported();
    }
};

pub fn loadSafetensors(
    allocator: std.mem.Allocator,
    ctx: Context,
    path: []const u8,
) (Error || std.mem.Allocator.Error)![]NamedArray {
    _ = allocator;
    _ = ctx;
    _ = path;
    return error.MlxFailure;
}

pub fn loadSafetensorTensor(
    allocator: std.mem.Allocator,
    ctx: Context,
    path: []const u8,
    dims: []const i32,
    dtype: c.mlx_dtype,
    data_offset: u64,
) (Error || std.mem.Allocator.Error)!Array {
    _ = allocator;
    _ = ctx;
    _ = path;
    _ = dims;
    _ = dtype;
    _ = data_offset;
    return error.MlxFailure;
}

pub fn saveSafetensors(
    allocator: std.mem.Allocator,
    path: []const u8,
    names: []const []const u8,
    arrays: []const Array,
) (Error || std.mem.Allocator.Error)!void {
    _ = allocator;
    _ = path;
    _ = names;
    _ = arrays;
    return error.MlxFailure;
}

pub fn deinitNamedArrays(allocator: std.mem.Allocator, entries: []NamedArray) void {
    for (entries) |entry| {
        allocator.free(entry.name);
        var array = entry.array;
        array.deinit();
    }
    allocator.free(entries);
}
