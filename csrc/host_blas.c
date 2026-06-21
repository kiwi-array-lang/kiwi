#include "host_blas.h"

#include <limits.h>

#if defined(__APPLE__)
#include <Availability.h>
#include <dlfcn.h>
#include <pthread.h>

#if (defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED >= 130300) || \
    (defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 160400) || \
    (defined(__TV_OS_VERSION_MIN_REQUIRED) && __TV_OS_VERSION_MIN_REQUIRED >= 160400) || \
    (defined(__WATCH_OS_VERSION_MIN_REQUIRED) && __WATCH_OS_VERSION_MIN_REQUIRED >= 90400)
#define ACCELERATE_NEW_LAPACK
#endif

#include <vecLib/cblas.h>

static int kiwi_host_blas_dims_fit_int(size_t rows, size_t cols, size_t inner) {
  return rows <= (size_t)INT_MAX && cols <= (size_t)INT_MAX && inner <= (size_t)INT_MAX;
}

static int kiwi_host_blas_len_fits_int(size_t len) {
  return len <= (size_t)INT_MAX;
}

typedef float (*kiwi_cblas_sdot_fn)(const int, const float*, const int, const float*, const int);
typedef double (*kiwi_cblas_ddot_fn)(const int, const double*, const int, const double*, const int);
typedef void (*kiwi_cblas_sgemm_fn)(
    const enum CBLAS_ORDER,
    const enum CBLAS_TRANSPOSE,
    const enum CBLAS_TRANSPOSE,
    const int,
    const int,
    const int,
    const float,
    const float*,
    const int,
    const float*,
    const int,
    const float,
    float*,
    const int);
typedef void (*kiwi_cblas_dgemm_fn)(
    const enum CBLAS_ORDER,
    const enum CBLAS_TRANSPOSE,
    const enum CBLAS_TRANSPOSE,
    const int,
    const int,
    const int,
    const double,
    const double*,
    const int,
    const double*,
    const int,
    const double,
    double*,
    const int);

typedef struct KiwiHostBlasSymbols {
  kiwi_cblas_sgemm_fn sgemm;
  kiwi_cblas_dgemm_fn dgemm;
  kiwi_cblas_sdot_fn sdot;
  kiwi_cblas_ddot_fn ddot;
} KiwiHostBlasSymbols;

static KiwiHostBlasSymbols kiwi_host_blas_symbols = {0};
static pthread_once_t kiwi_host_blas_once = PTHREAD_ONCE_INIT;

/* Resolve CBLAS symbols dynamically when the Darwin linker does not bind the SDK stubs. */
static void* kiwi_host_blas_open_accelerate(void) {
  void* handle = dlopen("/System/Library/Frameworks/Accelerate.framework/Accelerate", RTLD_LAZY | RTLD_LOCAL);
  if (handle != NULL) {
    return handle;
  }
  return dlopen(
      "/System/Library/Frameworks/Accelerate.framework/Frameworks/vecLib.framework/vecLib",
      RTLD_LAZY | RTLD_LOCAL);
}

static void kiwi_host_blas_load_once(void) {
  void* handle = kiwi_host_blas_open_accelerate();
  if (handle == NULL) {
    return;
  }
  kiwi_host_blas_symbols.sgemm = (kiwi_cblas_sgemm_fn)dlsym(handle, "cblas_sgemm");
  kiwi_host_blas_symbols.dgemm = (kiwi_cblas_dgemm_fn)dlsym(handle, "cblas_dgemm");
  kiwi_host_blas_symbols.sdot = (kiwi_cblas_sdot_fn)dlsym(handle, "cblas_sdot");
  kiwi_host_blas_symbols.ddot = (kiwi_cblas_ddot_fn)dlsym(handle, "cblas_ddot");
}

static const KiwiHostBlasSymbols* kiwi_host_blas_get(void) {
  pthread_once(&kiwi_host_blas_once, kiwi_host_blas_load_once);
  if (kiwi_host_blas_symbols.sgemm == NULL || kiwi_host_blas_symbols.dgemm == NULL ||
      kiwi_host_blas_symbols.sdot == NULL || kiwi_host_blas_symbols.ddot == NULL) {
    return NULL;
  }
  return &kiwi_host_blas_symbols;
}
#endif

int kiwi_host_blas_sgemm_rowmajor_ex(
    float* out,
    const float* left,
    int left_transpose,
    const float* right,
    int right_transpose,
    size_t rows,
    size_t cols,
    size_t inner) {
#if defined(__APPLE__)
  const KiwiHostBlasSymbols* blas = kiwi_host_blas_get();
  if (blas == NULL) {
    return 0;
  }
  if (rows == 0 || cols == 0) {
    return 1;
  }
  if (inner == 0 || !kiwi_host_blas_dims_fit_int(rows, cols, inner)) {
    return 0;
  }
  if (rows > ((size_t)-1) / inner || inner > ((size_t)-1) / cols || rows > ((size_t)-1) / cols) {
    return 0;
  }
  const int m = (int)rows;
  const int n = (int)cols;
  const int k = (int)inner;
  const enum CBLAS_TRANSPOSE trans_a = left_transpose ? CblasTrans : CblasNoTrans;
  const enum CBLAS_TRANSPOSE trans_b = right_transpose ? CblasTrans : CblasNoTrans;
  const int lda = left_transpose ? m : k;
  const int ldb = right_transpose ? k : n;
  blas->sgemm(CblasRowMajor, trans_a, trans_b, m, n, k, 1.0f, left, lda, right, ldb, 0.0f, out, n);
  return 1;
#else
  (void)out;
  (void)left;
  (void)left_transpose;
  (void)right;
  (void)right_transpose;
  (void)rows;
  (void)cols;
  (void)inner;
  return 0;
#endif
}

int kiwi_host_blas_sgemm_rowmajor(
    float* out,
    const float* left,
    const float* right,
    size_t rows,
    size_t cols,
    size_t inner) {
  return kiwi_host_blas_sgemm_rowmajor_ex(out, left, 0, right, 0, rows, cols, inner);
}

int kiwi_host_blas_sgemm_rowmajor_batched(
    float* out,
    const float* left,
    const float* right,
    size_t batch,
    size_t rows,
    size_t cols,
    size_t inner) {
#if defined(__APPLE__)
  const KiwiHostBlasSymbols* blas = kiwi_host_blas_get();
  if (blas == NULL) {
    return 0;
  }
  if (batch == 0 || rows == 0 || cols == 0) {
    return 1;
  }
  if (inner == 0 || !kiwi_host_blas_dims_fit_int(rows, cols, inner)) {
    return 0;
  }
  if (rows > ((size_t)-1) / inner || inner > ((size_t)-1) / cols || rows > ((size_t)-1) / cols) {
    return 0;
  }
  const int m = (int)rows;
  const int n = (int)cols;
  const int k = (int)inner;
  const size_t left_stride = rows * inner;
  const size_t right_stride = inner * cols;
  const size_t out_stride = rows * cols;
  for (size_t idx = 0; idx < batch; ++idx) {
    blas->sgemm(
        CblasRowMajor,
        CblasNoTrans,
        CblasNoTrans,
        m,
        n,
        k,
        1.0f,
        left + idx * left_stride,
        k,
        right + idx * right_stride,
        n,
        0.0f,
        out + idx * out_stride,
        n);
  }
  return 1;
#else
  (void)out;
  (void)left;
  (void)right;
  (void)batch;
  (void)rows;
  (void)cols;
  (void)inner;
  return 0;
#endif
}

int kiwi_host_blas_dgemm_rowmajor_ex(
    double* out,
    const double* left,
    int left_transpose,
    const double* right,
    int right_transpose,
    size_t rows,
    size_t cols,
    size_t inner) {
#if defined(__APPLE__)
  const KiwiHostBlasSymbols* blas = kiwi_host_blas_get();
  if (blas == NULL) {
    return 0;
  }
  if (rows == 0 || cols == 0) {
    return 1;
  }
  if (inner == 0 || !kiwi_host_blas_dims_fit_int(rows, cols, inner)) {
    return 0;
  }
  const int m = (int)rows;
  const int n = (int)cols;
  const int k = (int)inner;
  const enum CBLAS_TRANSPOSE trans_a = left_transpose ? CblasTrans : CblasNoTrans;
  const enum CBLAS_TRANSPOSE trans_b = right_transpose ? CblasTrans : CblasNoTrans;
  const int lda = left_transpose ? m : k;
  const int ldb = right_transpose ? k : n;
  blas->dgemm(CblasRowMajor, trans_a, trans_b, m, n, k, 1.0, left, lda, right, ldb, 0.0, out, n);
  return 1;
#else
  (void)out;
  (void)left;
  (void)left_transpose;
  (void)right;
  (void)right_transpose;
  (void)rows;
  (void)cols;
  (void)inner;
  return 0;
#endif
}

int kiwi_host_blas_dgemm_rowmajor(
    double* out,
    const double* left,
    const double* right,
    size_t rows,
    size_t cols,
    size_t inner) {
  return kiwi_host_blas_dgemm_rowmajor_ex(out, left, 0, right, 0, rows, cols, inner);
}

int kiwi_host_blas_dgemm_rowmajor_batched(
    double* out,
    const double* left,
    const double* right,
    size_t batch,
    size_t rows,
    size_t cols,
    size_t inner) {
#if defined(__APPLE__)
  const KiwiHostBlasSymbols* blas = kiwi_host_blas_get();
  if (blas == NULL) {
    return 0;
  }
  if (batch == 0 || rows == 0 || cols == 0) {
    return 1;
  }
  if (inner == 0 || !kiwi_host_blas_dims_fit_int(rows, cols, inner)) {
    return 0;
  }
  const int m = (int)rows;
  const int n = (int)cols;
  const int k = (int)inner;
  const size_t left_stride = rows * inner;
  const size_t right_stride = inner * cols;
  const size_t out_stride = rows * cols;
  for (size_t idx = 0; idx < batch; ++idx) {
    blas->dgemm(
        CblasRowMajor,
        CblasNoTrans,
        CblasNoTrans,
        m,
        n,
        k,
        1.0,
        left + idx * left_stride,
        k,
        right + idx * right_stride,
        n,
        0.0,
        out + idx * out_stride,
        n);
  }
  return 1;
#else
  (void)out;
  (void)left;
  (void)right;
  (void)batch;
  (void)rows;
  (void)cols;
  (void)inner;
  return 0;
#endif
}

int kiwi_host_blas_sdot(float* out, const float* left, const float* right, size_t len) {
#if defined(__APPLE__)
  const KiwiHostBlasSymbols* blas = kiwi_host_blas_get();
  if (blas == NULL) {
    return 0;
  }
  if (!kiwi_host_blas_len_fits_int(len)) {
    return 0;
  }
  if (len == 0) {
    *out = 0.0f;
    return 1;
  }
  *out = blas->sdot((int)len, left, 1, right, 1);
  return 1;
#else
  (void)out;
  (void)left;
  (void)right;
  (void)len;
  return 0;
#endif
}

int kiwi_host_blas_ddot(double* out, const double* left, const double* right, size_t len) {
#if defined(__APPLE__)
  const KiwiHostBlasSymbols* blas = kiwi_host_blas_get();
  if (blas == NULL) {
    return 0;
  }
  if (!kiwi_host_blas_len_fits_int(len)) {
    return 0;
  }
  if (len == 0) {
    *out = 0.0;
    return 1;
  }
  *out = blas->ddot((int)len, left, 1, right, 1);
  return 1;
#else
  (void)out;
  (void)left;
  (void)right;
  (void)len;
  return 0;
#endif
}
