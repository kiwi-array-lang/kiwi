const std = @import("std");

pub const SourceKind = enum {
    csv,
    parquet,

    pub fn detect(path: []const u8) ?SourceKind {
        const ext = std.fs.path.extension(path);
        if (std.ascii.eqlIgnoreCase(ext, ".csv")) return .csv;
        if (std.ascii.eqlIgnoreCase(ext, ".parquet")) return .parquet;
        return null;
    }

    pub fn text(self: SourceKind) []const u8 {
        return @tagName(self);
    }
};

pub const Connection = struct {
    pub fn init(_: std.mem.Allocator, _: ?[]const u8) !Connection {
        return error.Unsupported;
    }

    pub fn deinit(_: *Connection) void {}

    pub fn validateQuery(_: *Connection, _: []const u8) !void {
        return error.Unsupported;
    }

    pub fn countFileRows(_: *Connection, _: SourceKind, _: []const u8) !usize {
        return error.Unsupported;
    }

    pub fn countFileRowsWithDiagnostic(_: *Connection, _: SourceKind, _: []const u8, diagnostic: *?[]u8) !usize {
        diagnostic.* = null;
        return error.Unsupported;
    }

    pub fn countQueryRows(_: *Connection, _: []const u8) !usize {
        return error.Unsupported;
    }

    pub fn countQueryRowsWithDiagnostic(_: *Connection, _: []const u8, diagnostic: *?[]u8) !usize {
        diagnostic.* = null;
        return error.Unsupported;
    }

    pub fn executeQueryResult(_: *Connection, _: []const u8) !QueryResult {
        return error.Unsupported;
    }
};

pub fn sqlStringLiteral(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.append(allocator, '\'');
    for (text) |ch| {
        if (ch == '\'') {
            try out.appendSlice(allocator, "''");
        } else {
            try out.append(allocator, ch);
        }
    }
    try out.append(allocator, '\'');
    return try out.toOwnedSlice(allocator);
}

pub fn sqlIdentifier(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.append(allocator, '"');
    for (text) |ch| {
        if (ch == '"') {
            try out.appendSlice(allocator, "\"\"");
        } else {
            try out.append(allocator, ch);
        }
    }
    try out.append(allocator, '"');
    return try out.toOwnedSlice(allocator);
}

pub const PreparedStatement = struct {
    pub fn init(_: *Connection, _: []const u8) !PreparedStatement {
        return error.Unsupported;
    }

    pub fn initWithDiagnostic(_: *Connection, _: []const u8, diagnostic: *?[]u8) !PreparedStatement {
        diagnostic.* = null;
        return error.Unsupported;
    }

    pub fn deinit(_: *PreparedStatement) void {}

    pub fn paramCount(_: *const PreparedStatement) usize {
        return 0;
    }

    pub fn parameterName(_: *PreparedStatement, _: std.mem.Allocator, _: usize) ![]u8 {
        return error.Unsupported;
    }

    pub fn bindNull(_: *PreparedStatement, _: usize) !void {
        return error.Unsupported;
    }

    pub fn bindBoolean(_: *PreparedStatement, _: usize, _: bool) !void {
        return error.Unsupported;
    }

    pub fn bindInt64(_: *PreparedStatement, _: usize, _: i64) !void {
        return error.Unsupported;
    }

    pub fn bindDouble(_: *PreparedStatement, _: usize, _: f64) !void {
        return error.Unsupported;
    }

    pub fn bindVarchar(_: *PreparedStatement, _: usize, _: []const u8) !void {
        return error.Unsupported;
    }

    pub fn clearBindings(_: *PreparedStatement) !void {
        return error.Unsupported;
    }

    pub fn querySingleCount(_: *PreparedStatement) !usize {
        return error.Unsupported;
    }

    pub fn querySingleCountWithDiagnostic(_: *PreparedStatement, diagnostic: *?[]u8) !usize {
        diagnostic.* = null;
        return error.Unsupported;
    }

    pub fn execute(_: *PreparedStatement) !void {
        return error.Unsupported;
    }

    pub fn executeWithDiagnostic(_: *PreparedStatement, diagnostic: *?[]u8) !void {
        diagnostic.* = null;
        return error.Unsupported;
    }

    pub fn executeResult(_: *PreparedStatement) !QueryResult {
        return error.Unsupported;
    }

    pub fn executeResultWithDiagnostic(_: *PreparedStatement, diagnostic: *?[]u8) !QueryResult {
        diagnostic.* = null;
        return error.Unsupported;
    }
};

pub const Appender = struct {
    pub fn init(_: *Connection, _: []const u8) !Appender {
        return error.Unsupported;
    }

    pub fn deinit(_: *Appender) void {}

    pub fn closeWithDiagnostic(_: *Appender, diagnostic: *?[]u8) !void {
        diagnostic.* = null;
        return error.Unsupported;
    }

    pub fn endRow(_: *Appender) !void {
        return error.Unsupported;
    }

    pub fn appendNull(_: *Appender) !void {
        return error.Unsupported;
    }

    pub fn appendBool(_: *Appender, _: bool) !void {
        return error.Unsupported;
    }

    pub fn appendInt64(_: *Appender, _: i64) !void {
        return error.Unsupported;
    }

    pub fn appendDouble(_: *Appender, _: f64) !void {
        return error.Unsupported;
    }

    pub fn appendVarchar(_: *Appender, _: []const u8) !void {
        return error.Unsupported;
    }

    pub fn appendDate(_: *Appender, _: i32) !void {
        return error.Unsupported;
    }

    pub fn appendTime(_: *Appender, _: i64) !void {
        return error.Unsupported;
    }

    pub fn appendTimestamp(_: *Appender, _: i64) !void {
        return error.Unsupported;
    }

    pub fn appendTimeNs(_: *Appender, _: i64) !void {
        return error.Unsupported;
    }

    pub fn appendTimeTz(_: *Appender, _: i64) !void {
        return error.Unsupported;
    }

    pub fn appendTimestampS(_: *Appender, _: i64) !void {
        return error.Unsupported;
    }

    pub fn appendTimestampMs(_: *Appender, _: i64) !void {
        return error.Unsupported;
    }

    pub fn appendTimestampNs(_: *Appender, _: i64) !void {
        return error.Unsupported;
    }

    pub fn appendTimestampTz(_: *Appender, _: i64) !void {
        return error.Unsupported;
    }
};

pub const QueryResult = struct {
    pub fn deinit(_: *QueryResult) void {}

    pub fn rowCount(_: *const QueryResult) usize {
        return 0;
    }

    pub fn columnCount(_: *const QueryResult) usize {
        return 0;
    }

    pub fn columnName(_: *const QueryResult, _: usize) ![]u8 {
        return error.Unsupported;
    }

    pub fn columnTypeId(_: *const QueryResult, _: usize) !TypeId {
        return error.Unsupported;
    }

    pub fn fetchChunk(_: *QueryResult) ?DataChunk {
        return null;
    }
};

pub const TypeId = enum(u8) {
    invalid = 0,
    boolean = 1,
    tinyint = 2,
    smallint = 3,
    integer = 4,
    bigint = 5,
    utinyint = 6,
    usmallint = 7,
    uinteger = 8,
    ubigint = 9,
    float = 10,
    double = 11,
    timestamp = 12,
    date = 13,
    time = 14,
    interval = 15,
    hugeint = 16,
    varchar = 17,
    blob = 18,
    decimal = 19,
    timestamp_s = 20,
    timestamp_ms = 21,
    timestamp_ns = 22,
    enum_type = 23,
    list = 24,
    struct_type = 25,
    map = 26,
    uuid = 27,
    union_type = 28,
    bit = 29,
    time_tz = 30,
    timestamp_tz = 31,
    uhugeint = 32,
    array = 33,
    any = 34,
    bignum = 35,
    sqlnull = 36,
    string_literal = 37,
    integer_literal = 38,
    time_ns = 39,
};

pub const DataChunk = struct {
    pub fn deinit(_: *DataChunk) void {}

    pub fn rowCount(_: *const DataChunk) usize {
        return 0;
    }

    pub fn vectorData(_: *const DataChunk, _: usize) !*const anyopaque {
        return error.Unsupported;
    }

    pub fn validity(_: *const DataChunk, _: usize) ?[*]const u64 {
        return null;
    }

    pub fn rowIsValid(_: *const DataChunk, _: usize, _: usize) bool {
        return false;
    }

    pub fn rowBool(_: *const DataChunk, _: usize, _: usize) !bool {
        return error.Unsupported;
    }

    pub fn rowInt(_: *const DataChunk, _: usize, _: usize, _: TypeId) !i64 {
        return error.Unsupported;
    }

    pub fn rowFloat(_: *const DataChunk, _: usize, _: usize, _: TypeId) !f64 {
        return error.Unsupported;
    }

    pub fn rowString(_: *const DataChunk, _: std.mem.Allocator, _: usize, _: usize) ![]u8 {
        return error.Unsupported;
    }
};
