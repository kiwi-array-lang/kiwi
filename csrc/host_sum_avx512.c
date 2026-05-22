#include "host_sum.h"

#if defined(__x86_64__) || defined(_M_X64)
#include <immintrin.h>

#if defined(__clang__)
#pragma clang attribute push(__attribute__((target("avx512f,avx512bw,evex512"))), apply_to=function)
#endif

static int64_t kiwi_avx512_hsum_epi64(__m512i v) {
  int64_t tmp[8];
  _mm512_storeu_si512((void*)tmp, v);
  return tmp[0] + tmp[1] + tmp[2] + tmp[3] + tmp[4] + tmp[5] + tmp[6] + tmp[7];
}

static __m512i kiwi_avx512_signed_sad_i8(__m512i v) {
  const __m512i sign_flip = _mm512_set1_epi8((char)0x80);
  const __m512i zero = _mm512_setzero_si512();
  const __m512i correction = _mm512_set1_epi64(8 * 128);
  const __m512i biased = _mm512_xor_si512(v, sign_flip);
  return _mm512_sub_epi64(_mm512_sad_epu8(biased, zero), correction);
}

static void kiwi_avx512_accumulate_i16_pairs(__m512i pairs, __m512i* lo, __m512i* hi) {
  *lo = _mm512_add_epi64(*lo, _mm512_cvtepi32_epi64(_mm512_castsi512_si256(pairs)));
  *hi = _mm512_add_epi64(*hi, _mm512_cvtepi32_epi64(_mm512_extracti64x4_epi64(pairs, 1)));
}

static void kiwi_avx512_accumulate_i32(__m512i values, __m512i* lo, __m512i* hi) {
  *lo = _mm512_add_epi64(*lo, _mm512_cvtepi32_epi64(_mm512_castsi512_si256(values)));
  *hi = _mm512_add_epi64(*hi, _mm512_cvtepi32_epi64(_mm512_extracti64x4_epi64(values, 1)));
}

int64_t kiwi_host_sum_i8_avx512(const int8_t* items, size_t len) {
  size_t i = 0;
  __m512i acc0 = _mm512_setzero_si512();
  __m512i acc1 = _mm512_setzero_si512();
  __m512i acc2 = _mm512_setzero_si512();
  __m512i acc3 = _mm512_setzero_si512();
  for (; i + 256 <= len; i += 256) {
    acc0 = _mm512_add_epi64(acc0, kiwi_avx512_signed_sad_i8(_mm512_loadu_si512((const void*)(items + i))));
    acc1 = _mm512_add_epi64(acc1, kiwi_avx512_signed_sad_i8(_mm512_loadu_si512((const void*)(items + i + 64))));
    acc2 = _mm512_add_epi64(acc2, kiwi_avx512_signed_sad_i8(_mm512_loadu_si512((const void*)(items + i + 128))));
    acc3 = _mm512_add_epi64(acc3, kiwi_avx512_signed_sad_i8(_mm512_loadu_si512((const void*)(items + i + 192))));
  }
  for (; i + 64 <= len; i += 64) {
    acc0 = _mm512_add_epi64(acc0, kiwi_avx512_signed_sad_i8(_mm512_loadu_si512((const void*)(items + i))));
  }
  const __m512i acc = _mm512_add_epi64(_mm512_add_epi64(acc0, acc1), _mm512_add_epi64(acc2, acc3));
  int64_t total = kiwi_avx512_hsum_epi64(acc);
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i16_avx512(const int16_t* items, size_t len) {
  const __m512i ones = _mm512_set1_epi16(1);
  size_t i = 0;
  __m512i acc0 = _mm512_setzero_si512();
  __m512i acc1 = _mm512_setzero_si512();
  __m512i acc2 = _mm512_setzero_si512();
  __m512i acc3 = _mm512_setzero_si512();
  for (; i + 128 <= len; i += 128) {
    const __m512i v0 = _mm512_madd_epi16(_mm512_loadu_si512((const void*)(items + i)), ones);
    const __m512i v1 = _mm512_madd_epi16(_mm512_loadu_si512((const void*)(items + i + 32)), ones);
    const __m512i v2 = _mm512_madd_epi16(_mm512_loadu_si512((const void*)(items + i + 64)), ones);
    const __m512i v3 = _mm512_madd_epi16(_mm512_loadu_si512((const void*)(items + i + 96)), ones);
    kiwi_avx512_accumulate_i16_pairs(v0, &acc0, &acc1);
    kiwi_avx512_accumulate_i16_pairs(v1, &acc2, &acc3);
    kiwi_avx512_accumulate_i16_pairs(v2, &acc0, &acc1);
    kiwi_avx512_accumulate_i16_pairs(v3, &acc2, &acc3);
  }
  for (; i + 32 <= len; i += 32) {
    const __m512i v = _mm512_madd_epi16(_mm512_loadu_si512((const void*)(items + i)), ones);
    kiwi_avx512_accumulate_i16_pairs(v, &acc0, &acc1);
  }
  const __m512i acc = _mm512_add_epi64(_mm512_add_epi64(acc0, acc1), _mm512_add_epi64(acc2, acc3));
  int64_t total = kiwi_avx512_hsum_epi64(acc);
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i32_avx512(const int32_t* items, size_t len) {
  size_t i = 0;
  __m512i acc0 = _mm512_setzero_si512();
  __m512i acc1 = _mm512_setzero_si512();
  __m512i acc2 = _mm512_setzero_si512();
  __m512i acc3 = _mm512_setzero_si512();
  for (; i + 64 <= len; i += 64) {
    kiwi_avx512_accumulate_i32(_mm512_loadu_si512((const void*)(items + i)), &acc0, &acc1);
    kiwi_avx512_accumulate_i32(_mm512_loadu_si512((const void*)(items + i + 16)), &acc2, &acc3);
    kiwi_avx512_accumulate_i32(_mm512_loadu_si512((const void*)(items + i + 32)), &acc0, &acc1);
    kiwi_avx512_accumulate_i32(_mm512_loadu_si512((const void*)(items + i + 48)), &acc2, &acc3);
  }
  for (; i + 16 <= len; i += 16) {
    kiwi_avx512_accumulate_i32(_mm512_loadu_si512((const void*)(items + i)), &acc0, &acc1);
  }
  const __m512i acc = _mm512_add_epi64(_mm512_add_epi64(acc0, acc1), _mm512_add_epi64(acc2, acc3));
  int64_t total = kiwi_avx512_hsum_epi64(acc);
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i64_avx512(const int64_t* items, size_t len) {
  size_t i = 0;
  __m512i acc0 = _mm512_setzero_si512();
  __m512i acc1 = _mm512_setzero_si512();
  __m512i acc2 = _mm512_setzero_si512();
  __m512i acc3 = _mm512_setzero_si512();
  for (; i + 32 <= len; i += 32) {
    acc0 = _mm512_add_epi64(acc0, _mm512_loadu_si512((const void*)(items + i)));
    acc1 = _mm512_add_epi64(acc1, _mm512_loadu_si512((const void*)(items + i + 8)));
    acc2 = _mm512_add_epi64(acc2, _mm512_loadu_si512((const void*)(items + i + 16)));
    acc3 = _mm512_add_epi64(acc3, _mm512_loadu_si512((const void*)(items + i + 24)));
  }
  for (; i + 8 <= len; i += 8) {
    acc0 = _mm512_add_epi64(acc0, _mm512_loadu_si512((const void*)(items + i)));
  }
  const __m512i acc = _mm512_add_epi64(_mm512_add_epi64(acc0, acc1), _mm512_add_epi64(acc2, acc3));
  int64_t total = kiwi_avx512_hsum_epi64(acc);
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

#if defined(__clang__)
#pragma clang attribute pop
#endif
#endif
