#include "host_transpose.h"

#if defined(__aarch64__)
#include <arm_neon.h>

static inline void kiwi_store_i8_8x8(int8_t* out, size_t rows, size_t rb, size_t cb,
                                    int8x8_t c0, int8x8_t c1, int8x8_t c2, int8x8_t c3,
                                    int8x8_t c4, int8x8_t c5, int8x8_t c6, int8x8_t c7) {
  vst1_s8(out + (cb + 0) * rows + rb, c0);
  vst1_s8(out + (cb + 1) * rows + rb, c1);
  vst1_s8(out + (cb + 2) * rows + rb, c2);
  vst1_s8(out + (cb + 3) * rows + rb, c3);
  vst1_s8(out + (cb + 4) * rows + rb, c4);
  vst1_s8(out + (cb + 5) * rows + rb, c5);
  vst1_s8(out + (cb + 6) * rows + rb, c6);
  vst1_s8(out + (cb + 7) * rows + rb, c7);
}

static inline void kiwi_transpose_i8_8x8_store(int8_t* out, size_t rows, size_t rb, size_t cb,
                                              int8x8_t r0, int8x8_t r1, int8x8_t r2, int8x8_t r3,
                                              int8x8_t r4, int8x8_t r5, int8x8_t r6, int8x8_t r7) {
  uint8x8x2_t t0 = vtrn_u8(vreinterpret_u8_s8(r0), vreinterpret_u8_s8(r1));
  uint8x8x2_t t1 = vtrn_u8(vreinterpret_u8_s8(r2), vreinterpret_u8_s8(r3));
  uint8x8x2_t t2 = vtrn_u8(vreinterpret_u8_s8(r4), vreinterpret_u8_s8(r5));
  uint8x8x2_t t3 = vtrn_u8(vreinterpret_u8_s8(r6), vreinterpret_u8_s8(r7));
  uint16x4x2_t u0 = vtrn_u16(vreinterpret_u16_u8(t0.val[0]), vreinterpret_u16_u8(t1.val[0]));
  uint16x4x2_t u1 = vtrn_u16(vreinterpret_u16_u8(t0.val[1]), vreinterpret_u16_u8(t1.val[1]));
  uint16x4x2_t u2 = vtrn_u16(vreinterpret_u16_u8(t2.val[0]), vreinterpret_u16_u8(t3.val[0]));
  uint16x4x2_t u3 = vtrn_u16(vreinterpret_u16_u8(t2.val[1]), vreinterpret_u16_u8(t3.val[1]));
  uint32x2x2_t v0 = vtrn_u32(vreinterpret_u32_u16(u0.val[0]), vreinterpret_u32_u16(u2.val[0]));
  uint32x2x2_t v1 = vtrn_u32(vreinterpret_u32_u16(u1.val[0]), vreinterpret_u32_u16(u3.val[0]));
  uint32x2x2_t v2 = vtrn_u32(vreinterpret_u32_u16(u0.val[1]), vreinterpret_u32_u16(u2.val[1]));
  uint32x2x2_t v3 = vtrn_u32(vreinterpret_u32_u16(u1.val[1]), vreinterpret_u32_u16(u3.val[1]));
  kiwi_store_i8_8x8(out, rows, rb, cb,
                    vreinterpret_s8_u32(v0.val[0]), vreinterpret_s8_u32(v1.val[0]),
                    vreinterpret_s8_u32(v2.val[0]), vreinterpret_s8_u32(v3.val[0]),
                    vreinterpret_s8_u32(v0.val[1]), vreinterpret_s8_u32(v1.val[1]),
                    vreinterpret_s8_u32(v2.val[1]), vreinterpret_s8_u32(v3.val[1]));
}

static void kiwi_transpose_i8(int8_t* out, const int8_t* src, size_t rows, size_t cols) {
  size_t cb = 0;
  for (; cb + 8 <= cols; cb += 8) {
    size_t rb = 0;
    for (; rb + 8 <= rows; rb += 8) {
      int8x8_t r0 = vld1_s8(src + (rb + 0) * cols + cb);
      int8x8_t r1 = vld1_s8(src + (rb + 1) * cols + cb);
      int8x8_t r2 = vld1_s8(src + (rb + 2) * cols + cb);
      int8x8_t r3 = vld1_s8(src + (rb + 3) * cols + cb);
      int8x8_t r4 = vld1_s8(src + (rb + 4) * cols + cb);
      int8x8_t r5 = vld1_s8(src + (rb + 5) * cols + cb);
      int8x8_t r6 = vld1_s8(src + (rb + 6) * cols + cb);
      int8x8_t r7 = vld1_s8(src + (rb + 7) * cols + cb);
      kiwi_transpose_i8_8x8_store(out, rows, rb, cb, r0, r1, r2, r3, r4, r5, r6, r7);
    }
    for (; rb < rows; ++rb) {
      for (size_t c = cb; c < cb + 8; ++c) out[c * rows + rb] = src[rb * cols + c];
    }
  }
  for (; cb < cols; ++cb) {
    for (size_t rb = 0; rb < rows; ++rb) out[cb * rows + rb] = src[rb * cols + cb];
  }
}

static inline void kiwi_store_i16_8x8(int16_t* out, size_t rows, size_t rb, size_t cb,
                                      int16x8_t c0, int16x8_t c1, int16x8_t c2, int16x8_t c3,
                                      int16x8_t c4, int16x8_t c5, int16x8_t c6, int16x8_t c7) {
  vst1q_s16(out + (cb + 0) * rows + rb, c0);
  vst1q_s16(out + (cb + 1) * rows + rb, c1);
  vst1q_s16(out + (cb + 2) * rows + rb, c2);
  vst1q_s16(out + (cb + 3) * rows + rb, c3);
  vst1q_s16(out + (cb + 4) * rows + rb, c4);
  vst1q_s16(out + (cb + 5) * rows + rb, c5);
  vst1q_s16(out + (cb + 6) * rows + rb, c6);
  vst1q_s16(out + (cb + 7) * rows + rb, c7);
}

static inline void kiwi_transpose_i16_8x8_store(int16_t* out, size_t rows, size_t rb, size_t cb,
                                               int16x8_t r0, int16x8_t r1, int16x8_t r2, int16x8_t r3,
                                               int16x8_t r4, int16x8_t r5, int16x8_t r6, int16x8_t r7) {
  int16x8x2_t t0 = vtrnq_s16(r0, r1);
  int16x8x2_t t1 = vtrnq_s16(r2, r3);
  int16x8x2_t t2 = vtrnq_s16(r4, r5);
  int16x8x2_t t3 = vtrnq_s16(r6, r7);
  int32x4x2_t u0 = vtrnq_s32(vreinterpretq_s32_s16(t0.val[0]), vreinterpretq_s32_s16(t1.val[0]));
  int32x4x2_t u1 = vtrnq_s32(vreinterpretq_s32_s16(t0.val[1]), vreinterpretq_s32_s16(t1.val[1]));
  int32x4x2_t u2 = vtrnq_s32(vreinterpretq_s32_s16(t2.val[0]), vreinterpretq_s32_s16(t3.val[0]));
  int32x4x2_t u3 = vtrnq_s32(vreinterpretq_s32_s16(t2.val[1]), vreinterpretq_s32_s16(t3.val[1]));
  int64x2_t v00 = vzip1q_s64(vreinterpretq_s64_s32(u0.val[0]), vreinterpretq_s64_s32(u2.val[0]));
  int64x2_t v01 = vzip2q_s64(vreinterpretq_s64_s32(u0.val[0]), vreinterpretq_s64_s32(u2.val[0]));
  int64x2_t v10 = vzip1q_s64(vreinterpretq_s64_s32(u1.val[0]), vreinterpretq_s64_s32(u3.val[0]));
  int64x2_t v11 = vzip2q_s64(vreinterpretq_s64_s32(u1.val[0]), vreinterpretq_s64_s32(u3.val[0]));
  int64x2_t v20 = vzip1q_s64(vreinterpretq_s64_s32(u0.val[1]), vreinterpretq_s64_s32(u2.val[1]));
  int64x2_t v21 = vzip2q_s64(vreinterpretq_s64_s32(u0.val[1]), vreinterpretq_s64_s32(u2.val[1]));
  int64x2_t v30 = vzip1q_s64(vreinterpretq_s64_s32(u1.val[1]), vreinterpretq_s64_s32(u3.val[1]));
  int64x2_t v31 = vzip2q_s64(vreinterpretq_s64_s32(u1.val[1]), vreinterpretq_s64_s32(u3.val[1]));
  kiwi_store_i16_8x8(out, rows, rb, cb,
                     vreinterpretq_s16_s64(v00), vreinterpretq_s16_s64(v10),
                     vreinterpretq_s16_s64(v20), vreinterpretq_s16_s64(v30),
                     vreinterpretq_s16_s64(v01), vreinterpretq_s16_s64(v11),
                     vreinterpretq_s16_s64(v21), vreinterpretq_s16_s64(v31));
}

static void kiwi_transpose_i16(int16_t* out, const int16_t* src, size_t rows, size_t cols) {
  size_t cb = 0;
  for (; cb + 8 <= cols; cb += 8) {
    size_t rb = 0;
    for (; rb + 8 <= rows; rb += 8) {
      kiwi_transpose_i16_8x8_store(out, rows, rb, cb,
                                   vld1q_s16(src + (rb + 0) * cols + cb),
                                   vld1q_s16(src + (rb + 1) * cols + cb),
                                   vld1q_s16(src + (rb + 2) * cols + cb),
                                   vld1q_s16(src + (rb + 3) * cols + cb),
                                   vld1q_s16(src + (rb + 4) * cols + cb),
                                   vld1q_s16(src + (rb + 5) * cols + cb),
                                   vld1q_s16(src + (rb + 6) * cols + cb),
                                   vld1q_s16(src + (rb + 7) * cols + cb));
    }
    for (; rb < rows; ++rb) {
      for (size_t c = cb; c < cb + 8; ++c) out[c * rows + rb] = src[rb * cols + c];
    }
  }
  for (; cb < cols; ++cb) {
    for (size_t rb = 0; rb < rows; ++rb) out[cb * rows + rb] = src[rb * cols + cb];
  }
}

static inline void kiwi_transpose_i32_4x4_store(int32_t* out, size_t rows, size_t rb, size_t cb,
                                               int32x4_t r0, int32x4_t r1, int32x4_t r2, int32x4_t r3) {
  int32x4x2_t t0 = vtrnq_s32(r0, r1);
  int32x4x2_t t1 = vtrnq_s32(r2, r3);
  vst1q_s32(out + (cb + 0) * rows + rb, vcombine_s32(vget_low_s32(t0.val[0]), vget_low_s32(t1.val[0])));
  vst1q_s32(out + (cb + 1) * rows + rb, vcombine_s32(vget_low_s32(t0.val[1]), vget_low_s32(t1.val[1])));
  vst1q_s32(out + (cb + 2) * rows + rb, vcombine_s32(vget_high_s32(t0.val[0]), vget_high_s32(t1.val[0])));
  vst1q_s32(out + (cb + 3) * rows + rb, vcombine_s32(vget_high_s32(t0.val[1]), vget_high_s32(t1.val[1])));
}

static void kiwi_transpose_i32(int32_t* out, const int32_t* src, size_t rows, size_t cols) {
  size_t cb = 0;
  for (; cb + 4 <= cols; cb += 4) {
    size_t rb = 0;
    for (; rb + 4 <= rows; rb += 4) {
      kiwi_transpose_i32_4x4_store(out, rows, rb, cb,
                                   vld1q_s32(src + (rb + 0) * cols + cb),
                                   vld1q_s32(src + (rb + 1) * cols + cb),
                                   vld1q_s32(src + (rb + 2) * cols + cb),
                                   vld1q_s32(src + (rb + 3) * cols + cb));
    }
    for (; rb < rows; ++rb) {
      for (size_t c = cb; c < cb + 4; ++c) out[c * rows + rb] = src[rb * cols + c];
    }
  }
  for (; cb < cols; ++cb) {
    for (size_t rb = 0; rb < rows; ++rb) out[cb * rows + rb] = src[rb * cols + cb];
  }
}

static void kiwi_transpose_i64(int64_t* out, const int64_t* src, size_t rows, size_t cols) {
  size_t cb = 0;
  for (; cb + 2 <= cols; cb += 2) {
    size_t rb = 0;
    for (; rb + 2 <= rows; rb += 2) {
      int64x2_t r0 = vld1q_s64(src + (rb + 0) * cols + cb);
      int64x2_t r1 = vld1q_s64(src + (rb + 1) * cols + cb);
      vst1q_s64(out + (cb + 0) * rows + rb, vzip1q_s64(r0, r1));
      vst1q_s64(out + (cb + 1) * rows + rb, vzip2q_s64(r0, r1));
    }
    for (; rb < rows; ++rb) {
      out[(cb + 0) * rows + rb] = src[rb * cols + cb + 0];
      out[(cb + 1) * rows + rb] = src[rb * cols + cb + 1];
    }
  }
  for (; cb < cols; ++cb) {
    for (size_t rb = 0; rb < rows; ++rb) out[cb * rows + rb] = src[rb * cols + cb];
  }
}

static inline void kiwi_transpose_f32_4x4_store(float* out, size_t rows, size_t rb, size_t cb,
                                               float32x4_t r0, float32x4_t r1, float32x4_t r2, float32x4_t r3) {
  float32x4x2_t t0 = vtrnq_f32(r0, r1);
  float32x4x2_t t1 = vtrnq_f32(r2, r3);
  vst1q_f32(out + (cb + 0) * rows + rb, vcombine_f32(vget_low_f32(t0.val[0]), vget_low_f32(t1.val[0])));
  vst1q_f32(out + (cb + 1) * rows + rb, vcombine_f32(vget_low_f32(t0.val[1]), vget_low_f32(t1.val[1])));
  vst1q_f32(out + (cb + 2) * rows + rb, vcombine_f32(vget_high_f32(t0.val[0]), vget_high_f32(t1.val[0])));
  vst1q_f32(out + (cb + 3) * rows + rb, vcombine_f32(vget_high_f32(t0.val[1]), vget_high_f32(t1.val[1])));
}

int kiwi_host_transpose_f32_neon(float* out, const float* src, size_t rows, size_t cols) {
  size_t cb = 0;
  for (; cb + 4 <= cols; cb += 4) {
    size_t rb = 0;
    for (; rb + 4 <= rows; rb += 4) {
      kiwi_transpose_f32_4x4_store(out, rows, rb, cb,
                                   vld1q_f32(src + (rb + 0) * cols + cb),
                                   vld1q_f32(src + (rb + 1) * cols + cb),
                                   vld1q_f32(src + (rb + 2) * cols + cb),
                                   vld1q_f32(src + (rb + 3) * cols + cb));
    }
    for (; rb < rows; ++rb) {
      for (size_t c = cb; c < cb + 4; ++c) out[c * rows + rb] = src[rb * cols + c];
    }
  }
  for (; cb < cols; ++cb) {
    for (size_t rb = 0; rb < rows; ++rb) out[cb * rows + rb] = src[rb * cols + cb];
  }
  return 1;
}

int kiwi_host_transpose_f64_neon(double* out, const double* src, size_t rows, size_t cols) {
  size_t cb = 0;
  for (; cb + 2 <= cols; cb += 2) {
    size_t rb = 0;
    for (; rb + 2 <= rows; rb += 2) {
      float64x2_t r0 = vld1q_f64(src + (rb + 0) * cols + cb);
      float64x2_t r1 = vld1q_f64(src + (rb + 1) * cols + cb);
      vst1q_f64(out + (cb + 0) * rows + rb, vzip1q_f64(r0, r1));
      vst1q_f64(out + (cb + 1) * rows + rb, vzip2q_f64(r0, r1));
    }
    for (; rb < rows; ++rb) {
      out[(cb + 0) * rows + rb] = src[rb * cols + cb + 0];
      out[(cb + 1) * rows + rb] = src[rb * cols + cb + 1];
    }
  }
  for (; cb < cols; ++cb) {
    for (size_t rb = 0; rb < rows; ++rb) out[cb * rows + rb] = src[rb * cols + cb];
  }
  return 1;
}

int kiwi_host_transpose_int_neon(void* out, const void* src, size_t rows, size_t cols, int width) {
  switch (width) {
    case 1: kiwi_transpose_i8((int8_t*)out, (const int8_t*)src, rows, cols); return 1;
    case 2: kiwi_transpose_i16((int16_t*)out, (const int16_t*)src, rows, cols); return 1;
    case 4: kiwi_transpose_i32((int32_t*)out, (const int32_t*)src, rows, cols); return 1;
    case 8: kiwi_transpose_i64((int64_t*)out, (const int64_t*)src, rows, cols); return 1;
    default: return 0;
  }
}

#endif
