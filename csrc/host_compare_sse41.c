#include "host_compare.h"

#include <smmintrin.h>

#if defined(__clang__) && (defined(__x86_64__) || defined(_M_X64))
#pragma clang attribute push(__attribute__((target("sse4.1"))), apply_to=function)
#endif

static inline int kiwi_host_compare_f64_tail(double left, double right, int op) {
  return op == KIWI_HOST_COMPARE_EQ ? left == right
      : op == KIWI_HOST_COMPARE_LT ? left < right
                                    : left > right;
}

static inline int64_t kiwi_host_compare_load_int_tail(const void* items, int width, size_t idx) {
  switch (width) {
    case 1:
      return (int64_t)((const int8_t*)items)[idx];
    case 2:
      return (int64_t)((const int16_t*)items)[idx];
    case 4:
      return (int64_t)((const int32_t*)items)[idx];
    case 8:
      return ((const int64_t*)items)[idx];
    default:
      return 0;
  }
}

static inline int kiwi_host_compare_int_f64_tail(
    const void* int_items,
    int int_width,
    const double* float_items,
    size_t idx,
    int int_left,
    int op) {
  const double int_value = (double)kiwi_host_compare_load_int_tail(int_items, int_width, idx);
  const double float_value = float_items[idx];
  return kiwi_host_compare_f64_tail(
      int_left ? int_value : float_value,
      int_left ? float_value : int_value,
      op);
}

static inline uint8_t kiwi_host_compare_sse41_mask_f64(__m128d cmp) {
  return (uint8_t)(unsigned int)_mm_movemask_pd(cmp);
}

static inline __m128d kiwi_host_compare_sse41_i8_to_f64(const int8_t* items) {
  int raw = 0;
  __builtin_memcpy(&raw, items, sizeof(uint16_t));
  return _mm_cvtepi32_pd(_mm_cvtepi8_epi32(_mm_cvtsi32_si128(raw)));
}

static inline __m128d kiwi_host_compare_sse41_i16_to_f64(const int16_t* items) {
  int raw = 0;
  __builtin_memcpy(&raw, items, sizeof(raw));
  return _mm_cvtepi32_pd(_mm_cvtepi16_epi32(_mm_cvtsi32_si128(raw)));
}

static inline __m128d kiwi_host_compare_sse41_i32_to_f64(const int32_t* items) {
  long long raw = 0;
  __builtin_memcpy(&raw, items, sizeof(raw));
  return _mm_cvtepi32_pd(_mm_cvtsi64_si128(raw));
}

static inline __m128d kiwi_host_compare_sse41_i64_to_f64(const int64_t* items) {
  return _mm_set_pd((double)items[1], (double)items[0]);
}

#define KIWI_SSE41_INT_F64_CMP_EQ(INT_VALUES, FLOAT_VALUES) _mm_cmpeq_pd((INT_VALUES), (FLOAT_VALUES))
#define KIWI_SSE41_INT_F64_CMP_INT_LT_FLOAT(INT_VALUES, FLOAT_VALUES) _mm_cmplt_pd((INT_VALUES), (FLOAT_VALUES))
#define KIWI_SSE41_INT_F64_CMP_INT_GT_FLOAT(INT_VALUES, FLOAT_VALUES) _mm_cmpgt_pd((INT_VALUES), (FLOAT_VALUES))
#define KIWI_SSE41_INT_F64_CMP_FLOAT_LT_INT(INT_VALUES, FLOAT_VALUES) _mm_cmplt_pd((FLOAT_VALUES), (INT_VALUES))
#define KIWI_SSE41_INT_F64_CMP_FLOAT_GT_INT(INT_VALUES, FLOAT_VALUES) _mm_cmpgt_pd((FLOAT_VALUES), (INT_VALUES))

#define KIWI_DEFINE_SSE41_INT_F64_PACK2(NAME, TYPE, LOAD_INT, CMP) \
static inline uint8_t kiwi_host_compare_sse41_##NAME##_pack2( \
    const TYPE* int_items, \
    const double* float_items, \
    size_t idx) { \
  return kiwi_host_compare_sse41_mask_f64(CMP((LOAD_INT)(int_items + idx), _mm_loadu_pd(float_items + idx))); \
}

#define KIWI_DEFINE_SSE41_INT_F64_PACK8(NAME) \
static inline uint8_t kiwi_host_compare_sse41_##NAME##_pack8( \
    const void* int_items, \
    const double* float_items, \
    size_t idx) { \
  return (uint8_t)( \
      kiwi_host_compare_sse41_##NAME##_pack2(int_items, float_items, idx) | \
      (kiwi_host_compare_sse41_##NAME##_pack2(int_items, float_items, idx + 2) << 2) | \
      (kiwi_host_compare_sse41_##NAME##_pack2(int_items, float_items, idx + 4) << 4) | \
      (kiwi_host_compare_sse41_##NAME##_pack2(int_items, float_items, idx + 6) << 6)); \
}

#define KIWI_DEFINE_SSE41_INT_F64_PACKER_SET(PREFIX, TYPE, LOAD_INT) \
  KIWI_DEFINE_SSE41_INT_F64_PACK2(PREFIX##_eq, TYPE, LOAD_INT, KIWI_SSE41_INT_F64_CMP_EQ) \
  KIWI_DEFINE_SSE41_INT_F64_PACK2(PREFIX##_int_lt_float, TYPE, LOAD_INT, KIWI_SSE41_INT_F64_CMP_INT_LT_FLOAT) \
  KIWI_DEFINE_SSE41_INT_F64_PACK2(PREFIX##_int_gt_float, TYPE, LOAD_INT, KIWI_SSE41_INT_F64_CMP_INT_GT_FLOAT) \
  KIWI_DEFINE_SSE41_INT_F64_PACK2(PREFIX##_float_lt_int, TYPE, LOAD_INT, KIWI_SSE41_INT_F64_CMP_FLOAT_LT_INT) \
  KIWI_DEFINE_SSE41_INT_F64_PACK2(PREFIX##_float_gt_int, TYPE, LOAD_INT, KIWI_SSE41_INT_F64_CMP_FLOAT_GT_INT) \
  KIWI_DEFINE_SSE41_INT_F64_PACK8(PREFIX##_eq) \
  KIWI_DEFINE_SSE41_INT_F64_PACK8(PREFIX##_int_lt_float) \
  KIWI_DEFINE_SSE41_INT_F64_PACK8(PREFIX##_int_gt_float) \
  KIWI_DEFINE_SSE41_INT_F64_PACK8(PREFIX##_float_lt_int) \
  KIWI_DEFINE_SSE41_INT_F64_PACK8(PREFIX##_float_gt_int)

KIWI_DEFINE_SSE41_INT_F64_PACKER_SET(i8_f64, int8_t, kiwi_host_compare_sse41_i8_to_f64)
KIWI_DEFINE_SSE41_INT_F64_PACKER_SET(i16_f64, int16_t, kiwi_host_compare_sse41_i16_to_f64)
KIWI_DEFINE_SSE41_INT_F64_PACKER_SET(i32_f64, int32_t, kiwi_host_compare_sse41_i32_to_f64)
KIWI_DEFINE_SSE41_INT_F64_PACKER_SET(i64_f64, int64_t, kiwi_host_compare_sse41_i64_to_f64)

#undef KIWI_DEFINE_SSE41_INT_F64_PACKER_SET
#undef KIWI_DEFINE_SSE41_INT_F64_PACK8
#undef KIWI_DEFINE_SSE41_INT_F64_PACK2
#undef KIWI_SSE41_INT_F64_CMP_FLOAT_GT_INT
#undef KIWI_SSE41_INT_F64_CMP_FLOAT_LT_INT
#undef KIWI_SSE41_INT_F64_CMP_INT_GT_FLOAT
#undef KIWI_SSE41_INT_F64_CMP_INT_LT_FLOAT
#undef KIWI_SSE41_INT_F64_CMP_EQ

#define KIWI_SSE41_INT_F64_PACK8_LOOP(INT_PTR, PACK8_FN, PACK2_FN, TAIL_COMPARE) \
  KiwiHostCompareSummaryAccum summary = kiwi_host_compare_summary_accum_empty(); \
  size_t base = 0; \
  for (; base + 64 <= len; base += 64) { \
    const uint64_t word = \
        ((uint64_t)PACK8_FN((INT_PTR), float_items, base)) | \
        ((uint64_t)PACK8_FN((INT_PTR), float_items, base + 8) << 8) | \
        ((uint64_t)PACK8_FN((INT_PTR), float_items, base + 16) << 16) | \
        ((uint64_t)PACK8_FN((INT_PTR), float_items, base + 24) << 24) | \
        ((uint64_t)PACK8_FN((INT_PTR), float_items, base + 32) << 32) | \
        ((uint64_t)PACK8_FN((INT_PTR), float_items, base + 40) << 40) | \
        ((uint64_t)PACK8_FN((INT_PTR), float_items, base + 48) << 48) | \
        ((uint64_t)PACK8_FN((INT_PTR), float_items, base + 56) << 56); \
    out[base / 64] = word; \
    kiwi_host_compare_summary_accum_word(&summary, word, 64); \
  } \
  if (base < len) { \
    const size_t active = len - base; \
    uint64_t word = 0; \
    size_t bit = 0; \
    while (bit + 8 <= active) { \
      word |= (uint64_t)PACK8_FN((INT_PTR), float_items, base + bit) << bit; \
      bit += 8; \
    } \
    while (bit + 2 <= active) { \
      word |= (uint64_t)PACK2_FN((INT_PTR), float_items, base + bit) << bit; \
      bit += 2; \
    } \
    while (bit < active) { \
      if (TAIL_COMPARE(base + bit)) word |= UINT64_C(1) << bit; \
      ++bit; \
    } \
    out[base / 64] = word; \
    kiwi_host_compare_summary_accum_word(&summary, word, active); \
  } \
  kiwi_host_compare_summary_publish(kiwi_host_compare_summary_accum_finish(summary));

#define KIWI_SSE41_RUN_INT_F64_PACK8(INT_PTR, PREFIX) \
  do { \
    if (op == KIWI_HOST_COMPARE_EQ) { \
      KIWI_SSE41_INT_F64_PACK8_LOOP((INT_PTR), kiwi_host_compare_sse41_##PREFIX##_eq_pack8, kiwi_host_compare_sse41_##PREFIX##_eq_pack2, TAIL_COMPARE) \
    } else if (int_left) { \
      if (op == KIWI_HOST_COMPARE_LT) { \
        KIWI_SSE41_INT_F64_PACK8_LOOP((INT_PTR), kiwi_host_compare_sse41_##PREFIX##_int_lt_float_pack8, kiwi_host_compare_sse41_##PREFIX##_int_lt_float_pack2, TAIL_COMPARE) \
      } else { \
        KIWI_SSE41_INT_F64_PACK8_LOOP((INT_PTR), kiwi_host_compare_sse41_##PREFIX##_int_gt_float_pack8, kiwi_host_compare_sse41_##PREFIX##_int_gt_float_pack2, TAIL_COMPARE) \
      } \
    } else { \
      if (op == KIWI_HOST_COMPARE_LT) { \
        KIWI_SSE41_INT_F64_PACK8_LOOP((INT_PTR), kiwi_host_compare_sse41_##PREFIX##_float_lt_int_pack8, kiwi_host_compare_sse41_##PREFIX##_float_lt_int_pack2, TAIL_COMPARE) \
      } else { \
        KIWI_SSE41_INT_F64_PACK8_LOOP((INT_PTR), kiwi_host_compare_sse41_##PREFIX##_float_gt_int_pack8, kiwi_host_compare_sse41_##PREFIX##_float_gt_int_pack2, TAIL_COMPARE) \
      } \
    } \
  } while (0)

void kiwi_host_compare_int_f64_array_sse41(
    uint64_t* out,
    const void* int_items,
    int int_width,
    const double* float_items,
    size_t len,
    int int_left,
    int op) {
#define TAIL_COMPARE(IDX) kiwi_host_compare_int_f64_tail(int_items, int_width, float_items, (IDX), int_left, op)
  switch (int_width) {
    case 1:
      KIWI_SSE41_RUN_INT_F64_PACK8((const int8_t*)int_items, i8_f64);
      break;
    case 2:
      KIWI_SSE41_RUN_INT_F64_PACK8((const int16_t*)int_items, i16_f64);
      break;
    case 4:
      KIWI_SSE41_RUN_INT_F64_PACK8((const int32_t*)int_items, i32_f64);
      break;
    case 8:
      KIWI_SSE41_RUN_INT_F64_PACK8((const int64_t*)int_items, i64_f64);
      break;
    default:
      kiwi_host_compare_int_f64_array_scalar(out, int_items, int_width, float_items, len, int_left, op);
      break;
  }
#undef TAIL_COMPARE
}

#undef KIWI_SSE41_RUN_INT_F64_PACK8
#undef KIWI_SSE41_INT_F64_PACK8_LOOP

#if defined(__clang__) && (defined(__x86_64__) || defined(_M_X64))
#pragma clang attribute pop
#endif
