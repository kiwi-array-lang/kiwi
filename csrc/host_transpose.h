#ifndef KIWI_HOST_TRANSPOSE_H
#define KIWI_HOST_TRANSPOSE_H

#include <stddef.h>
#include <stdint.h>

int kiwi_host_transpose_int(void* out, const void* src, size_t rows, size_t cols, int width);
int kiwi_host_transpose_f32(float* out, const float* src, size_t rows, size_t cols);
int kiwi_host_transpose_f64(double* out, const double* src, size_t rows, size_t cols);

#if defined(__aarch64__)
int kiwi_host_transpose_int_neon(void* out, const void* src, size_t rows, size_t cols, int width);
int kiwi_host_transpose_f32_neon(float* out, const float* src, size_t rows, size_t cols);
int kiwi_host_transpose_f64_neon(double* out, const double* src, size_t rows, size_t cols);
#endif

#if defined(__x86_64__) || defined(_M_X64)
int kiwi_host_transpose_int_sse2(void* out, const void* src, size_t rows, size_t cols, int width);
int kiwi_host_transpose_f32_sse2(float* out, const float* src, size_t rows, size_t cols);
int kiwi_host_transpose_f64_sse2(double* out, const double* src, size_t rows, size_t cols);
#endif

#endif
