#ifndef KIWI_HOST_BLAS_H
#define KIWI_HOST_BLAS_H

#include <stddef.h>

int kiwi_host_blas_sgemm_rowmajor(
    float* out,
    const float* left,
    const float* right,
    size_t rows,
    size_t cols,
    size_t inner);

int kiwi_host_blas_dgemm_rowmajor(
    double* out,
    const double* left,
    const double* right,
    size_t rows,
    size_t cols,
    size_t inner);

int kiwi_host_blas_sdot(float* out, const float* left, const float* right, size_t len);
int kiwi_host_blas_ddot(double* out, const double* left, const double* right, size_t len);

#endif
