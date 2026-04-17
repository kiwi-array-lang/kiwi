const zig_builtin = @import("builtin");
const std = @import("std");
const build_options = @import("build_options");
const c = if (zig_builtin.target.cpu.arch == .wasm32)
    @import("wasm/c.zig").c
else
    @import("kiwi_runtime_c").c;

const placeholder = struct {
    const Self = @This();

    pub const backend_kind = .host_only;
    pub const supports_full_ops = false;

    pub const Error = error{
        MlxFailure,
        InvalidDevice,
        UnsupportedType,
    };

    pub const NamedArray = struct {
        name: []u8,
        array: Self.Array,
    };

    pub const DevicePreference = enum {
        auto,
        cpu,
        gpu,
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

    pub fn check(code: c_int) Self.Error!void {
        if (code != 0) return error.MlxFailure;
    }

    const max_rank = 8;

    fn initShape(dims: []const i32) [max_rank]c_int {
        std.debug.assert(dims.len <= max_rank);
        var out = [_]c_int{0} ** max_rank;
        for (dims, 0..) |dim, idx| out[idx] = dim;
        return out;
    }

    fn initArray(dtype_value: c.mlx_dtype, dims: []const i32) Self.Array {
        return .{
            .dtype_value = dtype_value,
            .shape_len = @intCast(dims.len),
            .shape_buf = initShape(dims),
        };
    }

    fn unsupportedArray() Self.Error!Self.Array {
        return error.MlxFailure;
    }

    pub const Context = struct {
        stream: c.mlx_stream = .{ .ctx = null },
        resolved: Self.DevicePreference = .cpu,

        pub fn init(preference: Self.DevicePreference) Self.Error!Self.Context {
            return switch (preference) {
                .gpu => error.InvalidDevice,
                .auto, .cpu => .{},
            };
        }

        pub fn deinit(self: *Self.Context) void {
            _ = self;
        }
    };

    pub const Array = struct {
        handle: c.mlx_array = .{ .ctx = null },
        dtype_value: c.mlx_dtype = c.MLX_INT32,
        shape_len: u8 = 0,
        shape_buf: [max_rank]c_int = [_]c_int{0} ** max_rank,

        pub fn empty() Self.Array {
            return .{};
        }

        pub fn clone(self: Self.Array) Self.Error!Self.Array {
            return self;
        }

        pub fn deinit(self: *Self.Array) void {
            self.* = .{};
        }

        pub fn isValid(self: Self.Array) bool {
            return self.handle.ctx != null;
        }

        pub fn fromBool(value: bool) Self.Array {
            _ = value;
            return initArray(c.MLX_BOOL, &.{});
        }

        pub fn fromInt(value: i32) Self.Array {
            _ = value;
            return initArray(c.MLX_INT32, &.{});
        }

        pub fn fromFloat(value: f32) Self.Array {
            _ = value;
            return initArray(c.MLX_FLOAT32, &.{});
        }

        pub fn fromBoolSlice(data: []const bool, dims: []const i32) Self.Array {
            _ = data;
            return initArray(c.MLX_BOOL, dims);
        }

        pub fn fromIntSlice(data: []const i32, dims: []const i32) Self.Array {
            _ = data;
            return initArray(c.MLX_INT32, dims);
        }

        pub fn fromFloatSlice(data: []const f32, dims: []const i32) Self.Array {
            _ = data;
            return initArray(c.MLX_FLOAT32, dims);
        }

        pub fn fromBoolSliceChecked(data: []const bool, dims: []const i32) (Self.Error || std.mem.Allocator.Error)!Self.Array {
            _ = data;
            return initArray(c.MLX_BOOL, dims);
        }

        pub fn fromIntSliceChecked(data: []const i32, dims: []const i32) (Self.Error || std.mem.Allocator.Error)!Self.Array {
            _ = data;
            return initArray(c.MLX_INT32, dims);
        }

        pub fn fromFloatSliceChecked(data: []const f32, dims: []const i32) (Self.Error || std.mem.Allocator.Error)!Self.Array {
            _ = data;
            return initArray(c.MLX_FLOAT32, dims);
        }

        pub fn ndim(self: Self.Array) usize {
            return self.shape_len;
        }

        pub fn size(self: Self.Array) usize {
            var total: usize = 1;
            for (self.shape()) |dim| total *= @as(usize, @intCast(dim));
            return total;
        }

        pub fn shape(self: Self.Array) []const c_int {
            return self.shape_buf[0..self.shape_len];
        }

        pub fn dtype(self: Self.Array) c.mlx_dtype {
            return self.dtype_value;
        }

        pub fn isScalar(self: Self.Array) bool {
            return self.ndim() == 0;
        }

        pub fn eval(self: Self.Array) Self.Error!void {
            _ = self;
        }

        pub fn boolItem(self: Self.Array) Self.Error!bool {
            _ = self;
            return error.UnsupportedType;
        }

        pub fn intItem(self: Self.Array) Self.Error!i64 {
            _ = self;
            return error.UnsupportedType;
        }

        pub fn floatItem(self: Self.Array) Self.Error!f64 {
            _ = self;
            return error.UnsupportedType;
        }

        pub fn readBools(self: Self.Array, allocator: std.mem.Allocator) (Self.Error || std.mem.Allocator.Error)![]bool {
            _ = self;
            _ = allocator;
            return error.MlxFailure;
        }

        pub fn readInts(self: Self.Array, allocator: std.mem.Allocator) (Self.Error || std.mem.Allocator.Error)![]i32 {
            _ = self;
            _ = allocator;
            return error.MlxFailure;
        }

        pub fn readFloats(self: Self.Array, allocator: std.mem.Allocator) (Self.Error || std.mem.Allocator.Error)![]f32 {
            _ = self;
            _ = allocator;
            return error.MlxFailure;
        }

        pub fn boolWhereIndices(ctx: Self.Context, mask: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = mask;
            return unsupportedArray();
        }

        pub fn cast(ctx: Self.Context, value: Self.Array, dtype_value: c.mlx_dtype) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            _ = dtype_value;
            return unsupportedArray();
        }

        pub fn concat(ctx: Self.Context, arrays: []const Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = arrays;
            return unsupportedArray();
        }

        pub fn cumsum0Inclusive(ctx: Self.Context, value: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            return unsupportedArray();
        }

        pub fn add(ctx: Self.Context, left: Self.Array, right: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = left;
            _ = right;
            return unsupportedArray();
        }

        pub fn sub(ctx: Self.Context, left: Self.Array, right: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = left;
            _ = right;
            return unsupportedArray();
        }

        pub fn mul(ctx: Self.Context, left: Self.Array, right: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = left;
            _ = right;
            return unsupportedArray();
        }

        pub fn div(ctx: Self.Context, left: Self.Array, right: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = left;
            _ = right;
            return unsupportedArray();
        }

        pub fn less(ctx: Self.Context, left: Self.Array, right: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = left;
            _ = right;
            return unsupportedArray();
        }

        pub fn greater(ctx: Self.Context, left: Self.Array, right: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = left;
            _ = right;
            return unsupportedArray();
        }

        pub fn equal(ctx: Self.Context, left: Self.Array, right: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = left;
            _ = right;
            return unsupportedArray();
        }

        pub fn negate(ctx: Self.Context, value: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            return unsupportedArray();
        }

        pub fn exp(ctx: Self.Context, value: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            return unsupportedArray();
        }

        pub fn log(ctx: Self.Context, value: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            return unsupportedArray();
        }

        pub fn tanh(ctx: Self.Context, value: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            return unsupportedArray();
        }

        pub fn sigmoid(ctx: Self.Context, value: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            return unsupportedArray();
        }

        pub fn sumAxis0(ctx: Self.Context, value: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            return unsupportedArray();
        }

        pub fn prodAxis0(ctx: Self.Context, value: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            return unsupportedArray();
        }

        pub fn minAxis0(ctx: Self.Context, value: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            return unsupportedArray();
        }

        pub fn maxAxis0(ctx: Self.Context, value: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            return unsupportedArray();
        }

        pub fn transpose(ctx: Self.Context, value: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            return unsupportedArray();
        }

        pub fn matmul(ctx: Self.Context, left: Self.Array, right: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = left;
            _ = right;
            return unsupportedArray();
        }

        pub fn reshape(ctx: Self.Context, value: Self.Array, dims: []const i32) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            _ = dims;
            return unsupportedArray();
        }

        pub fn slice(
            ctx: Self.Context,
            value: Self.Array,
            start: []const i32,
            stop: []const i32,
            stride: []const i32,
        ) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            _ = start;
            _ = stop;
            _ = stride;
            return unsupportedArray();
        }

        pub fn takeAxis(ctx: Self.Context, value: Self.Array, indices: Self.Array, axis: i32) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            _ = indices;
            _ = axis;
            return unsupportedArray();
        }

        pub fn reverse0(ctx: Self.Context, value: Self.Array) Self.Error!Self.Array {
            _ = ctx;
            _ = value;
            return unsupportedArray();
        }
    };

    pub fn loadSafetensors(
        allocator: std.mem.Allocator,
        ctx: Self.Context,
        path: []const u8,
    ) (Self.Error || std.mem.Allocator.Error)![]Self.NamedArray {
        _ = allocator;
        _ = ctx;
        _ = path;
        return error.MlxFailure;
    }

    pub fn loadSafetensorTensor(
        allocator: std.mem.Allocator,
        ctx: Self.Context,
        path: []const u8,
        dims: []const i32,
        dtype: c.mlx_dtype,
        data_offset: u64,
    ) (Self.Error || std.mem.Allocator.Error)!Self.Array {
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
        arrays: []const Self.Array,
    ) (Self.Error || std.mem.Allocator.Error)!void {
        _ = allocator;
        _ = path;
        _ = names;
        _ = arrays;
        return error.MlxFailure;
    }

    pub fn deinitNamedArrays(allocator: std.mem.Allocator, entries: []Self.NamedArray) void {
        _ = allocator;
        _ = entries;
    }
};

const runtime = if (zig_builtin.target.cpu.arch == .wasm32)
    @import("wasm/mlx.zig")
else if (build_options.runtime_has_mlx)
    @import("kiwi_runtime_mlx")
else
    placeholder;

pub const Error = runtime.Error;
pub const DevicePreference = @import("device.zig").DevicePreference;
pub const Context = runtime.Context;
pub const Array = runtime.Array;
pub const NamedArray = runtime.NamedArray;
pub const check = runtime.check;
pub const loadSafetensors = runtime.loadSafetensors;
pub const loadSafetensorTensor = runtime.loadSafetensorTensor;
pub const saveSafetensors = runtime.saveSafetensors;
pub const deinitNamedArrays = runtime.deinitNamedArrays;
pub const HotGradKind = runtime.HotGradKind;
pub const LoweredProgramTag = runtime.LoweredProgramTag;
pub const LoweredProgramInstr = runtime.LoweredProgramInstr;

pub const BackendKind = enum {
    mlx,
    webgpu,
    host_only,
};

pub const backend_kind: BackendKind = if (@hasDecl(runtime, "backend_kind"))
    switch (runtime.backend_kind) {
        .wasm_bridge => .webgpu,
        .host_only => .host_only,
        else => .mlx,
    }
else
    .mlx;
pub const supports_full_ops = if (@hasDecl(runtime, "supports_full_ops")) runtime.supports_full_ops else true;

fn runtimeDevicePreference(preference: DevicePreference) runtime.DevicePreference {
    return switch (preference) {
        .auto => .auto,
        .cpu => .cpu,
        .gpu => .gpu,
    };
}

pub fn initContext(preference: DevicePreference) Error!Context {
    return runtime.Context.init(runtimeDevicePreference(preference));
}
