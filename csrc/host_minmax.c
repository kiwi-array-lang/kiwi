#include "host_minmax.h"

#define KIWI_DEFINE_HOST_MINMAX_SCALAR(NAME, TYPE)                     \
  KiwiHostIntRange kiwi_host_minmax_##NAME##_scalar(const TYPE* items, \
                                                    size_t len) {      \
    if (len == 0) return (KiwiHostIntRange){.min = 0, .max = 0};       \
    TYPE min_value = items[0];                                         \
    TYPE max_value = items[0];                                         \
    for (size_t idx = 1; idx < len; idx++) {                           \
      TYPE value = items[idx];                                         \
      if (value < min_value) min_value = value;                        \
      if (value > max_value) max_value = value;                        \
    }                                                                  \
    return (KiwiHostIntRange){.min = min_value, .max = max_value};     \
  }

KIWI_DEFINE_HOST_MINMAX_SCALAR(i8, int8_t)
KIWI_DEFINE_HOST_MINMAX_SCALAR(i16, int16_t)
KIWI_DEFINE_HOST_MINMAX_SCALAR(i32, int32_t)
KIWI_DEFINE_HOST_MINMAX_SCALAR(i64, int64_t)

static const KiwiHostIntMinMaxDispatch kiwi_host_int_minmax_scalar_dispatch = {
    .minmax_i8 = kiwi_host_minmax_i8_scalar,
    .minmax_i16 = kiwi_host_minmax_i16_scalar,
    .minmax_i32 = kiwi_host_minmax_i32_scalar,
    .minmax_i64 = kiwi_host_minmax_i64_scalar,
    .name = "scalar",
};

const KiwiHostIntMinMaxDispatch* kiwi_host_int_minmax_dispatch(void) {
  return &kiwi_host_int_minmax_scalar_dispatch;
}
