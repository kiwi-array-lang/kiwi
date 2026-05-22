#ifndef KIWI_HOST_DYAD_H
#define KIWI_HOST_DYAD_H

#include <stddef.h>
#include <stdint.h>

enum {
  KIWI_HOST_DYAD_ADD = 1,
  KIWI_HOST_DYAD_SUB = 2,
  KIWI_HOST_DYAD_MUL = 3,
  KIWI_HOST_DYAD_DIV = 4,
  KIWI_HOST_DYAD_MIN = 5,
  KIWI_HOST_DYAD_MAX = 6,
};

int kiwi_host_dyad_f64_array(double* out, const double* left, const double* right, size_t len, int op);
int kiwi_host_dyad_f64_scalar(double* out, double scalar, const double* items, size_t len, int scalar_left, int op);
int kiwi_host_dyad_int_array(void* out, const void* left, const void* right, size_t len, int width, int op);
int kiwi_host_dyad_int_scalar(void* out, int64_t scalar, const void* items, size_t len, int width, int scalar_left, int op);

#if defined(__aarch64__)
int kiwi_host_dyad_f64_array_neon(double* out, const double* left, const double* right, size_t len, int op);
int kiwi_host_dyad_f64_scalar_neon(double* out, double scalar, const double* items, size_t len, int scalar_left, int op);
int kiwi_host_dyad_int_array_neon(void* out, const void* left, const void* right, size_t len, int width, int op);
int kiwi_host_dyad_int_scalar_neon(void* out, int64_t scalar, const void* items, size_t len, int width, int scalar_left, int op);
#endif

#endif
