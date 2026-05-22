#include "host_dyad.h"

#if defined(__aarch64__)
#include <arm_neon.h>
#include <math.h>

static inline float64x2_t kiwi_f64_add_v(float64x2_t a, float64x2_t b) { return vaddq_f64(a, b); }
static inline float64x2_t kiwi_f64_sub_v(float64x2_t a, float64x2_t b) { return vsubq_f64(a, b); }
static inline float64x2_t kiwi_f64_mul_v(float64x2_t a, float64x2_t b) { return vmulq_f64(a, b); }
static inline float64x2_t kiwi_f64_div_v(float64x2_t a, float64x2_t b) { return vdivq_f64(a, b); }
static inline float64x2_t kiwi_f64_min_v(float64x2_t a, float64x2_t b) { return vminnmq_f64(a, b); }
static inline float64x2_t kiwi_f64_max_v(float64x2_t a, float64x2_t b) { return vmaxnmq_f64(a, b); }

static inline double kiwi_f64_add_s(double a, double b) { return a + b; }
static inline double kiwi_f64_sub_s(double a, double b) { return a - b; }
static inline double kiwi_f64_mul_s(double a, double b) { return a * b; }
static inline double kiwi_f64_div_s(double a, double b) { return a / b; }
static inline double kiwi_f64_min_s(double a, double b) { return fmin(a, b); }
static inline double kiwi_f64_max_s(double a, double b) { return fmax(a, b); }

#define KIWI_F64_ARRAY_LOOP(NAME, VOP, SOP)                                                       \
  static void kiwi_dyad_f64_array_##NAME(double* out, const double* left, const double* right,     \
                                         size_t len) {                                             \
    size_t i = 0;                                                                                  \
    for (; i + 8 <= len; i += 8) {                                                                 \
      float64x2_t a0 = vld1q_f64(left + i);                                                        \
      float64x2_t b0 = vld1q_f64(right + i);                                                       \
      float64x2_t a1 = vld1q_f64(left + i + 2);                                                    \
      float64x2_t b1 = vld1q_f64(right + i + 2);                                                   \
      float64x2_t a2 = vld1q_f64(left + i + 4);                                                    \
      float64x2_t b2 = vld1q_f64(right + i + 4);                                                   \
      float64x2_t a3 = vld1q_f64(left + i + 6);                                                    \
      float64x2_t b3 = vld1q_f64(right + i + 6);                                                   \
      vst1q_f64(out + i, VOP(a0, b0));                                                             \
      vst1q_f64(out + i + 2, VOP(a1, b1));                                                         \
      vst1q_f64(out + i + 4, VOP(a2, b2));                                                         \
      vst1q_f64(out + i + 6, VOP(a3, b3));                                                         \
    }                                                                                              \
    for (; i + 2 <= len; i += 2) {                                                                 \
      float64x2_t a = vld1q_f64(left + i);                                                         \
      float64x2_t b = vld1q_f64(right + i);                                                        \
      vst1q_f64(out + i, VOP(a, b));                                                               \
    }                                                                                              \
    for (; i < len; ++i) {                                                                         \
      out[i] = SOP(left[i], right[i]);                                                             \
    }                                                                                              \
  }

#define KIWI_F64_SCALAR_LOOP(NAME, VOP, SOP)                                                       \
  static void kiwi_dyad_f64_scalar_##NAME(double* out, double scalar, const double* items,          \
                                          size_t len, int scalar_left) {                            \
    float64x2_t scalar_v = vdupq_n_f64(scalar);                                                     \
    size_t i = 0;                                                                                  \
    if (scalar_left) {                                                                             \
      for (; i + 8 <= len; i += 8) {                                                               \
        float64x2_t b0 = vld1q_f64(items + i);                                                     \
        float64x2_t b1 = vld1q_f64(items + i + 2);                                                 \
        float64x2_t b2 = vld1q_f64(items + i + 4);                                                 \
        float64x2_t b3 = vld1q_f64(items + i + 6);                                                 \
        vst1q_f64(out + i, VOP(scalar_v, b0));                                                     \
        vst1q_f64(out + i + 2, VOP(scalar_v, b1));                                                 \
        vst1q_f64(out + i + 4, VOP(scalar_v, b2));                                                 \
        vst1q_f64(out + i + 6, VOP(scalar_v, b3));                                                 \
      }                                                                                            \
      for (; i + 2 <= len; i += 2) {                                                               \
        float64x2_t b = vld1q_f64(items + i);                                                      \
        vst1q_f64(out + i, VOP(scalar_v, b));                                                      \
      }                                                                                            \
      for (; i < len; ++i) {                                                                       \
        out[i] = SOP(scalar, items[i]);                                                            \
      }                                                                                            \
    } else {                                                                                       \
      for (; i + 8 <= len; i += 8) {                                                               \
        float64x2_t a0 = vld1q_f64(items + i);                                                     \
        float64x2_t a1 = vld1q_f64(items + i + 2);                                                 \
        float64x2_t a2 = vld1q_f64(items + i + 4);                                                 \
        float64x2_t a3 = vld1q_f64(items + i + 6);                                                 \
        vst1q_f64(out + i, VOP(a0, scalar_v));                                                     \
        vst1q_f64(out + i + 2, VOP(a1, scalar_v));                                                 \
        vst1q_f64(out + i + 4, VOP(a2, scalar_v));                                                 \
        vst1q_f64(out + i + 6, VOP(a3, scalar_v));                                                 \
      }                                                                                            \
      for (; i + 2 <= len; i += 2) {                                                               \
        float64x2_t a = vld1q_f64(items + i);                                                      \
        vst1q_f64(out + i, VOP(a, scalar_v));                                                      \
      }                                                                                            \
      for (; i < len; ++i) {                                                                       \
        out[i] = SOP(items[i], scalar);                                                            \
      }                                                                                            \
    }                                                                                              \
  }

KIWI_F64_ARRAY_LOOP(add, kiwi_f64_add_v, kiwi_f64_add_s)
KIWI_F64_ARRAY_LOOP(sub, kiwi_f64_sub_v, kiwi_f64_sub_s)
KIWI_F64_ARRAY_LOOP(mul, kiwi_f64_mul_v, kiwi_f64_mul_s)
KIWI_F64_ARRAY_LOOP(div, kiwi_f64_div_v, kiwi_f64_div_s)
KIWI_F64_ARRAY_LOOP(min, kiwi_f64_min_v, kiwi_f64_min_s)
KIWI_F64_ARRAY_LOOP(max, kiwi_f64_max_v, kiwi_f64_max_s)

KIWI_F64_SCALAR_LOOP(add, kiwi_f64_add_v, kiwi_f64_add_s)
KIWI_F64_SCALAR_LOOP(sub, kiwi_f64_sub_v, kiwi_f64_sub_s)
KIWI_F64_SCALAR_LOOP(mul, kiwi_f64_mul_v, kiwi_f64_mul_s)
KIWI_F64_SCALAR_LOOP(div, kiwi_f64_div_v, kiwi_f64_div_s)
KIWI_F64_SCALAR_LOOP(min, kiwi_f64_min_v, kiwi_f64_min_s)
KIWI_F64_SCALAR_LOOP(max, kiwi_f64_max_v, kiwi_f64_max_s)

static inline int64x2_t kiwi_minq_s64(int64x2_t a, int64x2_t b) {
  uint64x2_t mask = vcgtq_s64(a, b);
  return vreinterpretq_s64_u64(vbslq_u64(mask, vreinterpretq_u64_s64(b), vreinterpretq_u64_s64(a)));
}

static inline int64x2_t kiwi_maxq_s64(int64x2_t a, int64x2_t b) {
  uint64x2_t mask = vcgtq_s64(a, b);
  return vreinterpretq_s64_u64(vbslq_u64(mask, vreinterpretq_u64_s64(a), vreinterpretq_u64_s64(b)));
}

static inline int8x16_t kiwi_addq_s8(int8x16_t a, int8x16_t b) { return vaddq_s8(a, b); }
static inline int16x8_t kiwi_addq_s16(int16x8_t a, int16x8_t b) { return vaddq_s16(a, b); }
static inline int32x4_t kiwi_addq_s32(int32x4_t a, int32x4_t b) { return vaddq_s32(a, b); }
static inline int64x2_t kiwi_addq_s64(int64x2_t a, int64x2_t b) { return vaddq_s64(a, b); }

static inline int8x16_t kiwi_subq_s8(int8x16_t a, int8x16_t b) { return vsubq_s8(a, b); }
static inline int16x8_t kiwi_subq_s16(int16x8_t a, int16x8_t b) { return vsubq_s16(a, b); }
static inline int32x4_t kiwi_subq_s32(int32x4_t a, int32x4_t b) { return vsubq_s32(a, b); }
static inline int64x2_t kiwi_subq_s64(int64x2_t a, int64x2_t b) { return vsubq_s64(a, b); }

static inline int8x16_t kiwi_mulq_s8(int8x16_t a, int8x16_t b) { return vmulq_s8(a, b); }
static inline int16x8_t kiwi_mulq_s16(int16x8_t a, int16x8_t b) { return vmulq_s16(a, b); }
static inline int32x4_t kiwi_mulq_s32(int32x4_t a, int32x4_t b) { return vmulq_s32(a, b); }

static inline int8x16_t kiwi_minq_s8(int8x16_t a, int8x16_t b) { return vminq_s8(a, b); }
static inline int16x8_t kiwi_minq_s16(int16x8_t a, int16x8_t b) { return vminq_s16(a, b); }
static inline int32x4_t kiwi_minq_s32(int32x4_t a, int32x4_t b) { return vminq_s32(a, b); }

static inline int8x16_t kiwi_maxq_s8(int8x16_t a, int8x16_t b) { return vmaxq_s8(a, b); }
static inline int16x8_t kiwi_maxq_s16(int16x8_t a, int16x8_t b) { return vmaxq_s16(a, b); }
static inline int32x4_t kiwi_maxq_s32(int32x4_t a, int32x4_t b) { return vmaxq_s32(a, b); }

static inline int8_t kiwi_i8_add_s(int8_t a, int8_t b) { return (int8_t)(a + b); }
static inline int16_t kiwi_i16_add_s(int16_t a, int16_t b) { return (int16_t)(a + b); }
static inline int32_t kiwi_i32_add_s(int32_t a, int32_t b) { return a + b; }
static inline int64_t kiwi_i64_add_s(int64_t a, int64_t b) { return a + b; }

static inline int8_t kiwi_i8_sub_s(int8_t a, int8_t b) { return (int8_t)(a - b); }
static inline int16_t kiwi_i16_sub_s(int16_t a, int16_t b) { return (int16_t)(a - b); }
static inline int32_t kiwi_i32_sub_s(int32_t a, int32_t b) { return a - b; }
static inline int64_t kiwi_i64_sub_s(int64_t a, int64_t b) { return a - b; }

static inline int8_t kiwi_i8_mul_s(int8_t a, int8_t b) { return (int8_t)(a * b); }
static inline int16_t kiwi_i16_mul_s(int16_t a, int16_t b) { return (int16_t)(a * b); }
static inline int32_t kiwi_i32_mul_s(int32_t a, int32_t b) { return a * b; }

static inline int8_t kiwi_i8_min_s(int8_t a, int8_t b) { return a < b ? a : b; }
static inline int16_t kiwi_i16_min_s(int16_t a, int16_t b) { return a < b ? a : b; }
static inline int32_t kiwi_i32_min_s(int32_t a, int32_t b) { return a < b ? a : b; }
static inline int64_t kiwi_i64_min_s(int64_t a, int64_t b) { return a < b ? a : b; }

static inline int8_t kiwi_i8_max_s(int8_t a, int8_t b) { return a > b ? a : b; }
static inline int16_t kiwi_i16_max_s(int16_t a, int16_t b) { return a > b ? a : b; }
static inline int32_t kiwi_i32_max_s(int32_t a, int32_t b) { return a > b ? a : b; }
static inline int64_t kiwi_i64_max_s(int64_t a, int64_t b) { return a > b ? a : b; }

#define KIWI_INT_ARRAY_LOOP(NAME, TYPE, VEC, LANES, LOAD, STORE, VOP, SOP)                         \
  static void kiwi_dyad_##NAME##_array(TYPE* out, const TYPE* left, const TYPE* right, size_t len) {\
    size_t i = 0;                                                                                  \
    for (; i + (LANES) * 4 <= len; i += (LANES) * 4) {                                             \
      VEC a0 = LOAD(left + i);                                                                     \
      VEC b0 = LOAD(right + i);                                                                    \
      VEC a1 = LOAD(left + i + (LANES));                                                           \
      VEC b1 = LOAD(right + i + (LANES));                                                          \
      VEC a2 = LOAD(left + i + (LANES) * 2);                                                       \
      VEC b2 = LOAD(right + i + (LANES) * 2);                                                      \
      VEC a3 = LOAD(left + i + (LANES) * 3);                                                       \
      VEC b3 = LOAD(right + i + (LANES) * 3);                                                      \
      STORE(out + i, VOP(a0, b0));                                                                 \
      STORE(out + i + (LANES), VOP(a1, b1));                                                       \
      STORE(out + i + (LANES) * 2, VOP(a2, b2));                                                   \
      STORE(out + i + (LANES) * 3, VOP(a3, b3));                                                   \
    }                                                                                              \
    for (; i + (LANES) <= len; i += (LANES)) {                                                     \
      VEC a = LOAD(left + i);                                                                      \
      VEC b = LOAD(right + i);                                                                     \
      STORE(out + i, VOP(a, b));                                                                   \
    }                                                                                              \
    for (; i < len; ++i) {                                                                         \
      out[i] = SOP(left[i], right[i]);                                                             \
    }                                                                                              \
  }

#define KIWI_INT_SCALAR_LOOP(NAME, TYPE, VEC, LANES, LOAD, STORE, DUP, VOP, SOP)                   \
  static void kiwi_dyad_##NAME##_scalar(TYPE* out, TYPE scalar, const TYPE* items, size_t len,      \
                                        int scalar_left) {                                          \
    VEC scalar_v = DUP(scalar);                                                                    \
    size_t i = 0;                                                                                  \
    if (scalar_left) {                                                                             \
      for (; i + (LANES) * 4 <= len; i += (LANES) * 4) {                                           \
        VEC b0 = LOAD(items + i);                                                                  \
        VEC b1 = LOAD(items + i + (LANES));                                                        \
        VEC b2 = LOAD(items + i + (LANES) * 2);                                                    \
        VEC b3 = LOAD(items + i + (LANES) * 3);                                                    \
        STORE(out + i, VOP(scalar_v, b0));                                                         \
        STORE(out + i + (LANES), VOP(scalar_v, b1));                                               \
        STORE(out + i + (LANES) * 2, VOP(scalar_v, b2));                                           \
        STORE(out + i + (LANES) * 3, VOP(scalar_v, b3));                                           \
      }                                                                                            \
      for (; i + (LANES) <= len; i += (LANES)) {                                                   \
        VEC b = LOAD(items + i);                                                                   \
        STORE(out + i, VOP(scalar_v, b));                                                          \
      }                                                                                            \
      for (; i < len; ++i) {                                                                       \
        out[i] = SOP(scalar, items[i]);                                                            \
      }                                                                                            \
    } else {                                                                                       \
      for (; i + (LANES) * 4 <= len; i += (LANES) * 4) {                                           \
        VEC a0 = LOAD(items + i);                                                                  \
        VEC a1 = LOAD(items + i + (LANES));                                                        \
        VEC a2 = LOAD(items + i + (LANES) * 2);                                                    \
        VEC a3 = LOAD(items + i + (LANES) * 3);                                                    \
        STORE(out + i, VOP(a0, scalar_v));                                                         \
        STORE(out + i + (LANES), VOP(a1, scalar_v));                                               \
        STORE(out + i + (LANES) * 2, VOP(a2, scalar_v));                                           \
        STORE(out + i + (LANES) * 3, VOP(a3, scalar_v));                                           \
      }                                                                                            \
      for (; i + (LANES) <= len; i += (LANES)) {                                                   \
        VEC a = LOAD(items + i);                                                                   \
        STORE(out + i, VOP(a, scalar_v));                                                          \
      }                                                                                            \
      for (; i < len; ++i) {                                                                       \
        out[i] = SOP(items[i], scalar);                                                            \
      }                                                                                            \
    }                                                                                              \
  }

KIWI_INT_ARRAY_LOOP(i8_add, int8_t, int8x16_t, 16, vld1q_s8, vst1q_s8, kiwi_addq_s8, kiwi_i8_add_s)
KIWI_INT_ARRAY_LOOP(i16_add, int16_t, int16x8_t, 8, vld1q_s16, vst1q_s16, kiwi_addq_s16, kiwi_i16_add_s)
KIWI_INT_ARRAY_LOOP(i32_add, int32_t, int32x4_t, 4, vld1q_s32, vst1q_s32, kiwi_addq_s32, kiwi_i32_add_s)
KIWI_INT_ARRAY_LOOP(i64_add, int64_t, int64x2_t, 2, vld1q_s64, vst1q_s64, kiwi_addq_s64, kiwi_i64_add_s)

KIWI_INT_ARRAY_LOOP(i8_sub, int8_t, int8x16_t, 16, vld1q_s8, vst1q_s8, kiwi_subq_s8, kiwi_i8_sub_s)
KIWI_INT_ARRAY_LOOP(i16_sub, int16_t, int16x8_t, 8, vld1q_s16, vst1q_s16, kiwi_subq_s16, kiwi_i16_sub_s)
KIWI_INT_ARRAY_LOOP(i32_sub, int32_t, int32x4_t, 4, vld1q_s32, vst1q_s32, kiwi_subq_s32, kiwi_i32_sub_s)
KIWI_INT_ARRAY_LOOP(i64_sub, int64_t, int64x2_t, 2, vld1q_s64, vst1q_s64, kiwi_subq_s64, kiwi_i64_sub_s)

KIWI_INT_ARRAY_LOOP(i8_mul, int8_t, int8x16_t, 16, vld1q_s8, vst1q_s8, kiwi_mulq_s8, kiwi_i8_mul_s)
KIWI_INT_ARRAY_LOOP(i16_mul, int16_t, int16x8_t, 8, vld1q_s16, vst1q_s16, kiwi_mulq_s16, kiwi_i16_mul_s)
KIWI_INT_ARRAY_LOOP(i32_mul, int32_t, int32x4_t, 4, vld1q_s32, vst1q_s32, kiwi_mulq_s32, kiwi_i32_mul_s)

KIWI_INT_ARRAY_LOOP(i8_min, int8_t, int8x16_t, 16, vld1q_s8, vst1q_s8, kiwi_minq_s8, kiwi_i8_min_s)
KIWI_INT_ARRAY_LOOP(i16_min, int16_t, int16x8_t, 8, vld1q_s16, vst1q_s16, kiwi_minq_s16, kiwi_i16_min_s)
KIWI_INT_ARRAY_LOOP(i32_min, int32_t, int32x4_t, 4, vld1q_s32, vst1q_s32, kiwi_minq_s32, kiwi_i32_min_s)
KIWI_INT_ARRAY_LOOP(i64_min, int64_t, int64x2_t, 2, vld1q_s64, vst1q_s64, kiwi_minq_s64, kiwi_i64_min_s)

KIWI_INT_ARRAY_LOOP(i8_max, int8_t, int8x16_t, 16, vld1q_s8, vst1q_s8, kiwi_maxq_s8, kiwi_i8_max_s)
KIWI_INT_ARRAY_LOOP(i16_max, int16_t, int16x8_t, 8, vld1q_s16, vst1q_s16, kiwi_maxq_s16, kiwi_i16_max_s)
KIWI_INT_ARRAY_LOOP(i32_max, int32_t, int32x4_t, 4, vld1q_s32, vst1q_s32, kiwi_maxq_s32, kiwi_i32_max_s)
KIWI_INT_ARRAY_LOOP(i64_max, int64_t, int64x2_t, 2, vld1q_s64, vst1q_s64, kiwi_maxq_s64, kiwi_i64_max_s)

KIWI_INT_SCALAR_LOOP(i8_add, int8_t, int8x16_t, 16, vld1q_s8, vst1q_s8, vdupq_n_s8, kiwi_addq_s8, kiwi_i8_add_s)
KIWI_INT_SCALAR_LOOP(i16_add, int16_t, int16x8_t, 8, vld1q_s16, vst1q_s16, vdupq_n_s16, kiwi_addq_s16, kiwi_i16_add_s)
KIWI_INT_SCALAR_LOOP(i32_add, int32_t, int32x4_t, 4, vld1q_s32, vst1q_s32, vdupq_n_s32, kiwi_addq_s32, kiwi_i32_add_s)
KIWI_INT_SCALAR_LOOP(i64_add, int64_t, int64x2_t, 2, vld1q_s64, vst1q_s64, vdupq_n_s64, kiwi_addq_s64, kiwi_i64_add_s)

KIWI_INT_SCALAR_LOOP(i8_sub, int8_t, int8x16_t, 16, vld1q_s8, vst1q_s8, vdupq_n_s8, kiwi_subq_s8, kiwi_i8_sub_s)
KIWI_INT_SCALAR_LOOP(i16_sub, int16_t, int16x8_t, 8, vld1q_s16, vst1q_s16, vdupq_n_s16, kiwi_subq_s16, kiwi_i16_sub_s)
KIWI_INT_SCALAR_LOOP(i32_sub, int32_t, int32x4_t, 4, vld1q_s32, vst1q_s32, vdupq_n_s32, kiwi_subq_s32, kiwi_i32_sub_s)
KIWI_INT_SCALAR_LOOP(i64_sub, int64_t, int64x2_t, 2, vld1q_s64, vst1q_s64, vdupq_n_s64, kiwi_subq_s64, kiwi_i64_sub_s)

KIWI_INT_SCALAR_LOOP(i8_mul, int8_t, int8x16_t, 16, vld1q_s8, vst1q_s8, vdupq_n_s8, kiwi_mulq_s8, kiwi_i8_mul_s)
KIWI_INT_SCALAR_LOOP(i16_mul, int16_t, int16x8_t, 8, vld1q_s16, vst1q_s16, vdupq_n_s16, kiwi_mulq_s16, kiwi_i16_mul_s)
KIWI_INT_SCALAR_LOOP(i32_mul, int32_t, int32x4_t, 4, vld1q_s32, vst1q_s32, vdupq_n_s32, kiwi_mulq_s32, kiwi_i32_mul_s)

KIWI_INT_SCALAR_LOOP(i8_min, int8_t, int8x16_t, 16, vld1q_s8, vst1q_s8, vdupq_n_s8, kiwi_minq_s8, kiwi_i8_min_s)
KIWI_INT_SCALAR_LOOP(i16_min, int16_t, int16x8_t, 8, vld1q_s16, vst1q_s16, vdupq_n_s16, kiwi_minq_s16, kiwi_i16_min_s)
KIWI_INT_SCALAR_LOOP(i32_min, int32_t, int32x4_t, 4, vld1q_s32, vst1q_s32, vdupq_n_s32, kiwi_minq_s32, kiwi_i32_min_s)
KIWI_INT_SCALAR_LOOP(i64_min, int64_t, int64x2_t, 2, vld1q_s64, vst1q_s64, vdupq_n_s64, kiwi_minq_s64, kiwi_i64_min_s)

KIWI_INT_SCALAR_LOOP(i8_max, int8_t, int8x16_t, 16, vld1q_s8, vst1q_s8, vdupq_n_s8, kiwi_maxq_s8, kiwi_i8_max_s)
KIWI_INT_SCALAR_LOOP(i16_max, int16_t, int16x8_t, 8, vld1q_s16, vst1q_s16, vdupq_n_s16, kiwi_maxq_s16, kiwi_i16_max_s)
KIWI_INT_SCALAR_LOOP(i32_max, int32_t, int32x4_t, 4, vld1q_s32, vst1q_s32, vdupq_n_s32, kiwi_maxq_s32, kiwi_i32_max_s)
KIWI_INT_SCALAR_LOOP(i64_max, int64_t, int64x2_t, 2, vld1q_s64, vst1q_s64, vdupq_n_s64, kiwi_maxq_s64, kiwi_i64_max_s)

int kiwi_host_dyad_f64_array_neon(double* out, const double* left, const double* right, size_t len, int op) {
  switch (op) {
    case KIWI_HOST_DYAD_ADD: kiwi_dyad_f64_array_add(out, left, right, len); return 1;
    case KIWI_HOST_DYAD_SUB: kiwi_dyad_f64_array_sub(out, left, right, len); return 1;
    case KIWI_HOST_DYAD_MUL: kiwi_dyad_f64_array_mul(out, left, right, len); return 1;
    case KIWI_HOST_DYAD_DIV: kiwi_dyad_f64_array_div(out, left, right, len); return 1;
    case KIWI_HOST_DYAD_MIN: kiwi_dyad_f64_array_min(out, left, right, len); return 1;
    case KIWI_HOST_DYAD_MAX: kiwi_dyad_f64_array_max(out, left, right, len); return 1;
    default: return 0;
  }
}

int kiwi_host_dyad_f64_scalar_neon(double* out, double scalar, const double* items, size_t len, int scalar_left, int op) {
  switch (op) {
    case KIWI_HOST_DYAD_ADD: kiwi_dyad_f64_scalar_add(out, scalar, items, len, scalar_left); return 1;
    case KIWI_HOST_DYAD_SUB: kiwi_dyad_f64_scalar_sub(out, scalar, items, len, scalar_left); return 1;
    case KIWI_HOST_DYAD_MUL: kiwi_dyad_f64_scalar_mul(out, scalar, items, len, scalar_left); return 1;
    case KIWI_HOST_DYAD_DIV: kiwi_dyad_f64_scalar_div(out, scalar, items, len, scalar_left); return 1;
    case KIWI_HOST_DYAD_MIN: kiwi_dyad_f64_scalar_min(out, scalar, items, len, scalar_left); return 1;
    case KIWI_HOST_DYAD_MAX: kiwi_dyad_f64_scalar_max(out, scalar, items, len, scalar_left); return 1;
    default: return 0;
  }
}

int kiwi_host_dyad_int_array_neon(void* out, const void* left, const void* right, size_t len, int width, int op) {
  switch (width) {
    case 1:
      switch (op) {
        case KIWI_HOST_DYAD_ADD: kiwi_dyad_i8_add_array((int8_t*)out, (const int8_t*)left, (const int8_t*)right, len); return 1;
        case KIWI_HOST_DYAD_SUB: kiwi_dyad_i8_sub_array((int8_t*)out, (const int8_t*)left, (const int8_t*)right, len); return 1;
        case KIWI_HOST_DYAD_MUL: kiwi_dyad_i8_mul_array((int8_t*)out, (const int8_t*)left, (const int8_t*)right, len); return 1;
        case KIWI_HOST_DYAD_MIN: kiwi_dyad_i8_min_array((int8_t*)out, (const int8_t*)left, (const int8_t*)right, len); return 1;
        case KIWI_HOST_DYAD_MAX: kiwi_dyad_i8_max_array((int8_t*)out, (const int8_t*)left, (const int8_t*)right, len); return 1;
        default: return 0;
      }
    case 2:
      switch (op) {
        case KIWI_HOST_DYAD_ADD: kiwi_dyad_i16_add_array((int16_t*)out, (const int16_t*)left, (const int16_t*)right, len); return 1;
        case KIWI_HOST_DYAD_SUB: kiwi_dyad_i16_sub_array((int16_t*)out, (const int16_t*)left, (const int16_t*)right, len); return 1;
        case KIWI_HOST_DYAD_MUL: kiwi_dyad_i16_mul_array((int16_t*)out, (const int16_t*)left, (const int16_t*)right, len); return 1;
        case KIWI_HOST_DYAD_MIN: kiwi_dyad_i16_min_array((int16_t*)out, (const int16_t*)left, (const int16_t*)right, len); return 1;
        case KIWI_HOST_DYAD_MAX: kiwi_dyad_i16_max_array((int16_t*)out, (const int16_t*)left, (const int16_t*)right, len); return 1;
        default: return 0;
      }
    case 4:
      switch (op) {
        case KIWI_HOST_DYAD_ADD: kiwi_dyad_i32_add_array((int32_t*)out, (const int32_t*)left, (const int32_t*)right, len); return 1;
        case KIWI_HOST_DYAD_SUB: kiwi_dyad_i32_sub_array((int32_t*)out, (const int32_t*)left, (const int32_t*)right, len); return 1;
        case KIWI_HOST_DYAD_MUL: kiwi_dyad_i32_mul_array((int32_t*)out, (const int32_t*)left, (const int32_t*)right, len); return 1;
        case KIWI_HOST_DYAD_MIN: kiwi_dyad_i32_min_array((int32_t*)out, (const int32_t*)left, (const int32_t*)right, len); return 1;
        case KIWI_HOST_DYAD_MAX: kiwi_dyad_i32_max_array((int32_t*)out, (const int32_t*)left, (const int32_t*)right, len); return 1;
        default: return 0;
      }
    case 8:
      switch (op) {
        case KIWI_HOST_DYAD_ADD: kiwi_dyad_i64_add_array((int64_t*)out, (const int64_t*)left, (const int64_t*)right, len); return 1;
        case KIWI_HOST_DYAD_SUB: kiwi_dyad_i64_sub_array((int64_t*)out, (const int64_t*)left, (const int64_t*)right, len); return 1;
        case KIWI_HOST_DYAD_MIN: kiwi_dyad_i64_min_array((int64_t*)out, (const int64_t*)left, (const int64_t*)right, len); return 1;
        case KIWI_HOST_DYAD_MAX: kiwi_dyad_i64_max_array((int64_t*)out, (const int64_t*)left, (const int64_t*)right, len); return 1;
        default: return 0;
      }
    default:
      return 0;
  }
}

int kiwi_host_dyad_int_scalar_neon(void* out, int64_t scalar, const void* items, size_t len, int width, int scalar_left, int op) {
  switch (width) {
    case 1:
      switch (op) {
        case KIWI_HOST_DYAD_ADD: kiwi_dyad_i8_add_scalar((int8_t*)out, (int8_t)scalar, (const int8_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_SUB: kiwi_dyad_i8_sub_scalar((int8_t*)out, (int8_t)scalar, (const int8_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_MUL: kiwi_dyad_i8_mul_scalar((int8_t*)out, (int8_t)scalar, (const int8_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_MIN: kiwi_dyad_i8_min_scalar((int8_t*)out, (int8_t)scalar, (const int8_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_MAX: kiwi_dyad_i8_max_scalar((int8_t*)out, (int8_t)scalar, (const int8_t*)items, len, scalar_left); return 1;
        default: return 0;
      }
    case 2:
      switch (op) {
        case KIWI_HOST_DYAD_ADD: kiwi_dyad_i16_add_scalar((int16_t*)out, (int16_t)scalar, (const int16_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_SUB: kiwi_dyad_i16_sub_scalar((int16_t*)out, (int16_t)scalar, (const int16_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_MUL: kiwi_dyad_i16_mul_scalar((int16_t*)out, (int16_t)scalar, (const int16_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_MIN: kiwi_dyad_i16_min_scalar((int16_t*)out, (int16_t)scalar, (const int16_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_MAX: kiwi_dyad_i16_max_scalar((int16_t*)out, (int16_t)scalar, (const int16_t*)items, len, scalar_left); return 1;
        default: return 0;
      }
    case 4:
      switch (op) {
        case KIWI_HOST_DYAD_ADD: kiwi_dyad_i32_add_scalar((int32_t*)out, (int32_t)scalar, (const int32_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_SUB: kiwi_dyad_i32_sub_scalar((int32_t*)out, (int32_t)scalar, (const int32_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_MUL: kiwi_dyad_i32_mul_scalar((int32_t*)out, (int32_t)scalar, (const int32_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_MIN: kiwi_dyad_i32_min_scalar((int32_t*)out, (int32_t)scalar, (const int32_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_MAX: kiwi_dyad_i32_max_scalar((int32_t*)out, (int32_t)scalar, (const int32_t*)items, len, scalar_left); return 1;
        default: return 0;
      }
    case 8:
      switch (op) {
        case KIWI_HOST_DYAD_ADD: kiwi_dyad_i64_add_scalar((int64_t*)out, scalar, (const int64_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_SUB: kiwi_dyad_i64_sub_scalar((int64_t*)out, scalar, (const int64_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_MIN: kiwi_dyad_i64_min_scalar((int64_t*)out, scalar, (const int64_t*)items, len, scalar_left); return 1;
        case KIWI_HOST_DYAD_MAX: kiwi_dyad_i64_max_scalar((int64_t*)out, scalar, (const int64_t*)items, len, scalar_left); return 1;
        default: return 0;
      }
    default:
      return 0;
  }
}

#endif
