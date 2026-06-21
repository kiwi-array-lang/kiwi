#include <stddef.h>
#include <stdint.h>
#include <string.h>

#if defined(__x86_64__) || defined(_M_X64)
#include <emmintrin.h>

static uint16_t kiwi_host_where_i16_offsets8_sse2[256][8];
static uint32_t kiwi_host_where_i32_offsets8_sse2[256][8];
static uint8_t kiwi_host_where_pop8_sse2[256];

__attribute__((constructor))
static void kiwi_host_where_sse2_tables_constructor(void) {
  for (unsigned mask = 0; mask < 256u; ++mask) {
    unsigned out = 0;
    for (unsigned lane = 0; lane < 8u; ++lane) {
      if (((mask >> lane) & 1u) == 0u) continue;
      kiwi_host_where_i16_offsets8_sse2[mask][out] = (uint16_t)lane;
      kiwi_host_where_i32_offsets8_sse2[mask][out++] = lane;
    }
    kiwi_host_where_pop8_sse2[mask] = (uint8_t)out;
    while (out < 8u) {
      kiwi_host_where_i16_offsets8_sse2[mask][out] = 0u;
      kiwi_host_where_i32_offsets8_sse2[mask][out++] = 0u;
    }
  }
}

size_t kiwi_host_where_i16_sse2(
    int16_t* dst,
    size_t dst_len,
    const uint64_t* mask_words,
    size_t mask_len) {
  size_t out_idx = 0;
  const uint8_t* mask_bytes = (const uint8_t*)mask_words;
  const size_t byte_count = (mask_len + 7u) / 8u;
  for (size_t byte_idx = 0; byte_idx < byte_count; ++byte_idx) {
    const uint8_t mask_byte = mask_bytes[byte_idx];
    const unsigned count = kiwi_host_where_pop8_sse2[mask_byte];
    if (count == 0u) continue;

    const __m128i base = _mm_set1_epi16((int16_t)(byte_idx * 8u));
    const __m128i offsets = _mm_loadu_si128((const __m128i*)(const void*)kiwi_host_where_i16_offsets8_sse2[mask_byte]);
    const __m128i values = _mm_add_epi16(base, offsets);
    if (out_idx + 8u <= dst_len) {
      _mm_storeu_si128((__m128i*)(void*)(dst + out_idx), values);
    } else {
      int16_t tmp[8];
      _mm_storeu_si128((__m128i*)(void*)tmp, values);
      memcpy(dst + out_idx, tmp, (size_t)count * sizeof(int16_t));
    }
    out_idx += count;
  }
  return out_idx;
}

static uint8_t kiwi_host_where_active_byte_mask(size_t mask_len, size_t byte_idx) {
  const size_t remaining = mask_len - byte_idx * 8u;
  const size_t active = remaining < 8u ? remaining : 8u;
  return active >= 8u ? 0xffu : (uint8_t)((1u << active) - 1u);
}

static void kiwi_host_where_i16_sse2_byte(
    int16_t* dst,
    size_t dst_len,
    size_t* out_idx,
    uint16_t base_value,
    uint8_t mask_byte) {
  const unsigned count = kiwi_host_where_pop8_sse2[mask_byte];
  if (count == 0u) return;

  const __m128i base = _mm_set1_epi16((int16_t)base_value);
  const __m128i offsets = _mm_loadu_si128((const __m128i*)(const void*)kiwi_host_where_i16_offsets8_sse2[mask_byte]);
  const __m128i values = _mm_add_epi16(base, offsets);
  if (*out_idx + 8u <= dst_len) {
    _mm_storeu_si128((__m128i*)(void*)(dst + *out_idx), values);
  } else {
    int16_t tmp[8];
    _mm_storeu_si128((__m128i*)(void*)tmp, values);
    memcpy(dst + *out_idx, tmp, (size_t)count * sizeof(int16_t));
  }
  *out_idx += count;
}

size_t kiwi_host_where_not_i16_sse2(
    int16_t* dst,
    size_t dst_len,
    const uint64_t* mask_words,
    size_t mask_len) {
  size_t out_idx = 0;
  const uint8_t* mask_bytes = (const uint8_t*)mask_words;
  const size_t byte_count = (mask_len + 7u) / 8u;
  for (size_t byte_idx = 0; byte_idx < byte_count; ++byte_idx) {
    const uint8_t mask_byte = (uint8_t)(~mask_bytes[byte_idx]) & kiwi_host_where_active_byte_mask(mask_len, byte_idx);
    const unsigned count = kiwi_host_where_pop8_sse2[mask_byte];
    if (count == 0u) continue;

    const __m128i base = _mm_set1_epi16((int16_t)(byte_idx * 8u));
    const __m128i offsets = _mm_loadu_si128((const __m128i*)(const void*)kiwi_host_where_i16_offsets8_sse2[mask_byte]);
    const __m128i values = _mm_add_epi16(base, offsets);
    if (out_idx + 8u <= dst_len) {
      _mm_storeu_si128((__m128i*)(void*)(dst + out_idx), values);
    } else {
      int16_t tmp[8];
      _mm_storeu_si128((__m128i*)(void*)tmp, values);
      memcpy(dst + out_idx, tmp, (size_t)count * sizeof(int16_t));
    }
    out_idx += count;
  }
  return out_idx;
}

static void kiwi_host_where_i32_sse2_byte(
    int32_t* dst,
    size_t dst_len,
    size_t* out_idx,
    uint32_t base_value,
    uint8_t mask_byte) {
  const unsigned count = kiwi_host_where_pop8_sse2[mask_byte];
  if (count == 0u) return;

  const __m128i base = _mm_set1_epi32((int32_t)base_value);
  const __m128i values0 = _mm_add_epi32(
      base,
      _mm_loadu_si128((const __m128i*)(const void*)kiwi_host_where_i32_offsets8_sse2[mask_byte]));
  const __m128i values1 = _mm_add_epi32(
      base,
      _mm_loadu_si128((const __m128i*)(const void*)(kiwi_host_where_i32_offsets8_sse2[mask_byte] + 4u)));
  if (*out_idx + 8u <= dst_len) {
    _mm_storeu_si128((__m128i*)(void*)(dst + *out_idx), values0);
    _mm_storeu_si128((__m128i*)(void*)(dst + *out_idx + 4u), values1);
  } else {
    int32_t tmp[8];
    _mm_storeu_si128((__m128i*)(void*)tmp, values0);
    _mm_storeu_si128((__m128i*)(void*)(tmp + 4u), values1);
    memcpy(dst + *out_idx, tmp, (size_t)count * sizeof(int32_t));
  }
  *out_idx += count;
}

size_t kiwi_host_where_i32_sse2(
    int32_t* dst,
    size_t dst_len,
    const uint64_t* mask_words,
    size_t mask_len) {
  size_t out_idx = 0;
  const uint8_t* mask_bytes = (const uint8_t*)mask_words;
  const size_t byte_count = (mask_len + 7u) / 8u;
  for (size_t byte_idx = 0; byte_idx < byte_count; ++byte_idx) {
    const uint8_t mask_byte = mask_bytes[byte_idx];
    if (mask_byte == 0u) continue;
    kiwi_host_where_i32_sse2_byte(dst, dst_len, &out_idx, (uint32_t)(byte_idx * 8u), mask_byte);
  }
  return out_idx;
}

size_t kiwi_host_where_not_i32_sse2(
    int32_t* dst,
    size_t dst_len,
    const uint64_t* mask_words,
    size_t mask_len) {
  size_t out_idx = 0;
  const uint8_t* mask_bytes = (const uint8_t*)mask_words;
  const size_t byte_count = (mask_len + 7u) / 8u;
  for (size_t byte_idx = 0; byte_idx < byte_count; ++byte_idx) {
    const uint8_t mask_byte = (uint8_t)(~mask_bytes[byte_idx]) & kiwi_host_where_active_byte_mask(mask_len, byte_idx);
    if (mask_byte == 0u) continue;
    kiwi_host_where_i32_sse2_byte(dst, dst_len, &out_idx, (uint32_t)(byte_idx * 8u), mask_byte);
  }
  return out_idx;
}

size_t kiwi_host_grade_bool_i16_sse2(
    int16_t* dst,
    size_t dst_len,
    const uint64_t* mask_words,
    size_t mask_len,
    size_t count_one,
    int ascending) {
  const size_t count_zero = mask_len - count_one;
  size_t zero_pos = ascending ? 0u : count_one;
  size_t one_pos = ascending ? count_zero : 0u;
  const size_t zero_limit = ascending ? count_zero : dst_len;
  const size_t one_limit = ascending ? dst_len : count_one;
  const uint8_t* mask_bytes = (const uint8_t*)mask_words;
  const size_t byte_count = (mask_len + 7u) / 8u;
  for (size_t byte_idx = 0; byte_idx < byte_count; ++byte_idx) {
    const uint8_t active_mask = kiwi_host_where_active_byte_mask(mask_len, byte_idx);
    const uint8_t ones = mask_bytes[byte_idx] & active_mask;
    const uint8_t zeros = (uint8_t)(~mask_bytes[byte_idx]) & active_mask;
    const uint16_t base = (uint16_t)(byte_idx * 8u);
    kiwi_host_where_i16_sse2_byte(dst, zero_limit, &zero_pos, base, zeros);
    kiwi_host_where_i16_sse2_byte(dst, one_limit, &one_pos, base, ones);
  }
  return mask_len;
}

size_t kiwi_host_grade_bool_i32_sse2(
    int32_t* dst,
    size_t dst_len,
    const uint64_t* mask_words,
    size_t mask_len,
    size_t count_one,
    int ascending) {
  const size_t count_zero = mask_len - count_one;
  size_t zero_pos = ascending ? 0u : count_one;
  size_t one_pos = ascending ? count_zero : 0u;
  const size_t zero_limit = ascending ? count_zero : dst_len;
  const size_t one_limit = ascending ? dst_len : count_one;
  const uint8_t* mask_bytes = (const uint8_t*)mask_words;
  const size_t byte_count = (mask_len + 7u) / 8u;
  for (size_t byte_idx = 0; byte_idx < byte_count; ++byte_idx) {
    const uint8_t active_mask = kiwi_host_where_active_byte_mask(mask_len, byte_idx);
    const uint8_t ones = mask_bytes[byte_idx] & active_mask;
    const uint8_t zeros = (uint8_t)(~mask_bytes[byte_idx]) & active_mask;
    const uint32_t base = (uint32_t)(byte_idx * 8u);
    kiwi_host_where_i32_sse2_byte(dst, zero_limit, &zero_pos, base, zeros);
    kiwi_host_where_i32_sse2_byte(dst, one_limit, &one_pos, base, ones);
  }
  return mask_len;
}
#else
size_t kiwi_host_where_i16_sse2(
    int16_t* dst,
    size_t dst_len,
    const uint64_t* mask_words,
    size_t mask_len) {
  (void)dst;
  (void)dst_len;
  (void)mask_words;
  (void)mask_len;
  return 0u;
}

size_t kiwi_host_where_not_i16_sse2(
    int16_t* dst,
    size_t dst_len,
    const uint64_t* mask_words,
    size_t mask_len) {
  (void)dst;
  (void)dst_len;
  (void)mask_words;
  (void)mask_len;
  return 0u;
}

size_t kiwi_host_where_i32_sse2(
    int32_t* dst,
    size_t dst_len,
    const uint64_t* mask_words,
    size_t mask_len) {
  (void)dst;
  (void)dst_len;
  (void)mask_words;
  (void)mask_len;
  return 0u;
}

size_t kiwi_host_where_not_i32_sse2(
    int32_t* dst,
    size_t dst_len,
    const uint64_t* mask_words,
    size_t mask_len) {
  (void)dst;
  (void)dst_len;
  (void)mask_words;
  (void)mask_len;
  return 0u;
}

size_t kiwi_host_grade_bool_i16_sse2(
    int16_t* dst,
    size_t dst_len,
    const uint64_t* mask_words,
    size_t mask_len,
    size_t count_one,
    int ascending) {
  (void)dst;
  (void)dst_len;
  (void)mask_words;
  (void)mask_len;
  (void)count_one;
  (void)ascending;
  return 0u;
}

size_t kiwi_host_grade_bool_i32_sse2(
    int32_t* dst,
    size_t dst_len,
    const uint64_t* mask_words,
    size_t mask_len,
    size_t count_one,
    int ascending) {
  (void)dst;
  (void)dst_len;
  (void)mask_words;
  (void)mask_len;
  (void)count_one;
  (void)ascending;
  return 0u;
}
#endif
