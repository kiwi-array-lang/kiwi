#include "host_find.h"

#if defined(__x86_64__) || defined(_M_X64)
#include <immintrin.h>

#if defined(__clang__)
#pragma clang attribute push(__attribute__((target("avx512f,avx512bw,evex512"))), apply_to=function)
#endif

#if defined(_MSC_VER)
#include <intrin.h>
static unsigned kiwi_avx512_ctz64(uint64_t mask) {
  unsigned long idx = 0;
  _BitScanForward64(&idx, mask);
  return (unsigned)idx;
}
#else
static unsigned kiwi_avx512_ctz64(uint64_t mask) {
  return (unsigned)__builtin_ctzll(mask);
}
#endif

static size_t kiwi_host_find_i8_avx512_block(const int8_t* items, size_t len, __m512i needle, int8_t query) {
  size_t idx = 0;
  while (len - idx >= 64) {
    const uint64_t mask = (uint64_t)_mm512_cmpeq_epi8_mask(_mm512_loadu_si512((const void*)(items + idx)), needle);
    if (mask != 0) {
      return idx + kiwi_avx512_ctz64(mask);
    }
    idx += 64;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_i8_avx512(const int8_t* items, size_t len, int8_t query) {
  const __m512i needle = _mm512_set1_epi8(query);
  size_t idx = 0;
  while (len - idx >= 512) {
    uint64_t any = 0;

#define KIWI_ACC_I8_AVX512(OFF) do { \
      any |= (uint64_t)_mm512_cmpeq_epi8_mask(_mm512_loadu_si512((const void*)(items + idx + (OFF))), needle); \
    } while (0)

    KIWI_ACC_I8_AVX512(0); KIWI_ACC_I8_AVX512(64); KIWI_ACC_I8_AVX512(128); KIWI_ACC_I8_AVX512(192);
    KIWI_ACC_I8_AVX512(256); KIWI_ACC_I8_AVX512(320); KIWI_ACC_I8_AVX512(384); KIWI_ACC_I8_AVX512(448);

#undef KIWI_ACC_I8_AVX512

    if (any != 0) {
      return idx + kiwi_host_find_i8_avx512_block(items + idx, 512, needle, query);
    }
    idx += 512;
  }
  return idx + kiwi_host_find_i8_avx512_block(items + idx, len - idx, needle, query);
}

static size_t kiwi_host_find_i16_avx512_block(const int16_t* items, size_t len, __m512i needle, int16_t query) {
  size_t idx = 0;
  while (len - idx >= 32) {
    const uint64_t mask = (uint64_t)_mm512_cmpeq_epi16_mask(_mm512_loadu_si512((const void*)(items + idx)), needle);
    if (mask != 0) {
      return idx + kiwi_avx512_ctz64(mask);
    }
    idx += 32;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_i16_avx512(const int16_t* items, size_t len, int16_t query) {
  const __m512i needle = _mm512_set1_epi16(query);
  size_t idx = 0;
  while (len - idx >= 256) {
    uint64_t any = 0;

#define KIWI_ACC_I16_AVX512(OFF) do { \
      any |= (uint64_t)_mm512_cmpeq_epi16_mask(_mm512_loadu_si512((const void*)(items + idx + (OFF))), needle); \
    } while (0)

    KIWI_ACC_I16_AVX512(0); KIWI_ACC_I16_AVX512(32); KIWI_ACC_I16_AVX512(64); KIWI_ACC_I16_AVX512(96);
    KIWI_ACC_I16_AVX512(128); KIWI_ACC_I16_AVX512(160); KIWI_ACC_I16_AVX512(192); KIWI_ACC_I16_AVX512(224);

#undef KIWI_ACC_I16_AVX512

    if (any != 0) {
      return idx + kiwi_host_find_i16_avx512_block(items + idx, 256, needle, query);
    }
    idx += 256;
  }
  return idx + kiwi_host_find_i16_avx512_block(items + idx, len - idx, needle, query);
}

static size_t kiwi_host_find_i32_avx512_block(const int32_t* items, size_t len, __m512i needle, int32_t query) {
  size_t idx = 0;
  while (len - idx >= 16) {
    const uint64_t mask = (uint64_t)_mm512_cmpeq_epi32_mask(_mm512_loadu_si512((const void*)(items + idx)), needle);
    if (mask != 0) {
      return idx + kiwi_avx512_ctz64(mask);
    }
    idx += 16;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_i32_avx512(const int32_t* items, size_t len, int32_t query) {
  const __m512i needle = _mm512_set1_epi32(query);
  size_t idx = 0;
  while (len - idx >= 128) {
    uint64_t any = 0;

#define KIWI_ACC_I32_AVX512(OFF) do { \
      any |= (uint64_t)_mm512_cmpeq_epi32_mask(_mm512_loadu_si512((const void*)(items + idx + (OFF))), needle); \
    } while (0)

    KIWI_ACC_I32_AVX512(0); KIWI_ACC_I32_AVX512(16); KIWI_ACC_I32_AVX512(32); KIWI_ACC_I32_AVX512(48);
    KIWI_ACC_I32_AVX512(64); KIWI_ACC_I32_AVX512(80); KIWI_ACC_I32_AVX512(96); KIWI_ACC_I32_AVX512(112);

#undef KIWI_ACC_I32_AVX512

    if (any != 0) {
      return idx + kiwi_host_find_i32_avx512_block(items + idx, 128, needle, query);
    }
    idx += 128;
  }
  return idx + kiwi_host_find_i32_avx512_block(items + idx, len - idx, needle, query);
}

static size_t kiwi_host_find_i64_avx512_block(const int64_t* items, size_t len, __m512i needle, int64_t query) {
  size_t idx = 0;
  while (len - idx >= 8) {
    const uint64_t mask = (uint64_t)_mm512_cmpeq_epi64_mask(_mm512_loadu_si512((const void*)(items + idx)), needle);
    if (mask != 0) {
      return idx + kiwi_avx512_ctz64(mask);
    }
    idx += 8;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_i64_avx512(const int64_t* items, size_t len, int64_t query) {
  const __m512i needle = _mm512_set1_epi64(query);
  size_t idx = 0;
  while (len - idx >= 64) {
    uint64_t any = 0;

#define KIWI_ACC_I64_AVX512(OFF) do { \
      any |= (uint64_t)_mm512_cmpeq_epi64_mask(_mm512_loadu_si512((const void*)(items + idx + (OFF))), needle); \
    } while (0)

    KIWI_ACC_I64_AVX512(0); KIWI_ACC_I64_AVX512(8); KIWI_ACC_I64_AVX512(16); KIWI_ACC_I64_AVX512(24);
    KIWI_ACC_I64_AVX512(32); KIWI_ACC_I64_AVX512(40); KIWI_ACC_I64_AVX512(48); KIWI_ACC_I64_AVX512(56);

#undef KIWI_ACC_I64_AVX512

    if (any != 0) {
      return idx + kiwi_host_find_i64_avx512_block(items + idx, 64, needle, query);
    }
    idx += 64;
  }
  return idx + kiwi_host_find_i64_avx512_block(items + idx, len - idx, needle, query);
}

static size_t kiwi_host_find_f64_avx512_block(const double* items, size_t len, __m512d needle, double query) {
  size_t idx = 0;
  while (len - idx >= 8) {
    const uint64_t mask = (uint64_t)_mm512_cmp_pd_mask(_mm512_loadu_pd(items + idx), needle, _CMP_EQ_OQ);
    if (mask != 0) {
      return idx + kiwi_avx512_ctz64(mask);
    }
    idx += 8;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_f64_avx512(const double* items, size_t len, double query) {
  const __m512d needle = _mm512_set1_pd(query);
  size_t idx = 0;
  while (len - idx >= 64) {
    uint64_t any = 0;

#define KIWI_ACC_F64_AVX512(OFF) do { \
      any |= (uint64_t)_mm512_cmp_pd_mask(_mm512_loadu_pd(items + idx + (OFF)), needle, _CMP_EQ_OQ); \
    } while (0)

    KIWI_ACC_F64_AVX512(0); KIWI_ACC_F64_AVX512(8); KIWI_ACC_F64_AVX512(16); KIWI_ACC_F64_AVX512(24);
    KIWI_ACC_F64_AVX512(32); KIWI_ACC_F64_AVX512(40); KIWI_ACC_F64_AVX512(48); KIWI_ACC_F64_AVX512(56);

#undef KIWI_ACC_F64_AVX512

    if (any != 0) {
      return idx + kiwi_host_find_f64_avx512_block(items + idx, 64, needle, query);
    }
    idx += 64;
  }
  return idx + kiwi_host_find_f64_avx512_block(items + idx, len - idx, needle, query);
}

#if defined(__clang__)
#pragma clang attribute pop
#endif
#endif
