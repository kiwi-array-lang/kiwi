const builtin = @import("builtin");
const std = @import("std");

const Allocator = std.mem.Allocator;
const max_history_entries: usize = 1_000;
const max_history_file_bytes: usize = 1 << 20;
const supports_interactive_editor = switch (builtin.os.tag) {
    .windows, .wasi => false,
    else => true,
};

pub const ReplInput = struct {
    allocator: Allocator,
    interactive: bool,
    history: History,

    pub fn init(allocator: Allocator) !ReplInput {
        const interactive = supports_interactive_editor and
            std.fs.File.stdin().isTty() and
            std.fs.File.stdout().isTty();
        var history = if (interactive)
            try History.init(allocator)
        else
            History.initEmpty(allocator);
        errdefer history.deinit();
        return .{
            .allocator = allocator,
            .interactive = interactive,
            .history = history,
        };
    }

    pub fn deinit(self: *ReplInput) void {
        self.history.deinit();
        self.* = undefined;
    }

    pub fn readLine(self: *ReplInput, prompt: []const u8) !?[]u8 {
        if (!self.interactive) return readBufferedLine(self.allocator, prompt);
        return readInteractiveLine(self.allocator, prompt, &self.history);
    }

    pub fn rememberLine(self: *ReplInput, line: []const u8) !void {
        if (!self.interactive) return;
        try self.history.add(line);
    }
};

const History = struct {
    allocator: Allocator,
    entries: std.ArrayList([]u8),
    path: ?[]u8,

    fn initEmpty(allocator: Allocator) History {
        return .{
            .allocator = allocator,
            .entries = .empty,
            .path = null,
        };
    }

    fn init(allocator: Allocator) !History {
        return initWithOwnedPath(allocator, try defaultHistoryPath(allocator));
    }

    fn initWithPath(allocator: Allocator, path: ?[]const u8) !History {
        return initWithOwnedPath(
            allocator,
            if (path) |value| try allocator.dupe(u8, value) else null,
        );
    }

    fn initWithOwnedPath(allocator: Allocator, path: ?[]u8) !History {
        var history = History.initEmpty(allocator);
        history.path = path;
        history.loadFromDisk() catch {};
        return history;
    }

    fn deinit(self: *History) void {
        for (self.entries.items) |entry| self.allocator.free(entry);
        self.entries.deinit(self.allocator);
        if (self.path) |path| self.allocator.free(path);
        self.* = undefined;
    }

    fn add(self: *History, line: []const u8) !void {
        const clean = std.mem.trimRight(u8, line, "\r");
        if (std.mem.trim(u8, clean, " \t").len == 0) return;
        const appended = try self.appendOwned(clean);
        if (!appended) return;
        self.appendToDisk(clean) catch {};
    }

    fn appendOwned(self: *History, line: []const u8) !bool {
        if (self.entries.items.len != 0 and std.mem.eql(u8, self.entries.items[self.entries.items.len - 1], line)) return false;
        if (self.entries.items.len == max_history_entries) {
            const removed = self.entries.orderedRemove(0);
            self.allocator.free(removed);
        }
        try self.entries.append(self.allocator, try self.allocator.dupe(u8, line));
        return true;
    }

    fn loadFromDisk(self: *History) !void {
        const path = self.path orelse return;
        const file = openPathForRead(path) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close();

        const data = try file.readToEndAlloc(self.allocator, max_history_file_bytes);
        defer self.allocator.free(data);

        var lines = std.mem.tokenizeScalar(u8, data, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trimRight(u8, raw, "\r");
            if (line.len == 0) continue;
            _ = try self.appendOwned(line);
        }
    }

    fn appendToDisk(self: *History, line: []const u8) !void {
        const path = self.path orelse return;
        var file = try createPathForAppend(path);
        defer file.close();
        try file.seekFromEnd(0);
        try file.writeAll(line);
        try file.writeAll("\n");
    }
};

const HistoryCursor = struct {
    index: ?usize = null,
    draft: ?[]u8 = null,

    fn deinit(self: *HistoryCursor, allocator: Allocator) void {
        if (self.draft) |draft| allocator.free(draft);
        self.* = undefined;
    }

    fn previous(self: *HistoryCursor, allocator: Allocator, history: *const History, current: []const u8) !?[]const u8 {
        if (history.entries.items.len == 0) return null;
        if (self.index == null) {
            if (self.draft == null) self.draft = try allocator.dupe(u8, current);
            self.index = history.entries.items.len - 1;
            return history.entries.items[self.index.?];
        }
        if (self.index.? == 0) return history.entries.items[0];
        self.index = self.index.? - 1;
        return history.entries.items[self.index.?];
    }

    fn next(self: *HistoryCursor, history: *const History) ?[]const u8 {
        if (self.index == null) return null;
        if (self.index.? + 1 < history.entries.items.len) {
            self.index = self.index.? + 1;
            return history.entries.items[self.index.?];
        }
        self.index = null;
        return self.draft orelse "";
    }
};

const LineBuffer = struct {
    allocator: Allocator,
    bytes: std.ArrayList(u8),
    cursor: usize = 0,

    fn init(allocator: Allocator) LineBuffer {
        return .{
            .allocator = allocator,
            .bytes = .empty,
            .cursor = 0,
        };
    }

    fn deinit(self: *LineBuffer) void {
        self.bytes.deinit(self.allocator);
        self.* = undefined;
    }

    fn slice(self: *const LineBuffer) []const u8 {
        return self.bytes.items;
    }

    fn replace(self: *LineBuffer, line: []const u8) !void {
        self.bytes.clearRetainingCapacity();
        try self.bytes.appendSlice(self.allocator, line);
        self.cursor = self.bytes.items.len;
    }

    fn insertByte(self: *LineBuffer, byte: u8) !void {
        try self.bytes.insertSlice(self.allocator, self.cursor, &.{byte});
        self.cursor += 1;
    }

    fn moveLeft(self: *LineBuffer) void {
        if (self.cursor != 0) self.cursor -= 1;
    }

    fn moveRight(self: *LineBuffer) void {
        if (self.cursor < self.bytes.items.len) self.cursor += 1;
    }

    fn moveHome(self: *LineBuffer) void {
        self.cursor = 0;
    }

    fn moveEnd(self: *LineBuffer) void {
        self.cursor = self.bytes.items.len;
    }

    fn backspace(self: *LineBuffer) bool {
        if (self.cursor == 0) return false;
        self.cursor -= 1;
        _ = self.bytes.orderedRemove(self.cursor);
        return true;
    }

    fn deleteForward(self: *LineBuffer) bool {
        if (self.cursor >= self.bytes.items.len) return false;
        _ = self.bytes.orderedRemove(self.cursor);
        return true;
    }

    fn clear(self: *LineBuffer) void {
        self.bytes.clearRetainingCapacity();
        self.cursor = 0;
    }

    fn killToEnd(self: *LineBuffer) void {
        self.bytes.shrinkRetainingCapacity(self.cursor);
    }

    fn takeOwned(self: *LineBuffer) ![]u8 {
        return self.bytes.toOwnedSlice(self.allocator);
    }
};

const EditorKey = union(enum) {
    byte: u8,
    enter,
    backspace,
    delete_forward,
    left,
    right,
    up,
    down,
    home,
    end,
    ctrl_a,
    ctrl_c,
    ctrl_d,
    ctrl_e,
    ctrl_k,
    ctrl_l,
    ctrl_u,
    eof,
};

fn defaultHistoryPath(allocator: Allocator) !?[]u8 {
    if (std.process.getEnvVarOwned(allocator, "KIWI_HISTORY")) |raw| {
        if (raw.len == 0) {
            allocator.free(raw);
            return null;
        }
        return raw;
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }

    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        return try std.fmt.allocPrint(allocator, "{s}/.kiwi_history", .{home});
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    }
}

fn readBufferedLine(allocator: Allocator, prompt: []const u8) !?[]u8 {
    const stdin = std.fs.File.stdin().deprecatedReader();
    const stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.writeAll(prompt);

    var line = std.ArrayList(u8).empty;
    errdefer line.deinit(allocator);

    stdin.streamUntilDelimiter(line.writer(allocator), '\n', null) catch |err| switch (err) {
        error.EndOfStream => {
            try stdout.writeByte('\n');
            return null;
        },
        else => return err,
    };
    return try line.toOwnedSlice(allocator);
}

fn readInteractiveLine(allocator: Allocator, prompt: []const u8, history: *History) !?[]u8 {
    if (!supports_interactive_editor) return readBufferedLine(allocator, prompt);

    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();
    var terminal = RawTerminalState.init(stdin) catch return readBufferedLine(allocator, prompt);
    defer terminal.deinit(stdin);

    var line = LineBuffer.init(allocator);
    defer line.deinit();
    var history_cursor = HistoryCursor{};
    defer history_cursor.deinit(allocator);

    try stdout.writeAll(prompt);

    while (true) {
        switch (try readEditorKey(stdin)) {
            .byte => |byte| {
                if (byte == '\t') {
                    try line.insertByte(' ');
                } else if (byte >= 0x20 and byte != 0x7f) {
                    try line.insertByte(byte);
                } else {
                    continue;
                }
            },
            .enter => {
                try stdout.writeAll("\r\n");
                return try line.takeOwned();
            },
            .backspace => _ = line.backspace(),
            .delete_forward => {
                if (line.slice().len == 0) continue;
                _ = line.deleteForward();
            },
            .left => line.moveLeft(),
            .right => line.moveRight(),
            .home, .ctrl_a => line.moveHome(),
            .end, .ctrl_e => line.moveEnd(),
            .up => {
                if (try history_cursor.previous(allocator, history, line.slice())) |entry| {
                    try line.replace(entry);
                } else {
                    continue;
                }
            },
            .down => {
                if (history_cursor.next(history)) |entry| {
                    try line.replace(entry);
                } else {
                    continue;
                }
            },
            .ctrl_k => line.killToEnd(),
            .ctrl_u => line.clear(),
            .ctrl_l => {
                try stdout.writeAll("\x1b[H\x1b[2J");
            },
            .ctrl_c => {
                line.clear();
                try stdout.writeAll("^C\r\n");
                return try allocator.dupe(u8, "");
            },
            .ctrl_d => {
                if (line.slice().len == 0) {
                    try stdout.writeAll("\r\n");
                    return null;
                }
                _ = line.deleteForward();
            },
            .eof => {
                try stdout.writeAll("\r\n");
                return null;
            },
        }

        try redrawLine(stdout, prompt, line.slice(), line.cursor);
    }
}

fn redrawLine(stdout: std.fs.File, prompt: []const u8, line: []const u8, cursor: usize) !void {
    try stdout.writeAll("\r");
    try stdout.writeAll(prompt);
    try stdout.writeAll(line);
    try stdout.writeAll("\x1b[K");
    if (line.len > cursor) {
        var buffer: [32]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buffer, "\x1b[{d}D", .{line.len - cursor});
        try stdout.writeAll(seq);
    }
}

fn openPathForRead(path: []const u8) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) return std.fs.openFileAbsolute(path, .{});
    return std.fs.cwd().openFile(path, .{});
}

fn createPathForAppend(path: []const u8) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) return std.fs.createFileAbsolute(path, .{ .truncate = false });
    return std.fs.cwd().createFile(path, .{ .truncate = false });
}

fn readEditorKey(stdin: std.fs.File) !EditorKey {
    const byte = readByte(stdin) catch |err| switch (err) {
        error.EndOfStream => return .eof,
        else => return err,
    };
    return switch (byte) {
        '\r', '\n' => .enter,
        0x01 => .ctrl_a,
        0x03 => .ctrl_c,
        0x04 => .ctrl_d,
        0x05 => .ctrl_e,
        0x0b => .ctrl_k,
        0x0c => .ctrl_l,
        0x15 => .ctrl_u,
        0x08, 0x7f => .backspace,
        0x1b => try readEscapeSequence(stdin),
        else => .{ .byte = byte },
    };
}

fn readEscapeSequence(stdin: std.fs.File) !EditorKey {
    const first = readByte(stdin) catch return .{ .byte = 0x1b };
    if (first == '[') {
        const second = readByte(stdin) catch return .{ .byte = 0x1b };
        return switch (second) {
            'A' => .up,
            'B' => .down,
            'C' => .right,
            'D' => .left,
            'F', '8' => .end,
            'H', '1', '7' => .home,
            '3' => blk: {
                const third = readByte(stdin) catch break :blk .{ .byte = 0x1b };
                break :blk if (third == '~') .delete_forward else .{ .byte = 0x1b };
            },
            '4' => blk: {
                const third = readByte(stdin) catch break :blk .{ .byte = 0x1b };
                break :blk if (third == '~') .end else .{ .byte = 0x1b };
            },
            else => .{ .byte = 0x1b },
        };
    }
    if (first == 'O') {
        const second = readByte(stdin) catch return .{ .byte = 0x1b };
        return switch (second) {
            'F' => .end,
            'H' => .home,
            else => .{ .byte = 0x1b },
        };
    }
    return .{ .byte = 0x1b };
}

fn readByte(file: std.fs.File) !u8 {
    var buffer: [1]u8 = undefined;
    while (true) {
        const read_len = try file.read(&buffer);
        if (read_len == 0) return error.EndOfStream;
        return buffer[0];
    }
}

const RawTerminalState = if (supports_interactive_editor) struct {
    original: std.posix.termios,

    fn init(file: std.fs.File) !RawTerminalState {
        var raw = try std.posix.tcgetattr(file.handle);
        const original = raw;
        raw.iflag.BRKINT = false;
        raw.iflag.ICRNL = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;
        raw.iflag.IXON = false;
        raw.oflag.OPOST = false;
        raw.cflag.CSIZE = .CS8;
        raw.cflag.CREAD = true;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.lflag.ISIG = false;
        raw.cc[@intFromEnum(std.c.V.MIN)] = 1;
        raw.cc[@intFromEnum(std.c.V.TIME)] = 0;
        try std.posix.tcsetattr(file.handle, .FLUSH, raw);
        return .{ .original = original };
    }

    fn deinit(self: *const RawTerminalState, file: std.fs.File) void {
        std.posix.tcsetattr(file.handle, .NOW, self.original) catch {};
    }
} else struct {
    fn init(_: std.fs.File) !RawTerminalState {
        return error.Unsupported;
    }

    fn deinit(_: *const RawTerminalState, _: std.fs.File) void {}
};

test "history cursor preserves draft while browsing" {
    var history = try History.initWithPath(std.testing.allocator, null);
    defer history.deinit();
    try history.add("1+2");
    try history.add("3+4");

    var cursor = HistoryCursor{};
    defer cursor.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("3+4", (try cursor.previous(std.testing.allocator, &history, "draft")).?);
    try std.testing.expectEqualStrings("1+2", (try cursor.previous(std.testing.allocator, &history, "ignored")).?);
    try std.testing.expectEqualStrings("3+4", cursor.next(&history).?);
    try std.testing.expectEqualStrings("draft", cursor.next(&history).?);
    try std.testing.expect(cursor.next(&history) == null);
}

test "line buffer edits around the cursor" {
    var line = LineBuffer.init(std.testing.allocator);
    defer line.deinit();

    try line.insertByte('1');
    try line.insertByte('3');
    line.moveLeft();
    try line.insertByte('2');
    try std.testing.expectEqualStrings("123", line.slice());
    try std.testing.expectEqual(@as(usize, 2), line.cursor);

    try std.testing.expect(line.backspace());
    try std.testing.expectEqualStrings("13", line.slice());
    try std.testing.expectEqual(@as(usize, 1), line.cursor);

    try std.testing.expect(line.deleteForward());
    try std.testing.expectEqualStrings("1", line.slice());
    try std.testing.expectEqual(@as(usize, 1), line.cursor);
}

test "history persists entries and skips consecutive duplicates" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/kiwi_history", .{tmp.sub_path[0..]});
    defer std.testing.allocator.free(path);

    {
        var history = try History.initWithPath(std.testing.allocator, path);
        defer history.deinit();
        try history.add("x:1");
        try history.add("1+2");
        try history.add("1+2");
    }

    {
        var history = try History.initWithPath(std.testing.allocator, path);
        defer history.deinit();
        try std.testing.expectEqual(@as(usize, 2), history.entries.items.len);
        try std.testing.expectEqualStrings("x:1", history.entries.items[0]);
        try std.testing.expectEqualStrings("1+2", history.entries.items[1]);
    }
}
