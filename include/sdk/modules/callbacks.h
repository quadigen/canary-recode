#ifndef KNE_MODULE_CALLBACKS_H
#define KNE_MODULE_CALLBACKS_H

#include "../kne_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Retains the Luau value at `index` (normally a function). The returned handle
 * stays valid until callbacks.release or extension unload. */
typedef kne_callback (KNE_CALL *kne_callbacks_retain_fn)(kne_extension ext, kne_vm vm, int32_t index);
typedef void (KNE_CALL *kne_callbacks_release_fn)(kne_extension ext, kne_callback callback);
typedef int32_t (KNE_CALL *kne_callbacks_valid_fn)(kne_extension ext, kne_callback callback);
typedef int32_t (KNE_CALL *kne_callbacks_call_fn)(kne_extension ext, kne_callback callback, const kne_value *args, int32_t arg_count, kne_value *out, int32_t out_capacity);

typedef struct kne_callbacks_api {
	uint32_t size;
	uint32_t version;
	kne_callbacks_retain_fn retain;
	kne_callbacks_release_fn release;
	kne_callbacks_valid_fn is_valid;
	kne_callbacks_call_fn call;
} kne_callbacks_api;

#ifdef __cplusplus
}
#endif

#endif
