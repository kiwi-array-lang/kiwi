#include <stddef.h>
#include <stdint.h>

#if defined(__aarch64__)
#include <arm_neon.h>
#endif

#if defined(__aarch64__)
static int kiwi_string_find_any_u8(uint8x16_t mask) {
  const uint64x2_t words = vreinterpretq_u64_u8(mask);
  return (vgetq_lane_u64(words, 0) | vgetq_lane_u64(words, 1)) != 0;
}

static uint8x16_t kiwi_string_find_query_mask(
    uint8x16_t bytes,
    uint8x16_t low0,
    uint8x16_t low1,
    uint8x16_t high_bit) {
  const uint8x16_t low_nibble = vandq_u8(bytes, vdupq_n_u8(15));
  const uint8x16_t high_nibble = vshrq_n_u8(bytes, 4);
  const uint8x16_t high_low = vandq_u8(high_nibble, vdupq_n_u8(7));
  const uint8x16_t low_mask0 = vqtbl1q_u8(low0, low_nibble);
  const uint8x16_t low_mask1 = vqtbl1q_u8(low1, low_nibble);
  const uint8x16_t high_group = vcgeq_u8(high_nibble, vdupq_n_u8(8));
  const uint8x16_t low_mask = vbslq_u8(high_group, low_mask1, low_mask0);
  const uint8x16_t bit = vqtbl1q_u8(high_bit, high_low);
  return vtstq_u8(vandq_u8(low_mask, bit), bit);
}
#endif

void kiwi_string_find_bytes_neon(
    int64_t* out,
    const uint8_t* haystack,
    size_t haystack_len,
    const uint8_t* queries,
    size_t query_len,
    int64_t miss) {
#if defined(__aarch64__)
  uint8_t wanted[256] = {0};
  size_t first[256];
  uint8_t low0_items[16] = {0};
  uint8_t low1_items[16] = {0};
  for (size_t idx = 0; idx < 256u; ++idx) {
    first[idx] = haystack_len;
  }

  size_t remaining = 0;
  for (size_t idx = 0; idx < query_len; ++idx) {
    const uint8_t query = queries[idx];
    if (wanted[query] == 0u) {
      wanted[query] = 1u;
      remaining += 1u;
      const uint8_t low = (uint8_t)(query & 15u);
      const uint8_t high = (uint8_t)(query >> 4u);
      if (high < 8u) {
        low0_items[low] |= (uint8_t)(1u << high);
      } else {
        low1_items[low] |= (uint8_t)(1u << (high - 8u));
      }
    }
  }

  const uint8x16_t low0 = vld1q_u8(low0_items);
  const uint8x16_t low1 = vld1q_u8(low1_items);
  static const uint8_t high_bit_items[16] = {
      1u, 2u, 4u, 8u, 16u, 32u, 64u, 128u,
      1u, 2u, 4u, 8u, 16u, 32u, 64u, 128u,
  };
  const uint8x16_t high_bit = vld1q_u8(high_bit_items);

  size_t idx = 0;
  while (idx + 64u <= haystack_len && remaining > 0u) {
    const uint8x16_t m0 = kiwi_string_find_query_mask(vld1q_u8(haystack + idx), low0, low1, high_bit);
    const uint8x16_t m1 = kiwi_string_find_query_mask(vld1q_u8(haystack + idx + 16u), low0, low1, high_bit);
    const uint8x16_t m2 = kiwi_string_find_query_mask(vld1q_u8(haystack + idx + 32u), low0, low1, high_bit);
    const uint8x16_t m3 = kiwi_string_find_query_mask(vld1q_u8(haystack + idx + 48u), low0, low1, high_bit);
    const uint8x16_t any = vorrq_u8(vorrq_u8(m0, m1), vorrq_u8(m2, m3));
    if (kiwi_string_find_any_u8(any)) {
      for (size_t scan = idx; scan < idx + 64u && remaining > 0u; ++scan) {
        const uint8_t byte = haystack[scan];
        if (wanted[byte] != 0u && first[byte] == haystack_len) {
          first[byte] = scan;
          remaining -= 1u;
        }
      }
    }
    idx += 64u;
  }
  while (idx < haystack_len && remaining > 0u) {
    const uint8_t byte = haystack[idx];
    if (wanted[byte] != 0u && first[byte] == haystack_len) {
      first[byte] = idx;
      remaining -= 1u;
    }
    idx += 1u;
  }

  for (size_t query_idx = 0; query_idx < query_len; ++query_idx) {
    const size_t found = first[queries[query_idx]];
    out[query_idx] = found < haystack_len ? (int64_t)found : miss;
  }
#else
  (void)haystack;
  (void)haystack_len;
  for (size_t idx = 0; idx < query_len; ++idx) {
    (void)queries[idx];
    out[idx] = miss;
  }
#endif
}
