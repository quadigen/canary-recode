#ifndef KNE_MODULE_EXPORTS_H
#define KNE_MODULE_EXPORTS_H

#include "../kne_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t (KNE_CALL *kne_export_exists_fn)(kne_extension ext, kne_instance instance, kne_string method);
typedef int32_t (KNE_CALL *kne_export_call_fn)(kne_extension ext, kne_instance instance, kne_string method, const kne_value *args, int32_t arg_count, kne_value *out, int32_t out_capacity);
typedef size_t (KNE_CALL *kne_export_count_fn)(kne_extension ext, kne_instance instance);
typedef kne_string (KNE_CALL *kne_export_name_at_fn)(kne_extension ext, kne_instance instance, size_t index);

typedef struct kne_exports_api {
	uint32_t size;
	uint32_t version;
	kne_export_exists_fn exists;
	kne_export_call_fn call;
	kne_export_count_fn count;
	kne_export_name_at_fn name_at;
} kne_exports_api;

#ifdef __cplusplus
}
#endif

#endif
