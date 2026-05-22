#ifndef KIWI_HOST_CPU_H
#define KIWI_HOST_CPU_H

#include <stdint.h>

typedef struct KiwiHostCpuFeatures {
  uint8_t neon;
  uint8_t sse41;
  uint8_t avx2;
  uint8_t avx512f;
  uint8_t avx512bw;
  uint8_t os_ymm;
  uint8_t os_zmm;
} KiwiHostCpuFeatures;

const KiwiHostCpuFeatures* kiwi_host_cpu_features(void);

static inline int kiwi_host_cpu_supports_sse41(const KiwiHostCpuFeatures* features) {
  return features->sse41 != 0;
}

static inline int kiwi_host_cpu_supports_avx2(const KiwiHostCpuFeatures* features) {
  return features->avx2 != 0 && features->os_ymm != 0;
}

static inline int kiwi_host_cpu_supports_avx512bw(const KiwiHostCpuFeatures* features) {
  return features->avx512f != 0 && features->avx512bw != 0 && features->os_zmm != 0;
}

#endif
