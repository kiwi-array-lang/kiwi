#include "host_compare.h"

#include <emmintrin.h>

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

static inline uint64_t kiwi_host_compare_sse2_mask_i16(__m128i cmp) {
  const unsigned int byte_mask = (unsigned int)_mm_movemask_epi8(cmp);
  uint64_t mask = 0;
  for (size_t i = 0; i < 8; ++i) {
    if ((byte_mask & (1u << (i * 2))) != 0) mask |= UINT64_C(1) << i;
  }
  return mask;
}

static inline uint64_t kiwi_host_compare_sse2_mask_i32(__m128i cmp) {
  const unsigned int byte_mask = (unsigned int)_mm_movemask_epi8(cmp);
  uint64_t mask = 0;
  for (size_t i = 0; i < 4; ++i) {
    if ((byte_mask & (1u << (i * 4))) != 0) mask |= UINT64_C(1) << i;
  }
  return mask;
}

static inline uint64_t kiwi_host_compare_sse2_mask_f64(__m128d cmp) {
  return (uint64_t)(unsigned int)_mm_movemask_pd(cmp);
}

#define KIWI_SSE2_WORD_LOOP(LANES, LOAD_COMPARE, TAIL_COMPARE) \
  KiwiHostCompareSummary summary = kiwi_host_compare_summary_empty(); \
  size_t out_idx = 0; \
  for (size_t base = 0; base < len; base += 64) { \
    const size_t active = len - base < 64 ? len - base : 64; \
    uint64_t word = 0; \
    size_t bit = 0; \
    while (bit + (LANES) <= active) { \
      word |= (LOAD_COMPARE(base + bit)) << bit; \
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

void kiwi_host_compare_i8_array_sse2(uint64_t* out, const int8_t* left, const int8_t* right, size_t len, int op) {
#define LOAD_COMPARE(IDX) ((uint64_t)(unsigned int)_mm_movemask_epi8(op == KIWI_HOST_COMPARE_EQ ? _mm_cmpeq_epi8(_mm_loadu_si128((const __m128i*)(left + (IDX))), _mm_loadu_si128((const __m128i*)(right + (IDX)))) : op == KIWI_HOST_COMPARE_LT ? _mm_cmpgt_epi8(_mm_loadu_si128((const __m128i*)(right + (IDX))), _mm_loadu_si128((const __m128i*)(left + (IDX)))) : _mm_cmpgt_epi8(_mm_loadu_si128((const __m128i*)(left + (IDX))), _mm_loadu_si128((const __m128i*)(right + (IDX))))))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_SSE2_WORD_LOOP(16, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i16_array_sse2(uint64_t* out, const int16_t* left, const int16_t* right, size_t len, int op) {
#define LOAD_COMPARE(IDX) kiwi_host_compare_sse2_mask_i16(op == KIWI_HOST_COMPARE_EQ ? _mm_cmpeq_epi16(_mm_loadu_si128((const __m128i*)(left + (IDX))), _mm_loadu_si128((const __m128i*)(right + (IDX)))) : op == KIWI_HOST_COMPARE_LT ? _mm_cmpgt_epi16(_mm_loadu_si128((const __m128i*)(right + (IDX))), _mm_loadu_si128((const __m128i*)(left + (IDX)))) : _mm_cmpgt_epi16(_mm_loadu_si128((const __m128i*)(left + (IDX))), _mm_loadu_si128((const __m128i*)(right + (IDX)))))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_SSE2_WORD_LOOP(8, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i32_array_sse2(uint64_t* out, const int32_t* left, const int32_t* right, size_t len, int op) {
#define LOAD_COMPARE(IDX) kiwi_host_compare_sse2_mask_i32(op == KIWI_HOST_COMPARE_EQ ? _mm_cmpeq_epi32(_mm_loadu_si128((const __m128i*)(left + (IDX))), _mm_loadu_si128((const __m128i*)(right + (IDX)))) : op == KIWI_HOST_COMPARE_LT ? _mm_cmpgt_epi32(_mm_loadu_si128((const __m128i*)(right + (IDX))), _mm_loadu_si128((const __m128i*)(left + (IDX)))) : _mm_cmpgt_epi32(_mm_loadu_si128((const __m128i*)(left + (IDX))), _mm_loadu_si128((const __m128i*)(right + (IDX)))))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_SSE2_WORD_LOOP(4, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i64_array_sse2(uint64_t* out, const int64_t* left, const int64_t* right, size_t len, int op) {
  kiwi_host_compare_i64_array_scalar(out, left, right, len, op);
}

void kiwi_host_compare_f64_array_sse2(uint64_t* out, const double* left, const double* right, size_t len, int op) {
#define LOAD_COMPARE(IDX) kiwi_host_compare_sse2_mask_f64(op == KIWI_HOST_COMPARE_EQ ? _mm_cmpeq_pd(_mm_loadu_pd(left + (IDX)), _mm_loadu_pd(right + (IDX))) : op == KIWI_HOST_COMPARE_LT ? _mm_cmplt_pd(_mm_loadu_pd(left + (IDX)), _mm_loadu_pd(right + (IDX))) : _mm_cmpgt_pd(_mm_loadu_pd(left + (IDX)), _mm_loadu_pd(right + (IDX))))
#define TAIL_COMPARE(IDX) kiwi_host_compare_f64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_SSE2_WORD_LOOP(2, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i8_scalar_sse2(uint64_t* out, const int8_t* items, size_t len, int8_t scalar, int scalar_left, int op) {
  const __m128i needle = _mm_set1_epi8(scalar);
#define LOAD_COMPARE(IDX) ((uint64_t)(unsigned int)_mm_movemask_epi8(op == KIWI_HOST_COMPARE_EQ ? _mm_cmpeq_epi8(needle, _mm_loadu_si128((const __m128i*)(items + (IDX)))) : scalar_left ? (op == KIWI_HOST_COMPARE_LT ? _mm_cmpgt_epi8(_mm_loadu_si128((const __m128i*)(items + (IDX))), needle) : _mm_cmpgt_epi8(needle, _mm_loadu_si128((const __m128i*)(items + (IDX))))) : (op == KIWI_HOST_COMPARE_LT ? _mm_cmpgt_epi8(needle, _mm_loadu_si128((const __m128i*)(items + (IDX)))) : _mm_cmpgt_epi8(_mm_loadu_si128((const __m128i*)(items + (IDX))), needle))))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_SSE2_WORD_LOOP(16, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i16_scalar_sse2(uint64_t* out, const int16_t* items, size_t len, int16_t scalar, int scalar_left, int op) {
  const __m128i needle = _mm_set1_epi16(scalar);
#define LOAD_COMPARE(IDX) kiwi_host_compare_sse2_mask_i16(op == KIWI_HOST_COMPARE_EQ ? _mm_cmpeq_epi16(needle, _mm_loadu_si128((const __m128i*)(items + (IDX)))) : scalar_left ? (op == KIWI_HOST_COMPARE_LT ? _mm_cmpgt_epi16(_mm_loadu_si128((const __m128i*)(items + (IDX))), needle) : _mm_cmpgt_epi16(needle, _mm_loadu_si128((const __m128i*)(items + (IDX))))) : (op == KIWI_HOST_COMPARE_LT ? _mm_cmpgt_epi16(needle, _mm_loadu_si128((const __m128i*)(items + (IDX)))) : _mm_cmpgt_epi16(_mm_loadu_si128((const __m128i*)(items + (IDX))), needle)))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_SSE2_WORD_LOOP(8, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i32_scalar_sse2(uint64_t* out, const int32_t* items, size_t len, int32_t scalar, int scalar_left, int op) {
  const __m128i needle = _mm_set1_epi32(scalar);
#define LOAD_COMPARE(IDX) kiwi_host_compare_sse2_mask_i32(op == KIWI_HOST_COMPARE_EQ ? _mm_cmpeq_epi32(needle, _mm_loadu_si128((const __m128i*)(items + (IDX)))) : scalar_left ? (op == KIWI_HOST_COMPARE_LT ? _mm_cmpgt_epi32(_mm_loadu_si128((const __m128i*)(items + (IDX))), needle) : _mm_cmpgt_epi32(needle, _mm_loadu_si128((const __m128i*)(items + (IDX))))) : (op == KIWI_HOST_COMPARE_LT ? _mm_cmpgt_epi32(needle, _mm_loadu_si128((const __m128i*)(items + (IDX)))) : _mm_cmpgt_epi32(_mm_loadu_si128((const __m128i*)(items + (IDX))), needle)))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_SSE2_WORD_LOOP(4, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_i64_scalar_sse2(uint64_t* out, const int64_t* items, size_t len, int64_t scalar, int scalar_left, int op) {
  kiwi_host_compare_i64_scalar_scalar(out, items, len, scalar, scalar_left, op);
}

void kiwi_host_compare_f64_scalar_sse2(uint64_t* out, const double* items, size_t len, double scalar, int scalar_left, int op) {
  const __m128d needle = _mm_set1_pd(scalar);
#define LOAD_COMPARE(IDX) kiwi_host_compare_sse2_mask_f64(op == KIWI_HOST_COMPARE_EQ ? _mm_cmpeq_pd(needle, _mm_loadu_pd(items + (IDX))) : scalar_left ? (op == KIWI_HOST_COMPARE_LT ? _mm_cmplt_pd(needle, _mm_loadu_pd(items + (IDX))) : _mm_cmpgt_pd(needle, _mm_loadu_pd(items + (IDX)))) : (op == KIWI_HOST_COMPARE_LT ? _mm_cmplt_pd(_mm_loadu_pd(items + (IDX)), needle) : _mm_cmpgt_pd(_mm_loadu_pd(items + (IDX)), needle)))
#define TAIL_COMPARE(IDX) kiwi_host_compare_f64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_SSE2_WORD_LOOP(2, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}
