const std = @import("std");

fn broadcastScalarLikeMlx(
    comptime api: anytype,
    ctx: *api.mlx.Context,
    scalar: api.mlx.Array,
    like: api.mlx.Array,
) api.KError!api.mlx.Array {
    var zero = api.mlx.Array.sub(ctx.*, like, like) catch |err| return api.mapMlxError(err);
    defer zero.deinit();
    return api.mlx.Array.add(ctx.*, zero, scalar) catch |err| return api.mapMlxError(err);
}

fn scalarNumericMlxArrayResultOwned(
    comptime api: anytype,
    value: *api.mlx.Array,
) api.KError!f64 {
    value.eval() catch |err| return api.mapMlxError(err);
    if (value.ndim() != 0) return error.Type;
    return switch (value.dtype()) {
        api.c.MLX_BOOL => @floatFromInt(@intFromBool(value.boolItem() catch |err| return api.mapMlxError(err))),
        api.c.MLX_INT32, api.c.MLX_INT64, api.c.MLX_UINT32 => @floatFromInt(value.intItem() catch |err| return api.mapMlxError(err)),
        api.c.MLX_FLOAT32, api.c.MLX_FLOAT64 => value.floatItem() catch |err| return api.mapMlxError(err),
        else => error.Type,
    };
}

fn materializeMlxAutogradInput(
    comptime api: anytype,
    self: *api.Session,
    value: api.Value,
) api.KError!api.mlx.Array {
    var arr = try api.materializeBackendArray(self, value);
    errdefer arr.deinit();
    if (arr.ndim() == 0) return arr;
    if (arr.dtype() == api.c.MLX_FLOAT32 or arr.dtype() == api.c.MLX_FLOAT64) return arr;

    const ctx = try api.backendContext(self);
    const casted = api.mlx.Array.cast(ctx.*, arr, api.c.MLX_FLOAT32) catch |err| return api.mapMlxError(err);
    arr.deinit();
    return casted;
}

fn takeOwnedMlxArray(comptime api: anytype, slot: *api.mlx.Array) api.mlx.Array {
    const value = slot.*;
    slot.* = api.mlx.Array.empty();
    return value;
}

fn accumulateOwnedMlxAdjoint(
    comptime api: anytype,
    ctx: *api.mlx.Context,
    slot: *api.mlx.Array,
    term: api.mlx.Array,
) api.KError!void {
    if (!slot.isValid()) {
        slot.* = term;
        return;
    }

    const combined = api.mlx.Array.add(ctx.*, slot.*, term) catch |err| return api.mapMlxError(err);
    slot.deinit();
    var owned_term = term;
    owned_term.deinit();
    slot.* = combined;
}

fn applyDenseAutodiffUnaryMapMlx(
    comptime api: anytype,
    ctx: *api.mlx.Context,
    op: api.BuiltinId,
    input: api.mlx.Array,
) api.KError!api.mlx.Array {
    return switch (op) {
        .exp => api.mlx.Array.exp(ctx.*, input) catch |err| return api.mapMlxError(err),
        .log => api.mlx.Array.log(ctx.*, input) catch |err| return api.mapMlxError(err),
        .tanh => api.mlx.Array.tanh(ctx.*, input) catch |err| return api.mapMlxError(err),
        .sigmoid => api.mlx.Array.sigmoid(ctx.*, input) catch |err| return api.mapMlxError(err),
        else => error.Internal,
    };
}

fn denseAutodiffUnaryMapDerivativeMlx(
    comptime api: anytype,
    ctx: *api.mlx.Context,
    op: api.BuiltinId,
    input: api.mlx.Array,
    output: api.mlx.Array,
) api.KError!api.mlx.Array {
    return switch (op) {
        .exp => output.clone() catch |err| return api.mapMlxError(err),
        .log => blk: {
            const one = api.mlx.Array.fromFloat(@as(f32, 1.0));
            break :blk api.mlx.Array.div(ctx.*, one, input) catch |err| return api.mapMlxError(err);
        },
        .tanh => blk: {
            var sq = api.mlx.Array.mul(ctx.*, output, output) catch |err| return api.mapMlxError(err);
            defer sq.deinit();
            const one = api.mlx.Array.fromFloat(@as(f32, 1.0));
            break :blk api.mlx.Array.sub(ctx.*, one, sq) catch |err| return api.mapMlxError(err);
        },
        .sigmoid => blk: {
            const one = api.mlx.Array.fromFloat(@as(f32, 1.0));
            var one_minus = api.mlx.Array.sub(ctx.*, one, output) catch |err| return api.mapMlxError(err);
            defer one_minus.deinit();
            break :blk api.mlx.Array.mul(ctx.*, output, one_minus) catch |err| return api.mapMlxError(err);
        },
        else => error.Internal,
    };
}

fn projectMlxAdjointToKind(
    comptime api: anytype,
    ctx: *api.mlx.Context,
    term: api.mlx.Array,
    target_kind: api.DenseAutodiffNodeKind,
    like: api.mlx.Array,
) api.KError!api.mlx.Array {
    return switch (target_kind) {
        .vector => if (term.ndim() == 0) blk: {
            const projected = try broadcastScalarLikeMlx(api, ctx, term, like);
            var owned_term = term;
            owned_term.deinit();
            break :blk projected;
        } else term,
        .scalar => if (term.ndim() == 0)
            term
        else blk: {
            const reduced = api.mlx.Array.sumAxis0(ctx.*, term) catch |err| return api.mapMlxError(err);
            var owned_term = term;
            owned_term.deinit();
            break :blk reduced;
        },
    };
}

fn executeDenseAutodiffProgramMlx(
    comptime api: anytype,
    self: *api.Session,
    program: *const api.DenseAutodiffProgram,
    input: api.mlx.Array,
) api.KError!struct { value: api.mlx.Array, grad: api.mlx.Array } {
    std.debug.assert(program.len > 0);
    std.debug.assert(program.root < program.len);
    std.debug.assert(program.nodes[0] == .input);

    const ctx = try api.backendContext(self);

    var forward: [api.dense_autodiff_max_nodes]api.mlx.Array = [_]api.mlx.Array{api.mlx.Array.empty()} ** api.dense_autodiff_max_nodes;
    var adjoint: [api.dense_autodiff_max_nodes]api.mlx.Array = [_]api.mlx.Array{api.mlx.Array.empty()} ** api.dense_autodiff_max_nodes;
    defer {
        for (forward[0..program.len]) |*item| item.deinit();
        for (adjoint[0..program.len]) |*item| item.deinit();
    }

    forward[0] = input;
    for (program.nodes[1..program.len], 1..) |node, idx| {
        forward[idx] = switch (node) {
            .input => unreachable,
            .const_scalar => |value| api.mlx.Array.fromFloat(@floatCast(value)),
            .scan_add => |src| api.mlx.Array.cumsum0Inclusive(ctx.*, forward[src]) catch |err| return api.mapMlxError(err),
            .unary_map => |value| try applyDenseAutodiffUnaryMapMlx(api, ctx, value.op, forward[value.src]),
            .neg => |src| api.mlx.Array.negate(ctx.*, forward[src]) catch |err| return api.mapMlxError(err),
            .add => |value| api.mlx.Array.add(ctx.*, forward[value.left], forward[value.right]) catch |err| return api.mapMlxError(err),
            .sub => |value| api.mlx.Array.sub(ctx.*, forward[value.left], forward[value.right]) catch |err| return api.mapMlxError(err),
            .mul => |value| api.mlx.Array.mul(ctx.*, forward[value.left], forward[value.right]) catch |err| return api.mapMlxError(err),
            .reduce_add => |src| api.mlx.Array.sumAxis0(ctx.*, forward[src]) catch |err| return api.mapMlxError(err),
        };
    }

    adjoint[program.root] = api.mlx.Array.fromFloat(@as(f32, 1.0));

    var rev = program.len;
    while (rev > 0) {
        rev -= 1;
        if (!adjoint[rev].isValid()) continue;
        switch (program.nodes[rev]) {
            .input, .const_scalar => {},
            .scan_add => |src| {
                var incoming = takeOwnedMlxArray(api, &adjoint[rev]);
                defer incoming.deinit();
                var reversed = api.mlx.Array.reverse0(ctx.*, incoming) catch |err| return api.mapMlxError(err);
                defer reversed.deinit();
                var suffix = api.mlx.Array.cumsum0Inclusive(ctx.*, reversed) catch |err| return api.mapMlxError(err);
                defer suffix.deinit();
                const term = api.mlx.Array.reverse0(ctx.*, suffix) catch |err| return api.mapMlxError(err);
                try accumulateOwnedMlxAdjoint(api, ctx, &adjoint[src], term);
            },
            .unary_map => |value| {
                var incoming = takeOwnedMlxArray(api, &adjoint[rev]);
                defer incoming.deinit();
                var deriv = try denseAutodiffUnaryMapDerivativeMlx(api, ctx, value.op, forward[value.src], forward[rev]);
                errdefer deriv.deinit();
                const term = api.mlx.Array.mul(ctx.*, incoming, deriv) catch |err| return api.mapMlxError(err);
                deriv.deinit();
                try accumulateOwnedMlxAdjoint(api, ctx, &adjoint[value.src], term);
            },
            .neg => |src| {
                var incoming = takeOwnedMlxArray(api, &adjoint[rev]);
                defer incoming.deinit();
                const term = api.mlx.Array.negate(ctx.*, incoming) catch |err| return api.mapMlxError(err);
                const projected = try projectMlxAdjointToKind(api, ctx, term, program.kinds[src], forward[src]);
                try accumulateOwnedMlxAdjoint(api, ctx, &adjoint[src], projected);
            },
            .add => |value| {
                var incoming = takeOwnedMlxArray(api, &adjoint[rev]);
                defer incoming.deinit();
                var right_term = incoming.clone() catch |err| return api.mapMlxError(err);
                errdefer right_term.deinit();
                const left_term = try projectMlxAdjointToKind(api, ctx, incoming, program.kinds[value.left], forward[value.left]);
                incoming = api.mlx.Array.empty();
                right_term = try projectMlxAdjointToKind(api, ctx, right_term, program.kinds[value.right], forward[value.right]);
                try accumulateOwnedMlxAdjoint(api, ctx, &adjoint[value.left], left_term);
                try accumulateOwnedMlxAdjoint(api, ctx, &adjoint[value.right], right_term);
            },
            .sub => |value| {
                var incoming = takeOwnedMlxArray(api, &adjoint[rev]);
                defer incoming.deinit();
                var right_base = incoming.clone() catch |err| return api.mapMlxError(err);
                errdefer right_base.deinit();
                var right_term = api.mlx.Array.negate(ctx.*, right_base) catch |err| return api.mapMlxError(err);
                right_base.deinit();
                errdefer right_term.deinit();
                const left_term = try projectMlxAdjointToKind(api, ctx, incoming, program.kinds[value.left], forward[value.left]);
                incoming = api.mlx.Array.empty();
                right_term = try projectMlxAdjointToKind(api, ctx, right_term, program.kinds[value.right], forward[value.right]);
                try accumulateOwnedMlxAdjoint(api, ctx, &adjoint[value.left], left_term);
                try accumulateOwnedMlxAdjoint(api, ctx, &adjoint[value.right], right_term);
            },
            .mul => |value| {
                var incoming = takeOwnedMlxArray(api, &adjoint[rev]);
                defer incoming.deinit();
                var left_term = api.mlx.Array.mul(ctx.*, incoming, forward[value.right]) catch |err| return api.mapMlxError(err);
                errdefer {
                    var owned = left_term;
                    owned.deinit();
                }
                var right_term = api.mlx.Array.mul(ctx.*, incoming, forward[value.left]) catch |err| return api.mapMlxError(err);
                errdefer {
                    var owned = right_term;
                    owned.deinit();
                }
                left_term = try projectMlxAdjointToKind(api, ctx, left_term, program.kinds[value.left], forward[value.left]);
                right_term = try projectMlxAdjointToKind(api, ctx, right_term, program.kinds[value.right], forward[value.right]);
                try accumulateOwnedMlxAdjoint(api, ctx, &adjoint[value.left], left_term);
                try accumulateOwnedMlxAdjoint(api, ctx, &adjoint[value.right], right_term);
            },
            .reduce_add => |src| {
                var incoming = takeOwnedMlxArray(api, &adjoint[rev]);
                defer incoming.deinit();
                const term = try broadcastScalarLikeMlx(api, ctx, incoming, forward[src]);
                try accumulateOwnedMlxAdjoint(api, ctx, &adjoint[src], term);
            },
        }
    }

    if (!adjoint[0].isValid()) {
        const zero = api.mlx.Array.sub(ctx.*, forward[0], forward[0]) catch |err| return api.mapMlxError(err);
        adjoint[0] = zero;
    }

    const value = forward[program.root];
    forward[program.root] = api.mlx.Array.empty();
    const grad = adjoint[0];
    adjoint[0] = api.mlx.Array.empty();
    return .{ .value = value, .grad = grad };
}

pub fn tryFastDenseAutogradBackend(
    comptime api: anytype,
    self: *api.Session,
    kind: api.DerivedVerbKind,
    program: *const api.DenseAutodiffProgram,
    value: api.Value,
) api.KError!?api.Value {
    var input = try materializeMlxAutogradInput(api, self, value);
    defer input.deinit();
    if (input.ndim() != 1) return null;

    const result = try executeDenseAutodiffProgramMlx(api, self, program, input);
    input = api.mlx.Array.empty();
    var original_value = result.value;
    defer original_value.deinit();
    var grad_value = result.grad;
    errdefer grad_value.deinit();

    const wrapped_grad = try api.wrapManagedBackendArray(self, grad_value);
    if (comptime api.enable_probe_instrumentation) self.last_dense_autodiff_exec_backend = .mlx;
    if (kind == .grad) return wrapped_grad;

    const original_scalar = try scalarNumericMlxArrayResultOwned(api, &original_value);
    const original_host = try api.numericScalarValueFromF64(self, original_scalar);
    defer api.releaseValue(self, original_host);
    defer api.releaseValue(self, wrapped_grad);
    const pair = [_]api.Value{ original_host, wrapped_grad };
    return try api.createManagedHostBoxedArray(self, &pair);
}
