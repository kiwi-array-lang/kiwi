#include "host_compare.h"

#include <arm_neon.h>

static inline int kiwi_host_compare_i64_tail(int64_t left, int64_t right, int op) {
  return op == KIWI_HOST_COMPARE_EQ ? left == right
      : op == KIWI_HOST_COMPARE_LT ? left < right
                                    : left > right;
}

static inline int kiwi_host_compare_f64_tail(double left, double right, int op) {
  return op == KIWI_HOST_COMPARE_EQ ? left == right
      : op == KIWI_HOST_COMPARE_LT ? left < right
                                    : left > right;
}

static inline int64_t kiwi_host_compare_load_int_tail(const void* items, int width, size_t idx) {
  switch (width) {
    case 1:
      return (int64_t)((const int8_t*)items)[idx];
    case 2:
      return (int64_t)((const int16_t*)items)[idx];
    case 4:
      return (int64_t)((const int32_t*)items)[idx];
    case 8:
      return ((const int64_t*)items)[idx];
    default:
      return 0;
  }
}

static inline int kiwi_host_compare_int_f64_tail(
    const void* int_items,
    int int_width,
    const double* float_items,
    size_t idx,
    int int_left,
    int op) {
  const double int_value = (double)kiwi_host_compare_load_int_tail(int_items, int_width, idx);
  const double float_value = float_items[idx];
  return kiwi_host_compare_f64_tail(
      int_left ? int_value : float_value,
      int_left ? float_value : int_value,
      op);
}

static const uint8_t kiwi_host_compare_mask_weights_u8[8] = {
    1, 2, 4, 8, 16, 32, 64, 128,
};

static const uint8_t kiwi_host_compare_mask_weights_u8x16[16] = {
    1, 2, 4, 8, 16, 32, 64, 128,
    1, 2, 4, 8, 16, 32, 64, 128,
};

static const uint8_t kiwi_host_compare_pack_shuffle_u8x16_pair[16] = {
    0, 4, 8, 12, 1, 5, 9, 13,
    2, 6, 10, 14, 3, 7, 11, 15,
};

static const uint16_t kiwi_host_compare_mask_weights_u16x8_pair[8] = {
    0x0101, 0x0202, 0x0404, 0x0808,
    0x1010, 0x2020, 0x4040, 0x8080,
};

static const uint32_t kiwi_host_compare_mask_weights_u32x4_pair[4] = {
    0x11, 0x22, 0x44, 0x88,
};

static inline uint64_t kiwi_host_compare_pack_u8x8(uint8x8_t cmp) {
  const uint8x8_t weights = vld1_u8(kiwi_host_compare_mask_weights_u8);
  return (uint64_t)vaddv_u8(vand_u8(cmp, weights));
}

static inline uint32_t kiwi_host_compare_pack_u8x16_pair(uint8x16_t first, uint8x16_t second) {
  const uint8x16_t weights = vld1q_u8(kiwi_host_compare_mask_weights_u8x16);
  const uint8x16_t shuffle = vld1q_u8(kiwi_host_compare_pack_shuffle_u8x16_pair);
  const uint8x16_t paired = vpaddq_u8(vandq_u8(first, weights), vandq_u8(second, weights));
  const uint8x16_t shuffled = vqtbl1q_u8(paired, shuffle);
  return vaddvq_u32(vreinterpretq_u32_u8(shuffled));
}

static inline uint16_t kiwi_host_compare_pack_u16x8_pair(uint16x8_t first, uint16x8_t second) {
  const uint16x8_t weights = vld1q_u16(kiwi_host_compare_mask_weights_u16x8_pair);
  const uint16x8_t merged = vsriq_n_u16(second, first, 8);
  return vaddvq_u16(vandq_u16(merged, weights));
}

static inline uint8_t kiwi_host_compare_pack_u32x4_pair(uint32x4_t first, uint32x4_t second) {
  const uint32x4_t weights = vld1q_u32(kiwi_host_compare_mask_weights_u32x4_pair);
  const uint32x4_t merged = vsriq_n_u32(second, first, 28);
  return (uint8_t)vaddvq_u32(vandq_u32(merged, weights));
}

static inline uint8_t kiwi_host_compare_pack_u64x2_quad(uint64x2_t a, uint64x2_t b, uint64x2_t c, uint64x2_t d) {
  const uint32x4_t lo = vuzp1q_u32(vreinterpretq_u32_u64(a), vreinterpretq_u32_u64(b));
  const uint32x4_t hi = vuzp1q_u32(vreinterpretq_u32_u64(c), vreinterpretq_u32_u64(d));
  return kiwi_host_compare_pack_u32x4_pair(lo, hi);
}

static inline uint64_t kiwi_host_compare_mask_u8x16(uint8x16_t cmp) {
  return kiwi_host_compare_pack_u8x8(vget_low_u8(cmp)) |
      (kiwi_host_compare_pack_u8x8(vget_high_u8(cmp)) << 8);
}

static inline uint64_t kiwi_host_compare_mask_u16x8(uint16x8_t cmp) {
  return kiwi_host_compare_pack_u8x8(vmovn_u16(cmp));
}

static inline uint64_t kiwi_host_compare_mask_u32x4(uint32x4_t cmp) {
  const uint16x4_t cmp16 = vmovn_u32(cmp);
  return kiwi_host_compare_pack_u8x8(vmovn_u16(vcombine_u16(cmp16, vdup_n_u16(0))));
}

static inline uint64_t kiwi_host_compare_mask_u64x2(uint64x2_t cmp) {
  return (vgetq_lane_u64(cmp, 0) & 1) | ((vgetq_lane_u64(cmp, 1) & 1) << 1);
}

static inline int16x8_t kiwi_host_compare_load_as_i16_neon(const void* items, int width, size_t idx) {
  switch (width) {
    case 1:
      return vmovl_s8(vld1_s8(((const int8_t*)items) + idx));
    case 2:
      return vld1q_s16(((const int16_t*)items) + idx);
    default:
      return vdupq_n_s16(0);
  }
}

static inline int32x4_t kiwi_host_compare_load_as_i32_neon(const void* items, int width, size_t idx) {
  switch (width) {
    case 1: {
      const int8_t* source = (const int8_t*)items;
      const int32_t lanes[4] = {
          (int32_t)source[idx + 0],
          (int32_t)source[idx + 1],
          (int32_t)source[idx + 2],
          (int32_t)source[idx + 3],
      };
      return vld1q_s32(lanes);
    }
    case 2:
      return vmovl_s16(vld1_s16(((const int16_t*)items) + idx));
    case 4:
      return vld1q_s32(((const int32_t*)items) + idx);
    default:
      return vdupq_n_s32(0);
  }
}

static inline int64x2_t kiwi_host_compare_load_as_i64_neon(const void* items, int width, size_t idx) {
  switch (width) {
    case 1: {
      const int8_t* source = (const int8_t*)items;
      const int64_t lanes[2] = {
          (int64_t)source[idx + 0],
          (int64_t)source[idx + 1],
      };
      return vld1q_s64(lanes);
    }
    case 2: {
      const int16_t* source = (const int16_t*)items;
      const int64_t lanes[2] = {
          (int64_t)source[idx + 0],
          (int64_t)source[idx + 1],
      };
      return vld1q_s64(lanes);
    }
    case 4:
      return vmovl_s32(vld1_s32(((const int32_t*)items) + idx));
    case 8:
      return vld1q_s64(((const int64_t*)items) + idx);
    default:
      return vdupq_n_s64(0);
  }
}

static inline uint8x16_t kiwi_host_compare_i8_cmp_neon(int8x16_t left, int8x16_t right, int op) {
  return op == KIWI_HOST_COMPARE_EQ ? vceqq_s8(left, right)
      : op == KIWI_HOST_COMPARE_LT ? vcgtq_s8(right, left)
                                    : vcgtq_s8(left, right);
}

static inline uint8x16_t kiwi_host_compare_i8_scalar_cmp_neon(
    int8x16_t items, int8x16_t needle, int scalar_left, int op) {
  if (op == KIWI_HOST_COMPARE_EQ) return vceqq_s8(items, needle);
  if (scalar_left) return op == KIWI_HOST_COMPARE_LT ? vcgtq_s8(items, needle) : vcgtq_s8(needle, items);
  return op == KIWI_HOST_COMPARE_LT ? vcgtq_s8(needle, items) : vcgtq_s8(items, needle);
}

static inline uint16x8_t kiwi_host_compare_i16_cmp_neon(int16x8_t left, int16x8_t right, int op) {
  return op == KIWI_HOST_COMPARE_EQ ? vceqq_s16(left, right)
      : op == KIWI_HOST_COMPARE_LT ? vcgtq_s16(right, left)
                                    : vcgtq_s16(left, right);
}

static inline uint16x8_t kiwi_host_compare_i16_scalar_cmp_neon(
    int16x8_t items, int16x8_t needle, int scalar_left, int op) {
  if (op == KIWI_HOST_COMPARE_EQ) return vceqq_s16(items, needle);
  if (scalar_left) return op == KIWI_HOST_COMPARE_LT ? vcgtq_s16(items, needle) : vcgtq_s16(needle, items);
  return op == KIWI_HOST_COMPARE_LT ? vcgtq_s16(needle, items) : vcgtq_s16(items, needle);
}

static inline uint64_t kiwi_host_compare_i16_mask_neon(int16x8_t left, int16x8_t right, int op) {
  return kiwi_host_compare_mask_u16x8(kiwi_host_compare_i16_cmp_neon(left, right, op));
}

static inline uint32x4_t kiwi_host_compare_i32_cmp_neon(int32x4_t left, int32x4_t right, int op) {
  return op == KIWI_HOST_COMPARE_EQ ? vceqq_s32(left, right)
      : op == KIWI_HOST_COMPARE_LT ? vcgtq_s32(right, left)
                                    : vcgtq_s32(left, right);
}

static inline uint64_t kiwi_host_compare_i32_mask_neon(int32x4_t left, int32x4_t right, int op) {
  return kiwi_host_compare_mask_u32x4(kiwi_host_compare_i32_cmp_neon(left, right, op));
}

static inline uint32x4_t kiwi_host_compare_i32_scalar_cmp_neon(
    int32x4_t items, int32x4_t needle, int scalar_left, int op) {
  if (op == KIWI_HOST_COMPARE_EQ) return vceqq_s32(items, needle);
  if (scalar_left) return op == KIWI_HOST_COMPARE_LT ? vcgtq_s32(items, needle) : vcgtq_s32(needle, items);
  return op == KIWI_HOST_COMPARE_LT ? vcgtq_s32(needle, items) : vcgtq_s32(items, needle);
}

static inline uint64x2_t kiwi_host_compare_i64_cmp_neon(int64x2_t left, int64x2_t right, int op) {
  return op == KIWI_HOST_COMPARE_EQ ? vceqq_s64(left, right)
      : op == KIWI_HOST_COMPARE_LT ? vcgtq_s64(right, left)
                                    : vcgtq_s64(left, right);
}

static inline uint64_t kiwi_host_compare_i64_mask_neon(int64x2_t left, int64x2_t right, int op) {
  return kiwi_host_compare_mask_u64x2(kiwi_host_compare_i64_cmp_neon(left, right, op));
}

static inline float64x2_t kiwi_host_compare_i32x2_to_f64_neon(int32x2_t values) {
  return vcvtq_f64_s64(vmovl_s32(values));
}

static inline uint32_t kiwi_host_compare_i8_array_pack32_neon(
    const int8_t* left, const int8_t* right, size_t idx, int op) {
  return kiwi_host_compare_pack_u8x16_pair(
      kiwi_host_compare_i8_cmp_neon(vld1q_s8(left + idx), vld1q_s8(right + idx), op),
      kiwi_host_compare_i8_cmp_neon(vld1q_s8(left + idx + 16), vld1q_s8(right + idx + 16), op));
}

static inline uint16_t kiwi_host_compare_i16_array_pack16_neon(
    const int16_t* left, const int16_t* right, size_t idx, int op) {
  return kiwi_host_compare_pack_u16x8_pair(
      kiwi_host_compare_i16_cmp_neon(vld1q_s16(left + idx), vld1q_s16(right + idx), op),
      kiwi_host_compare_i16_cmp_neon(vld1q_s16(left + idx + 8), vld1q_s16(right + idx + 8), op));
}

static inline uint32_t kiwi_host_compare_i8_scalar_pack32_neon(
    const int8_t* items, size_t idx, int8x16_t needle, int scalar_left, int op) {
  return kiwi_host_compare_pack_u8x16_pair(
      kiwi_host_compare_i8_scalar_cmp_neon(vld1q_s8(items + idx), needle, scalar_left, op),
      kiwi_host_compare_i8_scalar_cmp_neon(vld1q_s8(items + idx + 16), needle, scalar_left, op));
}

static inline uint16_t kiwi_host_compare_i16_scalar_pack16_neon(
    const int16_t* items, size_t idx, int16x8_t needle, int scalar_left, int op) {
  return kiwi_host_compare_pack_u16x8_pair(
      kiwi_host_compare_i16_scalar_cmp_neon(vld1q_s16(items + idx), needle, scalar_left, op),
      kiwi_host_compare_i16_scalar_cmp_neon(vld1q_s16(items + idx + 8), needle, scalar_left, op));
}

static inline uint8_t kiwi_host_compare_i32_array_pack8_neon(
    const int32_t* left, const int32_t* right, size_t idx, int op) {
  return kiwi_host_compare_pack_u32x4_pair(
      kiwi_host_compare_i32_cmp_neon(vld1q_s32(left + idx), vld1q_s32(right + idx), op),
      kiwi_host_compare_i32_cmp_neon(vld1q_s32(left + idx + 4), vld1q_s32(right + idx + 4), op));
}

static inline uint8_t kiwi_host_compare_i32_scalar_pack8_neon(
    const int32_t* items, size_t idx, int32x4_t needle, int scalar_left, int op) {
  return kiwi_host_compare_pack_u32x4_pair(
      kiwi_host_compare_i32_scalar_cmp_neon(vld1q_s32(items + idx), needle, scalar_left, op),
      kiwi_host_compare_i32_scalar_cmp_neon(vld1q_s32(items + idx + 4), needle, scalar_left, op));
}

#define KIWI_INT_F64_CMP_EQ(INT_VALUES, FLOAT_VALUES) vceqq_f64((INT_VALUES), (FLOAT_VALUES))
#define KIWI_INT_F64_CMP_INT_LT_FLOAT(INT_VALUES, FLOAT_VALUES) vcltq_f64((INT_VALUES), (FLOAT_VALUES))
#define KIWI_INT_F64_CMP_INT_GT_FLOAT(INT_VALUES, FLOAT_VALUES) vcgtq_f64((INT_VALUES), (FLOAT_VALUES))
#define KIWI_INT_F64_CMP_FLOAT_LT_INT(INT_VALUES, FLOAT_VALUES) vcltq_f64((FLOAT_VALUES), (INT_VALUES))
#define KIWI_INT_F64_CMP_FLOAT_GT_INT(INT_VALUES, FLOAT_VALUES) vcgtq_f64((FLOAT_VALUES), (INT_VALUES))

#define KIWI_DEFINE_I8_F64_PACK8_NEON(SUFFIX, CMP) \
static inline uint8_t kiwi_host_compare_i8_f64_##SUFFIX##_pack8_neon( \
    const int8_t* int_items, \
    const double* float_items, \
    size_t idx) { \
  const int16x8_t i16 = vmovl_s8(vld1_s8(int_items + idx)); \
  const int32x4_t low = vmovl_s16(vget_low_s16(i16)); \
  const int32x4_t high = vmovl_s16(vget_high_s16(i16)); \
  const uint64x2_t cmp0 = CMP(kiwi_host_compare_i32x2_to_f64_neon(vget_low_s32(low)), vld1q_f64(float_items + idx)); \
  const uint64x2_t cmp1 = CMP(kiwi_host_compare_i32x2_to_f64_neon(vget_high_s32(low)), vld1q_f64(float_items + idx + 2)); \
  const uint64x2_t cmp2 = CMP(kiwi_host_compare_i32x2_to_f64_neon(vget_low_s32(high)), vld1q_f64(float_items + idx + 4)); \
  const uint64x2_t cmp3 = CMP(kiwi_host_compare_i32x2_to_f64_neon(vget_high_s32(high)), vld1q_f64(float_items + idx + 6)); \
  return kiwi_host_compare_pack_u64x2_quad(cmp0, cmp1, cmp2, cmp3); \
}

#define KIWI_DEFINE_I16_F64_PACK8_NEON(SUFFIX, CMP) \
static inline uint8_t kiwi_host_compare_i16_f64_##SUFFIX##_pack8_neon( \
    const int16_t* int_items, \
    const double* float_items, \
    size_t idx) { \
  const int16x8_t i16 = vld1q_s16(int_items + idx); \
  const int32x4_t low = vmovl_s16(vget_low_s16(i16)); \
  const int32x4_t high = vmovl_s16(vget_high_s16(i16)); \
  const uint64x2_t cmp0 = CMP(kiwi_host_compare_i32x2_to_f64_neon(vget_low_s32(low)), vld1q_f64(float_items + idx)); \
  const uint64x2_t cmp1 = CMP(kiwi_host_compare_i32x2_to_f64_neon(vget_high_s32(low)), vld1q_f64(float_items + idx + 2)); \
  const uint64x2_t cmp2 = CMP(kiwi_host_compare_i32x2_to_f64_neon(vget_low_s32(high)), vld1q_f64(float_items + idx + 4)); \
  const uint64x2_t cmp3 = CMP(kiwi_host_compare_i32x2_to_f64_neon(vget_high_s32(high)), vld1q_f64(float_items + idx + 6)); \
  return kiwi_host_compare_pack_u64x2_quad(cmp0, cmp1, cmp2, cmp3); \
}

#define KIWI_DEFINE_I32_F64_PACK8_NEON(SUFFIX, CMP) \
static inline uint8_t kiwi_host_compare_i32_f64_##SUFFIX##_pack8_neon( \
    const int32_t* int_items, \
    const double* float_items, \
    size_t idx) { \
  const int32x4_t low = vld1q_s32(int_items + idx); \
  const int32x4_t high = vld1q_s32(int_items + idx + 4); \
  const uint64x2_t cmp0 = CMP(kiwi_host_compare_i32x2_to_f64_neon(vget_low_s32(low)), vld1q_f64(float_items + idx)); \
  const uint64x2_t cmp1 = CMP(kiwi_host_compare_i32x2_to_f64_neon(vget_high_s32(low)), vld1q_f64(float_items + idx + 2)); \
  const uint64x2_t cmp2 = CMP(kiwi_host_compare_i32x2_to_f64_neon(vget_low_s32(high)), vld1q_f64(float_items + idx + 4)); \
  const uint64x2_t cmp3 = CMP(kiwi_host_compare_i32x2_to_f64_neon(vget_high_s32(high)), vld1q_f64(float_items + idx + 6)); \
  return kiwi_host_compare_pack_u64x2_quad(cmp0, cmp1, cmp2, cmp3); \
}

#define KIWI_DEFINE_I64_F64_PACK8_NEON(SUFFIX, CMP) \
static inline uint8_t kiwi_host_compare_i64_f64_##SUFFIX##_pack8_neon( \
    const int64_t* int_items, \
    const double* float_items, \
    size_t idx) { \
  const uint64x2_t cmp0 = CMP(vcvtq_f64_s64(vld1q_s64(int_items + idx)), vld1q_f64(float_items + idx)); \
  const uint64x2_t cmp1 = CMP(vcvtq_f64_s64(vld1q_s64(int_items + idx + 2)), vld1q_f64(float_items + idx + 2)); \
  const uint64x2_t cmp2 = CMP(vcvtq_f64_s64(vld1q_s64(int_items + idx + 4)), vld1q_f64(float_items + idx + 4)); \
  const uint64x2_t cmp3 = CMP(vcvtq_f64_s64(vld1q_s64(int_items + idx + 6)), vld1q_f64(float_items + idx + 6)); \
  return kiwi_host_compare_pack_u64x2_quad(cmp0, cmp1, cmp2, cmp3); \
}

#define KIWI_DEFINE_INT_F64_PACK8_SET(WIDTH) \
  KIWI_DEFINE_I##WIDTH##_F64_PACK8_NEON(eq, KIWI_INT_F64_CMP_EQ) \
  KIWI_DEFINE_I##WIDTH##_F64_PACK8_NEON(int_lt_float, KIWI_INT_F64_CMP_INT_LT_FLOAT) \
  KIWI_DEFINE_I##WIDTH##_F64_PACK8_NEON(int_gt_float, KIWI_INT_F64_CMP_INT_GT_FLOAT) \
  KIWI_DEFINE_I##WIDTH##_F64_PACK8_NEON(float_lt_int, KIWI_INT_F64_CMP_FLOAT_LT_INT) \
  KIWI_DEFINE_I##WIDTH##_F64_PACK8_NEON(float_gt_int, KIWI_INT_F64_CMP_FLOAT_GT_INT)

KIWI_DEFINE_INT_F64_PACK8_SET(8)
KIWI_DEFINE_INT_F64_PACK8_SET(16)
KIWI_DEFINE_INT_F64_PACK8_SET(32)
KIWI_DEFINE_INT_F64_PACK8_SET(64)

#undef KIWI_DEFINE_INT_F64_PACK8_SET
#undef KIWI_DEFINE_I64_F64_PACK8_NEON
#undef KIWI_DEFINE_I32_F64_PACK8_NEON
#undef KIWI_DEFINE_I16_F64_PACK8_NEON
#undef KIWI_DEFINE_I8_F64_PACK8_NEON
#undef KIWI_INT_F64_CMP_FLOAT_GT_INT
#undef KIWI_INT_F64_CMP_FLOAT_LT_INT
#undef KIWI_INT_F64_CMP_INT_GT_FLOAT
#undef KIWI_INT_F64_CMP_INT_LT_FLOAT
#undef KIWI_INT_F64_CMP_EQ

#define KIWI_I8_I16_PACK16_NEON(NAME, CMP_LOW, CMP_HIGH) \
static inline uint16_t NAME(const int8_t* narrow, const int16_t* wide, size_t idx) { \
  const int8x16_t narrow8 = vld1q_s8(narrow + idx); \
  const int16x8_t narrow_low = vmovl_s8(vget_low_s8(narrow8)); \
  const int16x8_t narrow_high = vmovl_s8(vget_high_s8(narrow8)); \
  const int16x8_t wide_low = vld1q_s16(wide + idx); \
  const int16x8_t wide_high = vld1q_s16(wide + idx + 8); \
  return kiwi_host_compare_pack_u16x8_pair((CMP_LOW), (CMP_HIGH)); \
}

KIWI_I8_I16_PACK16_NEON(
    kiwi_host_compare_i8_i16_eq_pack16_neon,
    vceqq_s16(narrow_low, wide_low),
    vceqq_s16(narrow_high, wide_high))

KIWI_I8_I16_PACK16_NEON(
    kiwi_host_compare_i8_i16_narrow_lt_wide_pack16_neon,
    vcgtq_s16(wide_low, narrow_low),
    vcgtq_s16(wide_high, narrow_high))

KIWI_I8_I16_PACK16_NEON(
    kiwi_host_compare_i8_i16_narrow_gt_wide_pack16_neon,
    vcgtq_s16(narrow_low, wide_low),
    vcgtq_s16(narrow_high, wide_high))

#undef KIWI_I8_I16_PACK16_NEON

static inline uint16x8_t kiwi_host_compare_i16_i32_cmp8_neon(
    const int16_t* narrow, const int32_t* wide, size_t idx, int narrow_left, int op) {
  const int16x8_t narrow16 = vld1q_s16(narrow + idx);
  const int32x4_t narrow_low = vmovl_s16(vget_low_s16(narrow16));
  const int32x4_t narrow_high = vmovl_s16(vget_high_s16(narrow16));
  const int32x4_t wide_low = vld1q_s32(wide + idx);
  const int32x4_t wide_high = vld1q_s32(wide + idx + 4);
  const uint32x4_t cmp_low = narrow_left ? kiwi_host_compare_i32_cmp_neon(narrow_low, wide_low, op)
                                         : kiwi_host_compare_i32_cmp_neon(wide_low, narrow_low, op);
  const uint32x4_t cmp_high = narrow_left ? kiwi_host_compare_i32_cmp_neon(narrow_high, wide_high, op)
                                          : kiwi_host_compare_i32_cmp_neon(wide_high, narrow_high, op);
  return vcombine_u16(vmovn_u32(cmp_low), vmovn_u32(cmp_high));
}

static inline uint64_t kiwi_host_compare_i16_i32_mask_neon(
    const int16_t* narrow, const int32_t* wide, size_t idx, int narrow_left, int op) {
  return kiwi_host_compare_mask_u16x8(kiwi_host_compare_i16_i32_cmp8_neon(narrow, wide, idx, narrow_left, op));
}

static inline uint16_t kiwi_host_compare_i16_i32_pack16_neon(
    const int16_t* narrow, const int32_t* wide, size_t idx, int narrow_left, int op) {
  return kiwi_host_compare_pack_u16x8_pair(
      kiwi_host_compare_i16_i32_cmp8_neon(narrow, wide, idx, narrow_left, op),
      kiwi_host_compare_i16_i32_cmp8_neon(narrow, wide, idx + 8, narrow_left, op));
}

static inline uint64_t kiwi_host_compare_i32_i64_mask_neon(
    const int32_t* narrow, const int64_t* wide, size_t idx, int narrow_left, int op) {
  const int32x4_t narrow32 = vld1q_s32(narrow + idx);
  const int64x2_t narrow_low = vmovl_s32(vget_low_s32(narrow32));
  const int64x2_t narrow_high = vmovl_s32(vget_high_s32(narrow32));
  const int64x2_t wide_low = vld1q_s64(wide + idx);
  const int64x2_t wide_high = vld1q_s64(wide + idx + 2);
  const uint64x2_t cmp_low = narrow_left ? kiwi_host_compare_i64_cmp_neon(narrow_low, wide_low, op)
                                         : kiwi_host_compare_i64_cmp_neon(wide_low, narrow_low, op);
  const uint64x2_t cmp_high = narrow_left ? kiwi_host_compare_i64_cmp_neon(narrow_high, wide_high, op)
                                          : kiwi_host_compare_i64_cmp_neon(wide_high, narrow_high, op);
  return kiwi_host_compare_mask_u64x2(cmp_low) | (kiwi_host_compare_mask_u64x2(cmp_high) << 2);
}

static inline uint8_t kiwi_host_compare_i32_i64_pack8_neon(
    const int32_t* narrow, const int64_t* wide, size_t idx, int narrow_left, int op) {
  const int32x4_t narrow0 = vld1q_s32(narrow + idx);
  const int64x2_t narrow0_low = vmovl_s32(vget_low_s32(narrow0));
  const int64x2_t narrow0_high = vmovl_s32(vget_high_s32(narrow0));
  const int64x2_t wide0_low = vld1q_s64(wide + idx);
  const int64x2_t wide0_high = vld1q_s64(wide + idx + 2);
  const uint64x2_t cmp0 = narrow_left ? kiwi_host_compare_i64_cmp_neon(narrow0_low, wide0_low, op)
                                      : kiwi_host_compare_i64_cmp_neon(wide0_low, narrow0_low, op);
  const uint64x2_t cmp1 = narrow_left ? kiwi_host_compare_i64_cmp_neon(narrow0_high, wide0_high, op)
                                      : kiwi_host_compare_i64_cmp_neon(wide0_high, narrow0_high, op);

  const int32x4_t narrow1 = vld1q_s32(narrow + idx + 4);
  const int64x2_t narrow1_low = vmovl_s32(vget_low_s32(narrow1));
  const int64x2_t narrow1_high = vmovl_s32(vget_high_s32(narrow1));
  const int64x2_t wide1_low = vld1q_s64(wide + idx + 4);
  const int64x2_t wide1_high = vld1q_s64(wide + idx + 6);
  const uint64x2_t cmp2 = narrow_left ? kiwi_host_compare_i64_cmp_neon(narrow1_low, wide1_low, op)
                                      : kiwi_host_compare_i64_cmp_neon(wide1_low, narrow1_low, op);
  const uint64x2_t cmp3 = narrow_left ? kiwi_host_compare_i64_cmp_neon(narrow1_high, wide1_high, op)
                                      : kiwi_host_compare_i64_cmp_neon(wide1_high, narrow1_high, op);
  return kiwi_host_compare_pack_u64x2_quad(cmp0, cmp1, cmp2, cmp3);
}

#define KIWI_NEON_WORD_LOOP(LANES, LOAD_COMPARE, TAIL_COMPARE) \
  KiwiHostCompareSummary summary = kiwi_host_compare_summary_empty(); \
  size_t out_idx = 0; \
  for (size_t base = 0; base < len; base += 64) { \
    const size_t active = len - base < 64 ? len - base : 64; \
    uint64_t word = 0; \
    size_t bit = 0; \
    while (bit + (LANES) <= active) { \
      word |= (LOAD_COMPARE(base + bit)) << bit; \
      bit += (LANES); \
    } \
    while (bit < active) { \
      if (TAIL_COMPARE(base + bit)) word |= UINT64_C(1) << bit; \
      ++bit; \
    } \
    kiwi_host_compare_summary_note_word(&summary, word, active); \
    out[out_idx++] = word; \
  } \
  kiwi_host_compare_summary_publish(summary);

#define KIWI_NEON_PACK32_LOOP(LOAD_PACK32, TAIL_COMPARE) \
  KiwiHostCompareSummaryAccum summary = kiwi_host_compare_summary_accum_empty(); \
  size_t base = 0; \
  for (; base + 64 <= len; base += 64) { \
    const uint32_t lo = (LOAD_PACK32(base)); \
    const uint32_t hi = (LOAD_PACK32(base + 32)); \
    const uint64_t word = (uint64_t)lo | ((uint64_t)hi << 32); \
    out[base / 64] = word; \
    kiwi_host_compare_summary_accum_word(&summary, word, 64); \
  } \
  if (base < len) { \
    const size_t active = len - base; \
    uint64_t word = 0; \
    size_t bit = 0; \
    while (bit + 32 <= active) { \
      word |= (uint64_t)(LOAD_PACK32(base + bit)) << bit; \
      bit += 32; \
    } \
    while (bit < active) { \
      if (TAIL_COMPARE(base + bit)) word |= UINT64_C(1) << bit; \
      ++bit; \
    } \
    kiwi_host_compare_summary_accum_word(&summary, word, active); \
    out[base / 64] = word; \
  } \
  kiwi_host_compare_summary_publish(kiwi_host_compare_summary_accum_finish(summary));

#define KIWI_NEON_PACK16_LOOP(LOAD_PACK16, TAIL_COMPARE) \
  KiwiHostCompareSummaryAccum summary = kiwi_host_compare_summary_accum_empty(); \
  size_t base = 0; \
  for (; base + 64 <= len; base += 64) { \
    const uint16_t b0 = (LOAD_PACK16(base)); \
    const uint16_t b1 = (LOAD_PACK16(base + 16)); \
    const uint16_t b2 = (LOAD_PACK16(base + 32)); \
    const uint16_t b3 = (LOAD_PACK16(base + 48)); \
    const uint64_t word = (uint64_t)b0 | ((uint64_t)b1 << 16) | ((uint64_t)b2 << 32) | ((uint64_t)b3 << 48); \
    out[base / 64] = word; \
    kiwi_host_compare_summary_accum_word(&summary, word, 64); \
  } \
  if (base < len) { \
    const size_t active = len - base; \
    uint64_t word = 0; \
    size_t bit = 0; \
    while (bit + 16 <= active) { \
      word |= (uint64_t)(LOAD_PACK16(base + bit)) << bit; \
      bit += 16; \
    } \
    while (bit < active) { \
      if (TAIL_COMPARE(base + bit)) word |= UINT64_C(1) << bit; \
      ++bit; \
    } \
    kiwi_host_compare_summary_accum_word(&summary, word, active); \
    out[base / 64] = word; \
  } \
  kiwi_host_compare_summary_publish(kiwi_host_compare_summary_accum_finish(summary));

#define KIWI_NEON_PACK8_LOOP(LOAD_PACK8, TAIL_COMPARE) \
  KiwiHostCompareSummaryAccum summary = kiwi_host_compare_summary_accum_empty(); \
  size_t base = 0; \
  for (; base + 64 <= len; base += 64) { \
    const uint8_t b0 = (LOAD_PACK8(base)); \
    const uint8_t b1 = (LOAD_PACK8(base + 8)); \
    const uint8_t b2 = (LOAD_PACK8(base + 16)); \
    const uint8_t b3 = (LOAD_PACK8(base + 24)); \
    const uint8_t b4 = (LOAD_PACK8(base + 32)); \
    const uint8_t b5 = (LOAD_PACK8(base + 40)); \
    const uint8_t b6 = (LOAD_PACK8(base + 48)); \
    const uint8_t b7 = (LOAD_PACK8(base + 56)); \
    const uint64_t word = (uint64_t)b0 | ((uint64_t)b1 << 8) | ((uint64_t)b2 << 16) | ((uint64_t)b3 << 24) | ((uint64_t)b4 << 32) | ((uint64_t)b5 << 40) | ((uint64_t)b6 << 48) | ((uint64_t)b7 << 56); \
    out[base / 64] = word; \
    kiwi_host_compare_summary_accum_word(&summary, word, 64); \
  } \
  if (base < len) { \
    const size_t active = len - base; \
    uint64_t word = 0; \
    size_t bit = 0; \
    while (bit + 8 <= active) { \
      word |= (uint64_t)(LOAD_PACK8(base + bit)) << bit; \
      bit += 8; \
    } \
    while (bit < active) { \
      if (TAIL_COMPARE(base + bit)) word |= UINT64_C(1) << bit; \
      ++bit; \
    } \
    kiwi_host_compare_summary_accum_word(&summary, word, active); \
    out[base / 64] = word; \
  } \
  kiwi_host_compare_summary_publish(kiwi_host_compare_summary_accum_finish(summary));

#define KIWI_NEON_INT_F64_PACK8_LOOP(INT_PTR, PACK_FN, TAIL_COMPARE) \
  KiwiHostCompareSummaryAccum summary = kiwi_host_compare_summary_accum_empty(); \
  size_t base = 0; \
  for (; base + 64 <= len; base += 64) { \
    const uint8_t b0 = PACK_FN((INT_PTR), float_items, base); \
    const uint8_t b1 = PACK_FN((INT_PTR), float_items, base + 8); \
    const uint8_t b2 = PACK_FN((INT_PTR), float_items, base + 16); \
    const uint8_t b3 = PACK_FN((INT_PTR), float_items, base + 24); \
    const uint8_t b4 = PACK_FN((INT_PTR), float_items, base + 32); \
    const uint8_t b5 = PACK_FN((INT_PTR), float_items, base + 40); \
    const uint8_t b6 = PACK_FN((INT_PTR), float_items, base + 48); \
    const uint8_t b7 = PACK_FN((INT_PTR), float_items, base + 56); \
    const uint64_t word = (uint64_t)b0 | ((uint64_t)b1 << 8) | ((uint64_t)b2 << 16) | ((uint64_t)b3 << 24) | ((uint64_t)b4 << 32) | ((uint64_t)b5 << 40) | ((uint64_t)b6 << 48) | ((uint64_t)b7 << 56); \
    out[base / 64] = word; \
    kiwi_host_compare_summary_accum_word(&summary, word, 64); \
  } \
  if (base < len) { \
    const size_t active = len - base; \
    uint64_t word = 0; \
    size_t bit = 0; \
    while (bit + 8 <= active) { \
      word |= (uint64_t)PACK_FN((INT_PTR), float_items, base + bit) << bit; \
      bit += 8; \
    } \
    while (bit < active) { \
      if (TAIL_COMPARE(base + bit)) word |= UINT64_C(1) << bit; \
      ++bit; \
    } \
    kiwi_host_compare_summary_accum_word(&summary, word, active); \
    out[base / 64] = word; \
  } \
  kiwi_host_compare_summary_publish(kiwi_host_compare_summary_accum_finish(summary));

#define KIWI_NEON_RUN_INT_F64_PACK8(INT_PTR, PREFIX) \
  do { \
    if (op == KIWI_HOST_COMPARE_EQ) { \
      KIWI_NEON_INT_F64_PACK8_LOOP((INT_PTR), PREFIX##_eq_pack8_neon, TAIL_COMPARE) \
    } else if (int_left) { \
      if (op == KIWI_HOST_COMPARE_LT) { \
        KIWI_NEON_INT_F64_PACK8_LOOP((INT_PTR), PREFIX##_int_lt_float_pack8_neon, TAIL_COMPARE) \
      } else { \
        KIWI_NEON_INT_F64_PACK8_LOOP((INT_PTR), PREFIX##_int_gt_float_pack8_neon, TAIL_COMPARE) \
      } \
    } else { \
      if (op == KIWI_HOST_COMPARE_LT) { \
        KIWI_NEON_INT_F64_PACK8_LOOP((INT_PTR), PREFIX##_float_lt_int_pack8_neon, TAIL_COMPARE) \
      } else { \
        KIWI_NEON_INT_F64_PACK8_LOOP((INT_PTR), PREFIX##_float_gt_int_pack8_neon, TAIL_COMPARE) \
      } \
    } \
  } while (0)

void kiwi_host_compare_i8_array_neon(uint64_t* out, const int8_t* left, const int8_t* right, size_t len, int op) {
#define LOAD_PACK32(IDX) kiwi_host_compare_i8_array_pack32_neon(left, right, (IDX), op)
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_NEON_PACK32_LOOP(LOAD_PACK32, TAIL_COMPARE)
#undef LOAD_PACK32
#undef TAIL_COMPARE
}

void kiwi_host_compare_i16_array_neon(uint64_t* out, const int16_t* left, const int16_t* right, size_t len, int op) {
#define LOAD_PACK16(IDX) kiwi_host_compare_i16_array_pack16_neon(left, right, (IDX), op)
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_NEON_PACK16_LOOP(LOAD_PACK16, TAIL_COMPARE)
#undef LOAD_PACK16
#undef TAIL_COMPARE
}

void kiwi_host_compare_i32_array_neon(uint64_t* out, const int32_t* left, const int32_t* right, size_t len, int op) {
#define LOAD_PACK8(IDX) kiwi_host_compare_i32_array_pack8_neon(left, right, (IDX), op)
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_NEON_PACK8_LOOP(LOAD_PACK8, TAIL_COMPARE)
#undef LOAD_PACK8
#undef TAIL_COMPARE
}

void kiwi_host_compare_i64_array_neon(uint64_t* out, const int64_t* left, const int64_t* right, size_t len, int op) {
#define LOAD_COMPARE(IDX) kiwi_host_compare_mask_u64x2(op == KIWI_HOST_COMPARE_EQ ? vceqq_s64(vld1q_s64(left + (IDX)), vld1q_s64(right + (IDX))) : op == KIWI_HOST_COMPARE_LT ? vcgtq_s64(vld1q_s64(right + (IDX)), vld1q_s64(left + (IDX))) : vcgtq_s64(vld1q_s64(left + (IDX)), vld1q_s64(right + (IDX))))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_NEON_WORD_LOOP(2, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_f64_array_neon(uint64_t* out, const double* left, const double* right, size_t len, int op) {
#define LOAD_COMPARE(IDX) kiwi_host_compare_mask_u64x2(op == KIWI_HOST_COMPARE_EQ ? vceqq_f64(vld1q_f64(left + (IDX)), vld1q_f64(right + (IDX))) : op == KIWI_HOST_COMPARE_LT ? vcltq_f64(vld1q_f64(left + (IDX)), vld1q_f64(right + (IDX))) : vcgtq_f64(vld1q_f64(left + (IDX)), vld1q_f64(right + (IDX))))
#define TAIL_COMPARE(IDX) kiwi_host_compare_f64_tail(left[(IDX)], right[(IDX)], op)
  KIWI_NEON_WORD_LOOP(2, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_int_f64_array_neon(
    uint64_t* out,
    const void* int_items,
    int int_width,
    const double* float_items,
    size_t len,
    int int_left,
    int op) {
#define TAIL_COMPARE(IDX) kiwi_host_compare_int_f64_tail(int_items, int_width, float_items, (IDX), int_left, op)
  switch (int_width) {
    case 1: {
      KIWI_NEON_RUN_INT_F64_PACK8((const int8_t*)int_items, kiwi_host_compare_i8_f64);
      break;
    }
    case 2: {
      KIWI_NEON_RUN_INT_F64_PACK8((const int16_t*)int_items, kiwi_host_compare_i16_f64);
      break;
    }
    case 4: {
      KIWI_NEON_RUN_INT_F64_PACK8((const int32_t*)int_items, kiwi_host_compare_i32_f64);
      break;
    }
    case 8: {
      KIWI_NEON_RUN_INT_F64_PACK8((const int64_t*)int_items, kiwi_host_compare_i64_f64);
      break;
    }
    default:
      kiwi_host_compare_int_f64_array_scalar(out, int_items, int_width, float_items, len, int_left, op);
      break;
  }
#undef TAIL_COMPARE
}

void kiwi_host_compare_int_mixed_array_neon(uint64_t* out, const void* left, int left_width, const void* right, int right_width, size_t len, int op) {
  if ((left_width == 1 && right_width == 2) || (left_width == 2 && right_width == 1)) {
	    const int narrow_left = left_width == 1;
	    const int8_t* narrow = narrow_left ? (const int8_t*)left : (const int8_t*)right;
	    const int16_t* wide = narrow_left ? (const int16_t*)right : (const int16_t*)left;
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(kiwi_host_compare_load_int_tail(left, left_width, (IDX)), kiwi_host_compare_load_int_tail(right, right_width, (IDX)), op)
    if (op == KIWI_HOST_COMPARE_EQ) {
#define LOAD_PACK16(IDX) kiwi_host_compare_i8_i16_eq_pack16_neon(narrow, wide, (IDX))
      KIWI_NEON_PACK16_LOOP(LOAD_PACK16, TAIL_COMPARE)
#undef LOAD_PACK16
    } else if ((op == KIWI_HOST_COMPARE_LT && narrow_left) || (op == KIWI_HOST_COMPARE_GT && !narrow_left)) {
#define LOAD_PACK16(IDX) kiwi_host_compare_i8_i16_narrow_lt_wide_pack16_neon(narrow, wide, (IDX))
      KIWI_NEON_PACK16_LOOP(LOAD_PACK16, TAIL_COMPARE)
#undef LOAD_PACK16
    } else {
#define LOAD_PACK16(IDX) kiwi_host_compare_i8_i16_narrow_gt_wide_pack16_neon(narrow, wide, (IDX))
      KIWI_NEON_PACK16_LOOP(LOAD_PACK16, TAIL_COMPARE)
#undef LOAD_PACK16
    }
#undef TAIL_COMPARE
	    return;
	  }

  if ((left_width == 2 && right_width == 4) || (left_width == 4 && right_width == 2)) {
    const int narrow_left = left_width == 2;
    const int16_t* narrow = narrow_left ? (const int16_t*)left : (const int16_t*)right;
    const int32_t* wide = narrow_left ? (const int32_t*)right : (const int32_t*)left;
#define LOAD_PACK16(IDX) kiwi_host_compare_i16_i32_pack16_neon(narrow, wide, (IDX), narrow_left, op)
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(kiwi_host_compare_load_int_tail(left, left_width, (IDX)), kiwi_host_compare_load_int_tail(right, right_width, (IDX)), op)
    KIWI_NEON_PACK16_LOOP(LOAD_PACK16, TAIL_COMPARE)
#undef LOAD_PACK16
#undef TAIL_COMPARE
    return;
  }

  if ((left_width == 4 && right_width == 8) || (left_width == 8 && right_width == 4)) {
    const int narrow_left = left_width == 4;
    const int32_t* narrow = narrow_left ? (const int32_t*)left : (const int32_t*)right;
    const int64_t* wide = narrow_left ? (const int64_t*)right : (const int64_t*)left;
#define LOAD_PACK8(IDX) kiwi_host_compare_i32_i64_pack8_neon(narrow, wide, (IDX), narrow_left, op)
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(kiwi_host_compare_load_int_tail(left, left_width, (IDX)), kiwi_host_compare_load_int_tail(right, right_width, (IDX)), op)
    KIWI_NEON_PACK8_LOOP(LOAD_PACK8, TAIL_COMPARE)
#undef LOAD_PACK8
#undef TAIL_COMPARE
    return;
  }

  const int width = left_width > right_width ? left_width : right_width;
  switch (width) {
    case 2: {
#define LOAD_COMPARE(IDX) kiwi_host_compare_i16_mask_neon(kiwi_host_compare_load_as_i16_neon(left, left_width, (IDX)), kiwi_host_compare_load_as_i16_neon(right, right_width, (IDX)), op)
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(kiwi_host_compare_load_int_tail(left, left_width, (IDX)), kiwi_host_compare_load_int_tail(right, right_width, (IDX)), op)
      KIWI_NEON_WORD_LOOP(8, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
      return;
    }
    case 4: {
#define LOAD_COMPARE(IDX) kiwi_host_compare_i32_mask_neon(kiwi_host_compare_load_as_i32_neon(left, left_width, (IDX)), kiwi_host_compare_load_as_i32_neon(right, right_width, (IDX)), op)
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(kiwi_host_compare_load_int_tail(left, left_width, (IDX)), kiwi_host_compare_load_int_tail(right, right_width, (IDX)), op)
      KIWI_NEON_WORD_LOOP(4, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
      return;
    }
    case 8: {
#define LOAD_COMPARE(IDX) kiwi_host_compare_i64_mask_neon(kiwi_host_compare_load_as_i64_neon(left, left_width, (IDX)), kiwi_host_compare_load_as_i64_neon(right, right_width, (IDX)), op)
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(kiwi_host_compare_load_int_tail(left, left_width, (IDX)), kiwi_host_compare_load_int_tail(right, right_width, (IDX)), op)
      KIWI_NEON_WORD_LOOP(2, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
      return;
    }
    default:
      kiwi_host_compare_int_mixed_array_scalar(out, left, left_width, right, right_width, len, op);
      return;
  }
}

void kiwi_host_compare_i8_scalar_neon(uint64_t* out, const int8_t* items, size_t len, int8_t scalar, int scalar_left, int op) {
  const int8x16_t needle = vdupq_n_s8(scalar);
#define LOAD_PACK32(IDX) kiwi_host_compare_i8_scalar_pack32_neon(items, (IDX), needle, scalar_left, op)
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_NEON_PACK32_LOOP(LOAD_PACK32, TAIL_COMPARE)
#undef LOAD_PACK32
#undef TAIL_COMPARE
}

void kiwi_host_compare_i16_scalar_neon(uint64_t* out, const int16_t* items, size_t len, int16_t scalar, int scalar_left, int op) {
  const int16x8_t needle = vdupq_n_s16(scalar);
#define LOAD_PACK16(IDX) kiwi_host_compare_i16_scalar_pack16_neon(items, (IDX), needle, scalar_left, op)
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_NEON_PACK16_LOOP(LOAD_PACK16, TAIL_COMPARE)
#undef LOAD_PACK16
#undef TAIL_COMPARE
}

void kiwi_host_compare_i32_scalar_neon(uint64_t* out, const int32_t* items, size_t len, int32_t scalar, int scalar_left, int op) {
  const int32x4_t needle = vdupq_n_s32(scalar);
#define LOAD_PACK8(IDX) kiwi_host_compare_i32_scalar_pack8_neon(items, (IDX), needle, scalar_left, op)
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_NEON_PACK8_LOOP(LOAD_PACK8, TAIL_COMPARE)
#undef LOAD_PACK8
#undef TAIL_COMPARE
}

void kiwi_host_compare_i64_scalar_neon(uint64_t* out, const int64_t* items, size_t len, int64_t scalar, int scalar_left, int op) {
  const int64x2_t needle = vdupq_n_s64(scalar);
#define LOAD_COMPARE(IDX) kiwi_host_compare_mask_u64x2(op == KIWI_HOST_COMPARE_EQ ? vceqq_s64(needle, vld1q_s64(items + (IDX))) : scalar_left ? (op == KIWI_HOST_COMPARE_LT ? vcgtq_s64(vld1q_s64(items + (IDX)), needle) : vcgtq_s64(needle, vld1q_s64(items + (IDX)))) : (op == KIWI_HOST_COMPARE_LT ? vcgtq_s64(needle, vld1q_s64(items + (IDX))) : vcgtq_s64(vld1q_s64(items + (IDX)), needle)))
#define TAIL_COMPARE(IDX) kiwi_host_compare_i64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_NEON_WORD_LOOP(2, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}

void kiwi_host_compare_f64_scalar_neon(uint64_t* out, const double* items, size_t len, double scalar, int scalar_left, int op) {
  const float64x2_t needle = vdupq_n_f64(scalar);
#define LOAD_COMPARE(IDX) kiwi_host_compare_mask_u64x2(op == KIWI_HOST_COMPARE_EQ ? vceqq_f64(needle, vld1q_f64(items + (IDX))) : scalar_left ? (op == KIWI_HOST_COMPARE_LT ? vcltq_f64(needle, vld1q_f64(items + (IDX))) : vcgtq_f64(needle, vld1q_f64(items + (IDX)))) : (op == KIWI_HOST_COMPARE_LT ? vcltq_f64(vld1q_f64(items + (IDX)), needle) : vcgtq_f64(vld1q_f64(items + (IDX)), needle)))
#define TAIL_COMPARE(IDX) kiwi_host_compare_f64_tail(scalar_left ? scalar : items[(IDX)], scalar_left ? items[(IDX)] : scalar, op)
  KIWI_NEON_WORD_LOOP(2, LOAD_COMPARE, TAIL_COMPARE)
#undef LOAD_COMPARE
#undef TAIL_COMPARE
}
