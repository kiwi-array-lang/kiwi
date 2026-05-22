pub const c = struct {
    pub const mlx_array = extern struct {
        ctx: ?*anyopaque,
    };

    pub const mlx_device = extern struct {
        ctx: ?*anyopaque,
    };

    pub const mlx_stream = extern struct {
        ctx: ?*anyopaque,
    };

    pub const mlx_vector_array = extern struct {
        ctx: ?*anyopaque,
    };

    pub const mlx_map_string_to_array = extern struct {
        ctx: ?*anyopaque,
    };

    pub const mlx_map_string_to_array_iterator = extern struct {
        ctx: ?*anyopaque,
        map_ctx: ?*anyopaque,
    };

    pub const mlx_map_string_to_string = extern struct {
        ctx: ?*anyopaque,
    };

    pub const mlx_map_string_to_string_iterator = extern struct {
        ctx: ?*anyopaque,
        map_ctx: ?*anyopaque,
    };

    pub const mlx_dtype = enum(c_int) {
        MLX_BOOL,
        MLX_UINT8,
        MLX_UINT16,
        MLX_UINT32,
        MLX_UINT64,
        MLX_INT8,
        MLX_INT16,
        MLX_INT32,
        MLX_INT64,
        MLX_FLOAT16,
        MLX_FLOAT32,
        MLX_FLOAT64,
        MLX_BFLOAT16,
        MLX_COMPLEX64,
    };

    pub const mlx_device_type = enum(c_int) {
        MLX_CPU,
        MLX_GPU,
    };

    pub const MLX_BOOL = mlx_dtype.MLX_BOOL;
    pub const MLX_UINT8 = mlx_dtype.MLX_UINT8;
    pub const MLX_UINT16 = mlx_dtype.MLX_UINT16;
    pub const MLX_UINT32 = mlx_dtype.MLX_UINT32;
    pub const MLX_UINT64 = mlx_dtype.MLX_UINT64;
    pub const MLX_INT8 = mlx_dtype.MLX_INT8;
    pub const MLX_INT16 = mlx_dtype.MLX_INT16;
    pub const MLX_INT32 = mlx_dtype.MLX_INT32;
    pub const MLX_INT64 = mlx_dtype.MLX_INT64;
    pub const MLX_FLOAT16 = mlx_dtype.MLX_FLOAT16;
    pub const MLX_FLOAT32 = mlx_dtype.MLX_FLOAT32;
    pub const MLX_FLOAT64 = mlx_dtype.MLX_FLOAT64;
    pub const MLX_BFLOAT16 = mlx_dtype.MLX_BFLOAT16;
    pub const MLX_COMPLEX64 = mlx_dtype.MLX_COMPLEX64;

    pub const MLX_CPU = mlx_device_type.MLX_CPU;
    pub const MLX_GPU = mlx_device_type.MLX_GPU;

    pub extern fn mlx_array_new() mlx_array;
    pub extern fn mlx_array_free(arr: mlx_array) c_int;
    pub extern fn mlx_array_set(arr: *mlx_array, src: mlx_array) c_int;
    pub extern fn mlx_array_new_bool(val: bool) mlx_array;
    pub extern fn mlx_array_new_int(val: c_int) mlx_array;
    pub extern fn mlx_array_new_float32(val: f32) mlx_array;
    pub extern fn mlx_array_new_float64(val: f64) mlx_array;
    pub extern fn mlx_array_new_data(
        data: ?*const anyopaque,
        shape: [*]const c_int,
        dim: c_int,
        dtype: mlx_dtype,
    ) mlx_array;
    pub extern fn mlx_array_set_data(
        arr: *mlx_array,
        data: ?*const anyopaque,
        shape: [*]const c_int,
        dim: c_int,
        dtype: mlx_dtype,
    ) c_int;
    pub extern fn mlx_array_ndim(arr: mlx_array) usize;
    pub extern fn mlx_array_size(arr: mlx_array) usize;
    pub extern fn mlx_array_shape(arr: mlx_array) [*]const c_int;
    pub extern fn mlx_array_dtype(arr: mlx_array) mlx_dtype;
    pub extern fn mlx_array_eval(arr: mlx_array) c_int;
    pub extern fn mlx_array_item_bool(out: *bool, arr: mlx_array) c_int;
    pub extern fn mlx_array_item_uint32(out: *u32, arr: mlx_array) c_int;
    pub extern fn mlx_array_item_int32(out: *i32, arr: mlx_array) c_int;
    pub extern fn mlx_array_item_int64(out: *i64, arr: mlx_array) c_int;
    pub extern fn mlx_array_item_float32(out: *f32, arr: mlx_array) c_int;
    pub extern fn mlx_array_item_float64(out: *f64, arr: mlx_array) c_int;
    pub extern fn mlx_array_data_bool(arr: mlx_array) ?[*]const bool;
    pub extern fn mlx_array_data_uint32(arr: mlx_array) ?[*]const u32;
    pub extern fn mlx_array_data_int32(arr: mlx_array) ?[*]const i32;
    pub extern fn mlx_array_data_int64(arr: mlx_array) ?[*]const i64;
    pub extern fn mlx_array_data_float32(arr: mlx_array) ?[*]const f32;
    pub extern fn mlx_array_data_float64(arr: mlx_array) ?[*]const f64;

    pub extern fn mlx_device_new() mlx_device;
    pub extern fn mlx_device_new_type(device_type: mlx_device_type, index: c_int) mlx_device;
    pub extern fn mlx_get_default_device(device: *mlx_device) c_int;
    pub extern fn mlx_set_default_device(device: mlx_device) c_int;
    pub extern fn mlx_device_get_type(device_type: *mlx_device_type, device: mlx_device) c_int;
    pub extern fn mlx_device_is_available(available: *bool, device: mlx_device) c_int;
    pub extern fn mlx_device_free(device: mlx_device) c_int;

    pub extern fn mlx_stream_new() mlx_stream;
    pub extern fn mlx_stream_new_device(device: mlx_device) mlx_stream;
    pub extern fn mlx_stream_free(stream: mlx_stream) c_int;

    pub extern fn mlx_vector_array_new() mlx_vector_array;
    pub extern fn mlx_vector_array_free(vec: mlx_vector_array) c_int;
    pub extern fn mlx_vector_array_append_value(vec: mlx_vector_array, val: mlx_array) c_int;

    pub extern fn mlx_map_string_to_array_new() mlx_map_string_to_array;
    pub extern fn mlx_map_string_to_array_set(
        map: *mlx_map_string_to_array,
        src: mlx_map_string_to_array,
    ) c_int;
    pub extern fn mlx_map_string_to_array_free(map: mlx_map_string_to_array) c_int;
    pub extern fn mlx_map_string_to_array_insert(
        map: mlx_map_string_to_array,
        key: [*:0]const u8,
        value: mlx_array,
    ) c_int;
    pub extern fn mlx_map_string_to_array_get(
        value: *mlx_array,
        map: mlx_map_string_to_array,
        key: [*:0]const u8,
    ) c_int;
    pub extern fn mlx_map_string_to_array_iterator_new(
        map: mlx_map_string_to_array,
    ) mlx_map_string_to_array_iterator;
    pub extern fn mlx_map_string_to_array_iterator_free(
        it: mlx_map_string_to_array_iterator,
    ) c_int;
    pub extern fn mlx_map_string_to_array_iterator_next(
        key: *?[*:0]const u8,
        value: *mlx_array,
        it: mlx_map_string_to_array_iterator,
    ) c_int;

    pub extern fn mlx_map_string_to_string_new() mlx_map_string_to_string;
    pub extern fn mlx_map_string_to_string_set(
        map: *mlx_map_string_to_string,
        src: mlx_map_string_to_string,
    ) c_int;
    pub extern fn mlx_map_string_to_string_free(map: mlx_map_string_to_string) c_int;
    pub extern fn mlx_map_string_to_string_insert(
        map: mlx_map_string_to_string,
        key: [*:0]const u8,
        value: [*:0]const u8,
    ) c_int;
    pub extern fn mlx_map_string_to_string_get(
        value: *?[*:0]const u8,
        map: mlx_map_string_to_string,
        key: [*:0]const u8,
    ) c_int;
    pub extern fn mlx_map_string_to_string_iterator_new(
        map: mlx_map_string_to_string,
    ) mlx_map_string_to_string_iterator;
    pub extern fn mlx_map_string_to_string_iterator_free(
        it: mlx_map_string_to_string_iterator,
    ) c_int;
    pub extern fn mlx_map_string_to_string_iterator_next(
        key: *?[*:0]const u8,
        value: *?[*:0]const u8,
        it: mlx_map_string_to_string_iterator,
    ) c_int;

    pub extern fn mlx_load_safetensors(
        res_0: *mlx_map_string_to_array,
        res_1: *mlx_map_string_to_string,
        file: [*:0]const u8,
        s: mlx_stream,
    ) c_int;
    pub extern fn mlx_load_safetensor_tensor(
        res: *mlx_array,
        file: [*:0]const u8,
        shape: [*]const c_int,
        dim: c_int,
        dtype: mlx_dtype,
        data_offset: u64,
        s: mlx_stream,
    ) c_int;
    pub extern fn mlx_save_safetensors(
        file: [*:0]const u8,
        param: mlx_map_string_to_array,
        metadata: mlx_map_string_to_string,
    ) c_int;

    pub extern fn mlx_add(res: *mlx_array, a: mlx_array, b: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_subtract(res: *mlx_array, a: mlx_array, b: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_multiply(res: *mlx_array, a: mlx_array, b: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_divide(res: *mlx_array, a: mlx_array, b: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_remainder(res: *mlx_array, a: mlx_array, b: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_minimum(res: *mlx_array, a: mlx_array, b: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_maximum(res: *mlx_array, a: mlx_array, b: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_less(res: *mlx_array, a: mlx_array, b: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_greater(res: *mlx_array, a: mlx_array, b: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_equal(res: *mlx_array, a: mlx_array, b: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_logical_not(res: *mlx_array, a: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_negative(res: *mlx_array, a: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_sqrt(res: *mlx_array, a: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_sin(res: *mlx_array, a: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_cos(res: *mlx_array, a: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_floor(res: *mlx_array, a: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_astype(res: *mlx_array, a: mlx_array, dtype: mlx_dtype, stream: mlx_stream) c_int;
    pub extern fn mlx_arange(
        res: *mlx_array,
        start: f64,
        stop: f64,
        step: f64,
        dtype: mlx_dtype,
        stream: mlx_stream,
    ) c_int;
    pub extern fn mlx_transpose(res: *mlx_array, a: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_swapaxes(
        res: *mlx_array,
        a: mlx_array,
        axis1: c_int,
        axis2: c_int,
        stream: mlx_stream,
    ) c_int;
    pub extern fn mlx_copy(res: *mlx_array, a: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_matmul(res: *mlx_array, a: mlx_array, b: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_sum(res: *mlx_array, a: mlx_array, keepdims: bool, stream: mlx_stream) c_int;
    pub extern fn mlx_cumsum(
        res: *mlx_array,
        a: mlx_array,
        axis: c_int,
        reverse: bool,
        inclusive: bool,
        stream: mlx_stream,
    ) c_int;
    pub extern fn mlx_argmax(res: *mlx_array, a: mlx_array, keepdims: bool, stream: mlx_stream) c_int;
    pub extern fn mlxc_layer_norm(res: *mlx_array, a: mlx_array, weight: mlx_array, bias: mlx_array, eps: f32, stream: mlx_stream) c_int;
    pub extern fn mlxc_conv2d(res: *mlx_array, input: mlx_array, weight: mlx_array, stride_h: c_int, stride_w: c_int, padding_h: c_int, padding_w: c_int, stream: mlx_stream) c_int;
    pub extern fn mlxc_conv2d_bias(res: *mlx_array, input: mlx_array, weight: mlx_array, bias: mlx_array, stride_h: c_int, stride_w: c_int, padding_h: c_int, padding_w: c_int, stream: mlx_stream) c_int;
    pub extern fn mlxc_conv_transpose2d(res: *mlx_array, input: mlx_array, weight: mlx_array, stride_h: c_int, stride_w: c_int, padding_h: c_int, padding_w: c_int, stream: mlx_stream) c_int;
    pub extern fn mlxc_conv_transpose2d_bias(res: *mlx_array, input: mlx_array, weight: mlx_array, bias: mlx_array, stride_h: c_int, stride_w: c_int, padding_h: c_int, padding_w: c_int, stream: mlx_stream) c_int;
    pub extern fn mlxc_upsample_nearest2d(res: *mlx_array, input: mlx_array, scale_h: c_int, scale_w: c_int, stream: mlx_stream) c_int;
    pub extern fn mlxc_group_norm(res: *mlx_array, input: mlx_array, groups: c_int, weight: mlx_array, bias: mlx_array, eps: f32, stream: mlx_stream) c_int;
    pub extern fn mlxc_gelu(res: *mlx_array, a: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlxc_gelu_approx(res: *mlx_array, a: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlxc_mlp_dense(res: *mlx_array, x: mlx_array, gate_w: mlx_array, up_w: mlx_array, down_w: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlxc_softmax_last_axis(res: *mlx_array, a: mlx_array, precise: bool, stream: mlx_stream) c_int;
    pub extern fn mlxc_sdpa_none(res: *mlx_array, q: mlx_array, k: mlx_array, v: mlx_array, scale: f32, stream: mlx_stream) c_int;
    pub extern fn mlxc_sdpa_causal(res: *mlx_array, q: mlx_array, k: mlx_array, v: mlx_array, scale: f32, stream: mlx_stream) c_int;
    pub extern fn mlxc_sdpa_masked(res: *mlx_array, q: mlx_array, k: mlx_array, v: mlx_array, mask: mlx_array, scale: f32, stream: mlx_stream) c_int;
    pub extern fn mlxc_sam3_box_rpb_log(
        res: *mlx_array,
        reference_boxes: mlx_array,
        xw0: mlx_array,
        xb0: mlx_array,
        xw1: mlx_array,
        xb1: mlx_array,
        yw0: mlx_array,
        yb0: mlx_array,
        yw1: mlx_array,
        yb1: mlx_array,
        height: c_int,
        width: c_int,
        stream: mlx_stream,
    ) c_int;
    pub extern fn mlxc_rope(res: *mlx_array, a: mlx_array, dims: c_int, base: f32, offset: c_int, stream: mlx_stream) c_int;
    pub extern fn mlxc_rope_freqs(res: *mlx_array, a: mlx_array, dims: c_int, freqs: mlx_array, offset: c_int, stream: mlx_stream) c_int;
    pub extern fn mlx_argsort(res: *mlx_array, a: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_reshape(
        res: *mlx_array,
        a: mlx_array,
        shape: [*]const c_int,
        dim: usize,
        stream: mlx_stream,
    ) c_int;
    pub extern fn mlx_slice(
        res: *mlx_array,
        a: mlx_array,
        start: [*]const c_int,
        start_len: usize,
        stop: [*]const c_int,
        stop_len: usize,
        strides: [*]const c_int,
        strides_len: usize,
        stream: mlx_stream,
    ) c_int;
    pub extern fn mlx_slice_update(
        res: *mlx_array,
        a: mlx_array,
        update: mlx_array,
        start: [*]const c_int,
        start_len: usize,
        stop: [*]const c_int,
        stop_len: usize,
        strides: [*]const c_int,
        strides_len: usize,
        stream: mlx_stream,
    ) c_int;
    pub extern fn mlx_take(res: *mlx_array, a: mlx_array, indices: mlx_array, stream: mlx_stream) c_int;
    pub extern fn mlx_zeros(
        res: *mlx_array,
        shape: [*]const c_int,
        dim: usize,
        dtype: mlx_dtype,
        stream: mlx_stream,
    ) c_int;
    pub extern fn mlx_concatenate_axis(res: *mlx_array, arrays: mlx_vector_array, axis: c_int, stream: mlx_stream) c_int;
    pub extern fn mlx_concatenate(res: *mlx_array, arrays: mlx_vector_array, stream: mlx_stream) c_int;
    pub extern fn mlx_stack(res: *mlx_array, arrays: mlx_vector_array, stream: mlx_stream) c_int;
    pub extern fn mlx_contiguous(
        res: *mlx_array,
        a: mlx_array,
        allow_col_major: bool,
        stream: mlx_stream,
    ) c_int;
};
