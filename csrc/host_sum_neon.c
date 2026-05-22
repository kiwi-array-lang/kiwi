#include "host_sum.h"

#if defined(__aarch64__)
#include <arm_neon.h>

int64_t kiwi_host_sum_i8_neon(const int8_t* items, size_t len) {
  size_t i = 0;
  int64_t acc0 = 0;
  int64_t acc1 = 0;
  int64_t acc2 = 0;
  int64_t acc3 = 0;
  for (; i + 64 <= len; i += 64) {
    acc0 += vaddlvq_s8(vld1q_s8(items + i));
    acc1 += vaddlvq_s8(vld1q_s8(items + i + 16));
    acc2 += vaddlvq_s8(vld1q_s8(items + i + 32));
    acc3 += vaddlvq_s8(vld1q_s8(items + i + 48));
  }
  for (; i + 16 <= len; i += 16) {
    acc0 += vaddlvq_s8(vld1q_s8(items + i));
  }
  int64_t total = acc0 + acc1 + acc2 + acc3;
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i16_neon(const int16_t* items, size_t len) {
  size_t i = 0;
  int64_t acc0 = 0;
  int64_t acc1 = 0;
  int64_t acc2 = 0;
  int64_t acc3 = 0;
  for (; i + 32 <= len; i += 32) {
    acc0 += vaddlvq_s16(vld1q_s16(items + i));
    acc1 += vaddlvq_s16(vld1q_s16(items + i + 8));
    acc2 += vaddlvq_s16(vld1q_s16(items + i + 16));
    acc3 += vaddlvq_s16(vld1q_s16(items + i + 24));
  }
  for (; i + 8 <= len; i += 8) {
    acc0 += vaddlvq_s16(vld1q_s16(items + i));
  }
  int64_t total = acc0 + acc1 + acc2 + acc3;
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

int64_t kiwi_host_sum_i32_neon(const int32_t* items, size_t len) {
  size_t i = 0;
  int64_t acc0 = 0;
  int64_t acc1 = 0;
  int64_t acc2 = 0;
  int64_t acc3 = 0;
  for (; i + 16 <= len; i += 16) {
    acc0 += vaddlvq_s32(vld1q_s32(items + i));
    acc1 += vaddlvq_s32(vld1q_s32(items + i + 4));
    acc2 += vaddlvq_s32(vld1q_s32(items + i + 8));
    acc3 += vaddlvq_s32(vld1q_s32(items + i + 12));
  }
  for (; i + 4 <= len; i += 4) {
    acc0 += vaddlvq_s32(vld1q_s32(items + i));
  }
  int64_t total = acc0 + acc1 + acc2 + acc3;
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}

static int64_t kiwi_neon_hsum_s64(int64x2_t v) {
  return vgetq_lane_s64(v, 0) + vgetq_lane_s64(v, 1);
}

int64_t kiwi_host_sum_i64_neon(const int64_t* items, size_t len) {
  size_t i = 0;
  int64x2_t acc0 = vdupq_n_s64(0);
  int64x2_t acc1 = vdupq_n_s64(0);
  int64x2_t acc2 = vdupq_n_s64(0);
  int64x2_t acc3 = vdupq_n_s64(0);
  for (; i + 8 <= len; i += 8) {
    acc0 = vaddq_s64(acc0, vld1q_s64(items + i));
    acc1 = vaddq_s64(acc1, vld1q_s64(items + i + 2));
    acc2 = vaddq_s64(acc2, vld1q_s64(items + i + 4));
    acc3 = vaddq_s64(acc3, vld1q_s64(items + i + 6));
  }
  for (; i + 2 <= len; i += 2) {
    acc0 = vaddq_s64(acc0, vld1q_s64(items + i));
  }
  int64x2_t acc = vaddq_s64(vaddq_s64(acc0, acc1), vaddq_s64(acc2, acc3));
  int64_t total = kiwi_neon_hsum_s64(acc);
  for (; i < len; ++i) {
    total += items[i];
  }
  return total;
}
#endif
