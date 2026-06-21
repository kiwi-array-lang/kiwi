#include "host_transpose.h"

#if defined(__x86_64__) || defined(_M_X64)

#include <emmintrin.h>
#include <xmmintrin.h>

static inline void kiwi_store_low64(void* out, __m128i value) {
  _mm_storel_epi64((__m128i*)out, value);
}

static inline __m128i kiwi_load_low64(const void* src) {
  return _mm_loadl_epi64((const __m128i*)src);
}

static inline void kiwi_transpose_i8_8x8_store(int8_t* out, size_t rows, size_t rb, size_t cb,
                                              __m128i r0, __m128i r1, __m128i r2, __m128i r3,
                                              __m128i r4, __m128i r5, __m128i r6, __m128i r7) {
  const __m128i t0 = _mm_unpacklo_epi8(r0, r1);
  const __m128i t1 = _mm_unpacklo_epi8(r2, r3);
  const __m128i t2 = _mm_unpacklo_epi8(r4, r5);
  const __m128i t3 = _mm_unpacklo_epi8(r6, r7);
  const __m128i u0 = _mm_unpacklo_epi16(t0, t1);
  const __m128i u1 = _mm_unpackhi_epi16(t0, t1);
  const __m128i u2 = _mm_unpacklo_epi16(t2, t3);
  const __m128i u3 = _mm_unpackhi_epi16(t2, t3);
  const __m128i v0 = _mm_unpacklo_epi32(u0, u2);
  const __m128i v1 = _mm_unpackhi_epi32(u0, u2);
  const __m128i v2 = _mm_unpacklo_epi32(u1, u3);
  const __m128i v3 = _mm_unpackhi_epi32(u1, u3);
  kiwi_store_low64(out + (cb + 0) * rows + rb, v0);
  kiwi_store_low64(out + (cb + 1) * rows + rb, _mm_srli_si128(v0, 8));
  kiwi_store_low64(out + (cb + 2) * rows + rb, v1);
  kiwi_store_low64(out + (cb + 3) * rows + rb, _mm_srli_si128(v1, 8));
  kiwi_store_low64(out + (cb + 4) * rows + rb, v2);
  kiwi_store_low64(out + (cb + 5) * rows + rb, _mm_srli_si128(v2, 8));
  kiwi_store_low64(out + (cb + 6) * rows + rb, v3);
  kiwi_store_low64(out + (cb + 7) * rows + rb, _mm_srli_si128(v3, 8));
}

static void kiwi_transpose_i8(int8_t* out, const int8_t* src, size_t rows, size_t cols) {
  size_t cb = 0;
  for (; cb + 8 <= cols; cb += 8) {
    size_t rb = 0;
    for (; rb + 8 <= rows; rb += 8) {
      kiwi_transpose_i8_8x8_store(out, rows, rb, cb,
                                  kiwi_load_low64(src + (rb + 0) * cols + cb),
                                  kiwi_load_low64(src + (rb + 1) * cols + cb),
                                  kiwi_load_low64(src + (rb + 2) * cols + cb),
                                  kiwi_load_low64(src + (rb + 3) * cols + cb),
                                  kiwi_load_low64(src + (rb + 4) * cols + cb),
                                  kiwi_load_low64(src + (rb + 5) * cols + cb),
                                  kiwi_load_low64(src + (rb + 6) * cols + cb),
                                  kiwi_load_low64(src + (rb + 7) * cols + cb));
    }
    for (; rb < rows; ++rb) {
      for (size_t c = cb; c < cb + 8; ++c) out[c * rows + rb] = src[rb * cols + c];
    }
  }
  for (; cb < cols; ++cb) {
    for (size_t rb = 0; rb < rows; ++rb) out[cb * rows + rb] = src[rb * cols + cb];
  }
}

static inline void kiwi_transpose_i16_8x8_store(int16_t* out, size_t rows, size_t rb, size_t cb,
                                               __m128i r0, __m128i r1, __m128i r2, __m128i r3,
                                               __m128i r4, __m128i r5, __m128i r6, __m128i r7) {
  const __m128i lo0 = _mm_unpacklo_epi16(r0, r1);
  const __m128i lo1 = _mm_unpacklo_epi16(r2, r3);
  const __m128i lo2 = _mm_unpacklo_epi16(r4, r5);
  const __m128i lo3 = _mm_unpacklo_epi16(r6, r7);
  const __m128i a0 = _mm_unpacklo_epi32(lo0, lo1);
  const __m128i a1 = _mm_unpackhi_epi32(lo0, lo1);
  const __m128i a2 = _mm_unpacklo_epi32(lo2, lo3);
  const __m128i a3 = _mm_unpackhi_epi32(lo2, lo3);
  _mm_storeu_si128((__m128i*)(out + (cb + 0) * rows + rb), _mm_unpacklo_epi64(a0, a2));
  _mm_storeu_si128((__m128i*)(out + (cb + 1) * rows + rb), _mm_unpackhi_epi64(a0, a2));
  _mm_storeu_si128((__m128i*)(out + (cb + 2) * rows + rb), _mm_unpacklo_epi64(a1, a3));
  _mm_storeu_si128((__m128i*)(out + (cb + 3) * rows + rb), _mm_unpackhi_epi64(a1, a3));

  const __m128i hi0 = _mm_unpackhi_epi16(r0, r1);
  const __m128i hi1 = _mm_unpackhi_epi16(r2, r3);
  const __m128i hi2 = _mm_unpackhi_epi16(r4, r5);
  const __m128i hi3 = _mm_unpackhi_epi16(r6, r7);
  const __m128i b0 = _mm_unpacklo_epi32(hi0, hi1);
  const __m128i b1 = _mm_unpackhi_epi32(hi0, hi1);
  const __m128i b2 = _mm_unpacklo_epi32(hi2, hi3);
  const __m128i b3 = _mm_unpackhi_epi32(hi2, hi3);
  _mm_storeu_si128((__m128i*)(out + (cb + 4) * rows + rb), _mm_unpacklo_epi64(b0, b2));
  _mm_storeu_si128((__m128i*)(out + (cb + 5) * rows + rb), _mm_unpackhi_epi64(b0, b2));
  _mm_storeu_si128((__m128i*)(out + (cb + 6) * rows + rb), _mm_unpacklo_epi64(b1, b3));
  _mm_storeu_si128((__m128i*)(out + (cb + 7) * rows + rb), _mm_unpackhi_epi64(b1, b3));
}

static void kiwi_transpose_i16(int16_t* out, const int16_t* src, size_t rows, size_t cols) {
  size_t cb = 0;
  for (; cb + 8 <= cols; cb += 8) {
    size_t rb = 0;
    for (; rb + 8 <= rows; rb += 8) {
      kiwi_transpose_i16_8x8_store(out, rows, rb, cb,
                                   _mm_loadu_si128((const __m128i*)(src + (rb + 0) * cols + cb)),
                                   _mm_loadu_si128((const __m128i*)(src + (rb + 1) * cols + cb)),
                                   _mm_loadu_si128((const __m128i*)(src + (rb + 2) * cols + cb)),
                                   _mm_loadu_si128((const __m128i*)(src + (rb + 3) * cols + cb)),
                                   _mm_loadu_si128((const __m128i*)(src + (rb + 4) * cols + cb)),
                                   _mm_loadu_si128((const __m128i*)(src + (rb + 5) * cols + cb)),
                                   _mm_loadu_si128((const __m128i*)(src + (rb + 6) * cols + cb)),
                                   _mm_loadu_si128((const __m128i*)(src + (rb + 7) * cols + cb)));
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
                                               __m128i r0, __m128i r1, __m128i r2, __m128i r3) {
  const __m128i t0 = _mm_unpacklo_epi32(r0, r1);
  const __m128i t1 = _mm_unpackhi_epi32(r0, r1);
  const __m128i t2 = _mm_unpacklo_epi32(r2, r3);
  const __m128i t3 = _mm_unpackhi_epi32(r2, r3);
  _mm_storeu_si128((__m128i*)(out + (cb + 0) * rows + rb), _mm_unpacklo_epi64(t0, t2));
  _mm_storeu_si128((__m128i*)(out + (cb + 1) * rows + rb), _mm_unpackhi_epi64(t0, t2));
  _mm_storeu_si128((__m128i*)(out + (cb + 2) * rows + rb), _mm_unpacklo_epi64(t1, t3));
  _mm_storeu_si128((__m128i*)(out + (cb + 3) * rows + rb), _mm_unpackhi_epi64(t1, t3));
}

static void kiwi_transpose_i32(int32_t* out, const int32_t* src, size_t rows, size_t cols) {
  size_t cb = 0;
  for (; cb + 4 <= cols; cb += 4) {
    size_t rb = 0;
    for (; rb + 4 <= rows; rb += 4) {
      kiwi_transpose_i32_4x4_store(out, rows, rb, cb,
                                   _mm_loadu_si128((const __m128i*)(src + (rb + 0) * cols + cb)),
                                   _mm_loadu_si128((const __m128i*)(src + (rb + 1) * cols + cb)),
                                   _mm_loadu_si128((const __m128i*)(src + (rb + 2) * cols + cb)),
                                   _mm_loadu_si128((const __m128i*)(src + (rb + 3) * cols + cb)));
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
      const __m128i r0 = _mm_loadu_si128((const __m128i*)(src + (rb + 0) * cols + cb));
      const __m128i r1 = _mm_loadu_si128((const __m128i*)(src + (rb + 1) * cols + cb));
      _mm_storeu_si128((__m128i*)(out + (cb + 0) * rows + rb), _mm_unpacklo_epi64(r0, r1));
      _mm_storeu_si128((__m128i*)(out + (cb + 1) * rows + rb), _mm_unpackhi_epi64(r0, r1));
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
                                               __m128 r0, __m128 r1, __m128 r2, __m128 r3) {
  _MM_TRANSPOSE4_PS(r0, r1, r2, r3);
  _mm_storeu_ps(out + (cb + 0) * rows + rb, r0);
  _mm_storeu_ps(out + (cb + 1) * rows + rb, r1);
  _mm_storeu_ps(out + (cb + 2) * rows + rb, r2);
  _mm_storeu_ps(out + (cb + 3) * rows + rb, r3);
}

int kiwi_host_transpose_f32_sse2(float* out, const float* src, size_t rows, size_t cols) {
  size_t cb = 0;
  for (; cb + 4 <= cols; cb += 4) {
    size_t rb = 0;
    for (; rb + 4 <= rows; rb += 4) {
      kiwi_transpose_f32_4x4_store(out, rows, rb, cb,
                                   _mm_loadu_ps(src + (rb + 0) * cols + cb),
                                   _mm_loadu_ps(src + (rb + 1) * cols + cb),
                                   _mm_loadu_ps(src + (rb + 2) * cols + cb),
                                   _mm_loadu_ps(src + (rb + 3) * cols + cb));
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

int kiwi_host_transpose_f64_sse2(double* out, const double* src, size_t rows, size_t cols) {
  size_t cb = 0;
  for (; cb + 2 <= cols; cb += 2) {
    size_t rb = 0;
    for (; rb + 2 <= rows; rb += 2) {
      const __m128d r0 = _mm_loadu_pd(src + (rb + 0) * cols + cb);
      const __m128d r1 = _mm_loadu_pd(src + (rb + 1) * cols + cb);
      _mm_storeu_pd(out + (cb + 0) * rows + rb, _mm_unpacklo_pd(r0, r1));
      _mm_storeu_pd(out + (cb + 1) * rows + rb, _mm_unpackhi_pd(r0, r1));
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

int kiwi_host_transpose_int_sse2(void* out, const void* src, size_t rows, size_t cols, int width) {
  switch (width) {
    case 1: kiwi_transpose_i8((int8_t*)out, (const int8_t*)src, rows, cols); return 1;
    case 2: kiwi_transpose_i16((int16_t*)out, (const int16_t*)src, rows, cols); return 1;
    case 4: kiwi_transpose_i32((int32_t*)out, (const int32_t*)src, rows, cols); return 1;
    case 8: kiwi_transpose_i64((int64_t*)out, (const int64_t*)src, rows, cols); return 1;
    default: return 0;
  }
}

#endif
