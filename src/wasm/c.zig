pub const c = struct {
    pub const mlx_dtype = i32;

    // Keep the existing small wasm bridge dtype ABI stable. The bridge currently
    // produces only a narrow subset, but the runtime still names the broader
    // MLX dtype surface in generic helpers.
    pub const MLX_BOOL: mlx_dtype = 1;
    pub const MLX_INT32: mlx_dtype = 2;
    pub const MLX_INT64: mlx_dtype = 3;
    pub const MLX_UINT32: mlx_dtype = 4;
    pub const MLX_FLOAT32: mlx_dtype = 5;
    pub const MLX_FLOAT64: mlx_dtype = 6;
    pub const MLX_FLOAT16: mlx_dtype = 7;
    pub const MLX_BFLOAT16: mlx_dtype = 8;
    pub const MLX_UINT8: mlx_dtype = 9;
    pub const MLX_UINT16: mlx_dtype = 10;
    pub const MLX_UINT64: mlx_dtype = 11;
    pub const MLX_INT8: mlx_dtype = 12;
    pub const MLX_INT16: mlx_dtype = 13;
    pub const MLX_COMPLEX64: mlx_dtype = 14;
};
