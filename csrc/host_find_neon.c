#include "host_find.h"

#include <arm_neon.h>

static int kiwi_mask_any_u8(uint8x16_t mask) {
  const uint64x2_t words = vreinterpretq_u64_u8(mask);
  return (vgetq_lane_u64(words, 0) | vgetq_lane_u64(words, 1)) != 0;
}

static int kiwi_mask_any_u16(uint16x8_t mask) {
  const uint64x2_t words = vreinterpretq_u64_u16(mask);
  return (vgetq_lane_u64(words, 0) | vgetq_lane_u64(words, 1)) != 0;
}

static int kiwi_mask_any_u32(uint32x4_t mask) {
  const uint64x2_t words = vreinterpretq_u64_u32(mask);
  return (vgetq_lane_u64(words, 0) | vgetq_lane_u64(words, 1)) != 0;
}

static int kiwi_mask_any_u64(uint64x2_t mask) {
  return (vgetq_lane_u64(mask, 0) | vgetq_lane_u64(mask, 1)) != 0;
}

static size_t kiwi_match_u8(uint8x16_t mask, size_t base) {
  uint8_t lanes[16];
  vst1q_u8(lanes, mask);
  for (size_t lane = 0; lane < 16; ++lane) {
    if (lanes[lane] != 0) {
      return base + lane;
    }
  }
  return base + 16;
}

static size_t kiwi_match_u16(uint16x8_t mask, size_t base) {
  uint16_t lanes[8];
  vst1q_u16(lanes, mask);
  for (size_t lane = 0; lane < 8; ++lane) {
    if (lanes[lane] != 0) {
      return base + lane;
    }
  }
  return base + 8;
}

static size_t kiwi_match_u32(uint32x4_t mask, size_t base) {
  uint32_t lanes[4];
  vst1q_u32(lanes, mask);
  for (size_t lane = 0; lane < 4; ++lane) {
    if (lanes[lane] != 0) {
      return base + lane;
    }
  }
  return base + 4;
}

static size_t kiwi_match_u64(uint64x2_t mask, size_t base) {
  if (vgetq_lane_u64(mask, 0) != 0) {
    return base;
  }
  if (vgetq_lane_u64(mask, 1) != 0) {
    return base + 1;
  }
  return base + 2;
}

size_t kiwi_host_find_i8_neon(const int8_t* items, size_t len, int8_t query) {
  const int8x16_t needle = vdupq_n_s8(query);
  size_t idx = 0;
  while (len - idx >= 128) {
    const uint8x16_t m0 = vceqq_s8(vld1q_s8(items + idx), needle);
    const uint8x16_t m1 = vceqq_s8(vld1q_s8(items + idx + 16), needle);
    const uint8x16_t m2 = vceqq_s8(vld1q_s8(items + idx + 32), needle);
    const uint8x16_t m3 = vceqq_s8(vld1q_s8(items + idx + 48), needle);
    const uint8x16_t any = vorrq_u8(vorrq_u8(m0, m1), vorrq_u8(m2, m3));
    if (kiwi_mask_any_u8(any)) {
      if (kiwi_mask_any_u8(m0)) return kiwi_match_u8(m0, idx);
      if (kiwi_mask_any_u8(m1)) return kiwi_match_u8(m1, idx + 16);
      if (kiwi_mask_any_u8(m2)) return kiwi_match_u8(m2, idx + 32);
      return kiwi_match_u8(m3, idx + 48);
    }
    idx += 64;
  }
  while (len - idx >= 16) {
    const uint8x16_t mask = vceqq_s8(vld1q_s8(items + idx), needle);
    if (kiwi_mask_any_u8(mask)) {
      return kiwi_match_u8(mask, idx);
    }
    idx += 16;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) {
      return idx;
    }
  }
  return len;
}

size_t kiwi_host_find_i16_neon(const int16_t* items, size_t len, int16_t query) {
  const int16x8_t needle = vdupq_n_s16(query);
  size_t idx = 0;
  while (len - idx >= 64) {
    const uint16x8_t m0 = vceqq_s16(vld1q_s16(items + idx), needle);
    const uint16x8_t m1 = vceqq_s16(vld1q_s16(items + idx + 8), needle);
    const uint16x8_t m2 = vceqq_s16(vld1q_s16(items + idx + 16), needle);
    const uint16x8_t m3 = vceqq_s16(vld1q_s16(items + idx + 24), needle);
    const uint16x8_t any = vorrq_u16(vorrq_u16(m0, m1), vorrq_u16(m2, m3));
    if (kiwi_mask_any_u16(any)) {
      if (kiwi_mask_any_u16(m0)) return kiwi_match_u16(m0, idx);
      if (kiwi_mask_any_u16(m1)) return kiwi_match_u16(m1, idx + 8);
      if (kiwi_mask_any_u16(m2)) return kiwi_match_u16(m2, idx + 16);
      return kiwi_match_u16(m3, idx + 24);
    }
    idx += 32;
  }
  while (len - idx >= 8) {
    const uint16x8_t mask = vceqq_s16(vld1q_s16(items + idx), needle);
    if (kiwi_mask_any_u16(mask)) {
      return kiwi_match_u16(mask, idx);
    }
    idx += 8;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) {
      return idx;
    }
  }
  return len;
}

static inline size_t kiwi_host_find_i32_neon_block(const int32_t* items, size_t len, int32x4_t needle, int32_t query) {
  size_t idx = 0;
  while (len - idx >= 16) {
    const uint32x4_t m0 = vceqq_s32(vld1q_s32(items + idx), needle);
    const uint32x4_t m1 = vceqq_s32(vld1q_s32(items + idx + 4), needle);
    const uint32x4_t m2 = vceqq_s32(vld1q_s32(items + idx + 8), needle);
    const uint32x4_t m3 = vceqq_s32(vld1q_s32(items + idx + 12), needle);
    const uint32x4_t any = vorrq_u32(vorrq_u32(m0, m1), vorrq_u32(m2, m3));
    if (kiwi_mask_any_u32(any)) {
      if (kiwi_mask_any_u32(m0)) return kiwi_match_u32(m0, idx);
      if (kiwi_mask_any_u32(m1)) return kiwi_match_u32(m1, idx + 4);
      if (kiwi_mask_any_u32(m2)) return kiwi_match_u32(m2, idx + 8);
      return kiwi_match_u32(m3, idx + 12);
    }
    idx += 16;
  }
  while (len - idx >= 4) {
    const uint32x4_t mask = vceqq_s32(vld1q_s32(items + idx), needle);
    if (kiwi_mask_any_u32(mask)) {
      return kiwi_match_u32(mask, idx);
    }
    idx += 4;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) {
      return idx;
    }
  }
  return len;
}

size_t kiwi_host_find_i32_neon(const int32_t* items, size_t len, int32_t query) {
  const int32x4_t needle = vdupq_n_s32(query);
  size_t idx = 0;
  while (len - idx >= 128) {
    uint32x4_t any = vdupq_n_u32(0);

#define KIWI_ACC_I32_FIND(OFF) do { \
      const uint32x4_t m0 = vceqq_s32(vld1q_s32(items + idx + (OFF)), needle); \
      const uint32x4_t m1 = vceqq_s32(vld1q_s32(items + idx + (OFF) + 4), needle); \
      const uint32x4_t m2 = vceqq_s32(vld1q_s32(items + idx + (OFF) + 8), needle); \
      const uint32x4_t m3 = vceqq_s32(vld1q_s32(items + idx + (OFF) + 12), needle); \
      any = vorrq_u32(any, vorrq_u32(vorrq_u32(m0, m1), vorrq_u32(m2, m3))); \
    } while (0)

    KIWI_ACC_I32_FIND(0);
    KIWI_ACC_I32_FIND(16);
    KIWI_ACC_I32_FIND(32);
    KIWI_ACC_I32_FIND(48);
    KIWI_ACC_I32_FIND(64);
    KIWI_ACC_I32_FIND(80);
    KIWI_ACC_I32_FIND(96);
    KIWI_ACC_I32_FIND(112);

#undef KIWI_ACC_I32_FIND

    if (kiwi_mask_any_u32(any)) {
      return idx + kiwi_host_find_i32_neon_block(items + idx, 128, needle, query);
    }
    idx += 128;
  }
  return idx + kiwi_host_find_i32_neon_block(items + idx, len - idx, needle, query);
}

static inline size_t kiwi_host_find_i64_neon_block(const int64_t* items, size_t len, int64x2_t needle, int64_t query) {
  size_t idx = 0;
  while (len - idx >= 8) {
    const uint64x2_t m0 = vceqq_s64(vld1q_s64(items + idx), needle);
    const uint64x2_t m1 = vceqq_s64(vld1q_s64(items + idx + 2), needle);
    const uint64x2_t m2 = vceqq_s64(vld1q_s64(items + idx + 4), needle);
    const uint64x2_t m3 = vceqq_s64(vld1q_s64(items + idx + 6), needle);
    const uint64x2_t any = vorrq_u64(vorrq_u64(m0, m1), vorrq_u64(m2, m3));
    if (kiwi_mask_any_u64(any)) {
      if (kiwi_mask_any_u64(m0)) return kiwi_match_u64(m0, idx);
      if (kiwi_mask_any_u64(m1)) return kiwi_match_u64(m1, idx + 2);
      if (kiwi_mask_any_u64(m2)) return kiwi_match_u64(m2, idx + 4);
      return kiwi_match_u64(m3, idx + 6);
    }
    idx += 8;
  }
  while (len - idx >= 2) {
    const uint64x2_t mask = vceqq_s64(vld1q_s64(items + idx), needle);
    if (kiwi_mask_any_u64(mask)) {
      return kiwi_match_u64(mask, idx);
    }
    idx += 2;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) {
      return idx;
    }
  }
  return len;
}

size_t kiwi_host_find_i64_neon(const int64_t* items, size_t len, int64_t query) {
  const int64x2_t needle = vdupq_n_s64(query);
  size_t idx = 0;
  while (len - idx >= 64) {
    uint64x2_t any = vdupq_n_u64(0);

#define KIWI_ACC_I64_FIND(OFF) do { \
      const uint64x2_t m0 = vceqq_s64(vld1q_s64(items + idx + (OFF)), needle); \
      const uint64x2_t m1 = vceqq_s64(vld1q_s64(items + idx + (OFF) + 2), needle); \
      const uint64x2_t m2 = vceqq_s64(vld1q_s64(items + idx + (OFF) + 4), needle); \
      const uint64x2_t m3 = vceqq_s64(vld1q_s64(items + idx + (OFF) + 6), needle); \
      any = vorrq_u64(any, vorrq_u64(vorrq_u64(m0, m1), vorrq_u64(m2, m3))); \
    } while (0)

    KIWI_ACC_I64_FIND(0);
    KIWI_ACC_I64_FIND(8);
    KIWI_ACC_I64_FIND(16);
    KIWI_ACC_I64_FIND(24);
    KIWI_ACC_I64_FIND(32);
    KIWI_ACC_I64_FIND(40);
    KIWI_ACC_I64_FIND(48);
    KIWI_ACC_I64_FIND(56);

#undef KIWI_ACC_I64_FIND

    if (kiwi_mask_any_u64(any)) {
      return idx + kiwi_host_find_i64_neon_block(items + idx, 64, needle, query);
    }
    idx += 64;
  }
  return idx + kiwi_host_find_i64_neon_block(items + idx, len - idx, needle, query);
}

static inline size_t kiwi_host_find_f64_neon_block(const double* items, size_t len, float64x2_t needle, double query) {
  size_t idx = 0;
  while (len - idx >= 8) {
    const uint64x2_t m0 = vceqq_f64(vld1q_f64(items + idx), needle);
    const uint64x2_t m1 = vceqq_f64(vld1q_f64(items + idx + 2), needle);
    const uint64x2_t m2 = vceqq_f64(vld1q_f64(items + idx + 4), needle);
    const uint64x2_t m3 = vceqq_f64(vld1q_f64(items + idx + 6), needle);
    const uint64x2_t any = vorrq_u64(vorrq_u64(m0, m1), vorrq_u64(m2, m3));
    if (kiwi_mask_any_u64(any)) {
      if (kiwi_mask_any_u64(m0)) return kiwi_match_u64(m0, idx);
      if (kiwi_mask_any_u64(m1)) return kiwi_match_u64(m1, idx + 2);
      if (kiwi_mask_any_u64(m2)) return kiwi_match_u64(m2, idx + 4);
      return kiwi_match_u64(m3, idx + 6);
    }
    idx += 8;
  }
  while (len - idx >= 2) {
    const uint64x2_t mask = vceqq_f64(vld1q_f64(items + idx), needle);
    if (kiwi_mask_any_u64(mask)) {
      return kiwi_match_u64(mask, idx);
    }
    idx += 2;
  }
  for (; idx < len; ++idx) {
    if (items[idx] == query) {
      return idx;
    }
  }
  return len;
}

size_t kiwi_host_find_f64_neon(const double* items, size_t len, double query) {
  const float64x2_t needle = vdupq_n_f64(query);
  size_t idx = 0;
  while (len - idx >= 64) {
    uint64x2_t any = vdupq_n_u64(0);

#define KIWI_ACC_F64_FIND(OFF) do { \
      const uint64x2_t m0 = vceqq_f64(vld1q_f64(items + idx + (OFF)), needle); \
      const uint64x2_t m1 = vceqq_f64(vld1q_f64(items + idx + (OFF) + 2), needle); \
      const uint64x2_t m2 = vceqq_f64(vld1q_f64(items + idx + (OFF) + 4), needle); \
      const uint64x2_t m3 = vceqq_f64(vld1q_f64(items + idx + (OFF) + 6), needle); \
      any = vorrq_u64(any, vorrq_u64(vorrq_u64(m0, m1), vorrq_u64(m2, m3))); \
    } while (0)

    KIWI_ACC_F64_FIND(0);
    KIWI_ACC_F64_FIND(8);
    KIWI_ACC_F64_FIND(16);
    KIWI_ACC_F64_FIND(24);
    KIWI_ACC_F64_FIND(32);
    KIWI_ACC_F64_FIND(40);
    KIWI_ACC_F64_FIND(48);
    KIWI_ACC_F64_FIND(56);

#undef KIWI_ACC_F64_FIND

    if (kiwi_mask_any_u64(any)) {
      return idx + kiwi_host_find_f64_neon_block(items + idx, 64, needle, query);
    }
    idx += 64;
  }
  return idx + kiwi_host_find_f64_neon_block(items + idx, len - idx, needle, query);
}
