#ifndef KNE_MODULE_CORE_H
#define KNE_MODULE_CORE_H

#include "../kne_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (KNE_CALL *kne_log_fn)(kne_extension ext, kne_log_level level, kne_string message);
typedef void *(KNE_CALL *kne_alloc_fn)(kne_extension ext, size_t size);
typedef void *(KNE_CALL *kne_realloc_fn)(kne_extension ext, void *ptr, size_t size);
typedef void (KNE_CALL *kne_free_fn)(kne_extension ext, void *ptr);
typedef kne_string (KNE_CALL *kne_last_error_fn)(kne_extension ext);

typedef struct kne_core_api {
	uint32_t size;
	uint32_t version;
	kne_log_fn log;
	kne_alloc_fn allocate;
	kne_realloc_fn reallocate;
	kne_free_fn release;
	kne_last_error_fn last_error;
	kne_string engine_version;
	uint32_t abi_major;
	uint32_t abi_minor;
} kne_core_api;

#ifdef __cplusplus
}
#endif

#endif
