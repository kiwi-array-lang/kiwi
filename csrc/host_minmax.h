#ifndef KIWI_HOST_MINMAX_H
#define KIWI_HOST_MINMAX_H

#include <stddef.h>
#include <stdint.h>

typedef struct KiwiHostIntRange {
  int64_t min;
  int64_t max;
} KiwiHostIntRange;

typedef KiwiHostIntRange (*kiwi_host_minmax_i8_fn)(const int8_t* items, size_t len);
typedef KiwiHostIntRange (*kiwi_host_minmax_i16_fn)(const int16_t* items, size_t len);
typedef KiwiHostIntRange (*kiwi_host_minmax_i32_fn)(const int32_t* items, size_t len);
typedef KiwiHostIntRange (*kiwi_host_minmax_i64_fn)(const int64_t* items, size_t len);

typedef struct KiwiHostIntMinMaxDispatch {
  kiwi_host_minmax_i8_fn minmax_i8;
  kiwi_host_minmax_i16_fn minmax_i16;
  kiwi_host_minmax_i32_fn minmax_i32;
  kiwi_host_minmax_i64_fn minmax_i64;
  const char* name;
} KiwiHostIntMinMaxDispatch;

KiwiHostIntRange kiwi_host_minmax_i8_scalar(const int8_t* items, size_t len);
KiwiHostIntRange kiwi_host_minmax_i16_scalar(const int16_t* items, size_t len);
KiwiHostIntRange kiwi_host_minmax_i32_scalar(const int32_t* items, size_t len);
KiwiHostIntRange kiwi_host_minmax_i64_scalar(const int64_t* items, size_t len);

const KiwiHostIntMinMaxDispatch* kiwi_host_int_minmax_dispatch(void);

#endif
