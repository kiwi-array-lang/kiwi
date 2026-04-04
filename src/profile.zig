const std = @import("std");
const runtime = @import("runtime.zig");

pub const default_sample_hz: usize = 1000;
pub const label_sample_count = runtime.sampling_profile_label_count;
pub const op_sample_count = std.meta.fields(runtime.DebugOp).len;
pub const max_function_results = 12;
pub const max_code_results = 12;

pub const NamedCount = struct {
    name: []const u8,
    count: usize,
};

pub const CodeCount = struct {
    id: u16,
    kind: []const u8,
    count: usize,
    source: []const u8,
};

pub const FunctionCount = struct {
    slot: u16,
    name: []const u8,
    count: usize,
};

pub const ProfileResult = struct {
    name: []const u8,
    status: []const u8,
    err_name: ?[]const u8,
    sample_hz: usize,
    sample_period_ns: u64,
    duration_ms: f64,
    total_samples: usize,
    labels: [label_sample_count]NamedCount,
    ops: [op_sample_count]NamedCount,
    functions: []FunctionCount,
    codes: []CodeCount,

    pub fn deinit(self: *const ProfileResult, allocator: std.mem.Allocator) void {
        for (self.functions) |entry| allocator.free(entry.name);
        allocator.free(self.functions);
        for (self.codes) |entry| allocator.free(entry.source);
        allocator.free(self.codes);
    }
};

const Sampler = struct {
    session: *runtime.Session,
    sample_period_ns: u64,
    stop: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
    label_counts: [label_sample_count]usize = [_]usize{0} ** label_sample_count,
    op_counts: [op_sample_count]usize = [_]usize{0} ** op_sample_count,
    function_counts: [runtime.sampling_profile_max_callable_slot_count]usize = [_]usize{0} ** runtime.sampling_profile_max_callable_slot_count,
    code_counts: [runtime.sampling_profile_max_code_count]usize = [_]usize{0} ** runtime.sampling_profile_max_code_count,
    total_samples: usize = 0,

    fn sampleOnce(self: *Sampler) void {
        const state = self.session.samplingProfileState();
        self.label_counts[@intFromEnum(state.label)] += 1;
        if (state.op) |op| {
            self.op_counts[@intFromEnum(op)] += 1;
        }
        if (state.callable_slot != runtime.sampling_profile_no_callable_slot and state.callable_slot < self.function_counts.len) {
            self.function_counts[state.callable_slot] += 1;
        }
        if (state.code_id != 0 and state.code_id < self.code_counts.len) {
            self.code_counts[state.code_id] += 1;
        }
        self.total_samples += 1;
    }

    fn run(self: *Sampler) void {
        while (true) {
            self.sampleOnce();
            if (self.stop.load(.acquire) != 0) return;

            const deadline = monotonicNanos() + self.sample_period_ns;
            while (true) {
                if (self.stop.load(.acquire) != 0) return;
                const now = monotonicNanos();
                if (now >= deadline) break;
                std.Thread.sleep(@min(deadline - now, @as(u64, std.time.ns_per_ms)));
            }
        }
    }
};

pub const Collector = struct {
    allocator: std.mem.Allocator,
    session: *runtime.Session,
    sample_hz: usize,
    sample_period_ns: u64,
    sampler: Sampler,
    thread: ?std.Thread = null,

    pub fn init(allocator: std.mem.Allocator, session: *runtime.Session, sample_hz: usize) Collector {
        const clamped_hz = @max(@as(usize, 1), sample_hz);
        const sample_period_ns = @max(@as(u64, 1), @as(u64, std.time.ns_per_s) / @as(u64, clamped_hz));
        return .{
            .allocator = allocator,
            .session = session,
            .sample_hz = clamped_hz,
            .sample_period_ns = sample_period_ns,
            .sampler = .{
                .session = session,
                .sample_period_ns = sample_period_ns,
            },
        };
    }

    pub fn start(self: *Collector) !void {
        self.session.setSamplingProfileEnabled(true);
        errdefer self.session.setSamplingProfileEnabled(false);
        self.thread = try std.Thread.spawn(.{}, sampleThreadMain, .{&self.sampler});
    }

    pub fn cancel(self: *Collector) void {
        if (self.thread) |thread| {
            self.sampler.stop.store(1, .release);
            thread.join();
            self.thread = null;
        }
        self.session.setSamplingProfileEnabled(false);
    }

    pub fn finish(self: *Collector, name: []const u8, err_name: ?[]const u8, duration_ns: u64) !ProfileResult {
        self.cancel();
        return .{
            .name = name,
            .status = if (err_name == null) "ok" else "error",
            .err_name = err_name,
            .sample_hz = self.sample_hz,
            .sample_period_ns = self.sample_period_ns,
            .duration_ms = @as(f64, @floatFromInt(duration_ns)) / std.time.ns_per_ms,
            .total_samples = self.sampler.total_samples,
            .labels = makeLabelCounts(self.sampler.label_counts),
            .ops = makeOpCounts(self.sampler.op_counts),
            .functions = try makeFunctionCounts(self.allocator, self.session, self.sampler.function_counts),
            .codes = try makeCodeCounts(self.allocator, self.session, self.sampler.code_counts, self.sampler.total_samples),
        };
    }
};

fn sampleThreadMain(sampler: *Sampler) void {
    sampler.run();
}

fn monotonicNanos() u64 {
    return @intCast(std.time.nanoTimestamp());
}

fn makeLabelCounts(counts: [label_sample_count]usize) [label_sample_count]NamedCount {
    var result: [label_sample_count]NamedCount = undefined;
    inline for (std.meta.fields(runtime.SamplingProfileLabel), 0..) |field, idx| {
        result[idx] = .{
            .name = field.name,
            .count = counts[idx],
        };
    }
    return result;
}

fn makeOpCounts(counts: [op_sample_count]usize) [op_sample_count]NamedCount {
    var result: [op_sample_count]NamedCount = undefined;
    inline for (std.meta.fields(runtime.DebugOp), 0..) |field, idx| {
        result[idx] = .{
            .name = field.name,
            .count = counts[idx],
        };
    }
    return result;
}

fn countActiveCodes(counts: [runtime.sampling_profile_max_code_count]usize) usize {
    var total: usize = 0;
    for (counts) |count| {
        if (count != 0) total += 1;
    }
    return total;
}

fn normalizeSnippet(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, source, " \t\r\n");
    if (trimmed.len == 0) return try allocator.dupe(u8, "<unknown>");

    var collapsed = std.ArrayList(u8).empty;
    defer collapsed.deinit(allocator);
    var pending_space = false;
    for (trimmed) |ch| {
        if (std.ascii.isWhitespace(ch)) {
            pending_space = true;
            continue;
        }
        if (pending_space and collapsed.items.len != 0) try collapsed.append(allocator, ' ');
        pending_space = false;
        try collapsed.append(allocator, ch);
        if (collapsed.items.len >= 96) break;
    }
    if (trimmed.len > collapsed.items.len) try collapsed.appendSlice(allocator, "...");
    return try collapsed.toOwnedSlice(allocator);
}

fn sortCodeCountsDescending(items: []CodeCount) void {
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        var j = i;
        while (j > 0 and items[j - 1].count < items[j].count) : (j -= 1) {
            std.mem.swap(CodeCount, &items[j - 1], &items[j]);
        }
    }
}

fn countActiveFunctions(counts: [runtime.sampling_profile_max_callable_slot_count]usize) usize {
    var total: usize = 0;
    for (counts) |count| {
        if (count != 0) total += 1;
    }
    return total;
}

fn sortFunctionCountsDescending(items: []FunctionCount) void {
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        var j = i;
        while (j > 0 and items[j - 1].count < items[j].count) : (j -= 1) {
            std.mem.swap(FunctionCount, &items[j - 1], &items[j]);
        }
    }
}

fn makeFunctionCounts(
    allocator: std.mem.Allocator,
    session: *runtime.Session,
    counts: [runtime.sampling_profile_max_callable_slot_count]usize,
) ![]FunctionCount {
    const active = countActiveFunctions(counts);
    if (active == 0) return try allocator.alloc(FunctionCount, 0);

    var all = try allocator.alloc(FunctionCount, active);
    var initialized: usize = 0;
    errdefer {
        for (all[0..initialized]) |entry| allocator.free(entry.name);
        allocator.free(all);
    }

    var idx: usize = 0;
    for (counts, 0..) |count, slot_idx| {
        if (count == 0) continue;
        const slot: u16 = @intCast(slot_idx);
        const name = session.samplingProfileCallableName(slot) orelse "<unknown>";
        all[idx] = .{
            .slot = slot,
            .name = try allocator.dupe(u8, name),
            .count = count,
        };
        idx += 1;
        initialized = idx;
    }

    sortFunctionCountsDescending(all);
    const kept_len = @min(all.len, max_function_results);
    if (kept_len == all.len) return all;

    for (all[kept_len..]) |entry| allocator.free(entry.name);
    return try allocator.realloc(all, kept_len);
}

fn makeCodeCounts(
    allocator: std.mem.Allocator,
    session: *runtime.Session,
    counts: [runtime.sampling_profile_max_code_count]usize,
    total_samples: usize,
) ![]CodeCount {
    _ = total_samples;
    const active = countActiveCodes(counts);
    if (active == 0) return try allocator.alloc(CodeCount, 0);

    var all = try allocator.alloc(CodeCount, active);
    var initialized: usize = 0;
    errdefer {
        for (all[0..initialized]) |entry| allocator.free(entry.source);
        allocator.free(all);
    }

    var idx: usize = 0;
    for (counts, 0..) |count, code_idx| {
        if (count == 0) continue;
        const code_id: u16 = @intCast(code_idx);
        const info = session.samplingProfileCodeInfo(code_id) orelse runtime.SamplingProfileCodeInfo{
            .id = code_id,
            .kind = .none,
            .source = "",
        };
        all[idx] = .{
            .id = code_id,
            .kind = runtime.Session.samplingProfileCodeKindName(info.kind),
            .count = count,
            .source = try normalizeSnippet(allocator, info.source),
        };
        idx += 1;
        initialized = idx;
    }

    sortCodeCountsDescending(all);
    const kept_len = @min(all.len, max_code_results);
    if (kept_len == all.len) return all;

    for (all[kept_len..]) |entry| allocator.free(entry.source);
    return try allocator.realloc(all, kept_len);
}

fn sortCountsDescending(items: []NamedCount) void {
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        var j = i;
        while (j > 0 and items[j - 1].count < items[j].count) : (j -= 1) {
            std.mem.swap(NamedCount, &items[j - 1], &items[j]);
        }
    }
}

fn writeCountSection(writer: anytype, title: []const u8, total_samples: usize, counts: []const NamedCount, max_items: usize) !void {
    var ordered: [op_sample_count]NamedCount = undefined;
    if (counts.len > ordered.len) return error.InvalidArgument;
    @memcpy(ordered[0..counts.len], counts);
    sortCountsDescending(ordered[0..counts.len]);

    try writer.print("{s}:\n", .{title});
    var emitted: usize = 0;
    for (ordered[0..counts.len]) |entry| {
        if (entry.count == 0) continue;
        const share = if (total_samples == 0)
            0.0
        else
            (@as(f64, @floatFromInt(entry.count)) * 100.0) / @as(f64, @floatFromInt(total_samples));
        try writer.print("  {s} count={d} share={d:.1}%\n", .{ entry.name, entry.count, share });
        emitted += 1;
        if (emitted == max_items) break;
    }
    if (emitted == 0) try writer.writeAll("  none\n");
}

fn writeCodeSection(writer: anytype, total_samples: usize, counts: []const CodeCount) !void {
    try writer.writeAll("codes:\n");
    if (counts.len == 0) {
        try writer.writeAll("  none\n");
        return;
    }

    for (counts) |entry| {
        const share = if (total_samples == 0)
            0.0
        else
            (@as(f64, @floatFromInt(entry.count)) * 100.0) / @as(f64, @floatFromInt(total_samples));
        try writer.print(
            "  id={d} kind={s} count={d} share={d:.1}% source={s}\n",
            .{ entry.id, entry.kind, entry.count, share, entry.source },
        );
    }
}

fn writeFunctionSection(writer: anytype, total_samples: usize, counts: []const FunctionCount) !void {
    try writer.writeAll("functions:\n");
    if (counts.len == 0) {
        try writer.writeAll("  none\n");
        return;
    }

    for (counts) |entry| {
        const share = if (total_samples == 0)
            0.0
        else
            (@as(f64, @floatFromInt(entry.count)) * 100.0) / @as(f64, @floatFromInt(total_samples));
        try writer.print(
            "  slot={d} name={s} count={d} share={d:.1}%\n",
            .{ entry.slot, entry.name, entry.count, share },
        );
    }
}

pub fn writeProfileResultText(writer: anytype, result: ProfileResult) !void {
    try writer.print(
        "profile {s} status={s} hz={d} period_ns={d} duration_ms={d:.3} samples={d}",
        .{
            result.name,
            result.status,
            result.sample_hz,
            result.sample_period_ns,
            result.duration_ms,
            result.total_samples,
        },
    );
    if (result.err_name) |err_name| try writer.print(" err={s}", .{err_name});
    try writer.writeByte('\n');
    try writeCountSection(writer, "labels", result.total_samples, result.labels[0..], result.labels.len);
    try writeFunctionSection(writer, result.total_samples, result.functions);
    try writeCodeSection(writer, result.total_samples, result.codes);
    try writeCountSection(writer, "ops", result.total_samples, result.ops[0..], 12);
}
