#include "host_compare.h"

#include <immintrin.h>

#if defined(__clang__) && (defined(__x86_64__) || defined(_M_X64))
#pragma clang attribute push(__attribute__((target("avx512f,avx512bw,evex512"))), apply_to=function)
#endif

static inline int kiwi_host_compare_i64_tail(int64_t left, int64_t right, int op) {
  return op == KIWI_HOST_COMPARE_EQ ? left == right
      : op == KIWI_HOST_COMPARE_LT ? left < right
                                    : left > right;
}

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

static inline __mmask8 kiwi_host_compare_avx512_cmp_f64(__m512d left, __m512d right, int op) {
  switch (op) {
    case KIWI_HOST_COMPARE_EQ:
      return _mm512_cmp_pd_mask(left, right, _CMP_EQ_OQ);
    case KIWI_HOST_COMPARE_LT:
      return _mm512_cmp_pd_mask(left, right, _CMP_LT_OQ);
    default:
      return _mm512_cmp_pd_mask(left, right, _CMP_GT_OQ);
  }
}

#define KIWI_AVX512_WORD_LOOP(LANES, LOAD_COMPARE, TAIL_COMPARE) \
  KiwiHostCompareSummary summary = kiwi_host_compare_summary_empty(); \
  size_t out_idx = 0; \
  for (size_t base = 0; base < len; base += 64) { \
    const size_t active = len - base < 64 ? len - base : 64; \
    uint64_t word = 0; \
    size_t bit = 0; \
    while (bit + (LANES) <= active) { \
      word |= (uint64_t)(LOAD_COMPARE(base + bit)) << bit; \
      bit += (LANES); \
    } \
    while (bit < active) { \
      if (TAIL_COMPARE(base + bit)) word |= UINT64_C(1) << bit; \
      ++bit; \
    } \
    kiwi_host_compare_summary_note_word(&summary, word, active); \
    out[out_idx++] = word; \
  } \
  kiwi_host_compare_summary_publish(summary);

static inline __m512d kiwi_host_compare_avx512_i8_to_f64(const int8_t* items) {
  int64_t raw = 0;
  __builtin_memcpy(&raw, items, sizeof(raw));
  const __m512i widened = _mm512_cvtepi8_epi32(_mm_cvtsi64_si128((long long)raw));
  return _mm512_cvtepi32_pd(_mm512_castsi512_si256(widened));
}

static inline __m512d kiwi_host_compare_avx512_i16_to_f64(const int16_t* items) {
  const __m256i packed = _mm256_zextsi128_si256(_mm_loadu_si128((const __m128i*)(const void*)items));
  const __m512i widened = _mm512_cvtepi16_epi32(packed);
  return _mm512_cvtepi32_pd(_mm512_castsi512_si256(widened));
}

static inline __m512d kiwi_host_compare_avx512_i32_to_f64(const int32_t* items) {
  return _mm512_cvtepi32_pd(_mm256_loadu_si256((const __m256i*)(const void*)items));
}

static inline __m512d kiwi_host_compare_avx512_i64_to_f64(const int64_t* items) {
  return _mm512_set_pd(
      (double)items[7],
      (double)items[6],
      (double)items[5],
      (double)items[4],
      (double)items[3],
      (double)items[2],
      (double)items[1],
      (double)items[0]);
}

#define KIWI_AVX512_INT_F64_CMP_EQ(INT_VALUES, FLOAT_VALUES) _mm512_cmp_pd_mask((INT_VALUES), (FLOAT_VALUES), _CMP_EQ_OQ)
#define KIWI_AVX512_INT_F64_CMP_INT_LT_FLOAT(INT_VALUES, FLOAT_VALUES) _mm512_cmp_pd_mask((INT_VALUES), (FLOAT_VALUES), _CMP_LT_OQ)
#define KIWI_AVX512_INT_F64_CMP_INT_GT_FLOAT(INT_VALUES, FLOAT_VALUES) _mm512_cmp_pd_mask((INT_VALUES), (FLOAT_VALUES), _CMP_GT_OQ)
#define KIWI_AVX512_INT_F64_CMP_FLOAT_LT_INT(INT_VALUES, FLOAT_VALUES) _mm512_cmp_pd_mask((FLOAT_VALUES), (INT_VALUES), _CMP_LT_OQ)
#define KIWI_AVX512_INT_F64_CMP_FLOAT_GT_INT(INT_VALUES, FLOAT_VALUES) _mm512_cmp_pd_mask((FLOAT_VALUES), (INT_VALUES), _CMP_GT_OQ)

#define KIWI_DEFINE_AVX512_INT_F64_PACK8(NAME, TYPE, LOAD_INT, CMP) \
static inline uint8_t kiwi_host_compare_avx512_##NAME##_pack8( \
    const TYPE* int_items, \
    const double* float_items, \
    size_t idx) { \
  return (uint8_t)CMP((LOAD_INT)(int_items + idx), _mm512_loadu_pd(float_items + idx)); \
}

#define KIWI_DEFINE_AVX512_INT_F64_PACK8_SET(NAME, TYPE, LOAD_INT) \
  KIWI_DEFINE_AVX512_INT_F64_PACK8(NAME##_eq, TYPE, LOAD_INT, KIWI_AVX512_INT_F64_CMP_EQ) \
  KIWI_DEFINE_AVX512_INT_F64_PACK8(NAME##_int_lt_float, TYPE, LOAD_INT, KIWI_AVX512_INT_F64_CMP_INT_LT_FLOAT) \
  KIWI_DEFINE_AVX512_INT_F64_PACK8(NAME##_int_gt_float, TYPE, LOAD_INT, KIWI_AVX512_INT_F64_CMP_INT_GT_FLOAT) \
  KIWI_DEFINE_AVX512_INT_F64_PACK8(NAME##_float_lt_int, TYPE, LOAD_INT, KIWI_AVX512_INT_F64_CMP_FLOAT_LT_INT) \
  KIWI_DEFINE_AVX512_INT_F64_PACK8(NAME##_float_gt_int, TYPE, LOAD_INT, KIWI_AVX512_INT_F64_CMP_FLOAT_GT_INT)

KIWI_DEFINE_AVX512_INT_F64_PACK8_SET(i8_f64, int8_t, kiwi_host_compare_avx512_i8_to_f64)
KIWI_DEFINE_AVX512_INT_F64_PACK8_SET(i16_f64, int16_t, kiwi_host_compare_avx512_i16_to_f64)
KIWI_DEFINE_AVX512_INT_F64_PACK8_SET(i32_f64, int32_t, kiwi_host_compare_avx512_i32_to_f64)
KIWI_DEFINE_AVX512_INT_F64_PACK8_SET(i64_f64, int64_t, kiwi_host_compare_avx512_i64_to_f64)

#undef KIWI_DEFINE_AVX512_INT_F64_PACK8_SET
#undef KIWI_DEFINE_AVX512_INT_F64_PACK8
#undef KIWI_AVX512_INT_F64_CMP_FLOAT_GT_INT
#undef KIWI_AVX512_INT_F64_CMP_FLOAT_LT_INT
#undef KIWI_AVX512_INT_F64_CMP_INT_GT_FLOAT
#undef KIWI_AVX512_INT_F64_CMP_INT_LT_FLOAT
#undef KIWI_AVX512_INT_F64_CMP_EQ

#define KIWI_AVX512_INT_F64_PACK8_LOOP(INT_PTR, PACK_FN, TAIL_COMPARE) \
  KiwiHostCompareSummaryAccum summary = kiwi_host_compare_summary_accum_empty(); \
  size_t base = 0; \
  for (; base + 64 <= len; base += 64) { \
    const uint64_t word = \
        ((uint64_t)PACK_FN((INT_PTR), float_items, base)) | \
        ((uint64_t)PACK_FN((INT_PTR), float_items, base + 8) << 8) | \
        ((uint64_t)PACK_FN((INT_PTR), float_items, base + 16) << 16) | \
        ((uint64_t)PACK_FN((INT_PTR), float_items, base + 24) << 24) | \
        ((uint64_t)PACK_FN((INT_PTR), float_items, base + 32) << 32) | \
        ((uint64_t)PACK_FN((INT_PTR), float_items, base + 40) << 40) | \
        ((uint64_t)PACK_FN((INT_PTR), float_items, base + 48) << 48) | \
        ((uint64_t)PACK_FN((INT_PTR), float_items, base + 56) << 56); \
    out[base / 64] = word; \
    kiwi_host_compare_summary_accum_word(&summary, word, 64); \
  } \
  if (base < len) { \
    const size_t active = len - base; \
    uint64_t word = 0; \
    size_t bit = 0; \
    while (bit + 8 <= active) { \
      word |= (uint64_t)PACK_FN((INT_PTR), float_items, base + bit) << bit; \
      bit += 8; \
    } \
    while (bit < active) { \
      if (TAIL_COMPARE(base + bit)) word |= UINT64_C(1) << bit; \
      ++bit; \
    } \
    out[base / 64] = word; \
    kiwi_host_compare_summary_accum_word(&summary, word, active); \
  } \
  kiwi_host_compare_summary_publish(kiwi_host_compare_summary_accum_finish(summary));

#define KIWI_AVX512_RUN_INT_F64_PACK8(INT_PTR, PREFIX) \
  do { \
    if (op == KIWI_HOST_COMPARE_EQ) { \
      KIWI_AVX512_INT_F64_PACK8_LOOP((INT_PTR), kiwi_host_compare_avx512_##PREFIX##_eq_pack8, TAIL_COMPARE) \
    } else if (int_left) { \
      if (op == KIWI_HOST_COMPARE_LT) { \
        KIWI_AVX512_INT_F64_PACK8_LOOP((INT_PTR), kiwi_host_compare_avx512_##PREFIX##_int_lt_float_pack8, TAIL_COMPARE) \
      } else { \
        KIWI_AVX512_INT_F64_PACK8_LOOP((INT_PTR), kiwi_host_compare_avx512_##PREFIX##_int_gt_float_pack8, TAIL_COMPARE) \
      } \
    } else { \
      if (op == KIWI_HOST_COMPARE_LT) { \
        KIWI_AVX512_INT_F64_PACK8_LOOP((INT_PTR), kiwi_host_compare_avx512_##PREFIX##_float_lt_int_pack8, TAIL_COMPARE) \
      } else { \
        KIWI_AVX512_INT_F64_PACK8_LOOP((INT_PTR), kiwi_host_compare_avx512_##PREFIX##_float_gt_int_pack8, TAIL_COMPARE) \
      } \
    } \
  } while (0)

void kiwi_host_compare_i8_array_avx512(uint64_t* out, const int8_t* left, const int8_t* right, size_t len, int op) {
#define LOAD_COMPARE(IDX) (op == KIWI_HOST_COMPARE_EQ ? _mm512_cmpeq_epi8_mask(_mm512_loadu_si512((const void*)(left + (IDX))), _mm512_loadu_si512((const void*)(right + (IDX)))) : op == KIWI_HOST_COMPARE_LT ? _mm512_cmpgt_epi8_mask(_mm512_loadu_si512((const void*)(right + (IDX))), _mm512_loadu_si512((const void*)(left + (IDX)))) : _mm512_cmpgt_epi8_mask(_mm512_loadu_si512((const void*)(left + (IDX))), _mm512_loadu_si512((const void*)(right + (IDX)))))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_AVX512_WORD_LOOP(64, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i16_array_avx512(uint64_t* out, const int16_t* left, const int16_t* right, size_t len, int op) {
#define LOAD_COMPARE(IDX) (op == KIWI_HOST_COMPARE_EQ ? _mm512_cmpeq_epi16_mask(_mm512_loadu_si512((const void*)(left + (IDX))), _mm512_loadu_si512((const void*)(right + (IDX)))) : op == KIWI_HOST_COMPARE_LT ? _mm512_cmpgt_epi16_mask(_mm512_loadu_si512((const void*)(right + (IDX))), _mm512_loadu_si512((const void*)(left + (IDX)))) : _mm512_cmpgt_epi16_mask(_mm512_loadu_si512((const void*)(left + (IDX))), _mm512_loadu_si512((const void*)(right + (IDX)))))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_AVX512_WORD_LOOP(32, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i32_array_avx512(uint64_t* out, const int32_t* left, const int32_t* right, size_t len, int op) {
#define LOAD_COMPARE(IDX) (op == KIWI_HOST_COMPARE_EQ ? _mm512_cmpeq_epi32_mask(_mm512_loadu_si512((const void*)(left + (IDX))), _mm512_loadu_si512((const void*)(right + (IDX)))) : op == KIWI_HOST_COMPARE_LT ? _mm512_cmpgt_epi32_mask(_mm512_loadu_si512((const void*)(right + (IDX))), _mm512_loadu_si512((const void*)(left + (IDX)))) : _mm512_cmpgt_epi32_mask(_mm512_loadu_si512((const void*)(left + (IDX))), _mm512_loadu_si512((const void*)(right + (IDX)))))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_AVX512_WORD_LOOP(16, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i64_array_avx512(uint64_t* out, const int64_t* left, const int64_t* right, size_t len, int op) {
#define LOAD_COMPARE(IDX) (op == KIWI_HOST_COMPARE_EQ ? _mm512_cmpeq_epi64_mask(_mm512_loadu_si512((const void*)(left + (IDX))), _mm512_loadu_si512((const void*)(right + (IDX)))) : op == KIWI_HOST_COMPARE_LT ? _mm512_cmpgt_epi64_mask(_mm512_loadu_si512((const void*)(right + (IDX))), _mm512_loadu_si512((const void*)(left + (IDX)))) : _mm512_cmpgt_epi64_mask(_mm512_loadu_si512((const void*)(left + (IDX))), _mm512_loadu_si512((const void*)(right + (IDX)))))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_AVX512_WORD_LOOP(8, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_f64_array_avx512(uint64_t* out, const double* left, const double* right, size_t len, int op) {
#define LOAD_COMPARE(IDX) kiwi_host_compare_avx512_cmp_f64(_mm512_loadu_pd(left + (IDX)), _mm512_loadu_pd(right + (IDX)), op)
#define TAIL_COMPARE(IDX) kiwi_host_compare_f64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_AVX512_WORD_LOOP(8, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i8_scalar_avx512(uint64_t* out, const int8_t* items, size_t len, int8_t scalar, int scalar_left, int op) {
  const __m512i needle = _mm512_set1_epi8(scalar);
#define LOAD_COMPARE(IDX) (op == KIWI_HOST_COMPARE_EQ ? _mm512_cmpeq_epi8_mask(needle, _mm512_loadu_si512((const void*)(items + (IDX)))) : scalar_left ? (op == KIWI_HOST_COMPARE_LT ? _mm512_cmpgt_epi8_mask(_mm512_loadu_si512((const void*)(items + (IDX))), needle) : _mm512_cmpgt_epi8_mask(needle, _mm512_loadu_si512((const void*)(items + (IDX))))) : (op == KIWI_HOST_COMPARE_LT ? _mm512_cmpgt_epi8_mask(needle, _mm512_loadu_si512((const void*)(items + (IDX)))) : _mm512_cmpgt_epi8_mask(_mm512_loadu_si512((const void*)(items + (IDX))), needle)))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_AVX512_WORD_LOOP(64, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i16_scalar_avx512(uint64_t* out, const int16_t* items, size_t len, int16_t scalar, int scalar_left, int op) {
  const __m512i needle = _mm512_set1_epi16(scalar);
#define LOAD_COMPARE(IDX) (op == KIWI_HOST_COMPARE_EQ ? _mm512_cmpeq_epi16_mask(needle, _mm512_loadu_si512((const void*)(items + (IDX)))) : scalar_left ? (op == KIWI_HOST_COMPARE_LT ? _mm512_cmpgt_epi16_mask(_mm512_loadu_si512((const void*)(items + (IDX))), needle) : _mm512_cmpgt_epi16_mask(needle, _mm512_loadu_si512((const void*)(items + (IDX))))) : (op == KIWI_HOST_COMPARE_LT ? _mm512_cmpgt_epi16_mask(needle, _mm512_loadu_si512((const void*)(items + (IDX)))) : _mm512_cmpgt_epi16_mask(_mm512_loadu_si512((const void*)(items + (IDX))), needle)))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_AVX512_WORD_LOOP(32, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i32_scalar_avx512(uint64_t* out, const int32_t* items, size_t len, int32_t scalar, int scalar_left, int op) {
  const __m512i needle = _mm512_set1_epi32(scalar);
#define LOAD_COMPARE(IDX) (op == KIWI_HOST_COMPARE_EQ ? _mm512_cmpeq_epi32_mask(needle, _mm512_loadu_si512((const void*)(items + (IDX)))) : scalar_left ? (op == KIWI_HOST_COMPARE_LT ? _mm512_cmpgt_epi32_mask(_mm512_loadu_si512((const void*)(items + (IDX))), needle) : _mm512_cmpgt_epi32_mask(needle, _mm512_loadu_si512((const void*)(items + (IDX))))) : (op == KIWI_HOST_COMPARE_LT ? _mm512_cmpgt_epi32_mask(needle, _mm512_loadu_si512((const void*)(items + (IDX)))) : _mm512_cmpgt_epi32_mask(_mm512_loadu_si512((const void*)(items + (IDX))), needle)))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_AVX512_WORD_LOOP(16, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i64_scalar_avx512(uint64_t* out, const int64_t* items, size_t len, int64_t scalar, int scalar_left, int op) {
  const __m512i needle = _mm512_set1_epi64(scalar);
#define LOAD_COMPARE(IDX) (op == KIWI_HOST_COMPARE_EQ ? _mm512_cmpeq_epi64_mask(needle, _mm512_loadu_si512((const void*)(items + (IDX)))) : scalar_left ? (op == KIWI_HOST_COMPARE_LT ? _mm512_cmpgt_epi64_mask(_mm512_loadu_si512((const void*)(items + (IDX))), needle) : _mm512_cmpgt_epi64_mask(needle, _mm512_loadu_si512((const void*)(items + (IDX))))) : (op == KIWI_HOST_COMPARE_LT ? _mm512_cmpgt_epi64_mask(needle, _mm512_loadu_si512((const void*)(items + (IDX)))) : _mm512_cmpgt_epi64_mask(_mm512_loadu_si512((const void*)(items + (IDX))), needle)))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_AVX512_WORD_LOOP(8, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_f64_scalar_avx512(uint64_t* out, const double* items, size_t len, double scalar, int scalar_left, int op) {
  const __m512d needle = _mm512_set1_pd(scalar);
#define LOAD_COMPARE(IDX) (scalar_left ? kiwi_host_compare_avx512_cmp_f64(needle, _mm512_loadu_pd(items + (IDX)), op) : kiwi_host_compare_avx512_cmp_f64(_mm512_loadu_pd(items + (IDX)), needle, op))
#define TAIL_COMPARE(IDX) kiwi_host_compare_f64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_AVX512_WORD_LOOP(8, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_int_f64_array_avx512(
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
      KIWI_AVX512_RUN_INT_F64_PACK8((const int8_t*)int_items, i8_f64);
      break;
    case 2:
      KIWI_AVX512_RUN_INT_F64_PACK8((const int16_t*)int_items, i16_f64);
      break;
    case 4:
      KIWI_AVX512_RUN_INT_F64_PACK8((const int32_t*)int_items, i32_f64);
      break;
    case 8:
      KIWI_AVX512_RUN_INT_F64_PACK8((const int64_t*)int_items, i64_f64);
      break;
    default:
      kiwi_host_compare_int_f64_array_scalar(out, int_items, int_width, float_items, len, int_left, op);
      break;
  }
#undef TAIL_COMPARE
}

#undef KIWI_AVX512_RUN_INT_F64_PACK8
#undef KIWI_AVX512_INT_F64_PACK8_LOOP

#if defined(__clang__) && (defined(__x86_64__) || defined(_M_X64))
#pragma clang attribute pop
#endif
