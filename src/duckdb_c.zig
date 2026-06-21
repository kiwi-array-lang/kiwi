pub const idx_t = u64;
pub const duckdb_type = c_uint;
pub const duckdb_state = c_uint;
pub const duckdb_error_type = c_uint;

pub const DUCKDB_TYPE_BOOLEAN: duckdb_type = 1;
pub const DUCKDB_TYPE_BIGINT: duckdb_type = 5;
pub const DUCKDB_TYPE_DOUBLE: duckdb_type = 11;
pub const DUCKDB_TYPE_TIMESTAMP: duckdb_type = 12;
pub const DUCKDB_TYPE_DATE: duckdb_type = 13;
pub const DUCKDB_TYPE_TIME: duckdb_type = 14;
pub const DUCKDB_TYPE_VARCHAR: duckdb_type = 17;
pub const DUCKDB_TYPE_TIMESTAMP_S: duckdb_type = 20;
pub const DUCKDB_TYPE_TIMESTAMP_MS: duckdb_type = 21;
pub const DUCKDB_TYPE_TIMESTAMP_NS: duckdb_type = 22;
pub const DUCKDB_TYPE_TIME_TZ: duckdb_type = 30;
pub const DUCKDB_TYPE_TIMESTAMP_TZ: duckdb_type = 31;
pub const DUCKDB_TYPE_TIME_NS: duckdb_type = 39;

pub const DuckDBSuccess: duckdb_state = 0;
pub const DuckDBError: duckdb_state = 1;

pub const duckdb_delete_callback_t = ?*const fn (data: ?*anyopaque) callconv(.c) void;

pub const duckdb_date = extern struct {
    days: i32 = 0,
};

pub const duckdb_date_struct = extern struct {
    year: i32 = 0,
    month: i8 = 0,
    day: i8 = 0,
};

pub const duckdb_time = extern struct {
    micros: i64 = 0,
};

pub const duckdb_time_struct = extern struct {
    hour: i8 = 0,
    min: i8 = 0,
    sec: i8 = 0,
    micros: i32 = 0,
};

pub const duckdb_time_ns = extern struct {
    nanos: i64 = 0,
};

pub const duckdb_time_tz = extern struct {
    bits: u64 = 0,
};

pub const duckdb_time_tz_struct = extern struct {
    time: duckdb_time_struct = .{},
    offset: i32 = 0,
};

pub const duckdb_timestamp = extern struct {
    micros: i64 = 0,
};

pub const duckdb_timestamp_struct = extern struct {
    date: duckdb_date_struct = .{},
    time: duckdb_time_struct = .{},
};

pub const duckdb_timestamp_s = extern struct {
    seconds: i64 = 0,
};

pub const duckdb_timestamp_ms = extern struct {
    millis: i64 = 0,
};

pub const duckdb_timestamp_ns = extern struct {
    nanos: i64 = 0,
};

const duckdb_string_pointer = extern struct {
    length: u32 = 0,
    prefix: [4]u8 = .{ 0, 0, 0, 0 },
    ptr: [*c]u8 = null,
};

const duckdb_string_inline = extern struct {
    length: u32 = 0,
    inlined: [12]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
};

const duckdb_string_value = extern union {
    pointer: duckdb_string_pointer,
    inlined: duckdb_string_inline,
};

pub const duckdb_string_t = extern struct {
    value: duckdb_string_value = .{ .inlined = .{} },
};

pub const duckdb_result = extern struct {
    deprecated_column_count: idx_t = 0,
    deprecated_row_count: idx_t = 0,
    deprecated_rows_changed: idx_t = 0,
    deprecated_columns: ?*anyopaque = null,
    deprecated_error_message: ?*anyopaque = null,
    internal_data: ?*anyopaque = null,
};

pub const struct__duckdb_database = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_database = [*c]struct__duckdb_database;

pub const struct__duckdb_connection = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_connection = [*c]struct__duckdb_connection;

pub const struct__duckdb_prepared_statement = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_prepared_statement = [*c]struct__duckdb_prepared_statement;

pub const struct__duckdb_appender = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_appender = [*c]struct__duckdb_appender;

pub const struct__duckdb_logical_type = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_logical_type = [*c]struct__duckdb_logical_type;

pub const struct__duckdb_data_chunk = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_data_chunk = [*c]struct__duckdb_data_chunk;

pub const struct__duckdb_vector = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_vector = [*c]struct__duckdb_vector;

pub const struct__duckdb_value = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_value = [*c]struct__duckdb_value;

pub const struct__duckdb_error_data = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_error_data = [*c]struct__duckdb_error_data;

pub const struct__duckdb_function_info = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_function_info = [*c]struct__duckdb_function_info;

pub const struct__duckdb_bind_info = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_bind_info = [*c]struct__duckdb_bind_info;

pub const struct__duckdb_init_info = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_init_info = [*c]struct__duckdb_init_info;

pub const struct__duckdb_table_function = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_table_function = [*c]struct__duckdb_table_function;

pub const struct__duckdb_arrow_options = extern struct {
    internal_ptr: ?*anyopaque = null,
};
pub const duckdb_arrow_options = [*c]struct__duckdb_arrow_options;

pub const duckdb_table_function_bind_t = ?*const fn (info: duckdb_bind_info) callconv(.c) void;
pub const duckdb_table_function_init_t = ?*const fn (info: duckdb_init_info) callconv(.c) void;
pub const duckdb_table_function_t = ?*const fn (info: duckdb_function_info, output: duckdb_data_chunk) callconv(.c) void;

pub extern fn duckdb_open(path: [*c]const u8, out_database: [*c]duckdb_database) duckdb_state;
pub extern fn duckdb_close(database: [*c]duckdb_database) void;
pub extern fn duckdb_connect(database: duckdb_database, out_connection: [*c]duckdb_connection) duckdb_state;
pub extern fn duckdb_disconnect(connection: [*c]duckdb_connection) void;
pub extern fn duckdb_destroy_arrow_options(arrow_options: [*c]duckdb_arrow_options) void;
pub extern fn duckdb_destroy_error_data(error_data: [*c]duckdb_error_data) void;
pub extern fn duckdb_error_data_message(error_data: duckdb_error_data) [*c]const u8;
pub extern fn duckdb_error_data_has_error(error_data: duckdb_error_data) bool;
pub extern fn duckdb_query(connection: duckdb_connection, query: [*c]const u8, out_result: [*c]duckdb_result) duckdb_state;
pub extern fn duckdb_destroy_result(result: [*c]duckdb_result) void;
pub extern fn duckdb_column_name(result: [*c]duckdb_result, col: idx_t) [*c]const u8;
pub extern fn duckdb_column_logical_type(result: [*c]duckdb_result, col: idx_t) duckdb_logical_type;
pub extern fn duckdb_result_get_arrow_options(result: [*c]duckdb_result) duckdb_arrow_options;
pub extern fn duckdb_column_count(result: [*c]duckdb_result) idx_t;
pub extern fn duckdb_row_count(result: [*c]duckdb_result) idx_t;
pub extern fn duckdb_result_error(result: [*c]duckdb_result) [*c]const u8;
pub extern fn duckdb_value_int64(result: [*c]duckdb_result, col: idx_t, row: idx_t) i64;
pub extern fn duckdb_value_is_null(result: [*c]duckdb_result, col: idx_t, row: idx_t) bool;
pub extern fn duckdb_free(ptr: ?*anyopaque) void;
pub extern fn duckdb_vector_size() idx_t;
pub extern fn duckdb_string_t_length(string: duckdb_string_t) u32;
pub extern fn duckdb_string_t_data(string: [*c]duckdb_string_t) [*c]const u8;
pub extern fn duckdb_from_date(date: duckdb_date) duckdb_date_struct;
pub extern fn duckdb_is_finite_date(date: duckdb_date) bool;
pub extern fn duckdb_from_time(time: duckdb_time) duckdb_time_struct;
pub extern fn duckdb_from_time_tz(micros: duckdb_time_tz) duckdb_time_tz_struct;
pub extern fn duckdb_from_timestamp(ts: duckdb_timestamp) duckdb_timestamp_struct;
pub extern fn duckdb_is_finite_timestamp(ts: duckdb_timestamp) bool;
pub extern fn duckdb_prepare(connection: duckdb_connection, query: [*c]const u8, out_prepared_statement: [*c]duckdb_prepared_statement) duckdb_state;
pub extern fn duckdb_destroy_prepare(prepared_statement: [*c]duckdb_prepared_statement) void;
pub extern fn duckdb_prepare_error(prepared_statement: duckdb_prepared_statement) [*c]const u8;
pub extern fn duckdb_nparams(prepared_statement: duckdb_prepared_statement) idx_t;
pub extern fn duckdb_parameter_name(prepared_statement: duckdb_prepared_statement, index: idx_t) [*c]const u8;
pub extern fn duckdb_clear_bindings(prepared_statement: duckdb_prepared_statement) duckdb_state;
pub extern fn duckdb_bind_boolean(prepared_statement: duckdb_prepared_statement, param_idx: idx_t, val: bool) duckdb_state;
pub extern fn duckdb_bind_int64(prepared_statement: duckdb_prepared_statement, param_idx: idx_t, val: i64) duckdb_state;
pub extern fn duckdb_bind_double(prepared_statement: duckdb_prepared_statement, param_idx: idx_t, val: f64) duckdb_state;
pub extern fn duckdb_bind_varchar_length(prepared_statement: duckdb_prepared_statement, param_idx: idx_t, val: [*c]const u8, length: idx_t) duckdb_state;
pub extern fn duckdb_bind_null(prepared_statement: duckdb_prepared_statement, param_idx: idx_t) duckdb_state;
pub extern fn duckdb_execute_prepared(prepared_statement: duckdb_prepared_statement, out_result: [*c]duckdb_result) duckdb_state;
pub extern fn duckdb_destroy_value(value: [*c]duckdb_value) void;
pub extern fn duckdb_create_time_ns(input: duckdb_time_ns) duckdb_value;
pub extern fn duckdb_create_time_tz_value(value: duckdb_time_tz) duckdb_value;
pub extern fn duckdb_create_timestamp_tz(input: duckdb_timestamp) duckdb_value;
pub extern fn duckdb_create_timestamp_s(input: duckdb_timestamp_s) duckdb_value;
pub extern fn duckdb_create_timestamp_ms(input: duckdb_timestamp_ms) duckdb_value;
pub extern fn duckdb_create_timestamp_ns(input: duckdb_timestamp_ns) duckdb_value;
pub extern fn duckdb_get_varchar(value: duckdb_value) [*c]u8;
pub extern fn duckdb_create_logical_type(@"type": duckdb_type) duckdb_logical_type;
pub extern fn duckdb_get_type_id(@"type": duckdb_logical_type) duckdb_type;
pub extern fn duckdb_destroy_logical_type(@"type": [*c]duckdb_logical_type) void;
pub extern fn duckdb_destroy_data_chunk(chunk: [*c]duckdb_data_chunk) void;
pub extern fn duckdb_data_chunk_reset(chunk: duckdb_data_chunk) void;
pub extern fn duckdb_data_chunk_get_vector(chunk: duckdb_data_chunk, col_idx: idx_t) duckdb_vector;
pub extern fn duckdb_data_chunk_get_size(chunk: duckdb_data_chunk) idx_t;
pub extern fn duckdb_data_chunk_set_size(chunk: duckdb_data_chunk, size: idx_t) void;
pub extern fn duckdb_vector_get_data(vector: duckdb_vector) ?*anyopaque;
pub extern fn duckdb_vector_get_validity(vector: duckdb_vector) [*c]u64;
pub extern fn duckdb_vector_ensure_validity_writable(vector: duckdb_vector) void;
pub extern fn duckdb_vector_assign_string_element_len(vector: duckdb_vector, index: idx_t, str: [*c]const u8, str_len: idx_t) void;
pub extern fn duckdb_unsafe_vector_assign_string_element_len(vector: duckdb_vector, index: idx_t, str: [*c]const u8, str_len: idx_t) void;
pub extern fn duckdb_validity_set_row_invalid(validity: [*c]u64, row: idx_t) void;
pub extern fn duckdb_create_table_function() duckdb_table_function;
pub extern fn duckdb_destroy_table_function(table_function: [*c]duckdb_table_function) void;
pub extern fn duckdb_table_function_set_name(table_function: duckdb_table_function, name: [*c]const u8) void;
pub extern fn duckdb_table_function_add_parameter(table_function: duckdb_table_function, @"type": duckdb_logical_type) void;
pub extern fn duckdb_table_function_set_extra_info(table_function: duckdb_table_function, extra_info: ?*anyopaque, destroy: duckdb_delete_callback_t) void;
pub extern fn duckdb_table_function_set_bind(table_function: duckdb_table_function, bind: duckdb_table_function_bind_t) void;
pub extern fn duckdb_table_function_set_init(table_function: duckdb_table_function, init: duckdb_table_function_init_t) void;
pub extern fn duckdb_table_function_set_function(table_function: duckdb_table_function, function: duckdb_table_function_t) void;
pub extern fn duckdb_table_function_supports_projection_pushdown(table_function: duckdb_table_function, pushdown: bool) void;
pub extern fn duckdb_register_table_function(con: duckdb_connection, function: duckdb_table_function) duckdb_state;
pub extern fn duckdb_bind_get_extra_info(info: duckdb_bind_info) ?*anyopaque;
pub extern fn duckdb_bind_add_result_column(info: duckdb_bind_info, name: [*c]const u8, @"type": duckdb_logical_type) void;
pub extern fn duckdb_bind_get_parameter_count(info: duckdb_bind_info) idx_t;
pub extern fn duckdb_bind_get_parameter(info: duckdb_bind_info, index: idx_t) duckdb_value;
pub extern fn duckdb_bind_set_bind_data(info: duckdb_bind_info, bind_data: ?*anyopaque, destroy: duckdb_delete_callback_t) void;
pub extern fn duckdb_bind_set_cardinality(info: duckdb_bind_info, cardinality: idx_t, is_exact: bool) void;
pub extern fn duckdb_bind_set_error(info: duckdb_bind_info, @"error": [*c]const u8) void;
pub extern fn duckdb_init_get_bind_data(info: duckdb_init_info) ?*anyopaque;
pub extern fn duckdb_init_set_init_data(info: duckdb_init_info, init_data: ?*anyopaque, destroy: duckdb_delete_callback_t) void;
pub extern fn duckdb_init_get_column_count(info: duckdb_init_info) idx_t;
pub extern fn duckdb_init_get_column_index(info: duckdb_init_info, column_index: idx_t) idx_t;
pub extern fn duckdb_init_set_error(info: duckdb_init_info, @"error": [*c]const u8) void;
pub extern fn duckdb_function_get_bind_data(info: duckdb_function_info) ?*anyopaque;
pub extern fn duckdb_function_get_init_data(info: duckdb_function_info) ?*anyopaque;
pub extern fn duckdb_function_set_error(info: duckdb_function_info, @"error": [*c]const u8) void;
pub extern fn duckdb_appender_create(connection: duckdb_connection, schema: [*c]const u8, table: [*c]const u8, out_appender: [*c]duckdb_appender) duckdb_state;
pub extern fn duckdb_appender_error_data(appender: duckdb_appender) duckdb_error_data;
pub extern fn duckdb_appender_close(appender: duckdb_appender) duckdb_state;
pub extern fn duckdb_appender_destroy(appender: [*c]duckdb_appender) duckdb_state;
pub extern fn duckdb_appender_end_row(appender: duckdb_appender) duckdb_state;
pub extern fn duckdb_append_bool(appender: duckdb_appender, value: bool) duckdb_state;
pub extern fn duckdb_append_int64(appender: duckdb_appender, value: i64) duckdb_state;
pub extern fn duckdb_append_double(appender: duckdb_appender, value: f64) duckdb_state;
pub extern fn duckdb_append_date(appender: duckdb_appender, value: duckdb_date) duckdb_state;
pub extern fn duckdb_append_time(appender: duckdb_appender, value: duckdb_time) duckdb_state;
pub extern fn duckdb_append_timestamp(appender: duckdb_appender, value: duckdb_timestamp) duckdb_state;
pub extern fn duckdb_append_varchar_length(appender: duckdb_appender, val: [*c]const u8, length: idx_t) duckdb_state;
pub extern fn duckdb_append_null(appender: duckdb_appender) duckdb_state;
pub extern fn duckdb_append_value(appender: duckdb_appender, value: duckdb_value) duckdb_state;
pub extern fn duckdb_to_arrow_schema(arrow_options: duckdb_arrow_options, types: [*c]duckdb_logical_type, names: [*c][*c]const u8, column_count: idx_t, out_schema: ?*anyopaque) duckdb_error_data;
pub extern fn duckdb_data_chunk_to_arrow(arrow_options: duckdb_arrow_options, chunk: duckdb_data_chunk, out_arrow_array: ?*anyopaque) duckdb_error_data;
pub extern fn duckdb_fetch_chunk(result: duckdb_result) duckdb_data_chunk;
