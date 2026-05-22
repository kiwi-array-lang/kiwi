#include "host_dyad.h"
#include "host_cpu.h"

int kiwi_host_dyad_f64_array(double* out, const double* left, const double* right, size_t len, int op) {
#if defined(__aarch64__)
  const KiwiHostCpuFeatures* features = kiwi_host_cpu_features();
  if (features->neon != 0) {
    return kiwi_host_dyad_f64_array_neon(out, left, right, len, op);
  }
#else
  (void)out;
  (void)left;
  (void)right;
  (void)len;
  (void)op;
#endif
  return 0;
}

int kiwi_host_dyad_f64_scalar(double* out, double scalar, const double* items, size_t len, int scalar_left, int op) {
#if defined(__aarch64__)
  const KiwiHostCpuFeatures* features = kiwi_host_cpu_features();
  if (features->neon != 0) {
    return kiwi_host_dyad_f64_scalar_neon(out, scalar, items, len, scalar_left, op);
  }
#else
  (void)out;
  (void)scalar;
  (void)items;
  (void)len;
  (void)scalar_left;
  (void)op;
#endif
  return 0;
}

int kiwi_host_dyad_int_array(void* out, const void* left, const void* right, size_t len, int width, int op) {
#if defined(__aarch64__)
  const KiwiHostCpuFeatures* features = kiwi_host_cpu_features();
  if (features->neon != 0) {
    return kiwi_host_dyad_int_array_neon(out, left, right, len, width, op);
  }
#else
  (void)out;
  (void)left;
  (void)right;
  (void)len;
  (void)width;
  (void)op;
#endif
  return 0;
}

int kiwi_host_dyad_int_scalar(void* out, int64_t scalar, const void* items, size_t len, int width, int scalar_left, int op) {
#if defined(__aarch64__)
  const KiwiHostCpuFeatures* features = kiwi_host_cpu_features();
  if (features->neon != 0) {
    return kiwi_host_dyad_int_scalar_neon(out, scalar, items, len, width, scalar_left, op);
  }
#else
  (void)out;
  (void)scalar;
  (void)items;
  (void)len;
  (void)width;
  (void)scalar_left;
  (void)op;
#endif
  return 0;
}
