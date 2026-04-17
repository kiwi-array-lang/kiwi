const std = @import("std");
const runtime = @import("runtime.zig");

pub const ProbeCase = struct {
    name: []const u8,
    source: []const u8,
};

pub const ProbeResult = struct {
    name: []const u8,
    status: []const u8,
    err_name: ?[]const u8,
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
    host_matrix_row_copy_count: usize,
    host_matrix_index_copy_count: usize,
    host_matrix_mask_copy_count: usize,
    host_index_copy_count: usize,
    host_mask_copy_count: usize,
    projection_closure_alloc_count: usize,
    projection_closure_release_count: usize,
    apply_each_generic_count: usize,
    apply_fold_generic_count: usize,
    apply_scan_generic_count: usize,
    apply_each_right_generic_count: usize,
    apply_each_left_generic_count: usize,
    apply_each_right_fast_string_contains_count: usize,
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
    host_fold_fast_count: usize,
    host_scan_fast_count: usize,
    host_fold_scan_miss_unsupported_builtin_count: usize,
    host_fold_scan_miss_backend_override_count: usize,
    host_fold_scan_miss_non_numeric_or_shape_count: usize,
    host_fold_scan_miss_planner_non_host_count: usize,
    host_fold_scan_miss_preserve_generic_semantics_count: usize,
    host_fold_scan_miss_unsupported_input_count: usize,
    host_dense_dyad_host_count: usize,
    host_dense_dyad_miss_planner_backend_count: usize,
    host_dense_dyad_miss_mode_count: usize,
    host_dense_dyad_miss_view_count: usize,
    host_string_view_alloc_count: usize,
    host_string_view_release_count: usize,
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
    direct_closure1_hit_count: usize,
    direct_closure2_hit_count: usize,
    direct_closure3_hit_count: usize,
    direct_closure_miss_not_frozen_count: usize,
    direct_closure_miss_captures_count: usize,
    direct_closure_miss_unsupported_shape_count: usize,
    run_closure_mode_count: usize,
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

pub fn shouldRunCase(selected: []const []const u8, name: []const u8) bool {
    if (selected.len == 0) return true;
    for (selected) |wanted| {
        if (std.mem.eql(u8, wanted, name)) return true;
    }
    return false;
}

pub fn collectProbeResult(session: *runtime.Session, name: []const u8, err_name: ?[]const u8) ProbeResult {
    return .{
        .name = name,
        .status = if (err_name == null) "ok" else "error",
        .err_name = err_name,
        .host_realization_count = session.debugHostRealizationCount(),
        .structural_host_realization_count = session.debugStructuralHostRealizationCount(),
        .backend_realization_count = session.debugBackendRealizationCount(),
        .structural_backend_realization_count = session.debugStructuralBackendRealizationCount(),
        .host_realization_reuse_count = session.debugHostRealizationReuseCount(),
        .host_readback_count = session.debugHostReadbackCount(),
        .backend_realization_reuse_count = session.debugBackendRealizationReuseCount(),
        .backend_promotion_count = session.debugBackendPromotionCount(),
        .host_eviction_count = session.debugHostEvictionCount(),
        .backend_eviction_count = session.debugBackendEvictionCount(),
        .dual_resident_peak_count = session.debugDualResidentPeakCount(),
        .flat_concat_dense_view_count = session.debugFlatConcatDenseViewCount(),
        .first_axis_slice_dense_view_count = session.debugFirstAxisSliceDenseViewCount(),
        .first_axis_index_dense_view_count = session.debugFirstAxisIndexDenseViewCount(),
        .first_axis_concat_dense_view_count = session.debugFirstAxisConcatDenseViewCount(),
        .make_array_int_result_count = session.debugMakeArrayIntResultCount(),
        .make_array_float_result_count = session.debugMakeArrayFloatResultCount(),
        .make_array_boxed_fallback_count = session.debugMakeArrayBoxedFallbackCount(),
        .make_array_boxed_uniform_numeric_array_count = session.debugMakeArrayBoxedReasonCount(.uniform_numeric_array_unstacked),
        .make_array_boxed_irregular_numeric_array_count = session.debugMakeArrayBoxedReasonCount(.irregular_numeric_array),
        .make_array_boxed_non_numeric_item_count = session.debugMakeArrayBoxedReasonCount(.non_numeric_item),
        .host_matrix_row_copy_count = session.debugHostMatrixRowCopyCount(),
        .host_matrix_index_copy_count = session.debugHostMatrixIndexCopyCount(),
        .host_matrix_mask_copy_count = session.debugHostMatrixMaskCopyCount(),
        .host_index_copy_count = session.debugHostIndexCopyCount(),
        .host_mask_copy_count = session.debugHostMaskCopyCount(),
        .projection_closure_alloc_count = session.debugProjectionClosureAllocCount(),
        .projection_closure_release_count = session.debugProjectionClosureReleaseCount(),
        .apply_each_generic_count = session.debugApplyEachGenericCount(),
        .apply_fold_generic_count = session.debugApplyFoldGenericCount(),
        .apply_scan_generic_count = session.debugApplyScanGenericCount(),
        .apply_each_right_generic_count = session.debugApplyEachRightGenericCount(),
        .apply_each_left_generic_count = session.debugApplyEachLeftGenericCount(),
        .apply_each_right_fast_string_contains_count = session.debugApplyEachRightFastStringContainsCount(),
        .apply_each_fast_unary_lifted_count = session.debugApplyEachFastUnaryLiftedCount(),
        .apply_each_fast_dense_count = session.debugApplyEachFastDenseCount(),
        .apply_each_fast_dense_miss_unsupported_base_count = session.debugApplyEachFastDenseMissCount(.unsupported_base),
        .apply_each_fast_dense_miss_non_dense_args_or_shape_count = session.debugApplyEachFastDenseMissCount(.non_dense_args_or_shape),
        .apply_each_right_fast_dense_count = session.debugApplyEachRightFastDenseCount(),
        .apply_each_right_fast_dense_miss_unsupported_base_count = session.debugApplyEachRightFastDenseMissCount(.unsupported_base),
        .apply_each_right_fast_dense_miss_non_vector_right_count = session.debugApplyEachRightFastDenseMissCount(.non_vector_right),
        .each_right_fast_string_contains_miss_non_string_left_count = session.debugEachRightFastStringContainsMissNonStringLeftCount(),
        .each_right_fast_string_contains_miss_non_string_right_count = session.debugEachRightFastStringContainsMissNonStringRightCount(),
        .grade_structural_numeric_fast_count = session.debugGradeStructuralNumericFastCount(),
        .fast_dense_assign_attempt_count = session.debugFastDenseAssignAttemptCount(),
        .fast_dense_assign_hit_count = session.debugFastDenseAssignHitCount(),
        .fast_dense_assign_miss_count = session.debugFastDenseAssignMissCount(),
        .fast_dense_assign_reuse_count = session.debugFastDenseAssignReuseCount(),
        .fast_dense_assign_clone_count = session.debugFastDenseAssignCloneCount(),
        .fast_dense_assign_clone_non_unique_count = session.debugFastDenseAssignCloneReasonCount(.non_unique),
        .fast_dense_assign_clone_frozen_count = session.debugFastDenseAssignCloneReasonCount(.frozen),
        .fast_dense_assign_clone_other_count = session.debugFastDenseAssignCloneReasonCount(.other),
        .host_fold_fast_count = session.debugHostFoldFastCount(),
        .host_scan_fast_count = session.debugHostScanFastCount(),
        .host_fold_scan_miss_unsupported_builtin_count = session.debugHostFoldScanMissCount(.unsupported_builtin),
        .host_fold_scan_miss_backend_override_count = session.debugHostFoldScanMissCount(.backend_override),
        .host_fold_scan_miss_non_numeric_or_shape_count = session.debugHostFoldScanMissCount(.non_numeric_or_shape),
        .host_fold_scan_miss_planner_non_host_count = session.debugHostFoldScanMissCount(.planner_non_host),
        .host_fold_scan_miss_preserve_generic_semantics_count = session.debugHostFoldScanMissCount(.preserve_generic_semantics),
        .host_fold_scan_miss_unsupported_input_count = session.debugHostFoldScanMissCount(.unsupported_input),
        .host_dense_dyad_host_count = session.debugHostDenseDyadHostCount(),
        .host_dense_dyad_miss_planner_backend_count = session.debugHostDenseDyadMissCount(.planner_backend),
        .host_dense_dyad_miss_mode_count = session.debugHostDenseDyadMissCount(.mode),
        .host_dense_dyad_miss_view_count = session.debugHostDenseDyadMissCount(.view),
        .host_string_view_alloc_count = session.debugHostStringViewAllocCount(),
        .host_string_view_release_count = session.debugHostStringViewReleaseCount(),
        .flat_slice_alloc_count = session.debugNumericStructuralAllocCount(.flat_slice),
        .flat_slice_release_count = session.debugNumericStructuralReleaseCount(.flat_slice),
        .flat_concat_alloc_count = session.debugNumericStructuralAllocCount(.flat_concat),
        .flat_concat_release_count = session.debugNumericStructuralReleaseCount(.flat_concat),
        .flat_segments_alloc_count = session.debugNumericStructuralAllocCount(.flat_segments),
        .flat_segments_release_count = session.debugNumericStructuralReleaseCount(.flat_segments),
        .first_axis_slice_alloc_count = session.debugNumericStructuralAllocCount(.first_axis_slice),
        .first_axis_slice_release_count = session.debugNumericStructuralReleaseCount(.first_axis_slice),
        .first_axis_index_alloc_count = session.debugNumericStructuralAllocCount(.first_axis_index),
        .first_axis_index_release_count = session.debugNumericStructuralReleaseCount(.first_axis_index),
        .first_axis_concat_alloc_count = session.debugNumericStructuralAllocCount(.first_axis_concat),
        .first_axis_concat_release_count = session.debugNumericStructuralReleaseCount(.first_axis_concat),
        .reshape_view_alloc_count = session.debugNumericStructuralAllocCount(.reshape_view),
        .reshape_view_release_count = session.debugNumericStructuralReleaseCount(.reshape_view),
        .transpose_view_alloc_count = session.debugNumericStructuralAllocCount(.transpose_view),
        .transpose_view_release_count = session.debugNumericStructuralReleaseCount(.transpose_view),
        .direct_closure1_hit_count = session.debugDirectClosure1HitCount(),
        .direct_closure2_hit_count = session.debugDirectClosure2HitCount(),
        .direct_closure3_hit_count = session.debugDirectClosure3HitCount(),
        .direct_closure_miss_not_frozen_count = session.debugDirectClosureMissNotFrozenCount(),
        .direct_closure_miss_captures_count = session.debugDirectClosureMissCapturesCount(),
        .direct_closure_miss_unsupported_shape_count = session.debugDirectClosureMissUnsupportedShapeCount(),
        .run_closure_mode_count = session.debugRunClosureModeCount(),
        .apply_derived_closure_count = session.debugApplyDerivedClosureCount(),
        .apply_projection_count = session.debugApplyProjectionCount(),
        .autograd_builtin_grad_count = session.debugAutogradBuiltinGradCount(),
        .autograd_builtin_valuegrad_count = session.debugAutogradBuiltinValuegradCount(),
        .autograd_slow_finite_difference_count = session.debugAutogradSlowFiniteDifferenceCount(),
        .dense_autodiff_cache_hit_count = session.debugDenseAutodiffCacheHitCount(),
        .dense_autodiff_cache_miss_count = session.debugDenseAutodiffCacheMissCount(),
        .dense_autodiff_lower_success_count = session.debugDenseAutodiffLowerSuccessCount(),
        .dense_autodiff_reject_wrong_arity_count = session.debugDenseAutodiffRejectCount(.wrong_arity),
        .dense_autodiff_reject_non_vector_target_count = session.debugDenseAutodiffRejectCount(.non_vector_target),
        .dense_autodiff_reject_non_scalar_result_count = session.debugDenseAutodiffRejectCount(.non_scalar_result),
        .dense_autodiff_reject_unsupported_opcode_count = session.debugDenseAutodiffRejectCount(.unsupported_opcode),
        .dense_autodiff_reject_unsupported_shape_flow_count = session.debugDenseAutodiffRejectCount(.unsupported_shape_flow),
        .dense_autodiff_reject_unsupported_builtin_count = session.debugDenseAutodiffRejectCount(.unsupported_builtin),
        .dense_autodiff_reject_capture_or_global_dependency_count = session.debugDenseAutodiffRejectCount(.capture_or_global_dependency),
        .dense_autodiff_reject_non_dense_operand_count = session.debugDenseAutodiffRejectCount(.non_dense_operand),
        .planner_numeric_dyad_host_count = session.debugDensePlanCount(.numeric_dyad, .host),
        .planner_numeric_dyad_backend_count = session.debugDensePlanCount(.numeric_dyad, .mlx),
        .planner_compare_mask_host_count = session.debugDensePlanCount(.compare_mask, .host),
        .planner_compare_mask_backend_count = session.debugDensePlanCount(.compare_mask, .mlx),
        .planner_reduce_host_count = session.debugDensePlanCount(.reduce, .host),
        .planner_reduce_backend_count = session.debugDensePlanCount(.reduce, .mlx),
        .exec_numeric_dyad_host_count = session.debugDenseExecCount(.numeric_dyad, .host),
        .exec_numeric_dyad_backend_count = session.debugDenseExecCount(.numeric_dyad, .mlx),
        .exec_compare_mask_host_count = session.debugDenseExecCount(.compare_mask, .host),
        .exec_compare_mask_backend_count = session.debugDenseExecCount(.compare_mask, .mlx),
        .exec_reduce_host_count = session.debugDenseExecCount(.reduce, .host),
        .exec_reduce_backend_count = session.debugDenseExecCount(.reduce, .mlx),
        .exec_scan_host_count = session.debugDenseExecCount(.scan, .host),
        .exec_scan_backend_count = session.debugDenseExecCount(.scan, .mlx),
        .exec_matmul_host_count = session.debugDenseExecCount(.matmul, .host),
        .exec_matmul_backend_count = session.debugDenseExecCount(.matmul, .mlx),
        .exec_dense_autodiff_host_count = session.debugDenseExecCount(.dense_autodiff, .host),
        .exec_dense_autodiff_backend_count = session.debugDenseExecCount(.dense_autodiff, .mlx),
        .planner_scan_host_count = session.debugDensePlanCount(.scan, .host),
        .planner_scan_backend_count = session.debugDensePlanCount(.scan, .mlx),
        .planner_matmul_host_count = session.debugDensePlanCount(.matmul, .host),
        .planner_matmul_backend_count = session.debugDensePlanCount(.matmul, .mlx),
        .planner_dense_autodiff_host_count = session.debugDensePlanCount(.dense_autodiff, .host),
        .planner_dense_autodiff_backend_count = session.debugDensePlanCount(.dense_autodiff, .mlx),
        .last_dense_plan_region = session.lastDensePlanRegion(),
        .last_dense_plan_backend = session.lastDensePlanBackend(),
        .last_dense_exec_backend = session.lastDenseExecBackend(),
        .last_dense_plan_reason = session.lastDensePlanReason(),
        .last_dense_plan_overridden = session.lastDensePlanOverridden(),
        .last_dense_autodiff_exec_path = session.lastDenseAutodiffExecPath(),
    };
}

pub fn writeProbeResultText(writer: anytype, result: ProbeResult) !void {
    try writer.print("probe {s} status={s}", .{ result.name, result.status });
    if (result.err_name) |err_name| try writer.print(" err={s}", .{err_name});
    try writer.writeByte('\n');

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
    try writer.print("host_matrix_row_copy_count={d}\n", .{result.host_matrix_row_copy_count});
    try writer.print("host_matrix_index_copy_count={d}\n", .{result.host_matrix_index_copy_count});
    try writer.print("host_matrix_mask_copy_count={d}\n", .{result.host_matrix_mask_copy_count});
    try writer.print("host_index_copy_count={d}\n", .{result.host_index_copy_count});
    try writer.print("host_mask_copy_count={d}\n", .{result.host_mask_copy_count});
    try writer.print("projection_closure_alloc_count={d}\n", .{result.projection_closure_alloc_count});
    try writer.print("projection_closure_release_count={d}\n", .{result.projection_closure_release_count});
    try writer.print("apply_each_generic_count={d}\n", .{result.apply_each_generic_count});
    try writer.print("apply_fold_generic_count={d}\n", .{result.apply_fold_generic_count});
    try writer.print("apply_scan_generic_count={d}\n", .{result.apply_scan_generic_count});
    try writer.print("apply_each_right_generic_count={d}\n", .{result.apply_each_right_generic_count});
    try writer.print("apply_each_left_generic_count={d}\n", .{result.apply_each_left_generic_count});
    try writer.print("apply_each_right_fast_string_contains_count={d}\n", .{result.apply_each_right_fast_string_contains_count});
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
    try writer.print("host_fold_fast_count={d}\n", .{result.host_fold_fast_count});
    try writer.print("host_scan_fast_count={d}\n", .{result.host_scan_fast_count});
    try writer.print("host_fold_scan_miss_unsupported_builtin_count={d}\n", .{result.host_fold_scan_miss_unsupported_builtin_count});
    try writer.print("host_fold_scan_miss_backend_override_count={d}\n", .{result.host_fold_scan_miss_backend_override_count});
    try writer.print("host_fold_scan_miss_non_numeric_or_shape_count={d}\n", .{result.host_fold_scan_miss_non_numeric_or_shape_count});
    try writer.print("host_fold_scan_miss_planner_non_host_count={d}\n", .{result.host_fold_scan_miss_planner_non_host_count});
    try writer.print("host_fold_scan_miss_preserve_generic_semantics_count={d}\n", .{result.host_fold_scan_miss_preserve_generic_semantics_count});
    try writer.print("host_fold_scan_miss_unsupported_input_count={d}\n", .{result.host_fold_scan_miss_unsupported_input_count});
    try writer.print("host_dense_dyad_host_count={d}\n", .{result.host_dense_dyad_host_count});
    try writer.print("host_dense_dyad_miss_planner_backend_count={d}\n", .{result.host_dense_dyad_miss_planner_backend_count});
    try writer.print("host_dense_dyad_miss_mode_count={d}\n", .{result.host_dense_dyad_miss_mode_count});
    try writer.print("host_dense_dyad_miss_view_count={d}\n", .{result.host_dense_dyad_miss_view_count});
    try writer.print("host_string_view_alloc_count={d}\n", .{result.host_string_view_alloc_count});
    try writer.print("host_string_view_release_count={d}\n", .{result.host_string_view_release_count});
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
    try writer.print("direct_closure1_hit_count={d}\n", .{result.direct_closure1_hit_count});
    try writer.print("direct_closure2_hit_count={d}\n", .{result.direct_closure2_hit_count});
    try writer.print("direct_closure3_hit_count={d}\n", .{result.direct_closure3_hit_count});
    try writer.print("direct_closure_miss_not_frozen_count={d}\n", .{result.direct_closure_miss_not_frozen_count});
    try writer.print("direct_closure_miss_captures_count={d}\n", .{result.direct_closure_miss_captures_count});
    try writer.print("direct_closure_miss_unsupported_shape_count={d}\n", .{result.direct_closure_miss_unsupported_shape_count});
    try writer.print("run_closure_mode_count={d}\n", .{result.run_closure_mode_count});
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
    var out: std.io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try stringify.write(value);
    return out.toOwnedSlice();
}
