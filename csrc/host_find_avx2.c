#include "host_find.h"

#if defined(__x86_64__) || defined(_M_X64)
#include <immintrin.h>

#if defined(__clang__)
#pragma clang attribute push(__attribute__((target("avx2"))), apply_to=function)
#endif

#if defined(_MSC_VER)
#include <intrin.h>
static unsigned kiwi_avx2_ctz32(unsigned mask) {
  unsigned long idx = 0;
  _BitScanForward(&idx, mask);
  return (unsigned)idx;
}
#else
static unsigned kiwi_avx2_ctz32(unsigned mask) {
  return (unsigned)__builtin_ctz(mask);
}
#endif

static size_t kiwi_host_find_i8_avx2_block(const int8_t* items, size_t len, __m256i needle, int8_t query) {
  size_t idx = 0;
  while (len - idx >= 32) {
    const int mask = _mm256_movemask_epi8(_mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i*)(const void*)(items + idx)), needle));
    if (mask != 0) {
      return idx + kiwi_avx2_ctz32((unsigned)mask);
    }
    idx += 32;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_i8_avx2(const int8_t* items, size_t len, int8_t query) {
  const __m256i needle = _mm256_set1_epi8(query);
  size_t idx = 0;
  while (len - idx >= 512) {
    __m256i any = _mm256_setzero_si256();

#define KIWI_ACC_I8_AVX2(OFF) do { \
      any = _mm256_or_si256(any, _mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i*)(const void*)(items + idx + (OFF))), needle)); \
    } while (0)

    KIWI_ACC_I8_AVX2(0); KIWI_ACC_I8_AVX2(32); KIWI_ACC_I8_AVX2(64); KIWI_ACC_I8_AVX2(96);
    KIWI_ACC_I8_AVX2(128); KIWI_ACC_I8_AVX2(160); KIWI_ACC_I8_AVX2(192); KIWI_ACC_I8_AVX2(224);
    KIWI_ACC_I8_AVX2(256); KIWI_ACC_I8_AVX2(288); KIWI_ACC_I8_AVX2(320); KIWI_ACC_I8_AVX2(352);
    KIWI_ACC_I8_AVX2(384); KIWI_ACC_I8_AVX2(416); KIWI_ACC_I8_AVX2(448); KIWI_ACC_I8_AVX2(480);

#undef KIWI_ACC_I8_AVX2

    if (_mm256_movemask_epi8(any) != 0) {
      return idx + kiwi_host_find_i8_avx2_block(items + idx, 512, needle, query);
    }
    idx += 512;
  }
  return idx + kiwi_host_find_i8_avx2_block(items + idx, len - idx, needle, query);
}

static size_t kiwi_host_find_i16_avx2_block(const int16_t* items, size_t len, __m256i needle, int16_t query) {
  size_t idx = 0;
  while (len - idx >= 16) {
    const int mask = _mm256_movemask_epi8(_mm256_cmpeq_epi16(_mm256_loadu_si256((const __m256i*)(const void*)(items + idx)), needle));
    if (mask != 0) {
      return idx + kiwi_avx2_ctz32((unsigned)mask) / 2;
    }
    idx += 16;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_i16_avx2(const int16_t* items, size_t len, int16_t query) {
  const __m256i needle = _mm256_set1_epi16(query);
  size_t idx = 0;
  while (len - idx >= 256) {
    __m256i any = _mm256_setzero_si256();

#define KIWI_ACC_I16_AVX2(OFF) do { \
      any = _mm256_or_si256(any, _mm256_cmpeq_epi16(_mm256_loadu_si256((const __m256i*)(const void*)(items + idx + (OFF))), needle)); \
    } while (0)

    KIWI_ACC_I16_AVX2(0); KIWI_ACC_I16_AVX2(16); KIWI_ACC_I16_AVX2(32); KIWI_ACC_I16_AVX2(48);
    KIWI_ACC_I16_AVX2(64); KIWI_ACC_I16_AVX2(80); KIWI_ACC_I16_AVX2(96); KIWI_ACC_I16_AVX2(112);
    KIWI_ACC_I16_AVX2(128); KIWI_ACC_I16_AVX2(144); KIWI_ACC_I16_AVX2(160); KIWI_ACC_I16_AVX2(176);
    KIWI_ACC_I16_AVX2(192); KIWI_ACC_I16_AVX2(208); KIWI_ACC_I16_AVX2(224); KIWI_ACC_I16_AVX2(240);

#undef KIWI_ACC_I16_AVX2

    if (_mm256_movemask_epi8(any) != 0) {
      return idx + kiwi_host_find_i16_avx2_block(items + idx, 256, needle, query);
    }
    idx += 256;
  }
  return idx + kiwi_host_find_i16_avx2_block(items + idx, len - idx, needle, query);
}

static size_t kiwi_host_find_i32_avx2_block(const int32_t* items, size_t len, __m256i needle, int32_t query) {
  size_t idx = 0;
  while (len - idx >= 8) {
    const int mask = _mm256_movemask_epi8(_mm256_cmpeq_epi32(_mm256_loadu_si256((const __m256i*)(const void*)(items + idx)), needle));
    if (mask != 0) {
      return idx + kiwi_avx2_ctz32((unsigned)mask) / 4;
    }
    idx += 8;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_i32_avx2(const int32_t* items, size_t len, int32_t query) {
  const __m256i needle = _mm256_set1_epi32(query);
  size_t idx = 0;
  while (len - idx >= 128) {
    __m256i any = _mm256_setzero_si256();

#define KIWI_ACC_I32_AVX2(OFF) do { \
      any = _mm256_or_si256(any, _mm256_cmpeq_epi32(_mm256_loadu_si256((const __m256i*)(const void*)(items + idx + (OFF))), needle)); \
    } while (0)

    KIWI_ACC_I32_AVX2(0); KIWI_ACC_I32_AVX2(8); KIWI_ACC_I32_AVX2(16); KIWI_ACC_I32_AVX2(24);
    KIWI_ACC_I32_AVX2(32); KIWI_ACC_I32_AVX2(40); KIWI_ACC_I32_AVX2(48); KIWI_ACC_I32_AVX2(56);
    KIWI_ACC_I32_AVX2(64); KIWI_ACC_I32_AVX2(72); KIWI_ACC_I32_AVX2(80); KIWI_ACC_I32_AVX2(88);
    KIWI_ACC_I32_AVX2(96); KIWI_ACC_I32_AVX2(104); KIWI_ACC_I32_AVX2(112); KIWI_ACC_I32_AVX2(120);

#undef KIWI_ACC_I32_AVX2

    if (_mm256_movemask_epi8(any) != 0) {
      return idx + kiwi_host_find_i32_avx2_block(items + idx, 128, needle, query);
    }
    idx += 128;
  }
  return idx + kiwi_host_find_i32_avx2_block(items + idx, len - idx, needle, query);
}

static size_t kiwi_host_find_i64_avx2_block(const int64_t* items, size_t len, __m256i needle, int64_t query) {
  size_t idx = 0;
  while (len - idx >= 4) {
    const int mask = _mm256_movemask_epi8(_mm256_cmpeq_epi64(_mm256_loadu_si256((const __m256i*)(const void*)(items + idx)), needle));
    if (mask != 0) {
      return idx + kiwi_avx2_ctz32((unsigned)mask) / 8;
    }
    idx += 4;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_i64_avx2(const int64_t* items, size_t len, int64_t query) {
  const __m256i needle = _mm256_set1_epi64x(query);
  size_t idx = 0;
  while (len - idx >= 64) {
    __m256i any = _mm256_setzero_si256();

#define KIWI_ACC_I64_AVX2(OFF) do { \
      any = _mm256_or_si256(any, _mm256_cmpeq_epi64(_mm256_loadu_si256((const __m256i*)(const void*)(items + idx + (OFF))), needle)); \
    } while (0)

    KIWI_ACC_I64_AVX2(0); KIWI_ACC_I64_AVX2(4); KIWI_ACC_I64_AVX2(8); KIWI_ACC_I64_AVX2(12);
    KIWI_ACC_I64_AVX2(16); KIWI_ACC_I64_AVX2(20); KIWI_ACC_I64_AVX2(24); KIWI_ACC_I64_AVX2(28);
    KIWI_ACC_I64_AVX2(32); KIWI_ACC_I64_AVX2(36); KIWI_ACC_I64_AVX2(40); KIWI_ACC_I64_AVX2(44);
    KIWI_ACC_I64_AVX2(48); KIWI_ACC_I64_AVX2(52); KIWI_ACC_I64_AVX2(56); KIWI_ACC_I64_AVX2(60);

#undef KIWI_ACC_I64_AVX2

    if (_mm256_movemask_epi8(any) != 0) {
      return idx + kiwi_host_find_i64_avx2_block(items + idx, 64, needle, query);
    }
    idx += 64;
  }
  return idx + kiwi_host_find_i64_avx2_block(items + idx, len - idx, needle, query);
}

static size_t kiwi_host_find_f64_avx2_block(const double* items, size_t len, __m256d needle, double query) {
  size_t idx = 0;
  while (len - idx >= 4) {
    const int mask = _mm256_movemask_pd(_mm256_cmp_pd(_mm256_loadu_pd(items + idx), needle, _CMP_EQ_OQ));
    if (mask != 0) {
      return idx + kiwi_avx2_ctz32((unsigned)mask);
    }
    idx += 4;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_f64_avx2(const double* items, size_t len, double query) {
  const __m256d needle = _mm256_set1_pd(query);
  size_t idx = 0;
  while (len - idx >= 64) {
    __m256d any = _mm256_setzero_pd();

#define KIWI_ACC_F64_AVX2(OFF) do { \
      any = _mm256_or_pd(any, _mm256_cmp_pd(_mm256_loadu_pd(items + idx + (OFF)), needle, _CMP_EQ_OQ)); \
    } while (0)

    KIWI_ACC_F64_AVX2(0); KIWI_ACC_F64_AVX2(4); KIWI_ACC_F64_AVX2(8); KIWI_ACC_F64_AVX2(12);
    KIWI_ACC_F64_AVX2(16); KIWI_ACC_F64_AVX2(20); KIWI_ACC_F64_AVX2(24); KIWI_ACC_F64_AVX2(28);
    KIWI_ACC_F64_AVX2(32); KIWI_ACC_F64_AVX2(36); KIWI_ACC_F64_AVX2(40); KIWI_ACC_F64_AVX2(44);
    KIWI_ACC_F64_AVX2(48); KIWI_ACC_F64_AVX2(52); KIWI_ACC_F64_AVX2(56); KIWI_ACC_F64_AVX2(60);

#undef KIWI_ACC_F64_AVX2

    if (_mm256_movemask_pd(any) != 0) {
      return idx + kiwi_host_find_f64_avx2_block(items + idx, 64, needle, query);
    }
    idx += 64;
  }
  return idx + kiwi_host_find_f64_avx2_block(items + idx, len - idx, needle, query);
}

#if defined(__clang__)
#pragma clang attribute pop
#endif
#endif
