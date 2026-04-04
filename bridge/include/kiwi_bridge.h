#ifndef KIWI_BRIDGE_H
#define KIWI_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct kiwi_session kiwi_session_t;

typedef enum {
  KIWI_DEVICE_AUTO = 0,
  KIWI_DEVICE_CPU = 1,
  KIWI_DEVICE_GPU = 2,
} kiwi_device_preference_e;

typedef enum {
  KIWI_STATUS_OK = 0,
  KIWI_STATUS_PARSE = 1,
  KIWI_STATUS_TYPE = 2,
  KIWI_STATUS_NAME = 3,
  KIWI_STATUS_DOMAIN = 4,
  KIWI_STATUS_RANK = 5,
  KIWI_STATUS_NYI = 6,
  KIWI_STATUS_LENGTH = 7,
  KIWI_STATUS_INDEX = 8,
  KIWI_STATUS_MLX = 9,
  KIWI_STATUS_DEVICE = 10,
  KIWI_STATUS_ERROR = 11,
  KIWI_STATUS_OOM = 12,
} kiwi_status_e;

typedef enum {
  KIWI_AUTOGRAD_NONE = 0,
  KIWI_AUTOGRAD_MLX = 1,
  KIWI_AUTOGRAD_FINITE_DIFFERENCE = 2,
} kiwi_autograd_path_e;

typedef struct {
  kiwi_status_e status;
  bool echoed;
  kiwi_autograd_path_e autograd_path;
  char* text_ptr;
  uintptr_t text_len;
} kiwi_eval_result_s;

kiwi_session_t* kiwi_session_create(kiwi_device_preference_e device);
void kiwi_session_destroy(kiwi_session_t* session);
kiwi_eval_result_s kiwi_session_eval(
    kiwi_session_t* session,
    const char* source,
    uintptr_t source_len);
kiwi_status_e kiwi_session_set_global_float_array(
    kiwi_session_t* session,
    const char* name,
    uintptr_t name_len,
    const float* data,
    const int32_t* dims,
    uintptr_t ndim);
kiwi_status_e kiwi_session_set_global_int_array(
    kiwi_session_t* session,
    const char* name,
    uintptr_t name_len,
    const int32_t* data,
    const int32_t* dims,
    uintptr_t ndim);
kiwi_status_e kiwi_session_set_global_bool_array(
    kiwi_session_t* session,
    const char* name,
    uintptr_t name_len,
    const bool* data,
    const int32_t* dims,
    uintptr_t ndim);
void kiwi_eval_result_free(kiwi_eval_result_s result);
const char* kiwi_status_name(kiwi_status_e status);

#ifdef __cplusplus
}
#endif

#endif
