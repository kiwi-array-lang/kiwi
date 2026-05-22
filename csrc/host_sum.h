#ifndef KIWI_HOST_SUM_H
#define KIWI_HOST_SUM_H

#include <stddef.h>
#include <stdint.h>

typedef int64_t (*kiwi_host_sum_i8_fn)(const int8_t* items, size_t len);
typedef int64_t (*kiwi_host_sum_i16_fn)(const int16_t* items, size_t len);
typedef int64_t (*kiwi_host_sum_i32_fn)(const int32_t* items, size_t len);
typedef int64_t (*kiwi_host_sum_i64_fn)(const int64_t* items, size_t len);

typedef struct KiwiHostIntSumDispatch {
  kiwi_host_sum_i8_fn sum_i8;
  kiwi_host_sum_i16_fn sum_i16;
  kiwi_host_sum_i32_fn sum_i32;
  kiwi_host_sum_i64_fn sum_i64;
  const char* name;
} KiwiHostIntSumDispatch;

int64_t kiwi_host_sum_i8_scalar(const int8_t* items, size_t len);
int64_t kiwi_host_sum_i16_scalar(const int16_t* items, size_t len);
int64_t kiwi_host_sum_i32_scalar(const int32_t* items, size_t len);
int64_t kiwi_host_sum_i64_scalar(const int64_t* items, size_t len);

#if defined(__aarch64__)
int64_t kiwi_host_sum_i8_neon(const int8_t* items, size_t len);
int64_t kiwi_host_sum_i16_neon(const int16_t* items, size_t len);
int64_t kiwi_host_sum_i32_neon(const int32_t* items, size_t len);
int64_t kiwi_host_sum_i64_neon(const int64_t* items, size_t len);
#endif

#if defined(__x86_64__) || defined(_M_X64)
int64_t kiwi_host_sum_i8_sse2(const int8_t* items, size_t len);
int64_t kiwi_host_sum_i16_sse2(const int16_t* items, size_t len);
int64_t kiwi_host_sum_i32_sse2(const int32_t* items, size_t len);
int64_t kiwi_host_sum_i64_sse2(const int64_t* items, size_t len);

int64_t kiwi_host_sum_i8_avx2(const int8_t* items, size_t len);
int64_t kiwi_host_sum_i16_avx2(const int16_t* items, size_t len);
int64_t kiwi_host_sum_i32_avx2(const int32_t* items, size_t len);
int64_t kiwi_host_sum_i64_avx2(const int64_t* items, size_t len);

int64_t kiwi_host_sum_i8_avx512(const int8_t* items, size_t len);
int64_t kiwi_host_sum_i16_avx512(const int16_t* items, size_t len);
int64_t kiwi_host_sum_i32_avx512(const int32_t* items, size_t len);
int64_t kiwi_host_sum_i64_avx512(const int64_t* items, size_t len);
#endif

const KiwiHostIntSumDispatch* kiwi_host_int_sum_dispatch(void);

#endif
