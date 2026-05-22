#include "host_sum.h"

#if defined(__x86_64__) || defined(_M_X64)
#include <emmintrin.h>

static int64_t kiwi_sse2_hsum_epi64(__m128i v) {
  int64_t tmp[2];
  _mm_storeu_si128((__m128i*)(void*)tmp, v);
  return tmp[0] + tmp[1];
}

static __m128i kiwi_sse2_signed_sad_i8(__m128i v) {
  const __m128i sign_flip = _mm_set1_epi8((char)0x80);
  const __m128i zero = _mm_setzero_si128();
  const __m128i correction = _mm_set1_epi64x(8 * 128);
  const __m128i biased = _mm_xor_si128(v, sign_flip);
  return _mm_sub_epi64(_mm_sad_epu8(biased, zero), correction);
}

static __m128i kiwi_sse2_extendlo_epi32_to_epi64(__m128i v) {
  const __m128i sign = _mm_srai_epi32(v, 31);
  return _mm_unpacklo_epi32(v, sign);
}

static __m128i kiwi_sse2_extendhi_epi32_to_epi64(__m128i v) {
  const __m128i sign = _mm_srai_epi32(v, 31);
  return _mm_unpackhi_epi32(v, sign);
}

int64_t kiwi_host_sum_i8_sse2(const int8_t* items, size_t len) {
  size_t i = 0;
  __m128i acc0 = _mm_setzero_si128();
  __m128i acc1 = _mm_setzero_si128();
  __m128i acc2 = _mm_setzero_si128();
  __m128i acc3 = _mm_setzero_si128();
  for (; i + 64 <= len; i += 64) {
    acc0 = _mm_add_epi64(acc0, kiwi_sse2_signed_sad_i8(_mm_loadu_si128((const __m128i*)(const void*)(items + i))));
    acc1 = _mm_add_epi64(acc1, kiwi_sse2_signed_sad_i8(_mm_loadu_si128((const __m128i*)(const void*)(items + i + 16))));
    acc2 = _mm_add_epi64(acc2, kiwi_sse2_signed_sad_i8(_mm_loadu_si128((const __m128i*)(const void*)(items + i + 32))));
    acc3 = _mm_add_epi64(acc3, kiwi_sse2_signed_sad_i8(_mm_loadu_si128((const __m128i*)(const void*)(items + i + 48))));
  }
  for (; i + 16 <= len; i += 16) {
    acc0 = _mm_add_epi64(acc0, kiwi_sse2_signed_sad_i8(_mm_loadu_si128((const __m128i*)(const void*)(items + i))));
  }
  __m128i acc = _mm_add_epi64(_mm_add_epi64(acc0, acc1), _mm_add_epi64(acc2, acc3));
  int64_t total = kiwi_sse2_hsum_epi64(acc);
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i16_sse2(const int16_t* items, size_t len) {
  const __m128i ones = _mm_set1_epi16(1);
  size_t i = 0;
  __m128i acc0 = _mm_setzero_si128();
  __m128i acc1 = _mm_setzero_si128();
  __m128i acc2 = _mm_setzero_si128();
  __m128i acc3 = _mm_setzero_si128();
  for (; i + 32 <= len; i += 32) {
    const __m128i v0 = _mm_madd_epi16(_mm_loadu_si128((const __m128i*)(const void*)(items + i)), ones);
    const __m128i v1 = _mm_madd_epi16(_mm_loadu_si128((const __m128i*)(const void*)(items + i + 8)), ones);
    const __m128i v2 = _mm_madd_epi16(_mm_loadu_si128((const __m128i*)(const void*)(items + i + 16)), ones);
    const __m128i v3 = _mm_madd_epi16(_mm_loadu_si128((const __m128i*)(const void*)(items + i + 24)), ones);
    acc0 = _mm_add_epi64(acc0, kiwi_sse2_extendlo_epi32_to_epi64(v0));
    acc1 = _mm_add_epi64(acc1, kiwi_sse2_extendhi_epi32_to_epi64(v0));
    acc2 = _mm_add_epi64(acc2, kiwi_sse2_extendlo_epi32_to_epi64(v1));
    acc3 = _mm_add_epi64(acc3, kiwi_sse2_extendhi_epi32_to_epi64(v1));
    acc0 = _mm_add_epi64(acc0, kiwi_sse2_extendlo_epi32_to_epi64(v2));
    acc1 = _mm_add_epi64(acc1, kiwi_sse2_extendhi_epi32_to_epi64(v2));
    acc2 = _mm_add_epi64(acc2, kiwi_sse2_extendlo_epi32_to_epi64(v3));
    acc3 = _mm_add_epi64(acc3, kiwi_sse2_extendhi_epi32_to_epi64(v3));
  }
  for (; i + 8 <= len; i += 8) {
    const __m128i v = _mm_madd_epi16(_mm_loadu_si128((const __m128i*)(const void*)(items + i)), ones);
    acc0 = _mm_add_epi64(acc0, kiwi_sse2_extendlo_epi32_to_epi64(v));
    acc1 = _mm_add_epi64(acc1, kiwi_sse2_extendhi_epi32_to_epi64(v));
  }
  __m128i acc = _mm_add_epi64(_mm_add_epi64(acc0, acc1), _mm_add_epi64(acc2, acc3));
  int64_t total = kiwi_sse2_hsum_epi64(acc);
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i32_sse2(const int32_t* items, size_t len) {
  size_t i = 0;
  __m128i acc0 = _mm_setzero_si128();
  __m128i acc1 = _mm_setzero_si128();
  __m128i acc2 = _mm_setzero_si128();
  __m128i acc3 = _mm_setzero_si128();
  for (; i + 16 <= len; i += 16) {
    const __m128i v0 = _mm_loadu_si128((const __m128i*)(const void*)(items + i));
    const __m128i v1 = _mm_loadu_si128((const __m128i*)(const void*)(items + i + 4));
    const __m128i v2 = _mm_loadu_si128((const __m128i*)(const void*)(items + i + 8));
    const __m128i v3 = _mm_loadu_si128((const __m128i*)(const void*)(items + i + 12));
    acc0 = _mm_add_epi64(acc0, kiwi_sse2_extendlo_epi32_to_epi64(v0));
    acc1 = _mm_add_epi64(acc1, kiwi_sse2_extendhi_epi32_to_epi64(v0));
    acc2 = _mm_add_epi64(acc2, kiwi_sse2_extendlo_epi32_to_epi64(v1));
    acc3 = _mm_add_epi64(acc3, kiwi_sse2_extendhi_epi32_to_epi64(v1));
    acc0 = _mm_add_epi64(acc0, kiwi_sse2_extendlo_epi32_to_epi64(v2));
    acc1 = _mm_add_epi64(acc1, kiwi_sse2_extendhi_epi32_to_epi64(v2));
    acc2 = _mm_add_epi64(acc2, kiwi_sse2_extendlo_epi32_to_epi64(v3));
    acc3 = _mm_add_epi64(acc3, kiwi_sse2_extendhi_epi32_to_epi64(v3));
  }
  for (; i + 4 <= len; i += 4) {
    const __m128i v = _mm_loadu_si128((const __m128i*)(const void*)(items + i));
    acc0 = _mm_add_epi64(acc0, kiwi_sse2_extendlo_epi32_to_epi64(v));
    acc1 = _mm_add_epi64(acc1, kiwi_sse2_extendhi_epi32_to_epi64(v));
  }
  __m128i acc = _mm_add_epi64(_mm_add_epi64(acc0, acc1), _mm_add_epi64(acc2, acc3));
  int64_t total = kiwi_sse2_hsum_epi64(acc);
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i64_sse2(const int64_t* items, size_t len) {
  size_t i = 0;
  __m128i acc0 = _mm_setzero_si128();
  __m128i acc1 = _mm_setzero_si128();
  __m128i acc2 = _mm_setzero_si128();
  __m128i acc3 = _mm_setzero_si128();
  for (; i + 8 <= len; i += 8) {
    acc0 = _mm_add_epi64(acc0, _mm_loadu_si128((const __m128i*)(const void*)(items + i)));
    acc1 = _mm_add_epi64(acc1, _mm_loadu_si128((const __m128i*)(const void*)(items + i + 2)));
    acc2 = _mm_add_epi64(acc2, _mm_loadu_si128((const __m128i*)(const void*)(items + i + 4)));
    acc3 = _mm_add_epi64(acc3, _mm_loadu_si128((const __m128i*)(const void*)(items + i + 6)));
  }
  for (; i + 2 <= len; i += 2) {
    acc0 = _mm_add_epi64(acc0, _mm_loadu_si128((const __m128i*)(const void*)(items + i)));
  }
  __m128i acc = _mm_add_epi64(_mm_add_epi64(acc0, acc1), _mm_add_epi64(acc2, acc3));
  int64_t total = kiwi_sse2_hsum_epi64(acc);
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}
#endif
