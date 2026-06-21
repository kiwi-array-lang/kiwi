#include "host_find.h"
#include "host_cpu.h"

#include <stdatomic.h>

size_t kiwi_host_find_i8_scalar(const int8_t* items, size_t len, int8_t query) {
  for (size_t i = 0; i < len; ++i) {
    if (items[i] == query) {
      return i;
    }
  }
  return len;
}

size_t kiwi_host_find_i16_scalar(const int16_t* items, size_t len, int16_t query) {
  for (size_t i = 0; i < len; ++i) {
    if (items[i] == query) {
      return i;
    }
  }
  return len;
}

size_t kiwi_host_find_i32_scalar(const int32_t* items, size_t len, int32_t query) {
  for (size_t i = 0; i < len; ++i) {
    if (items[i] == query) {
      return i;
    }
  }
  return len;
}

size_t kiwi_host_find_i64_scalar(const int64_t* items, size_t len, int64_t query) {
  for (size_t i = 0; i < len; ++i) {
    if (items[i] == query) {
      return i;
    }
  }
  return len;
}

size_t kiwi_host_find_f64_scalar(const double* items, size_t len, double query) {
  for (size_t i = 0; i < len; ++i) {
    if (items[i] == query) {
      return i;
    }
  }
  return len;
}

void kiwi_host_find_i8_build_table_i32(int32_t* table, const int8_t* items, size_t len, int32_t miss) {
  for (size_t i = 0; i < 256; ++i) {
    table[i] = miss;
  }
  for (size_t i = len; i > 0; --i) {
    const size_t idx = i - 1;
    table[(uint8_t)items[idx]] = (int32_t)idx;
  }
}

void kiwi_host_find_i16_build_table_i32(int32_t* table, const int16_t* items, size_t len, int32_t miss) {
  for (size_t i = 0; i < 65536; ++i) {
    table[i] = miss;
  }
  for (size_t i = len; i > 0; --i) {
    const size_t idx = i - 1;
    table[(uint16_t)items[idx]] = (int32_t)idx;
  }
}

uint8_t kiwi_host_find_i8_lookup_table_i32(int32_t* out, const int32_t* table, const int8_t* queries, size_t len, int32_t miss) {
  uint8_t saw_miss = 0;
  for (size_t i = 0; i < len; ++i) {
    const int32_t value = table[(uint8_t)queries[i]];
    out[i] = value;
    saw_miss |= (uint8_t)(value == miss);
  }
  return saw_miss;
}

uint8_t kiwi_host_find_i16_lookup_table_i8_queries_i32(int32_t* out, const int32_t* table, const int8_t* queries, size_t len, int32_t miss) {
  uint8_t saw_miss = 0;
  for (size_t i = 0; i < len; ++i) {
    const int32_t value = table[(uint16_t)(int16_t)queries[i]];
    out[i] = value;
    saw_miss |= (uint8_t)(value == miss);
  }
  return saw_miss;
}

uint8_t kiwi_host_find_i16_lookup_table_i32(int32_t* out, const int32_t* table, const int16_t* queries, size_t len, int32_t miss) {
  uint8_t saw_miss = 0;
  for (size_t i = 0; i < len; ++i) {
    const int32_t value = table[(uint16_t)queries[i]];
    out[i] = value;
    saw_miss |= (uint8_t)(value == miss);
  }
  return saw_miss;
}

void kiwi_host_find_i8_lookup_table_i64_null(int64_t* out, const int32_t* table, const int8_t* queries, size_t len, int32_t miss, int64_t null_value) {
  for (size_t i = 0; i < len; ++i) {
    const int32_t value = table[(uint8_t)queries[i]];
    out[i] = value == miss ? null_value : (int64_t)value;
  }
}

void kiwi_host_find_i16_lookup_table_i8_queries_i64_null(int64_t* out, const int32_t* table, const int8_t* queries, size_t len, int32_t miss, int64_t null_value) {
  for (size_t i = 0; i < len; ++i) {
    const int32_t value = table[(uint16_t)(int16_t)queries[i]];
    out[i] = value == miss ? null_value : (int64_t)value;
  }
}

void kiwi_host_find_i16_lookup_table_i64_null(int64_t* out, const int32_t* table, const int16_t* queries, size_t len, int32_t miss, int64_t null_value) {
  for (size_t i = 0; i < len; ++i) {
    const int32_t value = table[(uint16_t)queries[i]];
    out[i] = value == miss ? null_value : (int64_t)value;
  }
}

static const KiwiHostFindDispatch kiwi_host_find_scalar_dispatch = {
    kiwi_host_find_i8_scalar,
    kiwi_host_find_i16_scalar,
    kiwi_host_find_i32_scalar,
    kiwi_host_find_i64_scalar,
    kiwi_host_find_f64_scalar,
    "scalar",
};

#if defined(__aarch64__)
static const KiwiHostFindDispatch kiwi_host_find_neon_dispatch = {
    kiwi_host_find_i8_neon,
    kiwi_host_find_i16_neon,
    kiwi_host_find_i32_neon,
    kiwi_host_find_i64_neon,
    kiwi_host_find_f64_neon,
    "neon",
};
#endif

#if defined(__x86_64__) || defined(_M_X64)
static const KiwiHostFindDispatch kiwi_host_find_sse2_dispatch = {
    kiwi_host_find_i8_sse2,
    kiwi_host_find_i16_sse2,
    kiwi_host_find_i32_sse2,
    kiwi_host_find_i64_sse2,
    kiwi_host_find_f64_sse2,
    "sse2",
};

static const KiwiHostFindDispatch kiwi_host_find_avx2_dispatch = {
    kiwi_host_find_i8_avx2,
    kiwi_host_find_i16_avx2,
    kiwi_host_find_i32_avx2,
    kiwi_host_find_i64_avx2,
    kiwi_host_find_f64_avx2,
    "avx2",
};

static const KiwiHostFindDispatch kiwi_host_find_avx512_dispatch = {
    kiwi_host_find_i8_avx512,
    kiwi_host_find_i16_avx512,
    kiwi_host_find_i32_avx512,
    kiwi_host_find_i64_avx512,
    kiwi_host_find_f64_avx512,
    "avx512",
};
#endif

static KiwiHostFindDispatch kiwi_host_find_selected_dispatch;
static atomic_uint kiwi_host_find_dispatch_ready;

const KiwiHostFindDispatch* kiwi_host_find_dispatch(void) {
  if (atomic_load_explicit(&kiwi_host_find_dispatch_ready, memory_order_acquire) == 2u) {
    return &kiwi_host_find_selected_dispatch;
  }

  unsigned expected = 0u;
  if (atomic_compare_exchange_strong_explicit(
          &kiwi_host_find_dispatch_ready,
          &expected,
          1u,
          memory_order_acq_rel,
          memory_order_acquire)) {
#if defined(__aarch64__)
    kiwi_host_find_selected_dispatch = kiwi_host_find_neon_dispatch;
#elif defined(__x86_64__) || defined(_M_X64)
    const KiwiHostCpuFeatures* features = kiwi_host_cpu_features();
    kiwi_host_find_selected_dispatch = kiwi_host_cpu_supports_avx512bw(features)
        ? kiwi_host_find_avx512_dispatch
        : (kiwi_host_cpu_supports_avx2(features)
               ? kiwi_host_find_avx2_dispatch
               : kiwi_host_find_sse2_dispatch);
#else
    kiwi_host_find_selected_dispatch = kiwi_host_find_scalar_dispatch;
#endif
    atomic_store_explicit(&kiwi_host_find_dispatch_ready, 2u, memory_order_release);
    return &kiwi_host_find_selected_dispatch;
  }

  while (atomic_load_explicit(&kiwi_host_find_dispatch_ready, memory_order_acquire) != 2u) {
  }
  return &kiwi_host_find_selected_dispatch;
}

size_t kiwi_host_find_i8(const int8_t* items, size_t len, int8_t query) {
#if defined(__aarch64__)
  return kiwi_host_find_i8_neon(items, len, query);
#elif defined(__x86_64__) || defined(_M_X64)
  return kiwi_host_find_dispatch()->find_i8(items, len, query);
#else
  return kiwi_host_find_i8_scalar(items, len, query);
#endif
}

size_t kiwi_host_find_i16(const int16_t* items, size_t len, int16_t query) {
#if defined(__aarch64__)
  return kiwi_host_find_i16_neon(items, len, query);
#elif defined(__x86_64__) || defined(_M_X64)
  return kiwi_host_find_dispatch()->find_i16(items, len, query);
#else
  return kiwi_host_find_i16_scalar(items, len, query);
#endif
}

size_t kiwi_host_find_i32(const int32_t* items, size_t len, int32_t query) {
#if defined(__aarch64__)
  return kiwi_host_find_i32_neon(items, len, query);
#elif defined(__x86_64__) || defined(_M_X64)
  return kiwi_host_find_dispatch()->find_i32(items, len, query);
#else
  return kiwi_host_find_i32_scalar(items, len, query);
#endif
}

size_t kiwi_host_find_i64(const int64_t* items, size_t len, int64_t query) {
#if defined(__aarch64__)
  return kiwi_host_find_i64_neon(items, len, query);
#elif defined(__x86_64__) || defined(_M_X64)
  return kiwi_host_find_dispatch()->find_i64(items, len, query);
#else
  return kiwi_host_find_i64_scalar(items, len, query);
#endif
}

size_t kiwi_host_find_f64(const double* items, size_t len, double query) {
#if defined(__aarch64__)
  return kiwi_host_find_f64_neon(items, len, query);
#elif defined(__x86_64__) || defined(_M_X64)
  return kiwi_host_find_dispatch()->find_f64(items, len, query);
#else
  return kiwi_host_find_f64_scalar(items, len, query);
#endif
}
