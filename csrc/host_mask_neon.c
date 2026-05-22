#include <stddef.h>
#include <stdint.h>
#include <string.h>

#if defined(__aarch64__)
#include <arm_neon.h>
#include <stdatomic.h>

static uint8_t kiwi_host_mask_i32_select4[16][16];
static uint32_t kiwi_host_where_i32_offsets8[256][8];
static uint8_t kiwi_host_mask_pop4[16];
static uint8_t kiwi_host_mask_pop8[256];
static atomic_uint kiwi_host_mask_i32_ready;

static void kiwi_host_mask_i32_init(void) {
  unsigned ready = atomic_load_explicit(&kiwi_host_mask_i32_ready, memory_order_acquire);
  if (ready == 2u) return;
  unsigned expected = 0u;
  if (!atomic_compare_exchange_strong_explicit(
          &kiwi_host_mask_i32_ready,
          &expected,
          1u,
          memory_order_acq_rel,
          memory_order_acquire)) {
    while (atomic_load_explicit(&kiwi_host_mask_i32_ready, memory_order_acquire) != 2u) {
    }
    return;
  }

  for (unsigned mask = 0; mask < 16u; ++mask) {
    unsigned out = 0;
    for (unsigned lane = 0; lane < 4u; ++lane) {
      if (((mask >> lane) & 1u) == 0u) continue;
      const unsigned byte_base = lane * 4u;
      kiwi_host_mask_i32_select4[mask][out++] = (uint8_t)(byte_base + 0u);
      kiwi_host_mask_i32_select4[mask][out++] = (uint8_t)(byte_base + 1u);
      kiwi_host_mask_i32_select4[mask][out++] = (uint8_t)(byte_base + 2u);
      kiwi_host_mask_i32_select4[mask][out++] = (uint8_t)(byte_base + 3u);
    }
    kiwi_host_mask_pop4[mask] = (uint8_t)(out / 4u);
    while (out < 16u) {
      kiwi_host_mask_i32_select4[mask][out++] = 0u;
    }

  }

  for (unsigned mask = 0; mask < 256u; ++mask) {
    unsigned out = 0;
    for (unsigned lane = 0; lane < 8u; ++lane) {
      if (((mask >> lane) & 1u) == 0u) continue;
      kiwi_host_where_i32_offsets8[mask][out++] = lane;
    }
    kiwi_host_mask_pop8[mask] = (uint8_t)out;
    while (out < 8u) {
      kiwi_host_where_i32_offsets8[mask][out++] = 0u;
    }
  }

  atomic_store_explicit(&kiwi_host_mask_i32_ready, 2u, memory_order_release);
}

static size_t kiwi_host_mask_active_bits(size_t len, size_t word_idx) {
  const size_t base = word_idx * 64u;
  const size_t remaining = len - base;
  return remaining < 64u ? remaining : 64u;
}

static uint64_t kiwi_host_mask_low_mask(size_t active) {
  return active >= 64u ? UINT64_MAX : ((UINT64_C(1) << active) - UINT64_C(1));
}

static uint64_t kiwi_host_mask_word(uint64_t word, size_t active) {
  return word & kiwi_host_mask_low_mask(active);
}

static void kiwi_host_mask_store_i32x4(
    int32_t* dst,
    size_t dst_len,
    size_t* out_idx,
    uint8x16_t packed,
    unsigned count) {
  if (count == 0u) return;
  if (*out_idx + 4u <= dst_len) {
    vst1q_u8((uint8_t*)(dst + *out_idx), packed);
  } else {
    uint8_t tmp[16];
    vst1q_u8(tmp, packed);
    memcpy(dst + *out_idx, tmp, (size_t)count * sizeof(int32_t));
  }
  *out_idx += count;
}

static void kiwi_host_mask_compress_i32_nibble(
    int32_t* dst,
    size_t dst_len,
    size_t* out_idx,
    const int32_t* src,
    uint8_t mask) {
  const unsigned count = kiwi_host_mask_pop4[mask];
  if (count == 0u) return;
  const uint8x16_t source = vld1q_u8((const uint8_t*)src);
  const uint8x16_t control = vld1q_u8(kiwi_host_mask_i32_select4[mask]);
  const uint8x16_t packed = vqtbl1q_u8(source, control);
  kiwi_host_mask_store_i32x4(dst, dst_len, out_idx, packed, count);
}

size_t kiwi_host_mask_compress_i32_neon(
    int32_t* dst,
    size_t dst_len,
    const int32_t* src,
    const uint64_t* mask_words,
    size_t mask_len) {
  kiwi_host_mask_i32_init();

  size_t out_idx = 0;
  const size_t word_count = (mask_len + 63u) / 64u;
  for (size_t word_idx = 0; word_idx < word_count; ++word_idx) {
    const size_t word_base = word_idx * 64u;
    const size_t active = kiwi_host_mask_active_bits(mask_len, word_idx);
    const uint64_t word = kiwi_host_mask_word(mask_words[word_idx], active);
    size_t bit_idx = 0;
    while (bit_idx + 8u <= active) {
      const uint8_t mask_byte = (uint8_t)((word >> bit_idx) & 0xffu);
      if (mask_byte == 0u) {
        bit_idx += 8u;
        continue;
      }
      if (mask_byte == 0xffu) {
        memcpy(dst + out_idx, src + word_base + bit_idx, 8u * sizeof(int32_t));
        out_idx += 8u;
        bit_idx += 8u;
        continue;
      }

      kiwi_host_mask_compress_i32_nibble(
          dst,
          dst_len,
          &out_idx,
          src + word_base + bit_idx,
          (uint8_t)(mask_byte & 0x0fu));
      kiwi_host_mask_compress_i32_nibble(
          dst,
          dst_len,
          &out_idx,
          src + word_base + bit_idx + 4u,
          (uint8_t)(mask_byte >> 4));
      bit_idx += 8u;
    }

    while (bit_idx < active) {
      if (((word >> bit_idx) & 1u) != 0u) {
        dst[out_idx++] = src[word_base + bit_idx];
      }
      ++bit_idx;
    }
  }
  return out_idx;
}

static void kiwi_host_where_i32_byte(
    int32_t* dst,
    size_t dst_len,
    size_t* out_idx,
    size_t base,
    uint8_t mask) {
  const unsigned count = kiwi_host_mask_pop8[mask];
  if (count == 0u) return;
  const uint32x4_t base_vec = vdupq_n_u32((uint32_t)base);
  const uint32x4_t values0 = vaddq_u32(base_vec, vld1q_u32(kiwi_host_where_i32_offsets8[mask]));
  const uint32x4_t values1 = vaddq_u32(base_vec, vld1q_u32(kiwi_host_where_i32_offsets8[mask] + 4u));
  if (*out_idx + 8u <= dst_len) {
    vst1q_s32(dst + *out_idx, vreinterpretq_s32_u32(values0));
    vst1q_s32(dst + *out_idx + 4u, vreinterpretq_s32_u32(values1));
  } else {
    int32_t tmp[8];
    vst1q_s32(tmp, vreinterpretq_s32_u32(values0));
    vst1q_s32(tmp + 4u, vreinterpretq_s32_u32(values1));
    memcpy(dst + *out_idx, tmp, (size_t)count * sizeof(int32_t));
  }
  *out_idx += count;
}

size_t kiwi_host_where_i32_neon(
    int32_t* dst,
    size_t dst_len,
    const uint64_t* mask_words,
    size_t mask_len) {
  kiwi_host_mask_i32_init();

  size_t out_idx = 0;
  const size_t word_count = (mask_len + 63u) / 64u;
  for (size_t word_idx = 0; word_idx < word_count; ++word_idx) {
    const size_t word_base = word_idx * 64u;
    const size_t active = kiwi_host_mask_active_bits(mask_len, word_idx);
    const uint64_t active_mask = kiwi_host_mask_low_mask(active);
    const uint64_t word = mask_words[word_idx] & active_mask;
    if (word == 0u) continue;

    size_t bit_idx = 0;
    while (bit_idx + 8u <= active) {
      const uint8_t mask_byte = (uint8_t)((word >> bit_idx) & 0xffu);
      if (mask_byte == 0u) {
        bit_idx += 8u;
        continue;
      }

      kiwi_host_where_i32_byte(dst, dst_len, &out_idx, word_base + bit_idx, mask_byte);
      bit_idx += 8u;
    }

    while (bit_idx < active) {
      if (((word >> bit_idx) & 1u) != 0u) {
        dst[out_idx++] = (int32_t)(word_base + bit_idx);
      }
      ++bit_idx;
    }
  }
  return out_idx;
}
#else
size_t kiwi_host_mask_compress_i32_neon(
    int32_t* dst,
    size_t dst_len,
    const int32_t* src,
    const uint64_t* mask_words,
    size_t mask_len) {
  (void)dst;
  (void)dst_len;
  (void)src;
  (void)mask_words;
  (void)mask_len;
  return 0u;
}

size_t kiwi_host_where_i32_neon(
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
#endif
