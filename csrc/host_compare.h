#ifndef KIWI_HOST_COMPARE_H
#define KIWI_HOST_COMPARE_H

#include <stddef.h>
#include <stdint.h>

#define KIWI_HOST_COMPARE_EQ 0
#define KIWI_HOST_COMPARE_LT 1
#define KIWI_HOST_COMPARE_GT 2

typedef struct KiwiHostCompareSummary {
  uint8_t saw_one;
  uint8_t saw_zero;
  uint8_t asc;
  uint8_t dsc;
  uint8_t has_prev;
  uint8_t first;
  uint8_t prev_last;
} KiwiHostCompareSummary;

typedef struct KiwiHostCompareSummaryAccum {
  uint64_t any_one;
  uint64_t any_zero;
  uint64_t asc_breaks;
  uint64_t dsc_breaks;
  uint8_t has_prev;
  uint8_t first;
  uint8_t prev_last;
} KiwiHostCompareSummaryAccum;

extern _Thread_local KiwiHostCompareSummary kiwi_host_compare_summary_state;

static inline KiwiHostCompareSummary kiwi_host_compare_summary_empty(void) {
  KiwiHostCompareSummary summary = {0, 0, 1, 1, 0, 0, 0};
  return summary;
}

static inline uint64_t kiwi_host_compare_low_mask(size_t active) {
  return active >= 64 ? UINT64_MAX : ((UINT64_C(1) << active) - UINT64_C(1));
}

static inline KiwiHostCompareSummaryAccum kiwi_host_compare_summary_accum_empty(void) {
  KiwiHostCompareSummaryAccum accum = {0, 0, 0, 0, 0, 0, 0};
  return accum;
}

static inline void kiwi_host_compare_summary_accum_word(KiwiHostCompareSummaryAccum* accum, uint64_t word, size_t active) {
  if (active == 0) return;
  const uint64_t active_mask = kiwi_host_compare_low_mask(active);
  word &= active_mask;
  accum->any_one |= word;
  accum->any_zero |= (~word) & active_mask;

  const uint8_t first = (uint8_t)(word & UINT64_C(1));
  if (accum->has_prev) {
    if (accum->prev_last > first) accum->asc_breaks |= UINT64_C(1);
    if (accum->prev_last < first) accum->dsc_breaks |= UINT64_C(1);
  } else {
    accum->has_prev = 1;
    accum->first = first;
  }

  const uint64_t transition_mask = kiwi_host_compare_low_mask(active - 1);
  accum->asc_breaks |= (word & ~(word >> 1)) & transition_mask;
  accum->dsc_breaks |= ((~word) & (word >> 1)) & transition_mask;
  accum->prev_last = (uint8_t)((word >> (active - 1)) & UINT64_C(1));
}

static inline KiwiHostCompareSummary kiwi_host_compare_summary_accum_finish(KiwiHostCompareSummaryAccum accum) {
  KiwiHostCompareSummary summary = {
      accum.any_one != 0,
      accum.any_zero != 0,
      accum.asc_breaks == 0,
      accum.dsc_breaks == 0,
      accum.has_prev,
      accum.first,
      accum.prev_last,
  };
  return summary;
}

static inline void kiwi_host_compare_summary_note_word(KiwiHostCompareSummary* summary, uint64_t word, size_t active) {
  if (active == 0) return;
  const uint64_t active_mask = kiwi_host_compare_low_mask(active);
  word &= active_mask;
  if (word != 0) summary->saw_one = 1;
  if (word != active_mask) summary->saw_zero = 1;

  if (summary->asc || summary->dsc) {
    const uint8_t first = (uint8_t)(word & UINT64_C(1));
    if (summary->has_prev) {
      if (summary->prev_last > first) summary->asc = 0;
      if (summary->prev_last < first) summary->dsc = 0;
    } else {
      summary->has_prev = 1;
      summary->first = first;
    }
  } else if (!summary->has_prev) {
    summary->has_prev = 1;
    summary->first = (uint8_t)(word & UINT64_C(1));
  }

  if (active > 1 && (summary->asc || summary->dsc) && word != 0 && word != active_mask) {
    const uint64_t transition_mask = kiwi_host_compare_low_mask(active - 1);
    if (((word & ~(word >> 1)) & transition_mask) != 0) summary->asc = 0;
    if (((~word & (word >> 1)) & transition_mask) != 0) summary->dsc = 0;
  }
  summary->prev_last = (uint8_t)((word >> (active - 1)) & UINT64_C(1));
}

static inline void kiwi_host_compare_summary_publish(KiwiHostCompareSummary summary) {
  kiwi_host_compare_summary_state = summary;
}

void kiwi_host_compare_last_summary(KiwiHostCompareSummary* out);

void kiwi_host_compare_i8_array(uint64_t* out, const int8_t* left, const int8_t* right, size_t len, int op);
void kiwi_host_compare_i16_array(uint64_t* out, const int16_t* left, const int16_t* right, size_t len, int op);
void kiwi_host_compare_i32_array(uint64_t* out, const int32_t* left, const int32_t* right, size_t len, int op);
void kiwi_host_compare_i64_array(uint64_t* out, const int64_t* left, const int64_t* right, size_t len, int op);
void kiwi_host_compare_f64_array(uint64_t* out, const double* left, const double* right, size_t len, int op);
void kiwi_host_compare_int_mixed_array(uint64_t* out, const void* left, int left_width, const void* right, int right_width, size_t len, int op);
void kiwi_host_compare_int_f64_array(uint64_t* out, const void* int_items, int int_width, const double* float_items, size_t len, int int_left, int op);

void kiwi_host_compare_i8_scalar(uint64_t* out, const int8_t* items, size_t len, int8_t scalar, int scalar_left, int op);
void kiwi_host_compare_i16_scalar(uint64_t* out, const int16_t* items, size_t len, int16_t scalar, int scalar_left, int op);
void kiwi_host_compare_i32_scalar(uint64_t* out, const int32_t* items, size_t len, int32_t scalar, int scalar_left, int op);
void kiwi_host_compare_i64_scalar(uint64_t* out, const int64_t* items, size_t len, int64_t scalar, int scalar_left, int op);
void kiwi_host_compare_f64_scalar(uint64_t* out, const double* items, size_t len, double scalar, int scalar_left, int op);

void kiwi_host_compare_i8_array_scalar(uint64_t* out, const int8_t* left, const int8_t* right, size_t len, int op);
void kiwi_host_compare_i16_array_scalar(uint64_t* out, const int16_t* left, const int16_t* right, size_t len, int op);
void kiwi_host_compare_i32_array_scalar(uint64_t* out, const int32_t* left, const int32_t* right, size_t len, int op);
void kiwi_host_compare_i64_array_scalar(uint64_t* out, const int64_t* left, const int64_t* right, size_t len, int op);
void kiwi_host_compare_f64_array_scalar(uint64_t* out, const double* left, const double* right, size_t len, int op);
void kiwi_host_compare_int_mixed_array_scalar(uint64_t* out, const void* left, int left_width, const void* right, int right_width, size_t len, int op);
void kiwi_host_compare_int_f64_array_scalar(uint64_t* out, const void* int_items, int int_width, const double* float_items, size_t len, int int_left, int op);

void kiwi_host_compare_i8_scalar_scalar(uint64_t* out, const int8_t* items, size_t len, int8_t scalar, int scalar_left, int op);
void kiwi_host_compare_i16_scalar_scalar(uint64_t* out, const int16_t* items, size_t len, int16_t scalar, int scalar_left, int op);
void kiwi_host_compare_i32_scalar_scalar(uint64_t* out, const int32_t* items, size_t len, int32_t scalar, int scalar_left, int op);
void kiwi_host_compare_i64_scalar_scalar(uint64_t* out, const int64_t* items, size_t len, int64_t scalar, int scalar_left, int op);
void kiwi_host_compare_f64_scalar_scalar(uint64_t* out, const double* items, size_t len, double scalar, int scalar_left, int op);

typedef void (*kiwi_host_compare_i8_array_fn)(uint64_t* out, const int8_t* left, const int8_t* right, size_t len, int op);
typedef void (*kiwi_host_compare_i16_array_fn)(uint64_t* out, const int16_t* left, const int16_t* right, size_t len, int op);
typedef void (*kiwi_host_compare_i32_array_fn)(uint64_t* out, const int32_t* left, const int32_t* right, size_t len, int op);
typedef void (*kiwi_host_compare_i64_array_fn)(uint64_t* out, const int64_t* left, const int64_t* right, size_t len, int op);
typedef void (*kiwi_host_compare_f64_array_fn)(uint64_t* out, const double* left, const double* right, size_t len, int op);

typedef void (*kiwi_host_compare_i8_scalar_fn)(uint64_t* out, const int8_t* items, size_t len, int8_t scalar, int scalar_left, int op);
typedef void (*kiwi_host_compare_i16_scalar_fn)(uint64_t* out, const int16_t* items, size_t len, int16_t scalar, int scalar_left, int op);
typedef void (*kiwi_host_compare_i32_scalar_fn)(uint64_t* out, const int32_t* items, size_t len, int32_t scalar, int scalar_left, int op);
typedef void (*kiwi_host_compare_i64_scalar_fn)(uint64_t* out, const int64_t* items, size_t len, int64_t scalar, int scalar_left, int op);
typedef void (*kiwi_host_compare_f64_scalar_fn)(uint64_t* out, const double* items, size_t len, double scalar, int scalar_left, int op);
typedef void (*kiwi_host_compare_int_f64_array_fn)(uint64_t* out, const void* int_items, int int_width, const double* float_items, size_t len, int int_left, int op);

typedef struct KiwiHostCompareDispatch {
  kiwi_host_compare_i8_array_fn i8_array;
  kiwi_host_compare_i16_array_fn i16_array;
  kiwi_host_compare_i32_array_fn i32_array;
  kiwi_host_compare_i64_array_fn i64_array;
  kiwi_host_compare_f64_array_fn f64_array;
  kiwi_host_compare_i8_scalar_fn i8_scalar;
  kiwi_host_compare_i16_scalar_fn i16_scalar;
  kiwi_host_compare_i32_scalar_fn i32_scalar;
  kiwi_host_compare_i64_scalar_fn i64_scalar;
  kiwi_host_compare_f64_scalar_fn f64_scalar;
  kiwi_host_compare_int_f64_array_fn int_f64_array;
  const char* name;
} KiwiHostCompareDispatch;

const KiwiHostCompareDispatch* kiwi_host_compare_dispatch(void);

#if defined(__aarch64__)
void kiwi_host_compare_i8_array_neon(uint64_t* out, const int8_t* left, const int8_t* right, size_t len, int op);
void kiwi_host_compare_i16_array_neon(uint64_t* out, const int16_t* left, const int16_t* right, size_t len, int op);
void kiwi_host_compare_i32_array_neon(uint64_t* out, const int32_t* left, const int32_t* right, size_t len, int op);
void kiwi_host_compare_i64_array_neon(uint64_t* out, const int64_t* left, const int64_t* right, size_t len, int op);
void kiwi_host_compare_f64_array_neon(uint64_t* out, const double* left, const double* right, size_t len, int op);
void kiwi_host_compare_int_mixed_array_neon(uint64_t* out, const void* left, int left_width, const void* right, int right_width, size_t len, int op);
void kiwi_host_compare_int_f64_array_neon(uint64_t* out, const void* int_items, int int_width, const double* float_items, size_t len, int int_left, int op);
void kiwi_host_compare_i8_scalar_neon(uint64_t* out, const int8_t* items, size_t len, int8_t scalar, int scalar_left, int op);
void kiwi_host_compare_i16_scalar_neon(uint64_t* out, const int16_t* items, size_t len, int16_t scalar, int scalar_left, int op);
void kiwi_host_compare_i32_scalar_neon(uint64_t* out, const int32_t* items, size_t len, int32_t scalar, int scalar_left, int op);
void kiwi_host_compare_i64_scalar_neon(uint64_t* out, const int64_t* items, size_t len, int64_t scalar, int scalar_left, int op);
void kiwi_host_compare_f64_scalar_neon(uint64_t* out, const double* items, size_t len, double scalar, int scalar_left, int op);
#endif

#if defined(__x86_64__) || defined(_M_X64)
void kiwi_host_compare_i8_array_sse2(uint64_t* out, const int8_t* left, const int8_t* right, size_t len, int op);
void kiwi_host_compare_i16_array_sse2(uint64_t* out, const int16_t* left, const int16_t* right, size_t len, int op);
void kiwi_host_compare_i32_array_sse2(uint64_t* out, const int32_t* left, const int32_t* right, size_t len, int op);
void kiwi_host_compare_i64_array_sse2(uint64_t* out, const int64_t* left, const int64_t* right, size_t len, int op);
void kiwi_host_compare_f64_array_sse2(uint64_t* out, const double* left, const double* right, size_t len, int op);
void kiwi_host_compare_i8_scalar_sse2(uint64_t* out, const int8_t* items, size_t len, int8_t scalar, int scalar_left, int op);
void kiwi_host_compare_i16_scalar_sse2(uint64_t* out, const int16_t* items, size_t len, int16_t scalar, int scalar_left, int op);
void kiwi_host_compare_i32_scalar_sse2(uint64_t* out, const int32_t* items, size_t len, int32_t scalar, int scalar_left, int op);
void kiwi_host_compare_i64_scalar_sse2(uint64_t* out, const int64_t* items, size_t len, int64_t scalar, int scalar_left, int op);
void kiwi_host_compare_f64_scalar_sse2(uint64_t* out, const double* items, size_t len, double scalar, int scalar_left, int op);
void kiwi_host_compare_int_f64_array_sse41(uint64_t* out, const void* int_items, int int_width, const double* float_items, size_t len, int int_left, int op);

void kiwi_host_compare_i8_array_avx2(uint64_t* out, const int8_t* left, const int8_t* right, size_t len, int op);
void kiwi_host_compare_i16_array_avx2(uint64_t* out, const int16_t* left, const int16_t* right, size_t len, int op);
void kiwi_host_compare_i32_array_avx2(uint64_t* out, const int32_t* left, const int32_t* right, size_t len, int op);
void kiwi_host_compare_i64_array_avx2(uint64_t* out, const int64_t* left, const int64_t* right, size_t len, int op);
void kiwi_host_compare_f64_array_avx2(uint64_t* out, const double* left, const double* right, size_t len, int op);
void kiwi_host_compare_i8_scalar_avx2(uint64_t* out, const int8_t* items, size_t len, int8_t scalar, int scalar_left, int op);
void kiwi_host_compare_i16_scalar_avx2(uint64_t* out, const int16_t* items, size_t len, int16_t scalar, int scalar_left, int op);
void kiwi_host_compare_i32_scalar_avx2(uint64_t* out, const int32_t* items, size_t len, int32_t scalar, int scalar_left, int op);
void kiwi_host_compare_i64_scalar_avx2(uint64_t* out, const int64_t* items, size_t len, int64_t scalar, int scalar_left, int op);
void kiwi_host_compare_f64_scalar_avx2(uint64_t* out, const double* items, size_t len, double scalar, int scalar_left, int op);
void kiwi_host_compare_int_f64_array_avx2(uint64_t* out, const void* int_items, int int_width, const double* float_items, size_t len, int int_left, int op);

void kiwi_host_compare_i8_array_avx512(uint64_t* out, const int8_t* left, const int8_t* right, size_t len, int op);
void kiwi_host_compare_i16_array_avx512(uint64_t* out, const int16_t* left, const int16_t* right, size_t len, int op);
void kiwi_host_compare_i32_array_avx512(uint64_t* out, const int32_t* left, const int32_t* right, size_t len, int op);
void kiwi_host_compare_i64_array_avx512(uint64_t* out, const int64_t* left, const int64_t* right, size_t len, int op);
void kiwi_host_compare_f64_array_avx512(uint64_t* out, const double* left, const double* right, size_t len, int op);
void kiwi_host_compare_i8_scalar_avx512(uint64_t* out, const int8_t* items, size_t len, int8_t scalar, int scalar_left, int op);
void kiwi_host_compare_i16_scalar_avx512(uint64_t* out, const int16_t* items, size_t len, int16_t scalar, int scalar_left, int op);
void kiwi_host_compare_i32_scalar_avx512(uint64_t* out, const int32_t* items, size_t len, int32_t scalar, int scalar_left, int op);
void kiwi_host_compare_i64_scalar_avx512(uint64_t* out, const int64_t* items, size_t len, int64_t scalar, int scalar_left, int op);
void kiwi_host_compare_f64_scalar_avx512(uint64_t* out, const double* items, size_t len, double scalar, int scalar_left, int op);
void kiwi_host_compare_int_f64_array_avx512(uint64_t* out, const void* int_items, int int_width, const double* float_items, size_t len, int int_left, int op);
#endif

#endif
