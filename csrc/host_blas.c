#include "host_blas.h"

#include <limits.h>

#if defined(__APPLE__)
typedef enum {
  KiwiCblasRowMajor = 101,
} KiwiCblasOrder;

typedef enum {
  KiwiCblasNoTrans = 111,
} KiwiCblasTranspose;

extern void cblas_sgemm(
    const KiwiCblasOrder order,
    const KiwiCblasTranspose trans_a,
    const KiwiCblasTranspose trans_b,
    const int rows,
    const int cols,
    const int inner,
    const float alpha,
    const float* left,
    const int lda,
    const float* right,
    const int ldb,
    const float beta,
    float* out,
    const int ldc);

extern void cblas_dgemm(
    const KiwiCblasOrder order,
    const KiwiCblasTranspose trans_a,
    const KiwiCblasTranspose trans_b,
    const int rows,
    const int cols,
    const int inner,
    const double alpha,
    const double* left,
    const int lda,
    const double* right,
    const int ldb,
    const double beta,
    double* out,
    const int ldc);

extern float cblas_sdot(const int len, const float* left, const int left_stride, const float* right, const int right_stride);
extern double cblas_ddot(const int len, const double* left, const int left_stride, const double* right, const int right_stride);

static int kiwi_host_blas_dims_fit_int(size_t rows, size_t cols, size_t inner) {
  return rows <= (size_t)INT_MAX && cols <= (size_t)INT_MAX && inner <= (size_t)INT_MAX;
}

static int kiwi_host_blas_len_fits_int(size_t len) {
  return len <= (size_t)INT_MAX;
}
#endif

int kiwi_host_blas_sgemm_rowmajor(
    float* out,
    const float* left,
    const float* right,
    size_t rows,
    size_t cols,
    size_t inner) {
#if defined(__APPLE__)
  if (rows == 0 || cols == 0) {
    return 1;
  }
  if (inner == 0 || !kiwi_host_blas_dims_fit_int(rows, cols, inner)) {
    return 0;
  }
  const int m = (int)rows;
  const int n = (int)cols;
  const int k = (int)inner;
  cblas_sgemm(KiwiCblasRowMajor, KiwiCblasNoTrans, KiwiCblasNoTrans, m, n, k, 1.0f, left, k, right, n, 0.0f, out, n);
  return 1;
#else
  (void)out;
  (void)left;
  (void)right;
  (void)rows;
  (void)cols;
  (void)inner;
  return 0;
#endif
}

int kiwi_host_blas_dgemm_rowmajor(
    double* out,
    const double* left,
    const double* right,
    size_t rows,
    size_t cols,
    size_t inner) {
#if defined(__APPLE__)
  if (rows == 0 || cols == 0) {
    return 1;
  }
  if (inner == 0 || !kiwi_host_blas_dims_fit_int(rows, cols, inner)) {
    return 0;
  }
  const int m = (int)rows;
  const int n = (int)cols;
  const int k = (int)inner;
  cblas_dgemm(KiwiCblasRowMajor, KiwiCblasNoTrans, KiwiCblasNoTrans, m, n, k, 1.0, left, k, right, n, 0.0, out, n);
  return 1;
#else
  (void)out;
  (void)left;
  (void)right;
  (void)rows;
  (void)cols;
  (void)inner;
  return 0;
#endif
}

int kiwi_host_blas_sdot(float* out, const float* left, const float* right, size_t len) {
#if defined(__APPLE__)
  if (!kiwi_host_blas_len_fits_int(len)) {
    return 0;
  }
  if (len == 0) {
    *out = 0.0f;
    return 1;
  }
  *out = cblas_sdot((int)len, left, 1, right, 1);
  return 1;
#else
  (void)out;
  (void)left;
  (void)right;
  (void)len;
  return 0;
#endif
}

int kiwi_host_blas_ddot(double* out, const double* left, const double* right, size_t len) {
#if defined(__APPLE__)
  if (!kiwi_host_blas_len_fits_int(len)) {
    return 0;
  }
  if (len == 0) {
    *out = 0.0;
    return 1;
  }
  *out = cblas_ddot((int)len, left, 1, right, 1);
  return 1;
#else
  (void)out;
  (void)left;
  (void)right;
  (void)len;
  return 0;
#endif
}
