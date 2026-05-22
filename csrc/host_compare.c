#include "host_compare.h"
#include "host_cpu.h"

#include <stdatomic.h>

_Thread_local KiwiHostCompareSummary kiwi_host_compare_summary_state = {0, 0, 1, 1, 0, 0, 0};

void kiwi_host_compare_last_summary(KiwiHostCompareSummary* out) {
  *out = kiwi_host_compare_summary_state;
}

static inline int kiwi_host_compare_i64_value(int64_t left, int64_t right, int op) {
  return op == KIWI_HOST_COMPARE_EQ ? left == right
      : op == KIWI_HOST_COMPARE_LT ? left < right
                                    : left > right;
}

static inline int kiwi_host_compare_f64_value(double left, double right, int op) {
  return op == KIWI_HOST_COMPARE_EQ ? left == right
      : op == KIWI_HOST_COMPARE_LT ? left < right
                                    : left > right;
}

static inline int64_t kiwi_host_compare_load_int_value(const void* items, int width, size_t idx) {
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

#define KIWI_DEFINE_INT_COMPARE_SCALAR(NAME, TYPE) \
  void kiwi_host_compare_##NAME##_array_scalar(uint64_t* out, const TYPE* left, const TYPE* right, size_t len, int op) { \
    KiwiHostCompareSummary summary = kiwi_host_compare_summary_empty(); \
    size_t out_idx = 0; \
    for (size_t base = 0; base < len; base += 64) { \
      const size_t active = len - base < 64 ? len - base : 64; \
      uint64_t word = 0; \
      for (size_t bit = 0; bit < active; ++bit) { \
        if (kiwi_host_compare_i64_value((int64_t)left[base + bit], (int64_t)right[base + bit], op)) { \
          word |= UINT64_C(1) << bit; \
        } \
      } \
      kiwi_host_compare_summary_note_word(&summary, word, active); \
      out[out_idx++] = word; \
    } \
    kiwi_host_compare_summary_publish(summary); \
  } \
  void kiwi_host_compare_##NAME##_scalar_scalar(uint64_t* out, const TYPE* items, size_t len, TYPE scalar, int scalar_left, int op) { \
    KiwiHostCompareSummary summary = kiwi_host_compare_summary_empty(); \
    size_t out_idx = 0; \
    for (size_t base = 0; base < len; base += 64) { \
      const size_t active = len - base < 64 ? len - base : 64; \
      uint64_t word = 0; \
      for (size_t bit = 0; bit < active; ++bit) { \
        const int64_t item = (int64_t)items[base + bit]; \
        const int64_t left = scalar_left ? (int64_t)scalar : item; \
        const int64_t right = scalar_left ? item : (int64_t)scalar; \
        if (kiwi_host_compare_i64_value(left, right, op)) { \
          word |= UINT64_C(1) << bit; \
        } \
      } \
      kiwi_host_compare_summary_note_word(&summary, word, active); \
      out[out_idx++] = word; \
    } \
    kiwi_host_compare_summary_publish(summary); \
  }

KIWI_DEFINE_INT_COMPARE_SCALAR(i8, int8_t)
KIWI_DEFINE_INT_COMPARE_SCALAR(i16, int16_t)
KIWI_DEFINE_INT_COMPARE_SCALAR(i32, int32_t)
KIWI_DEFINE_INT_COMPARE_SCALAR(i64, int64_t)

void kiwi_host_compare_int_mixed_array_scalar(uint64_t* out, const void* left, int left_width, const void* right, int right_width, size_t len, int op) {
  KiwiHostCompareSummary summary = kiwi_host_compare_summary_empty();
  size_t out_idx = 0;
  for (size_t base = 0; base < len; base += 64) {
    const size_t active = len - base < 64 ? len - base : 64;
    uint64_t word = 0;
    for (size_t bit = 0; bit < active; ++bit) {
      const int64_t left_value = kiwi_host_compare_load_int_value(left, left_width, base + bit);
      const int64_t right_value = kiwi_host_compare_load_int_value(right, right_width, base + bit);
      if (kiwi_host_compare_i64_value(left_value, right_value, op)) {
        word |= UINT64_C(1) << bit;
      }
    }
    kiwi_host_compare_summary_note_word(&summary, word, active);
    out[out_idx++] = word;
  }
  kiwi_host_compare_summary_publish(summary);
}

void kiwi_host_compare_int_f64_array_scalar(
    uint64_t* out,
    const void* int_items,
    int int_width,
    const double* float_items,
    size_t len,
    int int_left,
    int op) {
  KiwiHostCompareSummary summary = kiwi_host_compare_summary_empty();
  size_t out_idx = 0;
  for (size_t base = 0; base < len; base += 64) {
    const size_t active = len - base < 64 ? len - base : 64;
    uint64_t word = 0;
    for (size_t bit = 0; bit < active; ++bit) {
      const double int_value = (double)kiwi_host_compare_load_int_value(int_items, int_width, base + bit);
      const double float_value = float_items[base + bit];
      const double left = int_left ? int_value : float_value;
      const double right = int_left ? float_value : int_value;
      if (kiwi_host_compare_f64_value(left, right, op)) {
        word |= UINT64_C(1) << bit;
      }
    }
    kiwi_host_compare_summary_note_word(&summary, word, active);
    out[out_idx++] = word;
  }
  kiwi_host_compare_summary_publish(summary);
}

void kiwi_host_compare_f64_array_scalar(uint64_t* out, const double* left, const double* right, size_t len, int op) {
  KiwiHostCompareSummary summary = kiwi_host_compare_summary_empty();
  size_t out_idx = 0;
  for (size_t base = 0; base < len; base += 64) {
    const size_t active = len - base < 64 ? len - base : 64;
    uint64_t word = 0;
    for (size_t bit = 0; bit < active; ++bit) {
      if (kiwi_host_compare_f64_value(left[base + bit], right[base + bit], op)) {
        word |= UINT64_C(1) << bit;
      }
    }
    kiwi_host_compare_summary_note_word(&summary, word, active);
    out[out_idx++] = word;
  }
  kiwi_host_compare_summary_publish(summary);
}

void kiwi_host_compare_f64_scalar_scalar(uint64_t* out, const double* items, size_t len, double scalar, int scalar_left, int op) {
  KiwiHostCompareSummary summary = kiwi_host_compare_summary_empty();
  size_t out_idx = 0;
  for (size_t base = 0; base < len; base += 64) {
    const size_t active = len - base < 64 ? len - base : 64;
    uint64_t word = 0;
    for (size_t bit = 0; bit < active; ++bit) {
      const double item = items[base + bit];
      const double left = scalar_left ? scalar : item;
      const double right = scalar_left ? item : scalar;
      if (kiwi_host_compare_f64_value(left, right, op)) {
        word |= UINT64_C(1) << bit;
      }
    }
    kiwi_host_compare_summary_note_word(&summary, word, active);
    out[out_idx++] = word;
  }
  kiwi_host_compare_summary_publish(summary);
}

static const KiwiHostCompareDispatch kiwi_host_compare_scalar_dispatch = {
    kiwi_host_compare_i8_array_scalar,
    kiwi_host_compare_i16_array_scalar,
    kiwi_host_compare_i32_array_scalar,
    kiwi_host_compare_i64_array_scalar,
    kiwi_host_compare_f64_array_scalar,
    kiwi_host_compare_i8_scalar_scalar,
    kiwi_host_compare_i16_scalar_scalar,
    kiwi_host_compare_i32_scalar_scalar,
    kiwi_host_compare_i64_scalar_scalar,
    kiwi_host_compare_f64_scalar_scalar,
    kiwi_host_compare_int_f64_array_scalar,
    "scalar",
};

#if defined(__aarch64__)
static const KiwiHostCompareDispatch kiwi_host_compare_neon_dispatch = {
    kiwi_host_compare_i8_array_neon,
    kiwi_host_compare_i16_array_neon,
    kiwi_host_compare_i32_array_neon,
    kiwi_host_compare_i64_array_neon,
    kiwi_host_compare_f64_array_neon,
    kiwi_host_compare_i8_scalar_neon,
    kiwi_host_compare_i16_scalar_neon,
    kiwi_host_compare_i32_scalar_neon,
    kiwi_host_compare_i64_scalar_neon,
    kiwi_host_compare_f64_scalar_neon,
    kiwi_host_compare_int_f64_array_neon,
    "neon",
};
#endif

#if defined(__x86_64__) || defined(_M_X64)
static const KiwiHostCompareDispatch kiwi_host_compare_sse2_dispatch = {
    kiwi_host_compare_i8_array_sse2,
    kiwi_host_compare_i16_array_sse2,
    kiwi_host_compare_i32_array_sse2,
    kiwi_host_compare_i64_array_sse2,
    kiwi_host_compare_f64_array_sse2,
    kiwi_host_compare_i8_scalar_sse2,
    kiwi_host_compare_i16_scalar_sse2,
    kiwi_host_compare_i32_scalar_sse2,
    kiwi_host_compare_i64_scalar_sse2,
    kiwi_host_compare_f64_scalar_sse2,
    kiwi_host_compare_int_f64_array_scalar,
    "sse2",
};

static const KiwiHostCompareDispatch kiwi_host_compare_sse41_dispatch = {
    kiwi_host_compare_i8_array_sse2,
    kiwi_host_compare_i16_array_sse2,
    kiwi_host_compare_i32_array_sse2,
    kiwi_host_compare_i64_array_sse2,
    kiwi_host_compare_f64_array_sse2,
    kiwi_host_compare_i8_scalar_sse2,
    kiwi_host_compare_i16_scalar_sse2,
    kiwi_host_compare_i32_scalar_sse2,
    kiwi_host_compare_i64_scalar_sse2,
    kiwi_host_compare_f64_scalar_sse2,
    kiwi_host_compare_int_f64_array_sse41,
    "sse41",
};

static const KiwiHostCompareDispatch kiwi_host_compare_avx2_dispatch = {
    kiwi_host_compare_i8_array_avx2,
    kiwi_host_compare_i16_array_avx2,
    kiwi_host_compare_i32_array_avx2,
    kiwi_host_compare_i64_array_avx2,
    kiwi_host_compare_f64_array_avx2,
    kiwi_host_compare_i8_scalar_avx2,
    kiwi_host_compare_i16_scalar_avx2,
    kiwi_host_compare_i32_scalar_avx2,
    kiwi_host_compare_i64_scalar_avx2,
    kiwi_host_compare_f64_scalar_avx2,
    kiwi_host_compare_int_f64_array_avx2,
    "avx2",
};

static const KiwiHostCompareDispatch kiwi_host_compare_avx512_dispatch = {
    kiwi_host_compare_i8_array_avx512,
    kiwi_host_compare_i16_array_avx512,
    kiwi_host_compare_i32_array_avx512,
    kiwi_host_compare_i64_array_avx512,
    kiwi_host_compare_f64_array_avx512,
    kiwi_host_compare_i8_scalar_avx512,
    kiwi_host_compare_i16_scalar_avx512,
    kiwi_host_compare_i32_scalar_avx512,
    kiwi_host_compare_i64_scalar_avx512,
    kiwi_host_compare_f64_scalar_avx512,
    kiwi_host_compare_int_f64_array_avx512,
    "avx512",
};
#endif

static KiwiHostCompareDispatch kiwi_host_compare_selected_dispatch;
static atomic_uint kiwi_host_compare_dispatch_ready;

const KiwiHostCompareDispatch* kiwi_host_compare_dispatch(void) {
  if (atomic_load_explicit(&kiwi_host_compare_dispatch_ready, memory_order_acquire) == 2u) {
    return &kiwi_host_compare_selected_dispatch;
  }

  unsigned expected = 0u;
  if (atomic_compare_exchange_strong_explicit(
          &kiwi_host_compare_dispatch_ready,
          &expected,
          1u,
          memory_order_acq_rel,
          memory_order_acquire)) {
#if defined(__aarch64__)
    kiwi_host_compare_selected_dispatch = kiwi_host_compare_neon_dispatch;
#elif defined(__x86_64__) || defined(_M_X64)
    const KiwiHostCpuFeatures* features = kiwi_host_cpu_features();
    kiwi_host_compare_selected_dispatch = kiwi_host_cpu_supports_avx512bw(features)
        ? kiwi_host_compare_avx512_dispatch
        : (kiwi_host_cpu_supports_avx2(features)
               ? kiwi_host_compare_avx2_dispatch
               : (kiwi_host_cpu_supports_sse41(features)
                      ? kiwi_host_compare_sse41_dispatch
                      : kiwi_host_compare_sse2_dispatch));
#else
    kiwi_host_compare_selected_dispatch = kiwi_host_compare_scalar_dispatch;
#endif
    atomic_store_explicit(&kiwi_host_compare_dispatch_ready, 2u, memory_order_release);
    return &kiwi_host_compare_selected_dispatch;
  }

  while (atomic_load_explicit(&kiwi_host_compare_dispatch_ready, memory_order_acquire) != 2u) {
  }
  return &kiwi_host_compare_selected_dispatch;
}

#define KIWI_COMPARE_ARRAY_WRAPPER(NAME, TYPE, FIELD) \
  void kiwi_host_compare_##NAME##_array(uint64_t* out, const TYPE* left, const TYPE* right, size_t len, int op) { \
    kiwi_host_compare_summary_publish(kiwi_host_compare_summary_empty()); \
    if (len == 0) return; \
    kiwi_host_compare_dispatch()->FIELD(out, left, right, len, op); \
  }

#define KIWI_COMPARE_SCALAR_WRAPPER(NAME, TYPE, FIELD) \
  void kiwi_host_compare_##NAME##_scalar(uint64_t* out, const TYPE* items, size_t len, TYPE scalar, int scalar_left, int op) { \
    kiwi_host_compare_summary_publish(kiwi_host_compare_summary_empty()); \
    if (len == 0) return; \
    kiwi_host_compare_dispatch()->FIELD(out, items, len, scalar, scalar_left, op); \
  }

KIWI_COMPARE_ARRAY_WRAPPER(i8, int8_t, i8_array)
KIWI_COMPARE_ARRAY_WRAPPER(i16, int16_t, i16_array)
KIWI_COMPARE_ARRAY_WRAPPER(i32, int32_t, i32_array)
KIWI_COMPARE_ARRAY_WRAPPER(i64, int64_t, i64_array)
KIWI_COMPARE_ARRAY_WRAPPER(f64, double, f64_array)

KIWI_COMPARE_SCALAR_WRAPPER(i8, int8_t, i8_scalar)
KIWI_COMPARE_SCALAR_WRAPPER(i16, int16_t, i16_scalar)
KIWI_COMPARE_SCALAR_WRAPPER(i32, int32_t, i32_scalar)
KIWI_COMPARE_SCALAR_WRAPPER(i64, int64_t, i64_scalar)
KIWI_COMPARE_SCALAR_WRAPPER(f64, double, f64_scalar)

void kiwi_host_compare_int_mixed_array(uint64_t* out, const void* left, int left_width, const void* right, int right_width, size_t len, int op) {
  kiwi_host_compare_summary_publish(kiwi_host_compare_summary_empty());
  if (len == 0) return;
  if (left_width == right_width) {
    switch (left_width) {
      case 1:
        kiwi_host_compare_i8_array(out, (const int8_t*)left, (const int8_t*)right, len, op);
        return;
      case 2:
        kiwi_host_compare_i16_array(out, (const int16_t*)left, (const int16_t*)right, len, op);
        return;
      case 4:
        kiwi_host_compare_i32_array(out, (const int32_t*)left, (const int32_t*)right, len, op);
        return;
      case 8:
        kiwi_host_compare_i64_array(out, (const int64_t*)left, (const int64_t*)right, len, op);
        return;
      default:
        break;
    }
  }
#if defined(__aarch64__)
  kiwi_host_compare_int_mixed_array_neon(out, left, left_width, right, right_width, len, op);
#else
  kiwi_host_compare_int_mixed_array_scalar(out, left, left_width, right, right_width, len, op);
#endif
}

void kiwi_host_compare_int_f64_array(
    uint64_t* out,
    const void* int_items,
    int int_width,
    const double* float_items,
    size_t len,
    int int_left,
    int op) {
  kiwi_host_compare_summary_publish(kiwi_host_compare_summary_empty());
  if (len == 0) return;
  kiwi_host_compare_dispatch()->int_f64_array(out, int_items, int_width, float_items, len, int_left, op);
}
