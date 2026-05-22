#include "host_sum.h"

#if defined(__x86_64__) || defined(_M_X64)
#include <immintrin.h>

#if defined(__clang__)
#pragma clang attribute push(__attribute__((target("avx2"))), apply_to=function)
#endif

static int64_t kiwi_avx2_hsum_epi64(__m256i v) {
  int64_t tmp[4];
  _mm256_storeu_si256((__m256i*)(void*)tmp, v);
  return tmp[0] + tmp[1] + tmp[2] + tmp[3];
}

static __m256i kiwi_avx2_signed_sad_i8(__m256i v) {
  const __m256i sign_flip = _mm256_set1_epi8((char)0x80);
  const __m256i zero = _mm256_setzero_si256();
  const __m256i correction = _mm256_set1_epi64x(8 * 128);
  const __m256i biased = _mm256_xor_si256(v, sign_flip);
  return _mm256_sub_epi64(_mm256_sad_epu8(biased, zero), correction);
}

static void kiwi_avx2_accumulate_i16_pairs(__m256i pairs, __m256i* lo, __m256i* hi) {
  *lo = _mm256_add_epi64(*lo, _mm256_cvtepi32_epi64(_mm256_castsi256_si128(pairs)));
  *hi = _mm256_add_epi64(*hi, _mm256_cvtepi32_epi64(_mm256_extracti128_si256(pairs, 1)));
}

static void kiwi_avx2_accumulate_i32(__m256i values, __m256i* lo, __m256i* hi) {
  *lo = _mm256_add_epi64(*lo, _mm256_cvtepi32_epi64(_mm256_castsi256_si128(values)));
  *hi = _mm256_add_epi64(*hi, _mm256_cvtepi32_epi64(_mm256_extracti128_si256(values, 1)));
}

int64_t kiwi_host_sum_i8_avx2(const int8_t* items, size_t len) {
  size_t i = 0;
  __m256i acc0 = _mm256_setzero_si256();
  __m256i acc1 = _mm256_setzero_si256();
  __m256i acc2 = _mm256_setzero_si256();
  __m256i acc3 = _mm256_setzero_si256();
  for (; i + 128 <= len; i += 128) {
    acc0 = _mm256_add_epi64(acc0, kiwi_avx2_signed_sad_i8(_mm256_loadu_si256((const __m256i*)(const void*)(items + i))));
    acc1 = _mm256_add_epi64(acc1, kiwi_avx2_signed_sad_i8(_mm256_loadu_si256((const __m256i*)(const void*)(items + i + 32))));
    acc2 = _mm256_add_epi64(acc2, kiwi_avx2_signed_sad_i8(_mm256_loadu_si256((const __m256i*)(const void*)(items + i + 64))));
    acc3 = _mm256_add_epi64(acc3, kiwi_avx2_signed_sad_i8(_mm256_loadu_si256((const __m256i*)(const void*)(items + i + 96))));
  }
  for (; i + 32 <= len; i += 32) {
    acc0 = _mm256_add_epi64(acc0, kiwi_avx2_signed_sad_i8(_mm256_loadu_si256((const __m256i*)(const void*)(items + i))));
  }
  const __m256i acc = _mm256_add_epi64(_mm256_add_epi64(acc0, acc1), _mm256_add_epi64(acc2, acc3));
  int64_t total = kiwi_avx2_hsum_epi64(acc);
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i16_avx2(const int16_t* items, size_t len) {
  const __m256i ones = _mm256_set1_epi16(1);
  size_t i = 0;
  __m256i acc0 = _mm256_setzero_si256();
  __m256i acc1 = _mm256_setzero_si256();
  __m256i acc2 = _mm256_setzero_si256();
  __m256i acc3 = _mm256_setzero_si256();
  for (; i + 64 <= len; i += 64) {
    const __m256i v0 = _mm256_madd_epi16(_mm256_loadu_si256((const __m256i*)(const void*)(items + i)), ones);
    const __m256i v1 = _mm256_madd_epi16(_mm256_loadu_si256((const __m256i*)(const void*)(items + i + 16)), ones);
    const __m256i v2 = _mm256_madd_epi16(_mm256_loadu_si256((const __m256i*)(const void*)(items + i + 32)), ones);
    const __m256i v3 = _mm256_madd_epi16(_mm256_loadu_si256((const __m256i*)(const void*)(items + i + 48)), ones);
    kiwi_avx2_accumulate_i16_pairs(v0, &acc0, &acc1);
    kiwi_avx2_accumulate_i16_pairs(v1, &acc2, &acc3);
    kiwi_avx2_accumulate_i16_pairs(v2, &acc0, &acc1);
    kiwi_avx2_accumulate_i16_pairs(v3, &acc2, &acc3);
  }
  for (; i + 16 <= len; i += 16) {
    const __m256i v = _mm256_madd_epi16(_mm256_loadu_si256((const __m256i*)(const void*)(items + i)), ones);
    kiwi_avx2_accumulate_i16_pairs(v, &acc0, &acc1);
  }
  const __m256i acc = _mm256_add_epi64(_mm256_add_epi64(acc0, acc1), _mm256_add_epi64(acc2, acc3));
  int64_t total = kiwi_avx2_hsum_epi64(acc);
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i32_avx2(const int32_t* items, size_t len) {
  size_t i = 0;
  __m256i acc0 = _mm256_setzero_si256();
  __m256i acc1 = _mm256_setzero_si256();
  __m256i acc2 = _mm256_setzero_si256();
  __m256i acc3 = _mm256_setzero_si256();
  for (; i + 32 <= len; i += 32) {
    kiwi_avx2_accumulate_i32(_mm256_loadu_si256((const __m256i*)(const void*)(items + i)), &acc0, &acc1);
    kiwi_avx2_accumulate_i32(_mm256_loadu_si256((const __m256i*)(const void*)(items + i + 8)), &acc2, &acc3);
    kiwi_avx2_accumulate_i32(_mm256_loadu_si256((const __m256i*)(const void*)(items + i + 16)), &acc0, &acc1);
    kiwi_avx2_accumulate_i32(_mm256_loadu_si256((const __m256i*)(const void*)(items + i + 24)), &acc2, &acc3);
  }
  for (; i + 8 <= len; i += 8) {
    kiwi_avx2_accumulate_i32(_mm256_loadu_si256((const __m256i*)(const void*)(items + i)), &acc0, &acc1);
  }
  const __m256i acc = _mm256_add_epi64(_mm256_add_epi64(acc0, acc1), _mm256_add_epi64(acc2, acc3));
  int64_t total = kiwi_avx2_hsum_epi64(acc);
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i64_avx2(const int64_t* items, size_t len) {
  size_t i = 0;
  __m256i acc0 = _mm256_setzero_si256();
  __m256i acc1 = _mm256_setzero_si256();
  __m256i acc2 = _mm256_setzero_si256();
  __m256i acc3 = _mm256_setzero_si256();
  for (; i + 16 <= len; i += 16) {
    acc0 = _mm256_add_epi64(acc0, _mm256_loadu_si256((const __m256i*)(const void*)(items + i)));
    acc1 = _mm256_add_epi64(acc1, _mm256_loadu_si256((const __m256i*)(const void*)(items + i + 4)));
    acc2 = _mm256_add_epi64(acc2, _mm256_loadu_si256((const __m256i*)(const void*)(items + i + 8)));
    acc3 = _mm256_add_epi64(acc3, _mm256_loadu_si256((const __m256i*)(const void*)(items + i + 12)));
  }
  for (; i + 4 <= len; i += 4) {
    acc0 = _mm256_add_epi64(acc0, _mm256_loadu_si256((const __m256i*)(const void*)(items + i)));
  }
  const __m256i acc = _mm256_add_epi64(_mm256_add_epi64(acc0, acc1), _mm256_add_epi64(acc2, acc3));
  int64_t total = kiwi_avx2_hsum_epi64(acc);
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

#if defined(__clang__)
#pragma clang attribute pop
#endif
#endif
