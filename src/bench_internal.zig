const std = @import("std");
const runtime_device = @import("../src/device.zig");

pub const BackendMode = enum {
    auto,
    host,
    mlx_cpu,
    mlx_gpu,

    pub fn label(self: BackendMode) []const u8 {
        return switch (self) {
            .auto => "auto",
            .host => "host",
            .mlx_cpu => "mlx_cpu",
            .mlx_gpu => "mlx_gpu",
        };
    }
};

pub const BenchTiming = struct {};

pub const DenseAutodiffAuditRow = struct {};

pub const default_target_batch_ms = 30.0;
pub const default_vector_size: usize = 100_000;
pub const default_matmul_size: usize = 64;

pub fn runBenchCli(
    _: std.mem.Allocator,
    _: runtime_device.DevicePreference,
    _: BackendMode,
    _: []const u8,
    _: f64,
    _: usize,
    _: usize,
) !void {
    return error.InvalidArgument;
}

pub fn benchmarkNamedCase(_: std.mem.Allocator, _: []const u8) !?BenchTiming {
    return null;
}

pub fn benchmarkNamedCaseWithTarget(
    _: std.mem.Allocator,
    _: runtime_device.DevicePreference,
    _: []const u8,
    _: f64,
    _: usize,
    _: usize,
) !?BenchTiming {
    return null;
}

pub fn denseAutodiffAudit(_: std.mem.Allocator) ![]DenseAutodiffAuditRow {
    return error.InvalidArgument;
}

pub fn auditDenseAutodiffCli(_: std.mem.Allocator) !void {
    return error.InvalidArgument;
}

pub fn resolveVectorSize(_: []const u8, requested_size: usize) usize {
    return requested_size;
}

pub fn isRealisticStringBenchCase(_: []const u8) bool {
    return false;
}
