#include "host_transpose.h"
#include "host_cpu.h"

int kiwi_host_transpose_int(void* out, const void* src, size_t rows, size_t cols, int width) {
#if defined(__aarch64__)
  const KiwiHostCpuFeatures* features = kiwi_host_cpu_features();
  if (features->neon != 0) {
    return kiwi_host_transpose_int_neon(out, src, rows, cols, width);
  }
#elif defined(__x86_64__) || defined(_M_X64)
  return kiwi_host_transpose_int_sse2(out, src, rows, cols, width);
#else
  (void)out;
  (void)src;
  (void)rows;
  (void)cols;
  (void)width;
#endif
  return 0;
}

int kiwi_host_transpose_f32(float* out, const float* src, size_t rows, size_t cols) {
#if defined(__aarch64__)
  const KiwiHostCpuFeatures* features = kiwi_host_cpu_features();
  if (features->neon != 0) {
    return kiwi_host_transpose_f32_neon(out, src, rows, cols);
  }
#elif defined(__x86_64__) || defined(_M_X64)
  return kiwi_host_transpose_f32_sse2(out, src, rows, cols);
#else
  (void)out;
  (void)src;
  (void)rows;
  (void)cols;
#endif
  return 0;
}

int kiwi_host_transpose_f64(double* out, const double* src, size_t rows, size_t cols) {
#if defined(__aarch64__)
  const KiwiHostCpuFeatures* features = kiwi_host_cpu_features();
  if (features->neon != 0) {
    return kiwi_host_transpose_f64_neon(out, src, rows, cols);
  }
#elif defined(__x86_64__) || defined(_M_X64)
  return kiwi_host_transpose_f64_sse2(out, src, rows, cols);
#else
  (void)out;
  (void)src;
  (void)rows;
  (void)cols;
#endif
  return 0;
}
