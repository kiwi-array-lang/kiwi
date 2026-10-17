const std = @import("std");
const runtime = @import("runtime.zig");

pub const ProbeCase = struct {
    name: []const u8,
    source: []const u8,
};

pub const KernelProbeResult = struct {
    simd: [runtime.debug_simd_kernel_count]runtime.DebugNameCount,

    fn backendHasCounts(entries: []const runtime.DebugNameCount) bool {
        for (entries) |entry| {
            if (entry.count != 0) return true;
        }
        return false;
    }

    fn writeBackendJson(entries: []const runtime.DebugNameCount, stringify: anytype) !void {
        try stringify.beginObject();
        for (entries) |entry| {
            if (entry.count == 0) continue;
            try stringify.objectField(entry.name);
            try stringify.write(entry.count);
        }
        try stringify.endObject();
    }

    pub fn jsonStringify(self: KernelProbeResult, stringify: anytype) !void {
        try stringify.beginObject();
        if (backendHasCounts(self.simd[0..])) {
            try stringify.objectField("simd");
            try writeBackendJson(self.simd[0..], stringify);
        }
        try stringify.endObject();
    }
};

pub const ProbeResult = struct {
    name: []const u8,
    status: []const u8,
    err_name: ?[]const u8,
    kernels: KernelProbeResult,
    host_realization_count: usize,
    structural_host_realization_count: usize,
    backend_realization_count: usize,
    structural_backend_realization_count: usize,
    host_realization_reuse_count: usize,
    host_readback_count: usize,
    backend_realization_reuse_count: usize,
    backend_promotion_count: usize,
    host_eviction_count: usize,
    backend_eviction_count: usize,
    dual_resident_peak_count: usize,
    flat_concat_dense_view_count: usize,
    first_axis_slice_dense_view_count: usize,
    first_axis_index_dense_view_count: usize,
    first_axis_concat_dense_view_count: usize,
    make_array_int_result_count: usize,
    make_array_float_result_count: usize,
    make_array_boxed_fallback_count: usize,
    make_array_boxed_uniform_numeric_array_count: usize,
    make_array_boxed_irregular_numeric_array_count: usize,
    make_array_boxed_non_numeric_item_count: usize,
    make_array_boxed_len_0_count: usize,
    make_array_boxed_len_1_count: usize,
    make_array_boxed_len_2_count: usize,
    make_array_boxed_len_3_4_count: usize,
    make_array_boxed_len_5_8_count: usize,
    make_array_boxed_len_9_16_count: usize,
    make_array_boxed_len_17_32_count: usize,
    make_array_boxed_len_33_64_count: usize,
    make_array_boxed_len_65_128_count: usize,
    make_array_boxed_len_129_256_count: usize,
    make_array_boxed_len_257_plus_count: usize,
    host_matrix_row_copy_count: usize,
    host_matrix_index_copy_count: usize,
    host_matrix_mask_copy_count: usize,
    host_index_in_bounds_fast_count: usize,
    host_index_in_bounds_fallback_count: usize,
    host_index_copy_count: usize,
    host_mask_copy_count: usize,
    projection_closure_alloc_count: usize,
    projection_closure_release_count: usize,
    apply_each_generic_count: usize,
    apply_fold_generic_count: usize,
    apply_scan_generic_count: usize,
    apply_each_right_generic_count: usize,
    apply_each_left_generic_count: usize,
    apply_each_prior_fast_bit_count: usize,
    apply_each_prior_fast_bit_element_count: usize,
    apply_each_prior_generic_count: usize,
    apply_each_prior_generic_element_count: usize,
    apply_each_right_fast_string_contains_count: usize,
    apply_each_fast_numeric_unary_count: usize,
    apply_each_fast_numeric_vector_code_count: usize,
    apply_each_fast_numeric_closure_count: usize,
    apply_each_fast_unary_lifted_count: usize,
    apply_each_fast_dense_count: usize,
    apply_each_fast_dense_miss_unsupported_base_count: usize,
    apply_each_fast_dense_miss_non_dense_args_or_shape_count: usize,
    apply_each_right_fast_dense_count: usize,
    apply_each_right_fast_dense_miss_unsupported_base_count: usize,
    apply_each_right_fast_dense_miss_non_vector_right_count: usize,
    each_right_fast_string_contains_miss_non_string_left_count: usize,
    each_right_fast_string_contains_miss_non_string_right_count: usize,
    grade_structural_numeric_fast_count: usize,
    fast_dense_assign_attempt_count: usize,
    fast_dense_assign_hit_count: usize,
    fast_dense_assign_miss_count: usize,
    fast_dense_assign_reuse_count: usize,
    fast_dense_assign_clone_count: usize,
    fast_dense_assign_clone_non_unique_count: usize,
    fast_dense_assign_clone_frozen_count: usize,
    fast_dense_assign_clone_other_count: usize,
    fast_dense_assign_target_element_count: usize,
    fast_dense_assign_scalar_target_count: usize,
    fast_dense_assign_vector_target_count: usize,
    fast_dense_assign_scalar_rhs_count: usize,
    fast_dense_assign_vector_rhs_count: usize,
    indexed_assign_count: usize,
    indexed_assign_global_count: usize,
    indexed_assign_local_count: usize,
    owned_amend_count: usize,
    local_release_skip_count: usize,
    local_release_taken_count: usize,
    code_opcode_total_count: usize,
    code_opcode_top_counts: [runtime.debug_top_opcode_count]runtime.DebugCodeOpCount,
    code_opcode_family_counts: [runtime.debug_opcode_family_count]runtime.DebugOpcodeFamilyCount,
    jump_if_false_count: usize,
    jump_if_false_scalar_count: usize,
    inline_scalar_dyad_attempt_count: usize,
    inline_scalar_dyad_hit_count: usize,
    inline_scalar_dyad_fallback_count: usize,
    shaped_scalar_dyad_count: usize,
    global_call_slots_count: usize,
    global_call_slots_fast_count: usize,
    global_call_slots_fallback_count: usize,
    code_run_count: usize,
    code_tail_continue_count: usize,
    code_global_call_count: usize,
    code_global_call_direct_count: usize,
    code_global_call_fallback_count: usize,
    code_global_call_fallback_no_code_count: usize,
    code_global_call_fallback_arity_count: usize,
    code_global_call_fallback_other_reason_count: usize,
    code_global_call_fallback_builtin_count: usize,
    code_global_call_fallback_closure_count: usize,
    code_global_call_fallback_array_count: usize,
    code_global_call_fallback_other_kind_count: usize,
    code_compile_count: usize,
    code_compile_success_count: usize,
    code_compile_miss_arity_or_local_limit_count: usize,
    code_compile_miss_body_size_count: usize,
    code_compile_miss_invalid_code_count: usize,
    code_compile_miss_unsupported_opcode_or_operand_count: usize,
    code_compile_miss_target_or_offset_count: usize,
    code_compile_miss_code_body_size_count: usize,
    code_compile_miss_stack_size_count: usize,
    code_compile_unsupported_opcode_top_counts: [runtime.debug_top_opcode_count]runtime.DebugNameCount,
    code_indexed_assign_sources_count: usize,
    code_indexed_assign_stack_count: usize,
    dense_fusion_enabled: bool,
    dense_fusion_add_fold_map_candidates: usize,
    dense_fusion_add_fold_map_hits: usize,
    dense_fusion_add_fold_map_disabled: usize,
    host_fold_fast_count: usize,
    host_scan_fast_count: usize,
    host_fold_scan_miss_unsupported_builtin_count: usize,
    host_fold_scan_miss_backend_override_count: usize,
    host_fold_scan_miss_non_numeric_or_shape_count: usize,
    host_fold_scan_miss_planner_non_host_count: usize,
    host_fold_scan_miss_preserve_generic_semantics_count: usize,
    host_fold_scan_miss_unsupported_input_count: usize,
    host_dense_dyad_host_count: usize,
    host_dense_dyad_host_element_count: usize,
    host_dense_dyad_host_rowwise_count: usize,
    host_dense_dyad_host_with_backend_input_count: usize,
    host_dense_dyad_add_count: usize,
    host_dense_dyad_sub_count: usize,
    host_dense_dyad_mul_count: usize,
    host_dense_dyad_div_count: usize,
    host_dense_dyad_less_count: usize,
    host_dense_dyad_more_count: usize,
    host_dense_dyad_equal_count: usize,
    host_dense_dyad_miss_planner_backend_count: usize,
    host_dense_dyad_miss_mode_count: usize,
    host_dense_dyad_miss_view_count: usize,
    host_string_view_alloc_count: usize,
    host_string_view_release_count: usize,
    host_string_view_generic_count: usize,
    host_string_view_string_list_eager_view_count: usize,
    host_string_view_string_list_split_scalar_count: usize,
    host_string_view_len_0_count: usize,
    host_string_view_len_1_count: usize,
    host_string_view_len_2_count: usize,
    host_string_view_len_3_4_count: usize,
    host_string_view_len_5_8_count: usize,
    host_string_view_len_9_16_count: usize,
    host_string_view_len_17_32_count: usize,
    host_string_view_len_33_64_count: usize,
    host_string_view_len_65_128_count: usize,
    host_string_view_len_129_256_count: usize,
    host_string_view_len_257_plus_count: usize,
    host_string_list_item_value_count: usize,
    host_string_list_item_eager_owned_count: usize,
    host_string_list_item_eager_view_count: usize,
    host_string_list_item_split_scalar_count: usize,
    host_string_list_item_split_scalar_scan_byte_count: usize,
    host_string_list_item_split_scalar_scan_sep_count: usize,
    flat_slice_alloc_count: usize,
    flat_slice_release_count: usize,
    flat_concat_alloc_count: usize,
    flat_concat_release_count: usize,
    flat_segments_alloc_count: usize,
    flat_segments_release_count: usize,
    first_axis_slice_alloc_count: usize,
    first_axis_slice_release_count: usize,
    first_axis_index_alloc_count: usize,
    first_axis_index_release_count: usize,
    first_axis_concat_alloc_count: usize,
    first_axis_concat_release_count: usize,
    reshape_view_alloc_count: usize,
    reshape_view_release_count: usize,
    transpose_view_alloc_count: usize,
    transpose_view_release_count: usize,
    structured_derived2_hit_count: usize,
    apply_derived_closure_count: usize,
    apply_projection_count: usize,
    autograd_builtin_grad_count: usize,
    autograd_builtin_valuegrad_count: usize,
    autograd_slow_finite_difference_count: usize,
    dense_autodiff_cache_hit_count: usize,
    dense_autodiff_cache_miss_count: usize,
    dense_autodiff_lower_success_count: usize,
    dense_autodiff_reject_wrong_arity_count: usize,
    dense_autodiff_reject_non_vector_target_count: usize,
    dense_autodiff_reject_non_scalar_result_count: usize,
    dense_autodiff_reject_unsupported_opcode_count: usize,
    dense_autodiff_reject_unsupported_shape_flow_count: usize,
    dense_autodiff_reject_unsupported_builtin_count: usize,
    dense_autodiff_reject_capture_or_global_dependency_count: usize,
    dense_autodiff_reject_non_dense_operand_count: usize,
    planner_numeric_dyad_host_count: usize,
    planner_numeric_dyad_backend_count: usize,
    planner_compare_mask_host_count: usize,
    planner_compare_mask_backend_count: usize,
    planner_reduce_host_count: usize,
    planner_reduce_backend_count: usize,
    exec_numeric_dyad_host_count: usize,
    exec_numeric_dyad_backend_count: usize,
    exec_compare_mask_host_count: usize,
    exec_compare_mask_backend_count: usize,
    exec_reduce_host_count: usize,
    exec_reduce_backend_count: usize,
    exec_scan_host_count: usize,
    exec_scan_backend_count: usize,
    exec_matmul_host_count: usize,
    exec_matmul_backend_count: usize,
    exec_dense_autodiff_host_count: usize,
    exec_dense_autodiff_backend_count: usize,
    planner_scan_host_count: usize,
    planner_scan_backend_count: usize,
    planner_matmul_host_count: usize,
    planner_matmul_backend_count: usize,
    planner_dense_autodiff_host_count: usize,
    planner_dense_autodiff_backend_count: usize,
    last_dense_plan_region: ?[]const u8,
    last_dense_plan_backend: ?[]const u8,
    last_dense_exec_backend: ?[]const u8,
    last_dense_plan_reason: ?[]const u8,
    last_dense_plan_overridden: bool,
    last_dense_autodiff_exec_path: ?[]const u8,
};

pub fn collectProbeResult(session: *runtime.Session, name: []const u8, err_name: ?[]const u8) ProbeResult {
    const dense_fusion = session.debugDenseFusionStats();
    return .{
        .name = name,
        .status = if (err_name == null) "ok" else "error",
        .err_name = err_name,
        .kernels = .{ .simd = session.debugSimdKernelCounts() },
        .host_realization_count = session.debugRuntimeStats().host_realization_count,
        .structural_host_realization_count = session.debugRuntimeStats().structural_host_realization_count,
        .backend_realization_count = session.debugRuntimeStats().mlx_realization_count,
        .structural_backend_realization_count = session.debugRuntimeStats().structural_mlx_realization_count,
        .host_realization_reuse_count = session.debugRuntimeStats().host_realization_reuse_count,
        .host_readback_count = session.debugRuntimeStats().host_readback_count,
        .backend_realization_reuse_count = session.debugRuntimeStats().mlx_realization_reuse_count,
        .backend_promotion_count = session.debugRuntimeStats().mlx_promotion_count,
        .host_eviction_count = session.debugRuntimeStats().host_eviction_count,
        .backend_eviction_count = session.debugRuntimeStats().mlx_eviction_count,
        .dual_resident_peak_count = session.debugRuntimeStats().dual_resident_peak_count,
        .flat_concat_dense_view_count = session.debugRuntimeStats().flat_concat_dense_view_count,
        .first_axis_slice_dense_view_count = session.debugRuntimeStats().first_axis_slice_dense_view_count,
        .first_axis_index_dense_view_count = session.debugRuntimeStats().first_axis_index_dense_view_count,
        .first_axis_concat_dense_view_count = session.debugRuntimeStats().first_axis_concat_dense_view_count,
        .make_array_int_result_count = session.debugRuntimeStats().make_array_int_result_count,
        .make_array_float_result_count = session.debugRuntimeStats().make_array_float_result_count,
        .make_array_boxed_fallback_count = session.debugRuntimeStats().make_array_boxed_fallback_count,
        .make_array_boxed_uniform_numeric_array_count = session.debugRuntimeStats().make_array_boxed_reason_counts[@intFromEnum(runtime.DebugMakeArrayBoxedReason.uniform_numeric_array_unstacked)],
        .make_array_boxed_irregular_numeric_array_count = session.debugRuntimeStats().make_array_boxed_reason_counts[@intFromEnum(runtime.DebugMakeArrayBoxedReason.irregular_numeric_array)],
        .make_array_boxed_non_numeric_item_count = session.debugRuntimeStats().make_array_boxed_reason_counts[@intFromEnum(runtime.DebugMakeArrayBoxedReason.non_numeric_item)],
        .make_array_boxed_len_0_count = session.debugRuntimeStats().make_array_boxed_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_0)],
        .make_array_boxed_len_1_count = session.debugRuntimeStats().make_array_boxed_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_1)],
        .make_array_boxed_len_2_count = session.debugRuntimeStats().make_array_boxed_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_2)],
        .make_array_boxed_len_3_4_count = session.debugRuntimeStats().make_array_boxed_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_3_4)],
        .make_array_boxed_len_5_8_count = session.debugRuntimeStats().make_array_boxed_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_5_8)],
        .make_array_boxed_len_9_16_count = session.debugRuntimeStats().make_array_boxed_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_9_16)],
        .make_array_boxed_len_17_32_count = session.debugRuntimeStats().make_array_boxed_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_17_32)],
        .make_array_boxed_len_33_64_count = session.debugRuntimeStats().make_array_boxed_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_33_64)],
        .make_array_boxed_len_65_128_count = session.debugRuntimeStats().make_array_boxed_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_65_128)],
        .make_array_boxed_len_129_256_count = session.debugRuntimeStats().make_array_boxed_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_129_256)],
        .make_array_boxed_len_257_plus_count = session.debugRuntimeStats().make_array_boxed_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_257_plus)],
        .host_matrix_row_copy_count = session.debugRuntimeStats().host_matrix_row_copy_count,
        .host_matrix_index_copy_count = session.debugRuntimeStats().host_matrix_index_copy_count,
        .host_matrix_mask_copy_count = session.debugRuntimeStats().host_matrix_mask_copy_count,
        .host_index_in_bounds_fast_count = session.debugRuntimeStats().host_index_in_bounds_fast_count,
        .host_index_in_bounds_fallback_count = session.debugRuntimeStats().host_index_in_bounds_fallback_count,
        .host_index_copy_count = session.debugRuntimeStats().host_index_copy_count,
        .host_mask_copy_count = session.debugRuntimeStats().host_mask_copy_count,
        .projection_closure_alloc_count = session.debugRuntimeStats().projection_closure_alloc_count,
        .projection_closure_release_count = session.debugRuntimeStats().projection_closure_release_count,
        .apply_each_generic_count = session.debugRuntimeStats().apply_each_generic_count,
        .apply_fold_generic_count = session.debugRuntimeStats().apply_fold_generic_count,
        .apply_scan_generic_count = session.debugRuntimeStats().apply_scan_generic_count,
        .apply_each_right_generic_count = session.debugRuntimeStats().apply_each_right_generic_count,
        .apply_each_left_generic_count = session.debugRuntimeStats().apply_each_left_generic_count,
        .apply_each_prior_fast_bit_count = session.debugRuntimeStats().apply_each_prior_fast_bit_count,
        .apply_each_prior_fast_bit_element_count = session.debugRuntimeStats().apply_each_prior_fast_bit_element_count,
        .apply_each_prior_generic_count = session.debugRuntimeStats().apply_each_prior_generic_count,
        .apply_each_prior_generic_element_count = session.debugRuntimeStats().apply_each_prior_generic_element_count,
        .apply_each_right_fast_string_contains_count = session.debugRuntimeStats().apply_each_right_fast_string_contains_count,
        .apply_each_fast_numeric_unary_count = session.debugRuntimeStats().apply_each_fast_numeric_unary_count,
        .apply_each_fast_numeric_vector_code_count = session.debugRuntimeStats().apply_each_fast_numeric_vector_code_count,
        .apply_each_fast_numeric_closure_count = session.debugRuntimeStats().apply_each_fast_numeric_closure_count,
        .apply_each_fast_unary_lifted_count = session.debugRuntimeStats().apply_each_fast_unary_lifted_count,
        .apply_each_fast_dense_count = session.debugRuntimeStats().apply_each_fast_dense_count,
        .apply_each_fast_dense_miss_unsupported_base_count = session.debugRuntimeStats().apply_each_fast_dense_miss_counts[@intFromEnum(runtime.DebugDenseEachMiss.unsupported_base)],
        .apply_each_fast_dense_miss_non_dense_args_or_shape_count = session.debugRuntimeStats().apply_each_fast_dense_miss_counts[@intFromEnum(runtime.DebugDenseEachMiss.non_dense_args_or_shape)],
        .apply_each_right_fast_dense_count = session.debugRuntimeStats().apply_each_right_fast_dense_count,
        .apply_each_right_fast_dense_miss_unsupported_base_count = session.debugRuntimeStats().apply_each_right_fast_dense_miss_counts[@intFromEnum(runtime.DebugDenseEachRightMiss.unsupported_base)],
        .apply_each_right_fast_dense_miss_non_vector_right_count = session.debugRuntimeStats().apply_each_right_fast_dense_miss_counts[@intFromEnum(runtime.DebugDenseEachRightMiss.non_vector_right)],
        .each_right_fast_string_contains_miss_non_string_left_count = session.debugRuntimeStats().each_right_fast_string_contains_miss_non_string_left_count,
        .each_right_fast_string_contains_miss_non_string_right_count = session.debugRuntimeStats().each_right_fast_string_contains_miss_non_string_right_count,
        .grade_structural_numeric_fast_count = session.debugRuntimeStats().grade_structural_numeric_fast_count,
        .fast_dense_assign_attempt_count = session.debugRuntimeStats().fast_dense_assign_attempt_count,
        .fast_dense_assign_hit_count = session.debugRuntimeStats().fast_dense_assign_hit_count,
        .fast_dense_assign_miss_count = session.debugRuntimeStats().fast_dense_assign_miss_count,
        .fast_dense_assign_reuse_count = session.debugRuntimeStats().fast_dense_assign_reuse_count,
        .fast_dense_assign_clone_count = session.debugRuntimeStats().fast_dense_assign_clone_count,
        .fast_dense_assign_clone_non_unique_count = session.debugRuntimeStats().fast_dense_assign_clone_reason_counts[@intFromEnum(runtime.DebugFastDenseAssignCloneReason.non_unique)],
        .fast_dense_assign_clone_frozen_count = session.debugRuntimeStats().fast_dense_assign_clone_reason_counts[@intFromEnum(runtime.DebugFastDenseAssignCloneReason.frozen)],
        .fast_dense_assign_clone_other_count = session.debugRuntimeStats().fast_dense_assign_clone_reason_counts[@intFromEnum(runtime.DebugFastDenseAssignCloneReason.other)],
        .fast_dense_assign_target_element_count = session.debugRuntimeStats().fast_dense_assign_target_element_count,
        .fast_dense_assign_scalar_target_count = session.debugRuntimeStats().fast_dense_assign_scalar_target_count,
        .fast_dense_assign_vector_target_count = session.debugRuntimeStats().fast_dense_assign_vector_target_count,
        .fast_dense_assign_scalar_rhs_count = session.debugRuntimeStats().fast_dense_assign_scalar_rhs_count,
        .fast_dense_assign_vector_rhs_count = session.debugRuntimeStats().fast_dense_assign_vector_rhs_count,
        .indexed_assign_count = session.debugRuntimeStats().indexed_assign_count,
        .indexed_assign_global_count = session.debugRuntimeStats().indexed_assign_global_count,
        .indexed_assign_local_count = session.debugRuntimeStats().indexed_assign_local_count,
        .owned_amend_count = session.debugRuntimeStats().owned_amend_count,
        .local_release_skip_count = session.debugRuntimeStats().local_release_skip_count,
        .local_release_taken_count = session.debugRuntimeStats().local_release_taken_count,
        .code_opcode_total_count = session.debugRuntimeStats().code_op_total_count,
        .code_opcode_top_counts = session.debugCodeOpcodeTopCounts(),
        .code_opcode_family_counts = session.debugCodeOpcodeFamilyCounts(),
        .jump_if_false_count = session.debugRuntimeStats().jump_if_false_count,
        .jump_if_false_scalar_count = session.debugRuntimeStats().jump_if_false_scalar_count,
        .inline_scalar_dyad_attempt_count = session.debugRuntimeStats().inline_scalar_dyad_attempt_count,
        .inline_scalar_dyad_hit_count = session.debugRuntimeStats().inline_scalar_dyad_hit_count,
        .inline_scalar_dyad_fallback_count = session.debugRuntimeStats().inline_scalar_dyad_fallback_count,
        .shaped_scalar_dyad_count = session.debugRuntimeStats().shaped_scalar_dyad_count,
        .global_call_slots_count = session.debugRuntimeStats().code_run_count,
        .global_call_slots_fast_count = 0,
        .global_call_slots_fallback_count = 0,
        .code_run_count = session.debugRuntimeStats().code_run_count,
        .code_tail_continue_count = session.debugRuntimeStats().code_tail_continue_count,
        .code_global_call_count = session.debugRuntimeStats().code_global_call_count,
        .code_global_call_direct_count = session.debugRuntimeStats().code_global_call_direct_count,
        .code_global_call_fallback_count = session.debugRuntimeStats().code_global_call_fallback_count,
        .code_global_call_fallback_no_code_count = session.debugRuntimeStats().code_global_call_fallback_reason_counts[@intFromEnum(runtime.DebugCodeGlobalCallFallbackReason.no_code)],
        .code_global_call_fallback_arity_count = session.debugRuntimeStats().code_global_call_fallback_reason_counts[@intFromEnum(runtime.DebugCodeGlobalCallFallbackReason.arity)],
        .code_global_call_fallback_other_reason_count = session.debugRuntimeStats().code_global_call_fallback_reason_counts[@intFromEnum(runtime.DebugCodeGlobalCallFallbackReason.other)],
        .code_global_call_fallback_builtin_count = session.debugRuntimeStats().code_global_call_fallback_kind_counts[@intFromEnum(runtime.DebugCodeGlobalCallFallbackKind.builtin)],
        .code_global_call_fallback_closure_count = session.debugRuntimeStats().code_global_call_fallback_kind_counts[@intFromEnum(runtime.DebugCodeGlobalCallFallbackKind.closure)],
        .code_global_call_fallback_array_count = session.debugRuntimeStats().code_global_call_fallback_kind_counts[@intFromEnum(runtime.DebugCodeGlobalCallFallbackKind.array)],
        .code_global_call_fallback_other_kind_count = session.debugRuntimeStats().code_global_call_fallback_kind_counts[@intFromEnum(runtime.DebugCodeGlobalCallFallbackKind.other)],
        .code_compile_count = session.debugRuntimeStats().code_compile_count,
        .code_compile_success_count = session.debugRuntimeStats().code_compile_success_count,
        .code_compile_miss_arity_or_local_limit_count = session.debugRuntimeStats().code_compile_miss_counts[@intFromEnum(runtime.DebugCodeCompileMiss.arity_or_local_limit)],
        .code_compile_miss_body_size_count = session.debugRuntimeStats().code_compile_miss_counts[@intFromEnum(runtime.DebugCodeCompileMiss.body_size)],
        .code_compile_miss_invalid_code_count = session.debugRuntimeStats().code_compile_miss_counts[@intFromEnum(runtime.DebugCodeCompileMiss.invalid_code)],
        .code_compile_miss_unsupported_opcode_or_operand_count = session.debugRuntimeStats().code_compile_miss_counts[@intFromEnum(runtime.DebugCodeCompileMiss.unsupported_opcode_or_operand)],
        .code_compile_miss_target_or_offset_count = session.debugRuntimeStats().code_compile_miss_counts[@intFromEnum(runtime.DebugCodeCompileMiss.target_or_offset)],
        .code_compile_miss_code_body_size_count = session.debugRuntimeStats().code_compile_miss_counts[@intFromEnum(runtime.DebugCodeCompileMiss.code_body_size)],
        .code_compile_miss_stack_size_count = session.debugRuntimeStats().code_compile_miss_counts[@intFromEnum(runtime.DebugCodeCompileMiss.stack_size)],
        .code_compile_unsupported_opcode_top_counts = session.debugCodeCompileUnsupportedOpcodeTopCounts(),
        .code_indexed_assign_sources_count = session.debugRuntimeStats().code_indexed_assign_sources_count,
        .code_indexed_assign_stack_count = session.debugRuntimeStats().code_indexed_assign_stack_count,
        .dense_fusion_enabled = dense_fusion.enabled,
        .dense_fusion_add_fold_map_candidates = dense_fusion.compact_add_fold_map_candidates,
        .dense_fusion_add_fold_map_hits = dense_fusion.compact_add_fold_map_hits,
        .dense_fusion_add_fold_map_disabled = dense_fusion.compact_add_fold_map_disabled,
        .host_fold_fast_count = session.debugRuntimeStats().host_fold_fast_count,
        .host_scan_fast_count = session.debugRuntimeStats().host_scan_fast_count,
        .host_fold_scan_miss_unsupported_builtin_count = session.debugRuntimeStats().host_fold_scan_miss_counts[@intFromEnum(runtime.DebugHostFoldScanMiss.unsupported_builtin)],
        .host_fold_scan_miss_backend_override_count = session.debugRuntimeStats().host_fold_scan_miss_counts[@intFromEnum(runtime.DebugHostFoldScanMiss.backend_override)],
        .host_fold_scan_miss_non_numeric_or_shape_count = session.debugRuntimeStats().host_fold_scan_miss_counts[@intFromEnum(runtime.DebugHostFoldScanMiss.non_numeric_or_shape)],
        .host_fold_scan_miss_planner_non_host_count = session.debugRuntimeStats().host_fold_scan_miss_counts[@intFromEnum(runtime.DebugHostFoldScanMiss.planner_non_host)],
        .host_fold_scan_miss_preserve_generic_semantics_count = session.debugRuntimeStats().host_fold_scan_miss_counts[@intFromEnum(runtime.DebugHostFoldScanMiss.preserve_generic_semantics)],
        .host_fold_scan_miss_unsupported_input_count = session.debugRuntimeStats().host_fold_scan_miss_counts[@intFromEnum(runtime.DebugHostFoldScanMiss.unsupported_input)],
        .host_dense_dyad_host_count = session.debugRuntimeStats().host_dense_dyad_host_count,
        .host_dense_dyad_host_element_count = session.debugRuntimeStats().host_dense_dyad_host_element_count,
        .host_dense_dyad_host_rowwise_count = session.debugRuntimeStats().host_dense_dyad_host_rowwise_count,
        .host_dense_dyad_host_with_backend_input_count = session.debugRuntimeStats().host_dense_dyad_host_with_backend_input_count,
        .host_dense_dyad_add_count = session.debugRuntimeStats().host_dense_dyad_host_op_counts[@intFromEnum(runtime.DebugHostDenseDyadOp.add)],
        .host_dense_dyad_sub_count = session.debugRuntimeStats().host_dense_dyad_host_op_counts[@intFromEnum(runtime.DebugHostDenseDyadOp.sub)],
        .host_dense_dyad_mul_count = session.debugRuntimeStats().host_dense_dyad_host_op_counts[@intFromEnum(runtime.DebugHostDenseDyadOp.mul)],
        .host_dense_dyad_div_count = session.debugRuntimeStats().host_dense_dyad_host_op_counts[@intFromEnum(runtime.DebugHostDenseDyadOp.div)],
        .host_dense_dyad_less_count = session.debugRuntimeStats().host_dense_dyad_host_op_counts[@intFromEnum(runtime.DebugHostDenseDyadOp.less)],
        .host_dense_dyad_more_count = session.debugRuntimeStats().host_dense_dyad_host_op_counts[@intFromEnum(runtime.DebugHostDenseDyadOp.more)],
        .host_dense_dyad_equal_count = session.debugRuntimeStats().host_dense_dyad_host_op_counts[@intFromEnum(runtime.DebugHostDenseDyadOp.equal)],
        .host_dense_dyad_miss_planner_backend_count = session.debugRuntimeStats().host_dense_dyad_miss_counts[@intFromEnum(runtime.DebugHostDenseDyadMiss.planner_backend)],
        .host_dense_dyad_miss_mode_count = session.debugRuntimeStats().host_dense_dyad_miss_counts[@intFromEnum(runtime.DebugHostDenseDyadMiss.mode)],
        .host_dense_dyad_miss_view_count = session.debugRuntimeStats().host_dense_dyad_miss_counts[@intFromEnum(runtime.DebugHostDenseDyadMiss.view)],
        .host_string_view_alloc_count = session.debugRuntimeStats().host_string_view_alloc_count,
        .host_string_view_release_count = session.debugRuntimeStats().host_string_view_release_count,
        .host_string_view_generic_count = session.debugRuntimeStats().host_string_view_reason_counts[@intFromEnum(runtime.DebugHostStringViewReason.generic)],
        .host_string_view_string_list_eager_view_count = session.debugRuntimeStats().host_string_view_reason_counts[@intFromEnum(runtime.DebugHostStringViewReason.string_list_eager_view)],
        .host_string_view_string_list_split_scalar_count = session.debugRuntimeStats().host_string_view_reason_counts[@intFromEnum(runtime.DebugHostStringViewReason.string_list_split_scalar)],
        .host_string_view_len_0_count = session.debugRuntimeStats().host_string_view_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_0)],
        .host_string_view_len_1_count = session.debugRuntimeStats().host_string_view_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_1)],
        .host_string_view_len_2_count = session.debugRuntimeStats().host_string_view_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_2)],
        .host_string_view_len_3_4_count = session.debugRuntimeStats().host_string_view_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_3_4)],
        .host_string_view_len_5_8_count = session.debugRuntimeStats().host_string_view_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_5_8)],
        .host_string_view_len_9_16_count = session.debugRuntimeStats().host_string_view_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_9_16)],
        .host_string_view_len_17_32_count = session.debugRuntimeStats().host_string_view_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_17_32)],
        .host_string_view_len_33_64_count = session.debugRuntimeStats().host_string_view_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_33_64)],
        .host_string_view_len_65_128_count = session.debugRuntimeStats().host_string_view_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_65_128)],
        .host_string_view_len_129_256_count = session.debugRuntimeStats().host_string_view_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_129_256)],
        .host_string_view_len_257_plus_count = session.debugRuntimeStats().host_string_view_len_bucket_counts[@intFromEnum(runtime.DebugProbeLenBucket.len_257_plus)],
        .host_string_list_item_value_count = session.debugRuntimeStats().host_string_list_item_value_count,
        .host_string_list_item_eager_owned_count = session.debugRuntimeStats().host_string_list_item_eager_owned_count,
        .host_string_list_item_eager_view_count = session.debugRuntimeStats().host_string_list_item_eager_view_count,
        .host_string_list_item_split_scalar_count = session.debugRuntimeStats().host_string_list_item_split_scalar_count,
        .host_string_list_item_split_scalar_scan_byte_count = session.debugRuntimeStats().host_string_list_item_split_scalar_scan_byte_count,
        .host_string_list_item_split_scalar_scan_sep_count = session.debugRuntimeStats().host_string_list_item_split_scalar_scan_sep_count,
        .flat_slice_alloc_count = session.debugRuntimeStats().numeric_structural_alloc_counts[@intFromEnum(runtime.DebugNumericStructuralTag.flat_slice)],
        .flat_slice_release_count = session.debugRuntimeStats().numeric_structural_release_counts[@intFromEnum(runtime.DebugNumericStructuralTag.flat_slice)],
        .flat_concat_alloc_count = session.debugRuntimeStats().numeric_structural_alloc_counts[@intFromEnum(runtime.DebugNumericStructuralTag.flat_concat)],
        .flat_concat_release_count = session.debugRuntimeStats().numeric_structural_release_counts[@intFromEnum(runtime.DebugNumericStructuralTag.flat_concat)],
        .flat_segments_alloc_count = session.debugRuntimeStats().numeric_structural_alloc_counts[@intFromEnum(runtime.DebugNumericStructuralTag.flat_segments)],
        .flat_segments_release_count = session.debugRuntimeStats().numeric_structural_release_counts[@intFromEnum(runtime.DebugNumericStructuralTag.flat_segments)],
        .first_axis_slice_alloc_count = session.debugRuntimeStats().numeric_structural_alloc_counts[@intFromEnum(runtime.DebugNumericStructuralTag.first_axis_slice)],
        .first_axis_slice_release_count = session.debugRuntimeStats().numeric_structural_release_counts[@intFromEnum(runtime.DebugNumericStructuralTag.first_axis_slice)],
        .first_axis_index_alloc_count = session.debugRuntimeStats().numeric_structural_alloc_counts[@intFromEnum(runtime.DebugNumericStructuralTag.first_axis_index)],
        .first_axis_index_release_count = session.debugRuntimeStats().numeric_structural_release_counts[@intFromEnum(runtime.DebugNumericStructuralTag.first_axis_index)],
        .first_axis_concat_alloc_count = session.debugRuntimeStats().numeric_structural_alloc_counts[@intFromEnum(runtime.DebugNumericStructuralTag.first_axis_concat)],
        .first_axis_concat_release_count = session.debugRuntimeStats().numeric_structural_release_counts[@intFromEnum(runtime.DebugNumericStructuralTag.first_axis_concat)],
        .reshape_view_alloc_count = session.debugRuntimeStats().numeric_structural_alloc_counts[@intFromEnum(runtime.DebugNumericStructuralTag.reshape_view)],
        .reshape_view_release_count = session.debugRuntimeStats().numeric_structural_release_counts[@intFromEnum(runtime.DebugNumericStructuralTag.reshape_view)],
        .transpose_view_alloc_count = session.debugRuntimeStats().numeric_structural_alloc_counts[@intFromEnum(runtime.DebugNumericStructuralTag.transpose_view)],
        .transpose_view_release_count = session.debugRuntimeStats().numeric_structural_release_counts[@intFromEnum(runtime.DebugNumericStructuralTag.transpose_view)],
        .structured_derived2_hit_count = session.debugRuntimeStats().structured_derived2_hit_count,
        .apply_derived_closure_count = session.debugRuntimeStats().apply_derived_closure_count,
        .apply_projection_count = session.debugRuntimeStats().apply_projection_count,
        .autograd_builtin_grad_count = session.debugRuntimeStats().autograd_builtin_grad_count,
        .autograd_builtin_valuegrad_count = session.debugRuntimeStats().autograd_builtin_valuegrad_count,
        .autograd_slow_finite_difference_count = session.debugRuntimeStats().autograd_slow_finite_difference_count,
        .dense_autodiff_cache_hit_count = session.debugRuntimeStats().dense_autodiff_cache_hit_count,
        .dense_autodiff_cache_miss_count = session.debugRuntimeStats().dense_autodiff_cache_miss_count,
        .dense_autodiff_lower_success_count = session.debugRuntimeStats().dense_autodiff_lower_success_count,
        .dense_autodiff_reject_wrong_arity_count = session.debugDenseAutodiffRejectCount(.wrong_arity),
        .dense_autodiff_reject_non_vector_target_count = session.debugDenseAutodiffRejectCount(.non_vector_target),
        .dense_autodiff_reject_non_scalar_result_count = session.debugDenseAutodiffRejectCount(.non_scalar_result),
        .dense_autodiff_reject_unsupported_opcode_count = session.debugDenseAutodiffRejectCount(.unsupported_opcode),
        .dense_autodiff_reject_unsupported_shape_flow_count = session.debugDenseAutodiffRejectCount(.unsupported_shape_flow),
        .dense_autodiff_reject_unsupported_builtin_count = session.debugDenseAutodiffRejectCount(.unsupported_builtin),
        .dense_autodiff_reject_capture_or_global_dependency_count = session.debugDenseAutodiffRejectCount(.capture_or_global_dependency),
        .dense_autodiff_reject_non_dense_operand_count = session.debugDenseAutodiffRejectCount(.non_dense_operand),
        .planner_numeric_dyad_host_count = session.debugRuntimeStats().dense_plan_counts[@intFromEnum(runtime.DenseRegionKind.numeric_dyad)][@intFromEnum(runtime.DenseExecBackend.host)],
        .planner_numeric_dyad_backend_count = session.debugRuntimeStats().dense_plan_counts[@intFromEnum(runtime.DenseRegionKind.numeric_dyad)][@intFromEnum(runtime.DenseExecBackend.mlx)],
        .planner_compare_mask_host_count = session.debugRuntimeStats().dense_plan_counts[@intFromEnum(runtime.DenseRegionKind.compare_mask)][@intFromEnum(runtime.DenseExecBackend.host)],
        .planner_compare_mask_backend_count = session.debugRuntimeStats().dense_plan_counts[@intFromEnum(runtime.DenseRegionKind.compare_mask)][@intFromEnum(runtime.DenseExecBackend.mlx)],
        .planner_reduce_host_count = session.debugRuntimeStats().dense_plan_counts[@intFromEnum(runtime.DenseRegionKind.reduce)][@intFromEnum(runtime.DenseExecBackend.host)],
        .planner_reduce_backend_count = session.debugRuntimeStats().dense_plan_counts[@intFromEnum(runtime.DenseRegionKind.reduce)][@intFromEnum(runtime.DenseExecBackend.mlx)],
        .exec_numeric_dyad_host_count = session.debugRuntimeStats().dense_exec_counts[@intFromEnum(runtime.DenseRegionKind.numeric_dyad)][@intFromEnum(runtime.DenseExecBackend.host)],
        .exec_numeric_dyad_backend_count = session.debugRuntimeStats().dense_exec_counts[@intFromEnum(runtime.DenseRegionKind.numeric_dyad)][@intFromEnum(runtime.DenseExecBackend.mlx)],
        .exec_compare_mask_host_count = session.debugRuntimeStats().dense_exec_counts[@intFromEnum(runtime.DenseRegionKind.compare_mask)][@intFromEnum(runtime.DenseExecBackend.host)],
        .exec_compare_mask_backend_count = session.debugRuntimeStats().dense_exec_counts[@intFromEnum(runtime.DenseRegionKind.compare_mask)][@intFromEnum(runtime.DenseExecBackend.mlx)],
        .exec_reduce_host_count = session.debugRuntimeStats().dense_exec_counts[@intFromEnum(runtime.DenseRegionKind.reduce)][@intFromEnum(runtime.DenseExecBackend.host)],
        .exec_reduce_backend_count = session.debugRuntimeStats().dense_exec_counts[@intFromEnum(runtime.DenseRegionKind.reduce)][@intFromEnum(runtime.DenseExecBackend.mlx)],
        .exec_scan_host_count = session.debugRuntimeStats().dense_exec_counts[@intFromEnum(runtime.DenseRegionKind.scan)][@intFromEnum(runtime.DenseExecBackend.host)],
        .exec_scan_backend_count = session.debugRuntimeStats().dense_exec_counts[@intFromEnum(runtime.DenseRegionKind.scan)][@intFromEnum(runtime.DenseExecBackend.mlx)],
        .exec_matmul_host_count = session.debugRuntimeStats().dense_exec_counts[@intFromEnum(runtime.DenseRegionKind.matmul)][@intFromEnum(runtime.DenseExecBackend.host)],
        .exec_matmul_backend_count = session.debugRuntimeStats().dense_exec_counts[@intFromEnum(runtime.DenseRegionKind.matmul)][@intFromEnum(runtime.DenseExecBackend.mlx)],
        .exec_dense_autodiff_host_count = session.debugRuntimeStats().dense_exec_counts[@intFromEnum(runtime.DenseRegionKind.dense_autodiff)][@intFromEnum(runtime.DenseExecBackend.host)],
        .exec_dense_autodiff_backend_count = session.debugRuntimeStats().dense_exec_counts[@intFromEnum(runtime.DenseRegionKind.dense_autodiff)][@intFromEnum(runtime.DenseExecBackend.mlx)],
        .planner_scan_host_count = session.debugRuntimeStats().dense_plan_counts[@intFromEnum(runtime.DenseRegionKind.scan)][@intFromEnum(runtime.DenseExecBackend.host)],
        .planner_scan_backend_count = session.debugRuntimeStats().dense_plan_counts[@intFromEnum(runtime.DenseRegionKind.scan)][@intFromEnum(runtime.DenseExecBackend.mlx)],
        .planner_matmul_host_count = session.debugRuntimeStats().dense_plan_counts[@intFromEnum(runtime.DenseRegionKind.matmul)][@intFromEnum(runtime.DenseExecBackend.host)],
        .planner_matmul_backend_count = session.debugRuntimeStats().dense_plan_counts[@intFromEnum(runtime.DenseRegionKind.matmul)][@intFromEnum(runtime.DenseExecBackend.mlx)],
        .planner_dense_autodiff_host_count = session.debugRuntimeStats().dense_plan_counts[@intFromEnum(runtime.DenseRegionKind.dense_autodiff)][@intFromEnum(runtime.DenseExecBackend.host)],
        .planner_dense_autodiff_backend_count = session.debugRuntimeStats().dense_plan_counts[@intFromEnum(runtime.DenseRegionKind.dense_autodiff)][@intFromEnum(runtime.DenseExecBackend.mlx)],
        .last_dense_plan_region = session.lastDensePlanRegion(),
        .last_dense_plan_backend = session.lastDensePlanBackend(),
        .last_dense_exec_backend = session.lastDenseExecBackend(),
        .last_dense_plan_reason = session.lastDensePlanReason(),
        .last_dense_plan_overridden = session.lastDensePlanOverridden(),
        .last_dense_autodiff_exec_path = session.lastDenseAutodiffExecPath(),
    };
}

fn writeKernelProbeBackendText(writer: anytype, backend: []const u8, entries: []const runtime.DebugNameCount) !void {
    for (entries) |entry| {
        if (entry.count == 0) continue;
        try writer.print("kernel.{s}.{s}={d}\n", .{ backend, entry.name, entry.count });
    }
}

fn writeKernelProbeText(writer: anytype, kernels: KernelProbeResult) !void {
    try writeKernelProbeBackendText(writer, "simd", kernels.simd[0..]);
}

pub fn writeProbeResultText(writer: anytype, result: ProbeResult) !void {
    try writer.print("probe {s} status={s}", .{ result.name, result.status });
    if (result.err_name) |err_name| try writer.print(" err={s}", .{err_name});
    try writer.writeByte('\n');

    try writeKernelProbeText(writer, result.kernels);
    try writer.print("host_realization_count={d}\n", .{result.host_realization_count});
    try writer.print("structural_host_realization_count={d}\n", .{result.structural_host_realization_count});
    try writer.print("backend_realization_count={d}\n", .{result.backend_realization_count});
    try writer.print("structural_backend_realization_count={d}\n", .{result.structural_backend_realization_count});
    try writer.print("host_realization_reuse_count={d}\n", .{result.host_realization_reuse_count});
    try writer.print("host_readback_count={d}\n", .{result.host_readback_count});
    try writer.print("backend_realization_reuse_count={d}\n", .{result.backend_realization_reuse_count});
    try writer.print("backend_promotion_count={d}\n", .{result.backend_promotion_count});
    try writer.print("host_eviction_count={d}\n", .{result.host_eviction_count});
    try writer.print("backend_eviction_count={d}\n", .{result.backend_eviction_count});
    try writer.print("dual_resident_peak_count={d}\n", .{result.dual_resident_peak_count});
    try writer.print("flat_concat_dense_view_count={d}\n", .{result.flat_concat_dense_view_count});
    try writer.print("first_axis_slice_dense_view_count={d}\n", .{result.first_axis_slice_dense_view_count});
    try writer.print("first_axis_index_dense_view_count={d}\n", .{result.first_axis_index_dense_view_count});
    try writer.print("first_axis_concat_dense_view_count={d}\n", .{result.first_axis_concat_dense_view_count});
    try writer.print("make_array_int_result_count={d}\n", .{result.make_array_int_result_count});
    try writer.print("make_array_float_result_count={d}\n", .{result.make_array_float_result_count});
    try writer.print("make_array_boxed_fallback_count={d}\n", .{result.make_array_boxed_fallback_count});
    try writer.print("make_array_boxed_uniform_numeric_array_count={d}\n", .{result.make_array_boxed_uniform_numeric_array_count});
    try writer.print("make_array_boxed_irregular_numeric_array_count={d}\n", .{result.make_array_boxed_irregular_numeric_array_count});
    try writer.print("make_array_boxed_non_numeric_item_count={d}\n", .{result.make_array_boxed_non_numeric_item_count});
    try writer.print("make_array_boxed_len_0_count={d}\n", .{result.make_array_boxed_len_0_count});
    try writer.print("make_array_boxed_len_1_count={d}\n", .{result.make_array_boxed_len_1_count});
    try writer.print("make_array_boxed_len_2_count={d}\n", .{result.make_array_boxed_len_2_count});
    try writer.print("make_array_boxed_len_3_4_count={d}\n", .{result.make_array_boxed_len_3_4_count});
    try writer.print("make_array_boxed_len_5_8_count={d}\n", .{result.make_array_boxed_len_5_8_count});
    try writer.print("make_array_boxed_len_9_16_count={d}\n", .{result.make_array_boxed_len_9_16_count});
    try writer.print("make_array_boxed_len_17_32_count={d}\n", .{result.make_array_boxed_len_17_32_count});
    try writer.print("make_array_boxed_len_33_64_count={d}\n", .{result.make_array_boxed_len_33_64_count});
    try writer.print("make_array_boxed_len_65_128_count={d}\n", .{result.make_array_boxed_len_65_128_count});
    try writer.print("make_array_boxed_len_129_256_count={d}\n", .{result.make_array_boxed_len_129_256_count});
    try writer.print("make_array_boxed_len_257_plus_count={d}\n", .{result.make_array_boxed_len_257_plus_count});
    try writer.print("host_matrix_row_copy_count={d}\n", .{result.host_matrix_row_copy_count});
    try writer.print("host_matrix_index_copy_count={d}\n", .{result.host_matrix_index_copy_count});
    try writer.print("host_matrix_mask_copy_count={d}\n", .{result.host_matrix_mask_copy_count});
    try writer.print("host_index_in_bounds_fast_count={d}\n", .{result.host_index_in_bounds_fast_count});
    try writer.print("host_index_in_bounds_fallback_count={d}\n", .{result.host_index_in_bounds_fallback_count});
    try writer.print("host_index_copy_count={d}\n", .{result.host_index_copy_count});
    try writer.print("host_mask_copy_count={d}\n", .{result.host_mask_copy_count});
    try writer.print("projection_closure_alloc_count={d}\n", .{result.projection_closure_alloc_count});
    try writer.print("projection_closure_release_count={d}\n", .{result.projection_closure_release_count});
    try writer.print("apply_each_generic_count={d}\n", .{result.apply_each_generic_count});
    try writer.print("apply_fold_generic_count={d}\n", .{result.apply_fold_generic_count});
    try writer.print("apply_scan_generic_count={d}\n", .{result.apply_scan_generic_count});
    try writer.print("apply_each_right_generic_count={d}\n", .{result.apply_each_right_generic_count});
    try writer.print("apply_each_left_generic_count={d}\n", .{result.apply_each_left_generic_count});
    try writer.print("apply_each_prior_fast_bit_count={d}\n", .{result.apply_each_prior_fast_bit_count});
    try writer.print("apply_each_prior_fast_bit_element_count={d}\n", .{result.apply_each_prior_fast_bit_element_count});
    try writer.print("apply_each_prior_generic_count={d}\n", .{result.apply_each_prior_generic_count});
    try writer.print("apply_each_prior_generic_element_count={d}\n", .{result.apply_each_prior_generic_element_count});
    try writer.print("apply_each_right_fast_string_contains_count={d}\n", .{result.apply_each_right_fast_string_contains_count});
    try writer.print("apply_each_fast_numeric_unary_count={d}\n", .{result.apply_each_fast_numeric_unary_count});
    try writer.print("apply_each_fast_numeric_vector_code_count={d}\n", .{result.apply_each_fast_numeric_vector_code_count});
    try writer.print("apply_each_fast_numeric_closure_count={d}\n", .{result.apply_each_fast_numeric_closure_count});
    try writer.print("apply_each_fast_unary_lifted_count={d}\n", .{result.apply_each_fast_unary_lifted_count});
    try writer.print("apply_each_fast_dense_count={d}\n", .{result.apply_each_fast_dense_count});
    try writer.print("apply_each_fast_dense_miss_unsupported_base_count={d}\n", .{result.apply_each_fast_dense_miss_unsupported_base_count});
    try writer.print("apply_each_fast_dense_miss_non_dense_args_or_shape_count={d}\n", .{result.apply_each_fast_dense_miss_non_dense_args_or_shape_count});
    try writer.print("apply_each_right_fast_dense_count={d}\n", .{result.apply_each_right_fast_dense_count});
    try writer.print("apply_each_right_fast_dense_miss_unsupported_base_count={d}\n", .{result.apply_each_right_fast_dense_miss_unsupported_base_count});
    try writer.print("apply_each_right_fast_dense_miss_non_vector_right_count={d}\n", .{result.apply_each_right_fast_dense_miss_non_vector_right_count});
    try writer.print("each_right_fast_string_contains_miss_non_string_left_count={d}\n", .{result.each_right_fast_string_contains_miss_non_string_left_count});
    try writer.print("each_right_fast_string_contains_miss_non_string_right_count={d}\n", .{result.each_right_fast_string_contains_miss_non_string_right_count});
    try writer.print("grade_structural_numeric_fast_count={d}\n", .{result.grade_structural_numeric_fast_count});
    try writer.print("fast_dense_assign_attempt_count={d}\n", .{result.fast_dense_assign_attempt_count});
    try writer.print("fast_dense_assign_hit_count={d}\n", .{result.fast_dense_assign_hit_count});
    try writer.print("fast_dense_assign_miss_count={d}\n", .{result.fast_dense_assign_miss_count});
    try writer.print("fast_dense_assign_reuse_count={d}\n", .{result.fast_dense_assign_reuse_count});
    try writer.print("fast_dense_assign_clone_count={d}\n", .{result.fast_dense_assign_clone_count});
    try writer.print("fast_dense_assign_clone_non_unique_count={d}\n", .{result.fast_dense_assign_clone_non_unique_count});
    try writer.print("fast_dense_assign_clone_frozen_count={d}\n", .{result.fast_dense_assign_clone_frozen_count});
    try writer.print("fast_dense_assign_clone_other_count={d}\n", .{result.fast_dense_assign_clone_other_count});
    try writer.print("fast_dense_assign_target_element_count={d}\n", .{result.fast_dense_assign_target_element_count});
    try writer.print("fast_dense_assign_scalar_target_count={d}\n", .{result.fast_dense_assign_scalar_target_count});
    try writer.print("fast_dense_assign_vector_target_count={d}\n", .{result.fast_dense_assign_vector_target_count});
    try writer.print("fast_dense_assign_scalar_rhs_count={d}\n", .{result.fast_dense_assign_scalar_rhs_count});
    try writer.print("fast_dense_assign_vector_rhs_count={d}\n", .{result.fast_dense_assign_vector_rhs_count});
    try writer.print("indexed_assign_count={d}\n", .{result.indexed_assign_count});
    try writer.print("indexed_assign_global_count={d}\n", .{result.indexed_assign_global_count});
    try writer.print("indexed_assign_local_count={d}\n", .{result.indexed_assign_local_count});
    try writer.print("owned_amend_count={d}\n", .{result.owned_amend_count});
    try writer.print("local_release_skip_count={d}\n", .{result.local_release_skip_count});
    try writer.print("local_release_taken_count={d}\n", .{result.local_release_taken_count});
    try writer.print("code_opcode_total_count={d}\n", .{result.code_opcode_total_count});
    try writer.writeAll("code_opcode_top_counts=");
    var first_compact_op = true;
    for (result.code_opcode_top_counts) |entry| {
        if (entry.count == 0) continue;
        if (!first_compact_op) try writer.writeByte(',');
        first_compact_op = false;
        try writer.print("{s}[{d}]:{d}", .{ entry.name, entry.opcode, entry.count });
    }
    try writer.writeByte('\n');
    try writer.writeAll("code_opcode_family_counts=");
    var first_compact_family = true;
    for (result.code_opcode_family_counts) |entry| {
        if (entry.count == 0) continue;
        if (!first_compact_family) try writer.writeByte(',');
        first_compact_family = false;
        try writer.print("{s}:{d}", .{ entry.name, entry.count });
    }
    try writer.writeByte('\n');
    try writer.print("jump_if_false_count={d}\n", .{result.jump_if_false_count});
    try writer.print("jump_if_false_scalar_count={d}\n", .{result.jump_if_false_scalar_count});
    try writer.print("inline_scalar_dyad_attempt_count={d}\n", .{result.inline_scalar_dyad_attempt_count});
    try writer.print("inline_scalar_dyad_hit_count={d}\n", .{result.inline_scalar_dyad_hit_count});
    try writer.print("inline_scalar_dyad_fallback_count={d}\n", .{result.inline_scalar_dyad_fallback_count});
    try writer.print("shaped_scalar_dyad_count={d}\n", .{result.shaped_scalar_dyad_count});
    try writer.print("global_call_slots_count={d}\n", .{result.global_call_slots_count});
    try writer.print("global_call_slots_fast_count={d}\n", .{result.global_call_slots_fast_count});
    try writer.print("global_call_slots_fallback_count={d}\n", .{result.global_call_slots_fallback_count});
    try writer.print("code_run_count={d}\n", .{result.code_run_count});
    try writer.print("code_tail_continue_count={d}\n", .{result.code_tail_continue_count});
    try writer.print("code_global_call_count={d}\n", .{result.code_global_call_count});
    try writer.print("code_global_call_direct_count={d}\n", .{result.code_global_call_direct_count});
    try writer.print("code_global_call_fallback_count={d}\n", .{result.code_global_call_fallback_count});
    try writer.print("code_global_call_fallback_no_code_count={d}\n", .{result.code_global_call_fallback_no_code_count});
    try writer.print("code_global_call_fallback_arity_count={d}\n", .{result.code_global_call_fallback_arity_count});
    try writer.print("code_global_call_fallback_other_reason_count={d}\n", .{result.code_global_call_fallback_other_reason_count});
    try writer.print("code_global_call_fallback_builtin_count={d}\n", .{result.code_global_call_fallback_builtin_count});
    try writer.print("code_global_call_fallback_closure_count={d}\n", .{result.code_global_call_fallback_closure_count});
    try writer.print("code_global_call_fallback_array_count={d}\n", .{result.code_global_call_fallback_array_count});
    try writer.print("code_global_call_fallback_other_kind_count={d}\n", .{result.code_global_call_fallback_other_kind_count});
    try writer.print("code_compile_count={d}\n", .{result.code_compile_count});
    try writer.print("code_compile_success_count={d}\n", .{result.code_compile_success_count});
    try writer.print("code_compile_miss_arity_or_local_limit_count={d}\n", .{result.code_compile_miss_arity_or_local_limit_count});
    try writer.print("code_compile_miss_body_size_count={d}\n", .{result.code_compile_miss_body_size_count});
    try writer.print("code_compile_miss_invalid_code_count={d}\n", .{result.code_compile_miss_invalid_code_count});
    try writer.print("code_compile_miss_unsupported_opcode_or_operand_count={d}\n", .{result.code_compile_miss_unsupported_opcode_or_operand_count});
    try writer.print("code_compile_miss_target_or_offset_count={d}\n", .{result.code_compile_miss_target_or_offset_count});
    try writer.print("code_compile_miss_code_body_size_count={d}\n", .{result.code_compile_miss_code_body_size_count});
    try writer.print("code_compile_miss_stack_size_count={d}\n", .{result.code_compile_miss_stack_size_count});
    try writer.writeAll("code_compile_unsupported_opcode_top_counts=");
    var first_compact_compile_op = true;
    for (result.code_compile_unsupported_opcode_top_counts) |entry| {
        if (entry.count == 0) continue;
        if (!first_compact_compile_op) try writer.writeByte(',');
        first_compact_compile_op = false;
        try writer.print("{s}:{d}", .{ entry.name, entry.count });
    }
    try writer.writeByte('\n');
    try writer.print("code_indexed_assign_sources_count={d}\n", .{result.code_indexed_assign_sources_count});
    try writer.print("code_indexed_assign_stack_count={d}\n", .{result.code_indexed_assign_stack_count});
    try writer.print("dense_fusion_enabled={s}\n", .{if (result.dense_fusion_enabled) "true" else "false"});
    try writer.print("dense_fusion_add_fold_map_candidates={d}\n", .{result.dense_fusion_add_fold_map_candidates});
    try writer.print("dense_fusion_add_fold_map_hits={d}\n", .{result.dense_fusion_add_fold_map_hits});
    try writer.print("dense_fusion_add_fold_map_disabled={d}\n", .{result.dense_fusion_add_fold_map_disabled});
    try writer.print("host_fold_fast_count={d}\n", .{result.host_fold_fast_count});
    try writer.print("host_scan_fast_count={d}\n", .{result.host_scan_fast_count});
    try writer.print("host_fold_scan_miss_unsupported_builtin_count={d}\n", .{result.host_fold_scan_miss_unsupported_builtin_count});
    try writer.print("host_fold_scan_miss_backend_override_count={d}\n", .{result.host_fold_scan_miss_backend_override_count});
    try writer.print("host_fold_scan_miss_non_numeric_or_shape_count={d}\n", .{result.host_fold_scan_miss_non_numeric_or_shape_count});
    try writer.print("host_fold_scan_miss_planner_non_host_count={d}\n", .{result.host_fold_scan_miss_planner_non_host_count});
    try writer.print("host_fold_scan_miss_preserve_generic_semantics_count={d}\n", .{result.host_fold_scan_miss_preserve_generic_semantics_count});
    try writer.print("host_fold_scan_miss_unsupported_input_count={d}\n", .{result.host_fold_scan_miss_unsupported_input_count});
    try writer.print("host_dense_dyad_host_count={d}\n", .{result.host_dense_dyad_host_count});
    try writer.print("host_dense_dyad_host_element_count={d}\n", .{result.host_dense_dyad_host_element_count});
    try writer.print("host_dense_dyad_host_rowwise_count={d}\n", .{result.host_dense_dyad_host_rowwise_count});
    try writer.print("host_dense_dyad_host_with_backend_input_count={d}\n", .{result.host_dense_dyad_host_with_backend_input_count});
    try writer.print("host_dense_dyad_add_count={d}\n", .{result.host_dense_dyad_add_count});
    try writer.print("host_dense_dyad_sub_count={d}\n", .{result.host_dense_dyad_sub_count});
    try writer.print("host_dense_dyad_mul_count={d}\n", .{result.host_dense_dyad_mul_count});
    try writer.print("host_dense_dyad_div_count={d}\n", .{result.host_dense_dyad_div_count});
    try writer.print("host_dense_dyad_less_count={d}\n", .{result.host_dense_dyad_less_count});
    try writer.print("host_dense_dyad_more_count={d}\n", .{result.host_dense_dyad_more_count});
    try writer.print("host_dense_dyad_equal_count={d}\n", .{result.host_dense_dyad_equal_count});
    try writer.print("host_dense_dyad_miss_planner_backend_count={d}\n", .{result.host_dense_dyad_miss_planner_backend_count});
    try writer.print("host_dense_dyad_miss_mode_count={d}\n", .{result.host_dense_dyad_miss_mode_count});
    try writer.print("host_dense_dyad_miss_view_count={d}\n", .{result.host_dense_dyad_miss_view_count});
    try writer.print("host_string_view_alloc_count={d}\n", .{result.host_string_view_alloc_count});
    try writer.print("host_string_view_release_count={d}\n", .{result.host_string_view_release_count});
    try writer.print("host_string_view_generic_count={d}\n", .{result.host_string_view_generic_count});
    try writer.print("host_string_view_string_list_eager_view_count={d}\n", .{result.host_string_view_string_list_eager_view_count});
    try writer.print("host_string_view_string_list_split_scalar_count={d}\n", .{result.host_string_view_string_list_split_scalar_count});
    try writer.print("host_string_view_len_0_count={d}\n", .{result.host_string_view_len_0_count});
    try writer.print("host_string_view_len_1_count={d}\n", .{result.host_string_view_len_1_count});
    try writer.print("host_string_view_len_2_count={d}\n", .{result.host_string_view_len_2_count});
    try writer.print("host_string_view_len_3_4_count={d}\n", .{result.host_string_view_len_3_4_count});
    try writer.print("host_string_view_len_5_8_count={d}\n", .{result.host_string_view_len_5_8_count});
    try writer.print("host_string_view_len_9_16_count={d}\n", .{result.host_string_view_len_9_16_count});
    try writer.print("host_string_view_len_17_32_count={d}\n", .{result.host_string_view_len_17_32_count});
    try writer.print("host_string_view_len_33_64_count={d}\n", .{result.host_string_view_len_33_64_count});
    try writer.print("host_string_view_len_65_128_count={d}\n", .{result.host_string_view_len_65_128_count});
    try writer.print("host_string_view_len_129_256_count={d}\n", .{result.host_string_view_len_129_256_count});
    try writer.print("host_string_view_len_257_plus_count={d}\n", .{result.host_string_view_len_257_plus_count});
    try writer.print("host_string_list_item_value_count={d}\n", .{result.host_string_list_item_value_count});
    try writer.print("host_string_list_item_eager_owned_count={d}\n", .{result.host_string_list_item_eager_owned_count});
    try writer.print("host_string_list_item_eager_view_count={d}\n", .{result.host_string_list_item_eager_view_count});
    try writer.print("host_string_list_item_split_scalar_count={d}\n", .{result.host_string_list_item_split_scalar_count});
    try writer.print("host_string_list_item_split_scalar_scan_byte_count={d}\n", .{result.host_string_list_item_split_scalar_scan_byte_count});
    try writer.print("host_string_list_item_split_scalar_scan_sep_count={d}\n", .{result.host_string_list_item_split_scalar_scan_sep_count});
    try writer.print("flat_slice_alloc_count={d}\n", .{result.flat_slice_alloc_count});
    try writer.print("flat_slice_release_count={d}\n", .{result.flat_slice_release_count});
    try writer.print("flat_concat_alloc_count={d}\n", .{result.flat_concat_alloc_count});
    try writer.print("flat_concat_release_count={d}\n", .{result.flat_concat_release_count});
    try writer.print("flat_segments_alloc_count={d}\n", .{result.flat_segments_alloc_count});
    try writer.print("flat_segments_release_count={d}\n", .{result.flat_segments_release_count});
    try writer.print("first_axis_slice_alloc_count={d}\n", .{result.first_axis_slice_alloc_count});
    try writer.print("first_axis_slice_release_count={d}\n", .{result.first_axis_slice_release_count});
    try writer.print("first_axis_index_alloc_count={d}\n", .{result.first_axis_index_alloc_count});
    try writer.print("first_axis_index_release_count={d}\n", .{result.first_axis_index_release_count});
    try writer.print("first_axis_concat_alloc_count={d}\n", .{result.first_axis_concat_alloc_count});
    try writer.print("first_axis_concat_release_count={d}\n", .{result.first_axis_concat_release_count});
    try writer.print("reshape_view_alloc_count={d}\n", .{result.reshape_view_alloc_count});
    try writer.print("reshape_view_release_count={d}\n", .{result.reshape_view_release_count});
    try writer.print("transpose_view_alloc_count={d}\n", .{result.transpose_view_alloc_count});
    try writer.print("transpose_view_release_count={d}\n", .{result.transpose_view_release_count});
    try writer.print("structured_derived2_hit_count={d}\n", .{result.structured_derived2_hit_count});
    try writer.print("apply_derived_closure_count={d}\n", .{result.apply_derived_closure_count});
    try writer.print("apply_projection_count={d}\n", .{result.apply_projection_count});
    try writer.print("autograd_builtin_grad_count={d}\n", .{result.autograd_builtin_grad_count});
    try writer.print("autograd_builtin_valuegrad_count={d}\n", .{result.autograd_builtin_valuegrad_count});
    try writer.print("autograd_slow_finite_difference_count={d}\n", .{result.autograd_slow_finite_difference_count});
    try writer.print("dense_autodiff_cache_hit_count={d}\n", .{result.dense_autodiff_cache_hit_count});
    try writer.print("dense_autodiff_cache_miss_count={d}\n", .{result.dense_autodiff_cache_miss_count});
    try writer.print("dense_autodiff_lower_success_count={d}\n", .{result.dense_autodiff_lower_success_count});
    try writer.print("dense_autodiff_reject_wrong_arity_count={d}\n", .{result.dense_autodiff_reject_wrong_arity_count});
    try writer.print("dense_autodiff_reject_non_vector_target_count={d}\n", .{result.dense_autodiff_reject_non_vector_target_count});
    try writer.print("dense_autodiff_reject_non_scalar_result_count={d}\n", .{result.dense_autodiff_reject_non_scalar_result_count});
    try writer.print("dense_autodiff_reject_unsupported_opcode_count={d}\n", .{result.dense_autodiff_reject_unsupported_opcode_count});
    try writer.print("dense_autodiff_reject_unsupported_shape_flow_count={d}\n", .{result.dense_autodiff_reject_unsupported_shape_flow_count});
    try writer.print("dense_autodiff_reject_unsupported_builtin_count={d}\n", .{result.dense_autodiff_reject_unsupported_builtin_count});
    try writer.print("dense_autodiff_reject_capture_or_global_dependency_count={d}\n", .{result.dense_autodiff_reject_capture_or_global_dependency_count});
    try writer.print("dense_autodiff_reject_non_dense_operand_count={d}\n", .{result.dense_autodiff_reject_non_dense_operand_count});
    try writer.print("planner_numeric_dyad_host_count={d}\n", .{result.planner_numeric_dyad_host_count});
    try writer.print("planner_numeric_dyad_backend_count={d}\n", .{result.planner_numeric_dyad_backend_count});
    try writer.print("planner_compare_mask_host_count={d}\n", .{result.planner_compare_mask_host_count});
    try writer.print("planner_compare_mask_backend_count={d}\n", .{result.planner_compare_mask_backend_count});
    try writer.print("planner_reduce_host_count={d}\n", .{result.planner_reduce_host_count});
    try writer.print("planner_reduce_backend_count={d}\n", .{result.planner_reduce_backend_count});
    try writer.print("exec_numeric_dyad_host_count={d}\n", .{result.exec_numeric_dyad_host_count});
    try writer.print("exec_numeric_dyad_backend_count={d}\n", .{result.exec_numeric_dyad_backend_count});
    try writer.print("exec_compare_mask_host_count={d}\n", .{result.exec_compare_mask_host_count});
    try writer.print("exec_compare_mask_backend_count={d}\n", .{result.exec_compare_mask_backend_count});
    try writer.print("exec_reduce_host_count={d}\n", .{result.exec_reduce_host_count});
    try writer.print("exec_reduce_backend_count={d}\n", .{result.exec_reduce_backend_count});
    try writer.print("exec_scan_host_count={d}\n", .{result.exec_scan_host_count});
    try writer.print("exec_scan_backend_count={d}\n", .{result.exec_scan_backend_count});
    try writer.print("exec_matmul_host_count={d}\n", .{result.exec_matmul_host_count});
    try writer.print("exec_matmul_backend_count={d}\n", .{result.exec_matmul_backend_count});
    try writer.print("exec_dense_autodiff_host_count={d}\n", .{result.exec_dense_autodiff_host_count});
    try writer.print("exec_dense_autodiff_backend_count={d}\n", .{result.exec_dense_autodiff_backend_count});
    try writer.print("planner_scan_host_count={d}\n", .{result.planner_scan_host_count});
    try writer.print("planner_scan_backend_count={d}\n", .{result.planner_scan_backend_count});
    try writer.print("planner_matmul_host_count={d}\n", .{result.planner_matmul_host_count});
    try writer.print("planner_matmul_backend_count={d}\n", .{result.planner_matmul_backend_count});
    try writer.print("planner_dense_autodiff_host_count={d}\n", .{result.planner_dense_autodiff_host_count});
    try writer.print("planner_dense_autodiff_backend_count={d}\n", .{result.planner_dense_autodiff_backend_count});
    try writer.print("last_dense_plan_region={s}\n", .{result.last_dense_plan_region orelse "null"});
    try writer.print("last_dense_plan_backend={s}\n", .{result.last_dense_plan_backend orelse "null"});
    try writer.print("last_dense_exec_backend={s}\n", .{result.last_dense_exec_backend orelse "null"});
    try writer.print("last_dense_plan_reason={s}\n", .{result.last_dense_plan_reason orelse "null"});
    try writer.print("last_dense_plan_overridden={s}\n", .{if (result.last_dense_plan_overridden) "true" else "false"});
    try writer.print("last_dense_autodiff_exec_path={s}\n", .{result.last_dense_autodiff_exec_path orelse "null"});
}

pub fn allocJsonString(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try stringify.write(value);
    return out.toOwnedSlice();
}
