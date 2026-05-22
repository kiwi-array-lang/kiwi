#include "host_sum.h"
#include "host_cpu.h"

#include <stdatomic.h>

int64_t kiwi_host_sum_i8_scalar(const int8_t* items, size_t len) {
  int64_t total = 0;
  for (size_t i = 0; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i16_scalar(const int16_t* items, size_t len) {
  int64_t total = 0;
  for (size_t i = 0; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i32_scalar(const int32_t* items, size_t len) {
  int64_t total = 0;
  for (size_t i = 0; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i64_scalar(const int64_t* items, size_t len) {
  int64_t total = 0;
  for (size_t i = 0; i < len; ++i) {
    total += items[i];
  }
  return total;
}

static const KiwiHostIntSumDispatch kiwi_host_sum_scalar_dispatch = {
    kiwi_host_sum_i8_scalar,
    kiwi_host_sum_i16_scalar,
    kiwi_host_sum_i32_scalar,
    kiwi_host_sum_i64_scalar,
    "scalar",
};

#if defined(__aarch64__)
static const KiwiHostIntSumDispatch kiwi_host_sum_neon_dispatch = {
    kiwi_host_sum_i8_neon,
    kiwi_host_sum_i16_neon,
    kiwi_host_sum_i32_neon,
    kiwi_host_sum_i64_neon,
    "neon",
};
#endif

#if defined(__x86_64__) || defined(_M_X64)
static const KiwiHostIntSumDispatch kiwi_host_sum_sse2_dispatch = {
    kiwi_host_sum_i8_sse2,
    kiwi_host_sum_i16_sse2,
    kiwi_host_sum_i32_sse2,
    kiwi_host_sum_i64_sse2,
    "sse2",
};

static const KiwiHostIntSumDispatch kiwi_host_sum_avx2_dispatch = {
    kiwi_host_sum_i8_avx2,
    kiwi_host_sum_i16_avx2,
    kiwi_host_sum_i32_avx2,
    kiwi_host_sum_i64_avx2,
    "avx2",
};

static const KiwiHostIntSumDispatch kiwi_host_sum_avx512_dispatch = {
    kiwi_host_sum_i8_avx512,
    kiwi_host_sum_i16_avx512,
    kiwi_host_sum_i32_avx512,
    kiwi_host_sum_i64_avx512,
    "avx512",
};
#endif

static KiwiHostIntSumDispatch kiwi_host_sum_selected_dispatch;
static atomic_uint kiwi_host_sum_dispatch_ready;

const KiwiHostIntSumDispatch* kiwi_host_int_sum_dispatch(void) {
  if (atomic_load_explicit(&kiwi_host_sum_dispatch_ready, memory_order_acquire) == 2u) {
    return &kiwi_host_sum_selected_dispatch;
  }

  unsigned expected = 0u;
  if (atomic_compare_exchange_strong_explicit(
          &kiwi_host_sum_dispatch_ready,
          &expected,
          1u,
          memory_order_acq_rel,
          memory_order_acquire)) {
#if defined(__aarch64__)
    kiwi_host_sum_selected_dispatch = kiwi_host_sum_neon_dispatch;
#elif defined(__x86_64__) || defined(_M_X64)
    const KiwiHostCpuFeatures* features = kiwi_host_cpu_features();
    kiwi_host_sum_selected_dispatch = kiwi_host_cpu_supports_avx512bw(features)
        ? kiwi_host_sum_avx512_dispatch
        : (kiwi_host_cpu_supports_avx2(features)
               ? kiwi_host_sum_avx2_dispatch
               : kiwi_host_sum_sse2_dispatch);
#else
    kiwi_host_sum_selected_dispatch = kiwi_host_sum_scalar_dispatch;
#endif
    atomic_store_explicit(&kiwi_host_sum_dispatch_ready, 2u, memory_order_release);
    return &kiwi_host_sum_selected_dispatch;
  }

  while (atomic_load_explicit(&kiwi_host_sum_dispatch_ready, memory_order_acquire) != 2u) {
  }
  return &kiwi_host_sum_selected_dispatch;
}
