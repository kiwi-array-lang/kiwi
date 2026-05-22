const std = @import("std");

pub const c = @cImport({
    @cInclude("duckdb.h");
});

pub const ArrowFlag = struct {
    pub const dictionary_ordered: i64 = 1;
    pub const nullable: i64 = 2;
    pub const map_keys_sorted: i64 = 4;
};

pub const ArrowSchema = extern struct {
    format: ?[*:0]const u8,
    name: ?[*:0]const u8,
    metadata: ?[*:0]const u8,
    flags: i64,
    n_children: i64,
    children: ?[*]*ArrowSchema,
    dictionary: ?*ArrowSchema,
    release: ?*const fn (*ArrowSchema) callconv(.c) void,
    private_data: ?*anyopaque,
};

pub const ArrowArray = extern struct {
    length: i64,
    null_count: i64,
    offset: i64,
    n_buffers: i64,
    n_children: i64,
    buffers: ?[*]const ?*const anyopaque,
    children: ?[*]*ArrowArray,
    dictionary: ?*ArrowArray,
    release: ?*const fn (*ArrowArray) callconv(.c) void,
    private_data: ?*anyopaque,
};

pub const ArrowFieldSummary = struct {
    name: []u8,
    format: []u8,
    nullable: bool,
    buffer_count: usize,
    null_count: i64,
};

pub const ArrowExportSummary = struct {
    root_format: []u8,
    total_row_count: usize,
    first_batch_row_count: usize,
    fields: []ArrowFieldSummary,

    pub fn deinit(self: *ArrowExportSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.root_format);
        for (self.fields) |field| {
            allocator.free(field.name);
            allocator.free(field.format);
        }
        allocator.free(self.fields);
        self.* = undefined;
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
    allocator: std.mem.Allocator,
    db: c.duckdb_database = null,
    conn: c.duckdb_connection = null,

    pub fn init(allocator: std.mem.Allocator, db_path: ?[]const u8) !Connection {
        var diagnostic: ?[]u8 = null;
        defer if (diagnostic) |text| allocator.free(text);
        return try initWithDiagnostic(allocator, db_path, &diagnostic);
    }

    pub fn initWithDiagnostic(allocator: std.mem.Allocator, db_path: ?[]const u8, diagnostic: *?[]u8) !Connection {
        diagnostic.* = null;
        var self = Connection{ .allocator = allocator };

        const path_z = if (db_path) |path| try allocator.dupeZ(u8, path) else null;
        defer if (path_z) |buf| allocator.free(buf);

        if (c.duckdb_open(if (path_z) |buf| buf.ptr else null, &self.db) == c.DuckDBError) {
            return error.DuckDbOpenFailed;
        }
        errdefer c.duckdb_close(&self.db);

        if (c.duckdb_connect(self.db, &self.conn) == c.DuckDBError) {
            return error.DuckDbConnectFailed;
        }
        try self.loadConfiguredExtensionsWithDiagnostic(diagnostic);
        return self;
    }

    pub fn deinit(self: *Connection) void {
        if (self.conn != null) c.duckdb_disconnect(&self.conn);
        if (self.db != null) c.duckdb_close(&self.db);
    }

    pub fn countFileRows(self: *Connection, source_kind: SourceKind, source_path: []const u8) !usize {
        var diagnostic: ?[]u8 = null;
        defer if (diagnostic) |text| self.allocator.free(text);
        return try self.countFileRowsWithDiagnostic(source_kind, source_path, &diagnostic);
    }

    pub fn countFileRowsWithDiagnostic(
        self: *Connection,
        source_kind: SourceKind,
        source_path: []const u8,
        diagnostic: *?[]u8,
    ) !usize {
        const sql = try buildCountSql(self.allocator, source_kind, source_path);
        defer self.allocator.free(sql);
        return try self.querySingleCountWithDiagnostic(sql, diagnostic);
    }

    pub fn validateQuery(self: *Connection, sql: []const u8) !void {
        var stmt = try PreparedStatement.init(self, sql);
        defer stmt.deinit();
    }

    pub fn countQueryRows(self: *Connection, sql: []const u8) !usize {
        var diagnostic: ?[]u8 = null;
        defer if (diagnostic) |text| self.allocator.free(text);
        return try self.countQueryRowsWithDiagnostic(sql, &diagnostic);
    }

    pub fn countQueryRowsWithDiagnostic(self: *Connection, sql: []const u8, diagnostic: *?[]u8) !usize {
        const wrapped = try buildWrappedCountSql(self.allocator, sql);
        defer self.allocator.free(wrapped);
        return try self.querySingleCountWithDiagnostic(wrapped, diagnostic);
    }

    pub fn debugArrowSummary(self: *Connection, sql: []const u8) !ArrowExportSummary {
        var stmt = try PreparedStatement.init(self, sql);
        defer stmt.deinit();
        return try stmt.debugArrowSummary(self.allocator);
    }

    pub fn executeQueryResult(self: *Connection, sql: []const u8) !QueryResult {
        var stmt = try PreparedStatement.init(self, sql);
        defer stmt.deinit();
        return try stmt.executeResult();
    }

    fn querySingleCountWithDiagnostic(self: *Connection, sql: []const u8, diagnostic: *?[]u8) !usize {
        diagnostic.* = null;
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        var raw = std.mem.zeroInit(c.duckdb_result, .{});
        defer c.duckdb_destroy_result(&raw);
        if (c.duckdb_query(self.conn, sql_z.ptr, &raw) == c.DuckDBError) {
            diagnostic.* = duplicateResultError(self.allocator, &raw);
            return error.DuckDbQueryFailed;
        }
        if (c.duckdb_column_count(&raw) != 1 or c.duckdb_row_count(&raw) != 1) {
            return error.DuckDbUnexpectedResult;
        }
        if (c.duckdb_value_is_null(&raw, 0, 0)) return error.DuckDbUnexpectedResult;

        const value = c.duckdb_value_int64(&raw, 0, 0);
        if (value < 0) return error.DuckDbUnexpectedResult;
        return @intCast(value);
    }

    fn loadConfiguredExtensions(self: *Connection) !void {
        var diagnostic: ?[]u8 = null;
        defer if (diagnostic) |text| self.allocator.free(text);
        try self.loadConfiguredExtensionsWithDiagnostic(&diagnostic);
    }

    fn loadConfiguredExtensionsWithDiagnostic(self: *Connection, diagnostic: *?[]u8) !void {
        diagnostic.* = null;
        const extension_path = std.process.getEnvVarOwned(self.allocator, "KIWI_DUCKDB_EXTENSION_LOAD_PATH") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => return,
            else => return err,
        };
        defer self.allocator.free(extension_path);

        const trimmed = std.mem.trim(u8, extension_path, " \t\r\n");
        if (trimmed.len == 0) return;

        try self.loadExtensionPathWithDiagnostic(trimmed, diagnostic);
    }

    fn loadExtensionPath(self: *Connection, extension_path: []const u8) !void {
        var diagnostic: ?[]u8 = null;
        defer if (diagnostic) |text| self.allocator.free(text);
        try self.loadExtensionPathWithDiagnostic(extension_path, &diagnostic);
    }

    fn loadExtensionPathWithDiagnostic(self: *Connection, extension_path: []const u8, diagnostic: *?[]u8) !void {
        diagnostic.* = null;
        const quoted = try sqlStringLiteral(self.allocator, extension_path);
        defer self.allocator.free(quoted);

        const sql = try std.fmt.allocPrint(self.allocator, "LOAD {s}", .{quoted});
        defer self.allocator.free(sql);

        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        var raw = std.mem.zeroInit(c.duckdb_result, .{});
        defer c.duckdb_destroy_result(&raw);
        if (c.duckdb_query(self.conn, sql_z.ptr, &raw) == c.DuckDBError) {
            diagnostic.* = duplicateResultError(self.allocator, &raw);
            return error.DuckDbQueryFailed;
        }
    }
};

pub const Appender = struct {
    allocator: std.mem.Allocator,
    raw: c.duckdb_appender = null,

    pub fn init(conn: *Connection, table_name: []const u8) !Appender {
        const table_z = try conn.allocator.dupeZ(u8, table_name);
        defer conn.allocator.free(table_z);

        var self = Appender{ .allocator = conn.allocator };
        if (c.duckdb_appender_create(conn.conn, null, table_z.ptr, &self.raw) == c.DuckDBError) {
            return error.DuckDbAppenderFailed;
        }
        return self;
    }

    pub fn deinit(self: *Appender) void {
        if (self.raw != null) _ = c.duckdb_appender_destroy(&self.raw);
    }

    pub fn close(self: *Appender) !void {
        var diagnostic: ?[]u8 = null;
        defer if (diagnostic) |text| self.allocator.free(text);
        try self.closeWithDiagnostic(&diagnostic);
    }

    pub fn closeWithDiagnostic(self: *Appender, diagnostic: *?[]u8) !void {
        diagnostic.* = null;
        if (c.duckdb_appender_close(self.raw) == c.DuckDBError) {
            diagnostic.* = duplicateAppenderError(self.allocator, self.raw);
            return error.DuckDbAppenderFailed;
        }
    }

    pub fn endRow(self: *Appender) !void {
        if (c.duckdb_appender_end_row(self.raw) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }

    pub fn appendNull(self: *Appender) !void {
        if (c.duckdb_append_null(self.raw) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }

    pub fn appendBool(self: *Appender, value: bool) !void {
        if (c.duckdb_append_bool(self.raw, value) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }

    pub fn appendInt64(self: *Appender, value: i64) !void {
        if (c.duckdb_append_int64(self.raw, value) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }

    pub fn appendDouble(self: *Appender, value: f64) !void {
        if (c.duckdb_append_double(self.raw, value) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }

    pub fn appendVarchar(self: *Appender, value: []const u8) !void {
        if (c.duckdb_append_varchar_length(self.raw, value.ptr, @intCast(value.len)) == c.DuckDBError) {
            return error.DuckDbAppenderFailed;
        }
    }

    pub fn appendDate(self: *Appender, days: i32) !void {
        if (c.duckdb_append_date(self.raw, .{ .days = days }) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }

    pub fn appendTime(self: *Appender, micros: i64) !void {
        if (c.duckdb_append_time(self.raw, .{ .micros = micros }) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }

    pub fn appendTimestamp(self: *Appender, micros: i64) !void {
        if (c.duckdb_append_timestamp(self.raw, .{ .micros = micros }) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }

    pub fn appendTimeNs(self: *Appender, nanos: i64) !void {
        var value = c.duckdb_create_time_ns(.{ .nanos = nanos });
        if (value == null) return error.OutOfMemory;
        defer c.duckdb_destroy_value(&value);
        if (c.duckdb_append_value(self.raw, value) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }

    pub fn appendTimeTz(self: *Appender, bits: i64) !void {
        var value = c.duckdb_create_time_tz_value(.{ .bits = @bitCast(bits) });
        if (value == null) return error.OutOfMemory;
        defer c.duckdb_destroy_value(&value);
        if (c.duckdb_append_value(self.raw, value) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }

    pub fn appendTimestampS(self: *Appender, seconds: i64) !void {
        var value = c.duckdb_create_timestamp_s(.{ .seconds = seconds });
        if (value == null) return error.OutOfMemory;
        defer c.duckdb_destroy_value(&value);
        if (c.duckdb_append_value(self.raw, value) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }

    pub fn appendTimestampMs(self: *Appender, millis: i64) !void {
        var value = c.duckdb_create_timestamp_ms(.{ .millis = millis });
        if (value == null) return error.OutOfMemory;
        defer c.duckdb_destroy_value(&value);
        if (c.duckdb_append_value(self.raw, value) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }

    pub fn appendTimestampNs(self: *Appender, nanos: i64) !void {
        var value = c.duckdb_create_timestamp_ns(.{ .nanos = nanos });
        if (value == null) return error.OutOfMemory;
        defer c.duckdb_destroy_value(&value);
        if (c.duckdb_append_value(self.raw, value) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }

    pub fn appendTimestampTz(self: *Appender, micros: i64) !void {
        var value = c.duckdb_create_timestamp_tz(.{ .micros = micros });
        if (value == null) return error.OutOfMemory;
        defer c.duckdb_destroy_value(&value);
        if (c.duckdb_append_value(self.raw, value) == c.DuckDBError) return error.DuckDbAppenderFailed;
    }
};

pub const PreparedStatement = struct {
    allocator: std.mem.Allocator,
    stmt: c.duckdb_prepared_statement = null,

    pub fn init(conn: *Connection, sql: []const u8) !PreparedStatement {
        var diagnostic: ?[]u8 = null;
        defer if (diagnostic) |text| conn.allocator.free(text);
        return try initWithDiagnostic(conn, sql, &diagnostic);
    }

    pub fn initWithDiagnostic(conn: *Connection, sql: []const u8, diagnostic: *?[]u8) !PreparedStatement {
        diagnostic.* = null;
        const sql_z = try conn.allocator.dupeZ(u8, sql);
        defer conn.allocator.free(sql_z);

        var self = PreparedStatement{ .allocator = conn.allocator };
        if (c.duckdb_prepare(conn.conn, sql_z.ptr, &self.stmt) == c.DuckDBError) {
            diagnostic.* = duplicatePrepareError(conn.allocator, self.stmt);
            return error.DuckDbPrepareFailed;
        }
        return self;
    }

    pub fn deinit(self: *PreparedStatement) void {
        if (self.stmt != null) c.duckdb_destroy_prepare(&self.stmt);
    }

    pub fn paramCount(self: *const PreparedStatement) usize {
        return @intCast(c.duckdb_nparams(self.stmt));
    }

    pub fn parameterName(self: *PreparedStatement, allocator: std.mem.Allocator, index: usize) ![]u8 {
        const raw = c.duckdb_parameter_name(self.stmt, @intCast(index + 1)) orelse return error.DuckDbParameterNameFailed;
        defer c.duckdb_free(@constCast(raw));
        return try allocator.dupe(u8, std.mem.span(raw));
    }

    pub fn bindNull(self: *PreparedStatement, index: usize) !void {
        if (c.duckdb_bind_null(self.stmt, @intCast(index + 1)) == c.DuckDBError) {
            return error.DuckDbBindFailed;
        }
    }

    pub fn bindBoolean(self: *PreparedStatement, index: usize, value: bool) !void {
        if (c.duckdb_bind_boolean(self.stmt, @intCast(index + 1), value) == c.DuckDBError) {
            return error.DuckDbBindFailed;
        }
    }

    pub fn bindInt64(self: *PreparedStatement, index: usize, value: i64) !void {
        if (c.duckdb_bind_int64(self.stmt, @intCast(index + 1), value) == c.DuckDBError) {
            return error.DuckDbBindFailed;
        }
    }

    pub fn bindDouble(self: *PreparedStatement, index: usize, value: f64) !void {
        if (c.duckdb_bind_double(self.stmt, @intCast(index + 1), value) == c.DuckDBError) {
            return error.DuckDbBindFailed;
        }
    }

    pub fn bindVarchar(self: *PreparedStatement, index: usize, value: []const u8) !void {
        if (c.duckdb_bind_varchar_length(self.stmt, @intCast(index + 1), value.ptr, @intCast(value.len)) == c.DuckDBError) {
            return error.DuckDbBindFailed;
        }
    }

    pub fn clearBindings(self: *PreparedStatement) !void {
        if (c.duckdb_clear_bindings(self.stmt) == c.DuckDBError) {
            return error.DuckDbBindFailed;
        }
    }

    pub fn execute(self: *PreparedStatement) !void {
        var diagnostic: ?[]u8 = null;
        defer if (diagnostic) |text| self.allocator.free(text);
        try self.executeWithDiagnostic(&diagnostic);
    }

    pub fn executeWithDiagnostic(self: *PreparedStatement, diagnostic: *?[]u8) !void {
        diagnostic.* = null;
        var raw = std.mem.zeroInit(c.duckdb_result, .{});
        defer c.duckdb_destroy_result(&raw);
        if (c.duckdb_execute_prepared(self.stmt, &raw) == c.DuckDBError) {
            diagnostic.* = duplicateResultError(self.allocator, &raw);
            return error.DuckDbQueryFailed;
        }
    }

    pub fn executeResult(self: *PreparedStatement) !QueryResult {
        var diagnostic: ?[]u8 = null;
        defer if (diagnostic) |text| self.allocator.free(text);
        return try self.executeResultWithDiagnostic(&diagnostic);
    }

    pub fn executeResultWithDiagnostic(self: *PreparedStatement, diagnostic: *?[]u8) !QueryResult {
        diagnostic.* = null;
        var raw = std.mem.zeroInit(c.duckdb_result, .{});
        errdefer c.duckdb_destroy_result(&raw);
        if (c.duckdb_execute_prepared(self.stmt, &raw) == c.DuckDBError) {
            diagnostic.* = duplicateResultError(self.allocator, &raw);
            return error.DuckDbQueryFailed;
        }
        return .{
            .allocator = self.allocator,
            .raw = raw,
        };
    }

    pub fn querySingleCount(self: *PreparedStatement) !usize {
        var diagnostic: ?[]u8 = null;
        defer if (diagnostic) |text| self.allocator.free(text);
        return try self.querySingleCountWithDiagnostic(&diagnostic);
    }

    pub fn querySingleCountWithDiagnostic(self: *PreparedStatement, diagnostic: *?[]u8) !usize {
        diagnostic.* = null;
        var raw = std.mem.zeroInit(c.duckdb_result, .{});
        defer c.duckdb_destroy_result(&raw);
        if (c.duckdb_execute_prepared(self.stmt, &raw) == c.DuckDBError) {
            diagnostic.* = duplicateResultError(self.allocator, &raw);
            return error.DuckDbQueryFailed;
        }
        if (c.duckdb_column_count(&raw) != 1 or c.duckdb_row_count(&raw) != 1) {
            return error.DuckDbUnexpectedResult;
        }
        if (c.duckdb_value_is_null(&raw, 0, 0)) return error.DuckDbUnexpectedResult;

        const value = c.duckdb_value_int64(&raw, 0, 0);
        if (value < 0) return error.DuckDbUnexpectedResult;
        return @intCast(value);
    }

    pub fn debugArrowSummary(self: *PreparedStatement, allocator: std.mem.Allocator) !ArrowExportSummary {
        var raw = std.mem.zeroInit(c.duckdb_result, .{});
        defer c.duckdb_destroy_result(&raw);
        if (c.duckdb_execute_prepared(self.stmt, &raw) == c.DuckDBError) {
            return error.DuckDbQueryFailed;
        }

        const column_count: usize = @intCast(c.duckdb_column_count(&raw));
        var arrow_options = c.duckdb_result_get_arrow_options(&raw);
        defer c.duckdb_destroy_arrow_options(&arrow_options);

        const logical_types = try allocator.alloc(c.duckdb_logical_type, column_count);
        defer {
            for (logical_types) |*logical_type| c.duckdb_destroy_logical_type(logical_type);
            allocator.free(logical_types);
        }

        const names = try allocator.alloc([*:0]const u8, column_count);
        defer allocator.free(names);

        for (0..column_count) |idx| {
            logical_types[idx] = c.duckdb_column_logical_type(&raw, @intCast(idx));
            if (logical_types[idx] == null) return error.DuckDbUnexpectedResult;
            names[idx] = c.duckdb_column_name(&raw, @intCast(idx)) orelse return error.DuckDbUnexpectedResult;
        }

        var schema = std.mem.zeroes(ArrowSchema);
        defer releaseArrowSchema(&schema);
        try checkArrowError(c.duckdb_to_arrow_schema(
            arrow_options,
            logical_types.ptr,
            @ptrCast(names.ptr),
            @intCast(column_count),
            @ptrCast(&schema),
        ));

        var first_batch_row_count: usize = 0;
        var array = std.mem.zeroes(ArrowArray);
        var array_ready = false;
        defer if (array_ready) releaseArrowArray(&array);

        var chunk = c.duckdb_fetch_chunk(raw);
        defer if (chunk != null) c.duckdb_destroy_data_chunk(&chunk);
        if (chunk != null) {
            try checkArrowError(c.duckdb_data_chunk_to_arrow(arrow_options, chunk, @ptrCast(&array)));
            array_ready = true;
            if (array.length < 0 or array.n_children < 0) return error.DuckDbUnexpectedResult;
            first_batch_row_count = @intCast(array.length);
            if (@as(usize, @intCast(array.n_children)) != column_count) return error.DuckDbUnexpectedResult;
        }

        return try buildArrowSummary(
            allocator,
            &schema,
            if (array_ready) &array else null,
            @intCast(c.duckdb_row_count(&raw)),
            first_batch_row_count,
        );
    }
};

pub const QueryResult = struct {
    allocator: std.mem.Allocator,
    raw: c.duckdb_result,

    pub fn deinit(self: *QueryResult) void {
        c.duckdb_destroy_result(&self.raw);
    }

    pub fn rowCount(self: *const QueryResult) usize {
        return @intCast(c.duckdb_row_count(@constCast(&self.raw)));
    }

    pub fn columnCount(self: *const QueryResult) usize {
        return @intCast(c.duckdb_column_count(@constCast(&self.raw)));
    }

    pub fn columnName(self: *const QueryResult, index: usize) ![]u8 {
        const raw_name = c.duckdb_column_name(@constCast(&self.raw), @intCast(index)) orelse return error.DuckDbUnexpectedResult;
        return try self.allocator.dupe(u8, std.mem.span(raw_name));
    }

    pub fn columnTypeId(self: *const QueryResult, index: usize) !TypeId {
        var logical_type = c.duckdb_column_logical_type(@constCast(&self.raw), @intCast(index));
        defer c.duckdb_destroy_logical_type(&logical_type);
        if (logical_type == null) return error.DuckDbUnexpectedResult;
        return @enumFromInt(c.duckdb_get_type_id(logical_type));
    }

    pub fn fetchChunk(self: *QueryResult) ?DataChunk {
        const raw_chunk = c.duckdb_fetch_chunk(self.raw);
        if (raw_chunk == null) return null;
        return .{ .raw = raw_chunk };
    }
};

pub const DataChunk = struct {
    raw: c.duckdb_data_chunk,

    pub fn deinit(self: *DataChunk) void {
        c.duckdb_destroy_data_chunk(&self.raw);
    }

    pub fn rowCount(self: *const DataChunk) usize {
        return @intCast(c.duckdb_data_chunk_get_size(self.raw));
    }

    pub fn vector(self: *const DataChunk, index: usize) c.duckdb_vector {
        return c.duckdb_data_chunk_get_vector(self.raw, @intCast(index));
    }

    pub fn vectorData(self: *const DataChunk, index: usize) !*const anyopaque {
        const raw_vector = self.vector(index);
        return c.duckdb_vector_get_data(raw_vector) orelse error.DuckDbUnexpectedResult;
    }

    pub fn validity(self: *const DataChunk, index: usize) ?[*]const u64 {
        const raw_vector = self.vector(index);
        return c.duckdb_vector_get_validity(raw_vector);
    }

    pub fn rowIsValid(self: *const DataChunk, index: usize, row: usize) bool {
        const maybe_mask = self.validity(index);
        if (maybe_mask == null) return true;
        const mask = maybe_mask.?;
        const entry_idx = row / 64;
        const idx_in_entry = row % 64;
        return (mask[entry_idx] & (@as(u64, 1) << @intCast(idx_in_entry))) != 0;
    }

    pub fn rowBool(self: *const DataChunk, index: usize, row: usize) !bool {
        const data = try self.vectorData(index);
        const items: [*]const bool = @ptrCast(@alignCast(data));
        return items[row];
    }

    pub fn rowInt(self: *const DataChunk, index: usize, row: usize, type_id: TypeId) !i64 {
        const data = try self.vectorData(index);
        return switch (type_id) {
            .tinyint => @as([*]const i8, @ptrCast(@alignCast(data)))[row],
            .smallint => @as([*]const i16, @ptrCast(@alignCast(data)))[row],
            .integer => @as([*]const i32, @ptrCast(@alignCast(data)))[row],
            .bigint => @as([*]const i64, @ptrCast(@alignCast(data)))[row],
            .utinyint => @as([*]const u8, @ptrCast(@alignCast(data)))[row],
            .usmallint => @as([*]const u16, @ptrCast(@alignCast(data)))[row],
            .uinteger => @as([*]const u32, @ptrCast(@alignCast(data)))[row],
            .ubigint => std.math.cast(i64, @as([*]const u64, @ptrCast(@alignCast(data)))[row]) orelse error.Unsupported,
            else => error.Unsupported,
        };
    }

    pub fn rowFloat(self: *const DataChunk, index: usize, row: usize, type_id: TypeId) !f64 {
        const data = try self.vectorData(index);
        return switch (type_id) {
            .float => @as([*]const f32, @ptrCast(@alignCast(data)))[row],
            .double => @as([*]const f64, @ptrCast(@alignCast(data)))[row],
            else => error.Unsupported,
        };
    }

    pub fn rowString(self: *const DataChunk, allocator: std.mem.Allocator, index: usize, row: usize) ![]u8 {
        const raw_vector = self.vector(index);
        const data = c.duckdb_vector_get_data(raw_vector) orelse return error.DuckDbUnexpectedResult;
        const items: [*]const c.duckdb_string_t = @ptrCast(@alignCast(data));
        var item = items[row];
        const len: usize = c.duckdb_string_t_length(item);
        const ptr = c.duckdb_string_t_data(&item) orelse return error.DuckDbUnexpectedResult;
        return try allocator.dupe(u8, ptr[0..len]);
    }

    pub fn rowTemporalInt(self: *const DataChunk, index: usize, row: usize, type_id: TypeId) !i64 {
        const raw_vector = self.vector(index);
        const data = c.duckdb_vector_get_data(raw_vector) orelse return error.DuckDbUnexpectedResult;
        return switch (type_id) {
            .date => @as([*]const c.duckdb_date, @ptrCast(@alignCast(data)))[row].days,
            .time => @as([*]const c.duckdb_time, @ptrCast(@alignCast(data)))[row].micros,
            .time_ns => @as([*]const c.duckdb_time_ns, @ptrCast(@alignCast(data)))[row].nanos,
            .time_tz => @bitCast(@as([*]const c.duckdb_time_tz, @ptrCast(@alignCast(data)))[row].bits),
            .timestamp, .timestamp_tz => @as([*]const c.duckdb_timestamp, @ptrCast(@alignCast(data)))[row].micros,
            .timestamp_s => @as([*]const c.duckdb_timestamp_s, @ptrCast(@alignCast(data)))[row].seconds,
            .timestamp_ms => @as([*]const c.duckdb_timestamp_ms, @ptrCast(@alignCast(data)))[row].millis,
            .timestamp_ns => @as([*]const c.duckdb_timestamp_ns, @ptrCast(@alignCast(data)))[row].nanos,
            else => error.Unsupported,
        };
    }
};

fn buildArrowSummary(
    allocator: std.mem.Allocator,
    schema: *const ArrowSchema,
    array: ?*const ArrowArray,
    total_row_count: usize,
    first_batch_row_count: usize,
) !ArrowExportSummary {
    const root_format = try dupZString(allocator, schema.format orelse return error.DuckDbUnexpectedResult);
    errdefer allocator.free(root_format);

    if (schema.n_children < 0) return error.DuckDbUnexpectedResult;
    const field_count: usize = @intCast(schema.n_children);
    const fields = try allocator.alloc(ArrowFieldSummary, field_count);
    var initialized_fields: usize = 0;
    errdefer {
        for (0..initialized_fields) |idx| {
            allocator.free(fields[idx].name);
            allocator.free(fields[idx].format);
        }
        allocator.free(fields);
    }

    const child_schemas = schema.children orelse return error.DuckDbUnexpectedResult;
    const child_arrays = if (array) |a| a.children else null;

    for (0..field_count) |idx| {
        const child_schema = child_schemas[idx];
        const name = try dupZString(allocator, child_schema.name orelse return error.DuckDbUnexpectedResult);
        errdefer allocator.free(name);
        const format = try dupZString(allocator, child_schema.format orelse return error.DuckDbUnexpectedResult);
        errdefer allocator.free(format);

        var buffer_count: usize = 0;
        var null_count: i64 = 0;
        if (child_arrays) |children| {
            const child_array = children[idx];
            if (child_array.n_buffers < 0) return error.DuckDbUnexpectedResult;
            buffer_count = @intCast(child_array.n_buffers);
            null_count = child_array.null_count;
        }

        fields[idx] = .{
            .name = name,
            .format = format,
            .nullable = (child_schema.flags & ArrowFlag.nullable) != 0,
            .buffer_count = buffer_count,
            .null_count = null_count,
        };
        initialized_fields += 1;
    }

    return .{
        .root_format = root_format,
        .total_row_count = total_row_count,
        .first_batch_row_count = first_batch_row_count,
        .fields = fields,
    };
}

fn dupZString(allocator: std.mem.Allocator, text: [*:0]const u8) ![]u8 {
    return try allocator.dupe(u8, std.mem.span(text));
}

fn dupOptionalZString(allocator: std.mem.Allocator, text: ?[*:0]const u8) ?[]u8 {
    const raw = text orelse return null;
    const span = std.mem.span(raw);
    if (span.len == 0) return null;
    return allocator.dupe(u8, span) catch null;
}

fn duplicatePrepareError(allocator: std.mem.Allocator, stmt: c.duckdb_prepared_statement) ?[]u8 {
    if (stmt == null) return null;
    return dupOptionalZString(allocator, c.duckdb_prepare_error(stmt));
}

fn duplicateResultError(allocator: std.mem.Allocator, result: *const c.duckdb_result) ?[]u8 {
    return dupOptionalZString(allocator, c.duckdb_result_error(@constCast(result)));
}

fn duplicateAppenderError(allocator: std.mem.Allocator, appender: c.duckdb_appender) ?[]u8 {
    if (appender == null) return null;
    var error_data = c.duckdb_appender_error_data(appender);
    defer c.duckdb_destroy_error_data(&error_data);
    if (!c.duckdb_error_data_has_error(error_data)) return null;
    return dupOptionalZString(allocator, c.duckdb_error_data_message(error_data));
}

fn releaseArrowSchema(schema: *ArrowSchema) void {
    if (schema.release) |release| {
        release(schema);
        schema.release = null;
    }
}

fn releaseArrowArray(array: *ArrowArray) void {
    if (array.release) |release| {
        release(array);
        array.release = null;
    }
}

fn checkArrowError(err: c.duckdb_error_data) !void {
    var mutable_err = err;
    defer c.duckdb_destroy_error_data(&mutable_err);
    if (c.duckdb_error_data_has_error(mutable_err)) return error.DuckDbArrowFailed;
}

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

fn buildCountSql(allocator: std.mem.Allocator, source_kind: SourceKind, source_path: []const u8) ![]u8 {
    const quoted = try sqlStringLiteral(allocator, source_path);
    defer allocator.free(quoted);
    return switch (source_kind) {
        .csv => std.fmt.allocPrint(allocator, "select count(*) as n from read_csv_auto({s})", .{quoted}),
        .parquet => std.fmt.allocPrint(allocator, "select count(*) as n from read_parquet({s})", .{quoted}),
    };
}

fn buildWrappedCountSql(allocator: std.mem.Allocator, sql: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "select count(*) as n from ({s}) as kiwi_relation",
        .{sql},
    );
}
