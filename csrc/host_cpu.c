#include "host_cpu.h"

#include <stdatomic.h>

#if defined(__x86_64__) || defined(_M_X64)
#if defined(_MSC_VER)
#include <intrin.h>
static void kiwi_host_cpu_cpuid(int out[4], int leaf, int subleaf) {
  __cpuidex(out, leaf, subleaf);
}

static uint64_t kiwi_host_cpu_xgetbv(uint32_t index) {
  return _xgetbv(index);
}
#else
#include <cpuid.h>
static void kiwi_host_cpu_cpuid(int out[4], int leaf, int subleaf) {
  unsigned int eax = 0;
  unsigned int ebx = 0;
  unsigned int ecx = 0;
  unsigned int edx = 0;
  __cpuid_count((unsigned int)leaf, (unsigned int)subleaf, eax, ebx, ecx, edx);
  out[0] = (int)eax;
  out[1] = (int)ebx;
  out[2] = (int)ecx;
  out[3] = (int)edx;
}

static uint64_t kiwi_host_cpu_xgetbv(uint32_t index) {
  uint32_t eax = 0;
  uint32_t edx = 0;
  __asm__ volatile("xgetbv" : "=a"(eax), "=d"(edx) : "c"(index));
  return ((uint64_t)edx << 32) | eax;
}
#endif
#endif

static KiwiHostCpuFeatures kiwi_host_cpu_detect_features(void) {
  KiwiHostCpuFeatures features = {0, 0, 0, 0, 0, 0, 0};

#if defined(__aarch64__)
  features.neon = 1;
#elif defined(__x86_64__) || defined(_M_X64)
  int regs[4] = {0, 0, 0, 0};
  kiwi_host_cpu_cpuid(regs, 0, 0);
  const int max_leaf = regs[0];

  int has_avx = 0;
  if (max_leaf >= 1) {
    kiwi_host_cpu_cpuid(regs, 1, 0);
    const int ecx = regs[2];
    const int has_osxsave = (ecx & (1 << 27)) != 0;
    has_avx = (ecx & (1 << 28)) != 0;
    features.sse41 = (ecx & (1 << 19)) != 0;

    if (has_osxsave && has_avx) {
      const uint64_t xcr0 = kiwi_host_cpu_xgetbv(0);
      features.os_ymm = (xcr0 & 0x6) == 0x6;
      features.os_zmm = (xcr0 & 0xe6) == 0xe6;
    }
  }

  if (max_leaf >= 7) {
    kiwi_host_cpu_cpuid(regs, 7, 0);
    const int ebx = regs[1];
    features.avx2 = has_avx && ((ebx & (1 << 5)) != 0);
    features.avx512f = has_avx && ((ebx & (1 << 16)) != 0);
    features.avx512bw = (ebx & (1 << 30)) != 0;
  }
#endif

  return features;
}

static KiwiHostCpuFeatures kiwi_host_cpu_selected_features;
static atomic_uint kiwi_host_cpu_features_ready;

const KiwiHostCpuFeatures* kiwi_host_cpu_features(void) {
  if (atomic_load_explicit(&kiwi_host_cpu_features_ready, memory_order_acquire) == 2u) {
    return &kiwi_host_cpu_selected_features;
  }

  unsigned expected = 0u;
  if (atomic_compare_exchange_strong_explicit(
          &kiwi_host_cpu_features_ready,
          &expected,
          1u,
          memory_order_acq_rel,
          memory_order_acquire)) {
    kiwi_host_cpu_selected_features = kiwi_host_cpu_detect_features();
    atomic_store_explicit(&kiwi_host_cpu_features_ready, 2u, memory_order_release);
    return &kiwi_host_cpu_selected_features;
  }

  while (atomic_load_explicit(&kiwi_host_cpu_features_ready, memory_order_acquire) != 2u) {
  }
  return &kiwi_host_cpu_selected_features;
}
