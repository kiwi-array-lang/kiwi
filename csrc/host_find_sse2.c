#include "host_find.h"

#if defined(__x86_64__) || defined(_M_X64)
#include <emmintrin.h>

#if defined(_MSC_VER)
#include <intrin.h>
static unsigned kiwi_sse2_ctz32(unsigned mask) {
  unsigned long idx = 0;
  _BitScanForward(&idx, mask);
  return (unsigned)idx;
}
#else
static unsigned kiwi_sse2_ctz32(unsigned mask) {
  return (unsigned)__builtin_ctz(mask);
}
#endif

static __m128i kiwi_sse2_cmpeq_epi64(__m128i values, __m128i needle) {
  const __m128i eq32 = _mm_cmpeq_epi32(values, needle);
  const __m128i swapped = _mm_shuffle_epi32(eq32, _MM_SHUFFLE(2, 3, 0, 1));
  return _mm_and_si128(eq32, swapped);
}

static size_t kiwi_host_find_i8_sse2_block(const int8_t* items, size_t len, __m128i needle, int8_t query) {
  size_t idx = 0;
  while (len - idx >= 16) {
    const int mask = _mm_movemask_epi8(_mm_cmpeq_epi8(_mm_loadu_si128((const __m128i*)(const void*)(items + idx)), needle));
    if (mask != 0) {
      return idx + kiwi_sse2_ctz32((unsigned)mask);
    }
    idx += 16;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_i8_sse2(const int8_t* items, size_t len, int8_t query) {
  const __m128i needle = _mm_set1_epi8(query);
  size_t idx = 0;
  while (len - idx >= 512) {
    __m128i any = _mm_setzero_si128();

#define KIWI_ACC_I8_SSE2(OFF) do { \
      any = _mm_or_si128(any, _mm_cmpeq_epi8(_mm_loadu_si128((const __m128i*)(const void*)(items + idx + (OFF))), needle)); \
    } while (0)

    KIWI_ACC_I8_SSE2(0); KIWI_ACC_I8_SSE2(16); KIWI_ACC_I8_SSE2(32); KIWI_ACC_I8_SSE2(48);
    KIWI_ACC_I8_SSE2(64); KIWI_ACC_I8_SSE2(80); KIWI_ACC_I8_SSE2(96); KIWI_ACC_I8_SSE2(112);
    KIWI_ACC_I8_SSE2(128); KIWI_ACC_I8_SSE2(144); KIWI_ACC_I8_SSE2(160); KIWI_ACC_I8_SSE2(176);
    KIWI_ACC_I8_SSE2(192); KIWI_ACC_I8_SSE2(208); KIWI_ACC_I8_SSE2(224); KIWI_ACC_I8_SSE2(240);
    KIWI_ACC_I8_SSE2(256); KIWI_ACC_I8_SSE2(272); KIWI_ACC_I8_SSE2(288); KIWI_ACC_I8_SSE2(304);
    KIWI_ACC_I8_SSE2(320); KIWI_ACC_I8_SSE2(336); KIWI_ACC_I8_SSE2(352); KIWI_ACC_I8_SSE2(368);
    KIWI_ACC_I8_SSE2(384); KIWI_ACC_I8_SSE2(400); KIWI_ACC_I8_SSE2(416); KIWI_ACC_I8_SSE2(432);
    KIWI_ACC_I8_SSE2(448); KIWI_ACC_I8_SSE2(464); KIWI_ACC_I8_SSE2(480); KIWI_ACC_I8_SSE2(496);

#undef KIWI_ACC_I8_SSE2

    if (_mm_movemask_epi8(any) != 0) {
      return idx + kiwi_host_find_i8_sse2_block(items + idx, 512, needle, query);
    }
    idx += 512;
  }
  return idx + kiwi_host_find_i8_sse2_block(items + idx, len - idx, needle, query);
}

static size_t kiwi_host_find_i16_sse2_block(const int16_t* items, size_t len, __m128i needle, int16_t query) {
  size_t idx = 0;
  while (len - idx >= 8) {
    const int mask = _mm_movemask_epi8(_mm_cmpeq_epi16(_mm_loadu_si128((const __m128i*)(const void*)(items + idx)), needle));
    if (mask != 0) {
      return idx + kiwi_sse2_ctz32((unsigned)mask) / 2;
    }
    idx += 8;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_i16_sse2(const int16_t* items, size_t len, int16_t query) {
  const __m128i needle = _mm_set1_epi16(query);
  size_t idx = 0;
  while (len - idx >= 256) {
    __m128i any = _mm_setzero_si128();

#define KIWI_ACC_I16_SSE2(OFF) do { \
      any = _mm_or_si128(any, _mm_cmpeq_epi16(_mm_loadu_si128((const __m128i*)(const void*)(items + idx + (OFF))), needle)); \
    } while (0)

    KIWI_ACC_I16_SSE2(0); KIWI_ACC_I16_SSE2(8); KIWI_ACC_I16_SSE2(16); KIWI_ACC_I16_SSE2(24);
    KIWI_ACC_I16_SSE2(32); KIWI_ACC_I16_SSE2(40); KIWI_ACC_I16_SSE2(48); KIWI_ACC_I16_SSE2(56);
    KIWI_ACC_I16_SSE2(64); KIWI_ACC_I16_SSE2(72); KIWI_ACC_I16_SSE2(80); KIWI_ACC_I16_SSE2(88);
    KIWI_ACC_I16_SSE2(96); KIWI_ACC_I16_SSE2(104); KIWI_ACC_I16_SSE2(112); KIWI_ACC_I16_SSE2(120);
    KIWI_ACC_I16_SSE2(128); KIWI_ACC_I16_SSE2(136); KIWI_ACC_I16_SSE2(144); KIWI_ACC_I16_SSE2(152);
    KIWI_ACC_I16_SSE2(160); KIWI_ACC_I16_SSE2(168); KIWI_ACC_I16_SSE2(176); KIWI_ACC_I16_SSE2(184);
    KIWI_ACC_I16_SSE2(192); KIWI_ACC_I16_SSE2(200); KIWI_ACC_I16_SSE2(208); KIWI_ACC_I16_SSE2(216);
    KIWI_ACC_I16_SSE2(224); KIWI_ACC_I16_SSE2(232); KIWI_ACC_I16_SSE2(240); KIWI_ACC_I16_SSE2(248);

#undef KIWI_ACC_I16_SSE2

    if (_mm_movemask_epi8(any) != 0) {
      return idx + kiwi_host_find_i16_sse2_block(items + idx, 256, needle, query);
    }
    idx += 256;
  }
  return idx + kiwi_host_find_i16_sse2_block(items + idx, len - idx, needle, query);
}

static size_t kiwi_host_find_i32_sse2_block(const int32_t* items, size_t len, __m128i needle, int32_t query) {
  size_t idx = 0;
  while (len - idx >= 4) {
    const int mask = _mm_movemask_epi8(_mm_cmpeq_epi32(_mm_loadu_si128((const __m128i*)(const void*)(items + idx)), needle));
    if (mask != 0) {
      return idx + kiwi_sse2_ctz32((unsigned)mask) / 4;
    }
    idx += 4;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_i32_sse2(const int32_t* items, size_t len, int32_t query) {
  const __m128i needle = _mm_set1_epi32(query);
  size_t idx = 0;
  while (len - idx >= 128) {
    __m128i any = _mm_setzero_si128();

#define KIWI_ACC_I32_SSE2(OFF) do { \
      any = _mm_or_si128(any, _mm_cmpeq_epi32(_mm_loadu_si128((const __m128i*)(const void*)(items + idx + (OFF))), needle)); \
    } while (0)

    KIWI_ACC_I32_SSE2(0); KIWI_ACC_I32_SSE2(4); KIWI_ACC_I32_SSE2(8); KIWI_ACC_I32_SSE2(12);
    KIWI_ACC_I32_SSE2(16); KIWI_ACC_I32_SSE2(20); KIWI_ACC_I32_SSE2(24); KIWI_ACC_I32_SSE2(28);
    KIWI_ACC_I32_SSE2(32); KIWI_ACC_I32_SSE2(36); KIWI_ACC_I32_SSE2(40); KIWI_ACC_I32_SSE2(44);
    KIWI_ACC_I32_SSE2(48); KIWI_ACC_I32_SSE2(52); KIWI_ACC_I32_SSE2(56); KIWI_ACC_I32_SSE2(60);
    KIWI_ACC_I32_SSE2(64); KIWI_ACC_I32_SSE2(68); KIWI_ACC_I32_SSE2(72); KIWI_ACC_I32_SSE2(76);
    KIWI_ACC_I32_SSE2(80); KIWI_ACC_I32_SSE2(84); KIWI_ACC_I32_SSE2(88); KIWI_ACC_I32_SSE2(92);
    KIWI_ACC_I32_SSE2(96); KIWI_ACC_I32_SSE2(100); KIWI_ACC_I32_SSE2(104); KIWI_ACC_I32_SSE2(108);
    KIWI_ACC_I32_SSE2(112); KIWI_ACC_I32_SSE2(116); KIWI_ACC_I32_SSE2(120); KIWI_ACC_I32_SSE2(124);

#undef KIWI_ACC_I32_SSE2

    if (_mm_movemask_epi8(any) != 0) {
      return idx + kiwi_host_find_i32_sse2_block(items + idx, 128, needle, query);
    }
    idx += 128;
  }
  return idx + kiwi_host_find_i32_sse2_block(items + idx, len - idx, needle, query);
}

static size_t kiwi_host_find_i64_sse2_block(const int64_t* items, size_t len, __m128i needle, int64_t query) {
  size_t idx = 0;
  while (len - idx >= 2) {
    const int mask = _mm_movemask_epi8(kiwi_sse2_cmpeq_epi64(_mm_loadu_si128((const __m128i*)(const void*)(items + idx)), needle));
    if ((mask & 0x00ff) == 0x00ff) return idx;
    if ((mask & 0xff00) == 0xff00) return idx + 1;
    idx += 2;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_i64_sse2(const int64_t* items, size_t len, int64_t query) {
  const __m128i needle = _mm_set_epi64x(query, query);
  size_t idx = 0;
  while (len - idx >= 64) {
    __m128i any = _mm_setzero_si128();

#define KIWI_ACC_I64_SSE2(OFF) do { \
      any = _mm_or_si128(any, kiwi_sse2_cmpeq_epi64(_mm_loadu_si128((const __m128i*)(const void*)(items + idx + (OFF))), needle)); \
    } while (0)

    KIWI_ACC_I64_SSE2(0); KIWI_ACC_I64_SSE2(2); KIWI_ACC_I64_SSE2(4); KIWI_ACC_I64_SSE2(6);
    KIWI_ACC_I64_SSE2(8); KIWI_ACC_I64_SSE2(10); KIWI_ACC_I64_SSE2(12); KIWI_ACC_I64_SSE2(14);
    KIWI_ACC_I64_SSE2(16); KIWI_ACC_I64_SSE2(18); KIWI_ACC_I64_SSE2(20); KIWI_ACC_I64_SSE2(22);
    KIWI_ACC_I64_SSE2(24); KIWI_ACC_I64_SSE2(26); KIWI_ACC_I64_SSE2(28); KIWI_ACC_I64_SSE2(30);
    KIWI_ACC_I64_SSE2(32); KIWI_ACC_I64_SSE2(34); KIWI_ACC_I64_SSE2(36); KIWI_ACC_I64_SSE2(38);
    KIWI_ACC_I64_SSE2(40); KIWI_ACC_I64_SSE2(42); KIWI_ACC_I64_SSE2(44); KIWI_ACC_I64_SSE2(46);
    KIWI_ACC_I64_SSE2(48); KIWI_ACC_I64_SSE2(50); KIWI_ACC_I64_SSE2(52); KIWI_ACC_I64_SSE2(54);
    KIWI_ACC_I64_SSE2(56); KIWI_ACC_I64_SSE2(58); KIWI_ACC_I64_SSE2(60); KIWI_ACC_I64_SSE2(62);

#undef KIWI_ACC_I64_SSE2

    if (_mm_movemask_epi8(any) != 0) {
      return idx + kiwi_host_find_i64_sse2_block(items + idx, 64, needle, query);
    }
    idx += 64;
  }
  return idx + kiwi_host_find_i64_sse2_block(items + idx, len - idx, needle, query);
}

static size_t kiwi_host_find_f64_sse2_block(const double* items, size_t len, __m128d needle, double query) {
  size_t idx = 0;
  while (len - idx >= 2) {
    const int mask = _mm_movemask_pd(_mm_cmpeq_pd(_mm_loadu_pd(items + idx), needle));
    if (mask != 0) {
      return idx + kiwi_sse2_ctz32((unsigned)mask);
    }
    idx += 2;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) return idx;
  }
  return len;
}

size_t kiwi_host_find_f64_sse2(const double* items, size_t len, double query) {
  const __m128d needle = _mm_set1_pd(query);
  size_t idx = 0;
  while (len - idx >= 64) {
    __m128d any = _mm_setzero_pd();

#define KIWI_ACC_F64_SSE2(OFF) do { \
      any = _mm_or_pd(any, _mm_cmpeq_pd(_mm_loadu_pd(items + idx + (OFF)), needle)); \
    } while (0)

    KIWI_ACC_F64_SSE2(0); KIWI_ACC_F64_SSE2(2); KIWI_ACC_F64_SSE2(4); KIWI_ACC_F64_SSE2(6);
    KIWI_ACC_F64_SSE2(8); KIWI_ACC_F64_SSE2(10); KIWI_ACC_F64_SSE2(12); KIWI_ACC_F64_SSE2(14);
    KIWI_ACC_F64_SSE2(16); KIWI_ACC_F64_SSE2(18); KIWI_ACC_F64_SSE2(20); KIWI_ACC_F64_SSE2(22);
    KIWI_ACC_F64_SSE2(24); KIWI_ACC_F64_SSE2(26); KIWI_ACC_F64_SSE2(28); KIWI_ACC_F64_SSE2(30);
    KIWI_ACC_F64_SSE2(32); KIWI_ACC_F64_SSE2(34); KIWI_ACC_F64_SSE2(36); KIWI_ACC_F64_SSE2(38);
    KIWI_ACC_F64_SSE2(40); KIWI_ACC_F64_SSE2(42); KIWI_ACC_F64_SSE2(44); KIWI_ACC_F64_SSE2(46);
    KIWI_ACC_F64_SSE2(48); KIWI_ACC_F64_SSE2(50); KIWI_ACC_F64_SSE2(52); KIWI_ACC_F64_SSE2(54);
    KIWI_ACC_F64_SSE2(56); KIWI_ACC_F64_SSE2(58); KIWI_ACC_F64_SSE2(60); KIWI_ACC_F64_SSE2(62);

#undef KIWI_ACC_F64_SSE2

    if (_mm_movemask_pd(any) != 0) {
      return idx + kiwi_host_find_f64_sse2_block(items + idx, 64, needle, query);
    }
    idx += 64;
  }
  return idx + kiwi_host_find_f64_sse2_block(items + idx, len - idx, needle, query);
}
#endif
