#ifndef KIWI_HOST_FIND_H
#define KIWI_HOST_FIND_H

#include <stddef.h>
#include <stdint.h>

size_t kiwi_host_find_i8(const int8_t* items, size_t len, int8_t query);
size_t kiwi_host_find_i16(const int16_t* items, size_t len, int16_t query);
size_t kiwi_host_find_i32(const int32_t* items, size_t len, int32_t query);
size_t kiwi_host_find_i64(const int64_t* items, size_t len, int64_t query);
size_t kiwi_host_find_f64(const double* items, size_t len, double query);

size_t kiwi_host_find_i8_scalar(const int8_t* items, size_t len, int8_t query);
size_t kiwi_host_find_i16_scalar(const int16_t* items, size_t len, int16_t query);
size_t kiwi_host_find_i32_scalar(const int32_t* items, size_t len, int32_t query);
size_t kiwi_host_find_i64_scalar(const int64_t* items, size_t len, int64_t query);
size_t kiwi_host_find_f64_scalar(const double* items, size_t len, double query);

typedef size_t (*kiwi_host_find_i8_fn)(const int8_t* items, size_t len, int8_t query);
typedef size_t (*kiwi_host_find_i16_fn)(const int16_t* items, size_t len, int16_t query);
typedef size_t (*kiwi_host_find_i32_fn)(const int32_t* items, size_t len, int32_t query);
typedef size_t (*kiwi_host_find_i64_fn)(const int64_t* items, size_t len, int64_t query);
typedef size_t (*kiwi_host_find_f64_fn)(const double* items, size_t len, double query);

typedef struct KiwiHostFindDispatch {
  kiwi_host_find_i8_fn find_i8;
  kiwi_host_find_i16_fn find_i16;
  kiwi_host_find_i32_fn find_i32;
  kiwi_host_find_i64_fn find_i64;
  kiwi_host_find_f64_fn find_f64;
  const char* name;
} KiwiHostFindDispatch;

const KiwiHostFindDispatch* kiwi_host_find_dispatch(void);

#if defined(__aarch64__)
size_t kiwi_host_find_i8_neon(const int8_t* items, size_t len, int8_t query);
size_t kiwi_host_find_i16_neon(const int16_t* items, size_t len, int16_t query);
size_t kiwi_host_find_i32_neon(const int32_t* items, size_t len, int32_t query);
size_t kiwi_host_find_i64_neon(const int64_t* items, size_t len, int64_t query);
size_t kiwi_host_find_f64_neon(const double* items, size_t len, double query);
#endif

#if defined(__x86_64__) || defined(_M_X64)
size_t kiwi_host_find_i8_sse2(const int8_t* items, size_t len, int8_t query);
size_t kiwi_host_find_i16_sse2(const int16_t* items, size_t len, int16_t query);
size_t kiwi_host_find_i32_sse2(const int32_t* items, size_t len, int32_t query);
size_t kiwi_host_find_i64_sse2(const int64_t* items, size_t len, int64_t query);
size_t kiwi_host_find_f64_sse2(const double* items, size_t len, double query);

size_t kiwi_host_find_i8_avx2(const int8_t* items, size_t len, int8_t query);
size_t kiwi_host_find_i16_avx2(const int16_t* items, size_t len, int16_t query);
size_t kiwi_host_find_i32_avx2(const int32_t* items, size_t len, int32_t query);
size_t kiwi_host_find_i64_avx2(const int64_t* items, size_t len, int64_t query);
size_t kiwi_host_find_f64_avx2(const double* items, size_t len, double query);

size_t kiwi_host_find_i8_avx512(const int8_t* items, size_t len, int8_t query);
size_t kiwi_host_find_i16_avx512(const int16_t* items, size_t len, int16_t query);
size_t kiwi_host_find_i32_avx512(const int32_t* items, size_t len, int32_t query);
size_t kiwi_host_find_i64_avx512(const int64_t* items, size_t len, int64_t query);
size_t kiwi_host_find_f64_avx512(const double* items, size_t len, double query);
#endif

#endif
