const std = @import("std");

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
