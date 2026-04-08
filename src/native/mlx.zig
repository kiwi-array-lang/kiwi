const std = @import("std");
const c = @import("c.zig").c;

extern fn mlxc_hot_value_and_grad(value_res: ?*c.mlx_array, grad_res: *c.mlx_array, input: c.mlx_array, kind: c_int) c_int;
extern fn mlxc_lowered_value_and_grad(
    value_res: ?*c.mlx_array,
    grad_res: *c.mlx_array,
    program: ?[*]const LoweredProgramInstr,
    program_len: usize,
    refs: ?[*]const u32,
    refs_len: usize,
    consts: ?[*]const c.mlx_array,
    consts_len: usize,
    inputs: ?[*]const c.mlx_array,
    inputs_len: usize,
    root: u32,
    argnum: u32,
) c_int;
extern fn mlxc_take_axis(out: *c.mlx_array, value: c.mlx_array, indices: c.mlx_array, axis: c_int, stream: c.mlx_stream) c_int;
extern fn mlxc_where(out: *c.mlx_array, cond: c.mlx_array, left: c.mlx_array, right: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_bool_where_indices(out: *c.mlx_array, mask: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_logical_and(out: *c.mlx_array, left: c.mlx_array, right: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_logical_or(out: *c.mlx_array, left: c.mlx_array, right: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_sum_axis0(out: *c.mlx_array, value: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_prod_axis0(out: *c.mlx_array, value: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_min_axis0(out: *c.mlx_array, value: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_max_axis0(out: *c.mlx_array, value: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_cumprod0_inclusive(out: *c.mlx_array, value: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_cummin0_inclusive(out: *c.mlx_array, value: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_cummax0_inclusive(out: *c.mlx_array, value: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_exp(out: *c.mlx_array, value: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_log(out: *c.mlx_array, value: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_tanh(out: *c.mlx_array, value: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_sigmoid(out: *c.mlx_array, value: c.mlx_array, stream: c.mlx_stream) c_int;
extern fn mlxc_rms_norm(out: *c.mlx_array, value: c.mlx_array, weight: ?*const c.mlx_array, eps: f32, stream: c.mlx_stream) c_int;
extern fn mlxc_set_default_device_type(device_type: c.mlx_device_type, index: c_int) c_int;

pub const Error = error{
    MlxFailure,
    InvalidDevice,
    UnsupportedType,
};

pub const NamedArray = struct {
    name: []u8,
    array: Array,
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

pub const HotGradKind = enum(c_int) {
    square = 1,
    cube = 2,
    sumsq = 3,
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
};

pub const LoweredProgramInstr = extern struct {
    tag: u8,
    op: u8,
    reserved: u16 = 0,
    a: u32,
    b: u32,
    c: u32,
};

pub fn check(code: c_int) Error!void {
    if (code != 0) return error.MlxFailure;
}

pub const Context = struct {
    device: c.mlx_device,
    stream: c.mlx_stream,
    resolved: DevicePreference,

    pub fn init(preference: DevicePreference) Error!Context {
        var device = c.mlx_device_new();
        var stream = c.mlx_stream_new();
        var resolved = preference;
        switch (preference) {
            .auto => {
                try check(c.mlx_get_default_device(&device));
                var ty: c.mlx_device_type = c.MLX_CPU;
                try check(c.mlx_device_get_type(&ty, device));
                if (ty == c.MLX_GPU) {
                    var available = false;
                    try check(c.mlx_device_is_available(&available, device));
                    if (!available) {
                        _ = c.mlx_device_free(device);
                        device = c.mlx_device_new_type(c.MLX_CPU, 0);
                        resolved = .cpu;
                    } else {
                        resolved = .gpu;
                    }
                } else {
                    resolved = .cpu;
                }
            },
            .cpu => {
                device = c.mlx_device_new_type(c.MLX_CPU, 0);
            },
            .gpu => {
                device = c.mlx_device_new_type(c.MLX_GPU, 0);
                var available = false;
                try check(c.mlx_device_is_available(&available, device));
                if (!available) return error.InvalidDevice;
            },
        }
        // Scalar constructors in the C wrapper use MLX's process default device,
        // so keep that global default aligned with the session context we just
        // resolved. Without this, a "cpu" session can still materialize scalars
        // on the default GPU device.
        try check(mlxc_set_default_device_type(switch (resolved) {
            .gpu => c.MLX_GPU,
            else => c.MLX_CPU,
        }, 0));
        stream = c.mlx_stream_new_device(device);
        return .{
            .device = device,
            .stream = stream,
            .resolved = resolved,
        };
    }

    pub fn deinit(self: *Context) void {
        _ = c.mlx_stream_free(self.stream);
        _ = c.mlx_device_free(self.device);
    }
};

pub const Array = struct {
    handle: c.mlx_array,

    fn readSlice(self: Array, allocator: std.mem.Allocator, comptime T: type, data_fn: anytype) (Error || std.mem.Allocator.Error)![]T {
        var copied = c.mlx_array_new();
        errdefer _ = c.mlx_array_free(copied);

        const stream = c.mlx_stream_new();
        defer _ = c.mlx_stream_free(stream);

        try check(c.mlx_contiguous(&copied, self.handle, false, stream));
        const ptr = data_fn(copied) orelse return error.UnsupportedType;
        const out = try allocator.alloc(T, self.size());
        std.mem.copyForwards(T, out, ptr[0..self.size()]);
        _ = c.mlx_array_free(copied);
        return out;
    }

    pub fn empty() Array {
        return .{ .handle = c.mlx_array_new() };
    }

    pub fn clone(self: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_array_set(&out, self.handle));
        return .{ .handle = out };
    }

    pub fn deinit(self: *Array) void {
        if (self.handle.ctx != null) {
            _ = c.mlx_array_free(self.handle);
        }
        self.handle = c.mlx_array_new();
    }

    pub fn isValid(self: Array) bool {
        return self.handle.ctx != null;
    }

    pub fn fromBool(value: bool) Array {
        return .{ .handle = c.mlx_array_new_bool(value) };
    }

    pub fn fromInt(value: i32) Array {
        return .{ .handle = c.mlx_array_new_int(value) };
    }

    pub fn fromFloat(value: f32) Array {
        return .{ .handle = c.mlx_array_new_float32(value) };
    }

    pub fn fromBoolSlice(data: []const bool, dims: []const i32) Array {
        return .{ .handle = c.mlx_array_new_data(data.ptr, dims.ptr, @intCast(dims.len), c.MLX_BOOL) };
    }

    pub fn fromIntSlice(data: []const i32, dims: []const i32) Array {
        return .{ .handle = c.mlx_array_new_data(data.ptr, dims.ptr, @intCast(dims.len), c.MLX_INT32) };
    }

    pub fn fromFloatSlice(data: []const f32, dims: []const i32) Array {
        return .{ .handle = c.mlx_array_new_data(data.ptr, dims.ptr, @intCast(dims.len), c.MLX_FLOAT32) };
    }

    fn fromSliceChecked(data: ?*const anyopaque, dims: []const i32, elem_dtype: c.mlx_dtype) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_array_set_data(&out, data, dims.ptr, @intCast(dims.len), elem_dtype));
        return .{ .handle = out };
    }

    pub fn fromBoolSliceChecked(data: []const bool, dims: []const i32) Error!Array {
        return fromSliceChecked(data.ptr, dims, c.MLX_BOOL);
    }

    pub fn fromIntSliceChecked(data: []const i32, dims: []const i32) Error!Array {
        return fromSliceChecked(data.ptr, dims, c.MLX_INT32);
    }

    pub fn fromFloatSliceChecked(data: []const f32, dims: []const i32) Error!Array {
        return fromSliceChecked(data.ptr, dims, c.MLX_FLOAT32);
    }

    pub fn fromBfloat16BitsSliceChecked(data: []const u16, dims: []const i32) Error!Array {
        return fromSliceChecked(data.ptr, dims, c.MLX_BFLOAT16);
    }

    pub fn fromBytesChecked(data: []const u8, dims: []const i32, elem_dtype: c.mlx_dtype) Error!Array {
        return fromSliceChecked(data.ptr, dims, elem_dtype);
    }

    pub fn ndim(self: Array) usize {
        return c.mlx_array_ndim(self.handle);
    }

    pub fn size(self: Array) usize {
        return c.mlx_array_size(self.handle);
    }

    pub fn shape(self: Array) []const c_int {
        const ptr = c.mlx_array_shape(self.handle);
        return ptr[0..self.ndim()];
    }

    pub fn dtype(self: Array) c.mlx_dtype {
        return c.mlx_array_dtype(self.handle);
    }

    pub fn isScalar(self: Array) bool {
        return self.ndim() == 0;
    }

    pub fn eval(self: Array) Error!void {
        try check(c.mlx_array_eval(self.handle));
    }

    pub fn boolItem(self: Array) Error!bool {
        var out = false;
        try check(c.mlx_array_item_bool(&out, self.handle));
        return out;
    }

    pub fn intItem(self: Array) Error!i64 {
        return switch (self.dtype()) {
            c.MLX_BOOL => if (try self.boolItem()) 1 else 0,
            c.MLX_INT32 => blk: {
                var out: i32 = 0;
                try check(c.mlx_array_item_int32(&out, self.handle));
                break :blk out;
            },
            c.MLX_INT64 => blk: {
                var out: i64 = 0;
                try check(c.mlx_array_item_int64(&out, self.handle));
                break :blk out;
            },
            c.MLX_UINT32 => blk: {
                var out: u32 = 0;
                try check(c.mlx_array_item_uint32(&out, self.handle));
                break :blk @intCast(out);
            },
            else => return error.UnsupportedType,
        };
    }

    pub fn floatItem(self: Array) Error!f64 {
        return switch (self.dtype()) {
            c.MLX_FLOAT32 => blk: {
                var out: f32 = 0;
                try check(c.mlx_array_item_float32(&out, self.handle));
                break :blk out;
            },
            c.MLX_FLOAT64 => blk: {
                var out: f64 = 0;
                try check(c.mlx_array_item_float64(&out, self.handle));
                break :blk out;
            },
            c.MLX_FLOAT16, c.MLX_BFLOAT16 => blk: {
                var casted = try self.castFreshStream(c.MLX_FLOAT32);
                defer casted.deinit();
                var out: f32 = 0;
                try check(c.mlx_array_item_float32(&out, casted.handle));
                break :blk out;
            },
            c.MLX_BOOL, c.MLX_INT32, c.MLX_INT64, c.MLX_UINT32 => @floatFromInt(try self.intItem()),
            else => return error.UnsupportedType,
        };
    }

    pub fn readBools(self: Array, allocator: std.mem.Allocator) (Error || std.mem.Allocator.Error)![]bool {
        return self.readSlice(allocator, bool, c.mlx_array_data_bool);
    }

    pub fn readInts(self: Array, allocator: std.mem.Allocator) (Error || std.mem.Allocator.Error)![]i32 {
        return self.readSlice(allocator, i32, c.mlx_array_data_int32);
    }

    pub fn readFloats(self: Array, allocator: std.mem.Allocator) (Error || std.mem.Allocator.Error)![]f32 {
        return switch (self.dtype()) {
            c.MLX_FLOAT32 => self.readSlice(allocator, f32, c.mlx_array_data_float32),
            c.MLX_FLOAT16, c.MLX_BFLOAT16 => blk: {
                var casted = try self.castFreshStream(c.MLX_FLOAT32);
                defer casted.deinit();
                break :blk casted.readSlice(allocator, f32, c.mlx_array_data_float32);
            },
            else => error.UnsupportedType,
        };
    }

    pub fn add(ctx: Context, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_add(&out, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn sub(ctx: Context, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_subtract(&out, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn mul(ctx: Context, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_multiply(&out, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn div(ctx: Context, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_divide(&out, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn remainder(ctx: Context, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_remainder(&out, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn minimum(ctx: Context, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_minimum(&out, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn maximum(ctx: Context, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_maximum(&out, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn less(ctx: Context, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_less(&out, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn greater(ctx: Context, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_greater(&out, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn equal(ctx: Context, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_equal(&out, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn logicalNot(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_logical_not(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn logicalAnd(ctx: Context, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_logical_and(&out, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn logicalOr(ctx: Context, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_logical_or(&out, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn negate(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_negative(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn sqrt(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_sqrt(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn exp(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_exp(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn log(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_log(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn tanh(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_tanh(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn sigmoid(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_sigmoid(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn rmsNorm(ctx: Context, value: Array, weight: ?Array, eps: f32) Error!Array {
        var out = c.mlx_array_new();
        const weight_handle = if (weight) |w| &w.handle else null;
        try check(mlxc_rms_norm(&out, value.handle, weight_handle, eps, ctx.stream));
        return .{ .handle = out };
    }

    pub fn floor(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_floor(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn cast(ctx: Context, value: Array, target_dtype: c.mlx_dtype) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_astype(&out, value.handle, target_dtype, ctx.stream));
        return .{ .handle = out };
    }

    fn castFreshStream(self: Array, target_dtype: c.mlx_dtype) Error!Array {
        var out = c.mlx_array_new();
        errdefer _ = c.mlx_array_free(out);

        const stream = c.mlx_stream_new();
        defer _ = c.mlx_stream_free(stream);

        try check(c.mlx_astype(&out, self.handle, target_dtype, stream));
        return .{ .handle = out };
    }

    pub fn arangeStop(ctx: Context, stop: i32) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_arange(&out, 0, @floatFromInt(stop), 1, c.MLX_INT32, ctx.stream));
        return .{ .handle = out };
    }

    pub fn arange(ctx: Context, start: f64, stop: f64, step: f64, target_dtype: c.mlx_dtype) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_arange(&out, start, stop, step, target_dtype, ctx.stream));
        return .{ .handle = out };
    }

    pub fn transpose(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_transpose(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn swapAxes(ctx: Context, value: Array, axis1: i32, axis2: i32) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_swapaxes(&out, value.handle, axis1, axis2, ctx.stream));
        return .{ .handle = out };
    }

    pub fn copy(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_copy(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn matmul(ctx: Context, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_matmul(&out, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn sumAll(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_sum(&out, value.handle, false, ctx.stream));
        return .{ .handle = out };
    }

    pub fn sumAxis0(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_sum_axis0(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn prodAxis0(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_prod_axis0(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn minAxis0(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_min_axis0(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn maxAxis0(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_max_axis0(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn argmax(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_argmax(&out, value.handle, false, ctx.stream));
        return .{ .handle = out };
    }

    pub fn cumsum0(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_cumsum(&out, value.handle, 0, false, false, ctx.stream));
        return .{ .handle = out };
    }

    pub fn cumsum0Inclusive(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_cumsum(&out, value.handle, 0, false, true, ctx.stream));
        return .{ .handle = out };
    }

    pub fn cumprod0Inclusive(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_cumprod0_inclusive(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn cummin0Inclusive(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_cummin0_inclusive(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn cummax0Inclusive(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_cummax0_inclusive(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn argsort(ctx: Context, value: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_argsort(&out, value.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn where(ctx: Context, cond: Array, left: Array, right: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_where(&out, cond.handle, left.handle, right.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn boolWhereIndices(ctx: Context, mask: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_bool_where_indices(&out, mask.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn reshape(ctx: Context, value: Array, dims: []const i32) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_reshape(&out, value.handle, dims.ptr, dims.len, ctx.stream));
        return .{ .handle = out };
    }

    pub fn slice(ctx: Context, value: Array, start: []const i32, stop: []const i32, strides: []const i32) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_slice(&out, value.handle, start.ptr, start.len, stop.ptr, stop.len, strides.ptr, strides.len, ctx.stream));
        return .{ .handle = out };
    }

    pub fn sliceUpdate(ctx: Context, value: Array, update: Array, start: []const i32, stop: []const i32, strides: []const i32) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_slice_update(
            &out,
            value.handle,
            update.handle,
            start.ptr,
            start.len,
            stop.ptr,
            stop.len,
            strides.ptr,
            strides.len,
            ctx.stream,
        ));
        return .{ .handle = out };
    }

    pub fn take(ctx: Context, value: Array, indices: Array) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_take(&out, value.handle, indices.handle, ctx.stream));
        return .{ .handle = out };
    }

    pub fn takeAxis(ctx: Context, value: Array, indices: Array, axis: i32) Error!Array {
        var out = c.mlx_array_new();
        try check(mlxc_take_axis(&out, value.handle, indices.handle, axis, ctx.stream));
        return .{ .handle = out };
    }

    pub fn zeros(ctx: Context, dims: []const i32, target_dtype: c.mlx_dtype) Error!Array {
        var out = c.mlx_array_new();
        try check(c.mlx_zeros(&out, dims.ptr, dims.len, target_dtype, ctx.stream));
        return .{ .handle = out };
    }

    pub fn concat(ctx: Context, arrays: []const Array) Error!Array {
        const vec = c.mlx_vector_array_new();
        defer _ = c.mlx_vector_array_free(vec);
        for (arrays) |item| {
            try check(c.mlx_vector_array_append_value(vec, item.handle));
        }
        var out = c.mlx_array_new();
        try check(c.mlx_concatenate(&out, vec, ctx.stream));
        return .{ .handle = out };
    }

    pub fn stack(ctx: Context, arrays: []const Array) Error!Array {
        const vec = c.mlx_vector_array_new();
        defer _ = c.mlx_vector_array_free(vec);
        for (arrays) |item| {
            try check(c.mlx_vector_array_append_value(vec, item.handle));
        }
        var out = c.mlx_array_new();
        try check(c.mlx_stack(&out, vec, ctx.stream));
        return .{ .handle = out };
    }

    pub fn reverse0(ctx: Context, value: Array) Error!Array {
        const len = value.shape()[0];
        const idx = try arange(ctx, @floatFromInt(len - 1), -1, -1, c.MLX_INT32);
        defer {
            var tmp = idx;
            tmp.deinit();
        }
        return take(ctx, value, idx);
    }

    pub fn hotValueAndGrad(input: Array, kind: HotGradKind) Error!struct { value: Array, grad: Array } {
        var value_out = c.mlx_array_new();
        var grad_out = c.mlx_array_new();
        try check(mlxc_hot_value_and_grad(&value_out, &grad_out, input.handle, @intFromEnum(kind)));
        return .{
            .value = .{ .handle = value_out },
            .grad = .{ .handle = grad_out },
        };
    }

    pub fn loweredValueAndGrad(
        program: []const LoweredProgramInstr,
        refs: []const u32,
        consts: []const Array,
        inputs: []const Array,
        root: u32,
        argnum: u32,
    ) (Error || std.mem.Allocator.Error)!struct { value: Array, grad: Array } {
        const const_handles = try std.heap.page_allocator.alloc(c.mlx_array, consts.len);
        defer std.heap.page_allocator.free(const_handles);
        for (consts, 0..) |item, idx| const_handles[idx] = item.handle;

        const input_handles = try std.heap.page_allocator.alloc(c.mlx_array, inputs.len);
        defer std.heap.page_allocator.free(input_handles);
        for (inputs, 0..) |item, idx| input_handles[idx] = item.handle;

        var value_out = c.mlx_array_new();
        var grad_out = c.mlx_array_new();
        try check(mlxc_lowered_value_and_grad(
            &value_out,
            &grad_out,
            if (program.len == 0) null else program.ptr,
            program.len,
            if (refs.len == 0) null else refs.ptr,
            refs.len,
            if (const_handles.len == 0) null else const_handles.ptr,
            const_handles.len,
            if (input_handles.len == 0) null else input_handles.ptr,
            input_handles.len,
            root,
            argnum,
        ));
        return .{
            .value = .{ .handle = value_out },
            .grad = .{ .handle = grad_out },
        };
    }
};

pub fn loadSafetensors(
    allocator: std.mem.Allocator,
    ctx: Context,
    path: []const u8,
) (Error || std.mem.Allocator.Error)![]NamedArray {
    const zpath = try allocator.dupeZ(u8, path);
    defer allocator.free(zpath);

    var cpu_ctx: ?Context = null;
    defer {
        if (cpu_ctx) |*owned| owned.deinit();
        _ = mlxc_set_default_device_type(switch (ctx.resolved) {
            .gpu => c.MLX_GPU,
            else => c.MLX_CPU,
        }, 0);
    }
    const load_stream = if (ctx.resolved == .gpu) blk: {
        cpu_ctx = try Context.init(.cpu);
        break :blk cpu_ctx.?.stream;
    } else ctx.stream;

    var arrays = c.mlx_map_string_to_array_new();
    errdefer _ = c.mlx_map_string_to_array_free(arrays);
    var metadata = c.mlx_map_string_to_string_new();
    errdefer _ = c.mlx_map_string_to_string_free(metadata);

    try check(c.mlx_load_safetensors(&arrays, &metadata, zpath.ptr, load_stream));
    defer _ = c.mlx_map_string_to_array_free(arrays);
    defer _ = c.mlx_map_string_to_string_free(metadata);

    const iter = c.mlx_map_string_to_array_iterator_new(arrays);
    defer _ = c.mlx_map_string_to_array_iterator_free(iter);

    var out = std.ArrayList(NamedArray).empty;
    errdefer {
        for (out.items) |*entry| {
            allocator.free(entry.name);
            entry.array.deinit();
        }
        out.deinit(allocator);
    }

    while (true) {
        var key: ?[*:0]const u8 = null;
        var raw = c.mlx_array_new();
        const status = c.mlx_map_string_to_array_iterator_next(&key, &raw, iter);
        if (status == 2) {
            _ = c.mlx_array_free(raw);
            break;
        }
        try check(status);
        errdefer _ = c.mlx_array_free(raw);

        const name = try allocator.dupe(u8, std.mem.span(key orelse return error.MlxFailure));
        errdefer allocator.free(name);

        var array = Array{ .handle = raw };
        errdefer array.deinit();
        if (ctx.resolved == .gpu) {
            const copied = try Array.copy(ctx, array);
            array.deinit();
            array = copied;
        }

        try out.append(allocator, .{
            .name = name,
            .array = array,
        });
    }

    const owned = try out.toOwnedSlice(allocator);
    std.sort.block(NamedArray, owned, {}, struct {
        fn lessThan(_: void, left: NamedArray, right: NamedArray) bool {
            return std.mem.order(u8, left.name, right.name) == .lt;
        }
    }.lessThan);
    return owned;
}

pub fn deinitNamedArrays(allocator: std.mem.Allocator, entries: []NamedArray) void {
    for (entries) |*entry| {
        allocator.free(entry.name);
        entry.array.deinit();
    }
    allocator.free(entries);
}
