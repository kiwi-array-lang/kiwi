#include <stddef.h>
#include <stdint.h>
#include <string.h>

#if defined(__aarch64__)
#include <arm_neon.h>
#include <stdatomic.h>
#endif

#if defined(__aarch64__)
static uint8_t kiwi_string_mask_select8[256][8];
static atomic_uint kiwi_string_mask_select8_ready;

static void kiwi_init_string_mask_select8(void) {
  unsigned ready = atomic_load_explicit(&kiwi_string_mask_select8_ready, memory_order_acquire);
  if (ready == 2u) {
    return;
  }
  unsigned expected = 0u;
  if (!atomic_compare_exchange_strong_explicit(
          &kiwi_string_mask_select8_ready,
          &expected,
          1u,
          memory_order_acq_rel,
          memory_order_acquire)) {
    while (atomic_load_explicit(&kiwi_string_mask_select8_ready, memory_order_acquire) != 2u) {
    }
    return;
  }
  for (unsigned mask = 0; mask < 256; ++mask) {
    unsigned count = 0;
    for (unsigned bit = 0; bit < 8; ++bit) {
      if ((mask >> bit) & 1u) {
        kiwi_string_mask_select8[mask][count++] = (uint8_t)bit;
      }
    }
    while (count < 8) {
      kiwi_string_mask_select8[mask][count++] = 0;
    }
  }
  atomic_store_explicit(&kiwi_string_mask_select8_ready, 2u, memory_order_release);
}
#endif

static size_t kiwi_active_bits(size_t len, size_t word_idx) {
  const size_t base = word_idx * 64u;
  const size_t remaining = len - base;
  return remaining < 64u ? remaining : 64u;
}

static uint64_t kiwi_mask_word(uint64_t word, size_t active) {
  if (active >= 64u) {
    return word;
  }
  return word & ((UINT64_C(1) << active) - UINT64_C(1));
}

static void kiwi_copy_mask_tail(
    uint8_t* dst,
    size_t* out_idx,
    const uint8_t* src,
    uint8_t mask_byte) {
  for (unsigned bit = 0; bit < 8; ++bit) {
    if ((mask_byte >> bit) & 1u) {
      dst[(*out_idx)++] = src[bit];
    }
  }
}

size_t kiwi_string_mask_compress_neon(
    uint8_t* dst,
    size_t dst_len,
    const uint8_t* src,
    const uint64_t* mask_words,
    size_t mask_len) {
#if defined(__aarch64__)
  kiwi_init_string_mask_select8();
#endif

  size_t out_idx = 0;
  const size_t word_count = (mask_len + 63u) / 64u;
  for (size_t word_idx = 0; word_idx < word_count; ++word_idx) {
    const size_t word_base = word_idx * 64u;
    const size_t active = kiwi_active_bits(mask_len, word_idx);
    const uint64_t word = kiwi_mask_word(mask_words[word_idx], active);
    size_t bit_idx = 0;
    while (bit_idx + 8u <= active) {
      const uint8_t mask_byte = (uint8_t)((word >> bit_idx) & 0xffu);
      const unsigned count = (unsigned)__builtin_popcount((unsigned)mask_byte);
      if (count == 0u) {
        bit_idx += 8u;
        continue;
      }

      const uint8_t* block = src + word_base + bit_idx;
      if (count == 8u) {
        memcpy(dst + out_idx, block, 8u);
        out_idx += 8u;
        bit_idx += 8u;
        continue;
      }

#if defined(__aarch64__)
      const uint8x8_t source = vld1_u8(block);
      const uint8x8_t control = vld1_u8(kiwi_string_mask_select8[mask_byte]);
      const uint8x8_t packed = vtbl1_u8(source, control);
      if (out_idx + 8u <= dst_len) {
        vst1_u8(dst + out_idx, packed);
      } else {
        uint8_t tmp[8];
        vst1_u8(tmp, packed);
        memcpy(dst + out_idx, tmp, count);
      }
#else
      kiwi_copy_mask_tail(dst, &out_idx, block, mask_byte);
      bit_idx += 8u;
      continue;
#endif

      out_idx += count;
      bit_idx += 8u;
    }

    if (bit_idx < active) {
      const size_t tail_bits = active - bit_idx;
      const uint8_t tail_mask = (uint8_t)((word >> bit_idx) & ((1u << tail_bits) - 1u));
      kiwi_copy_mask_tail(dst, &out_idx, src + word_base + bit_idx, tail_mask);
    }
  }
  return out_idx;
}
