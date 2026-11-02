#ifndef KNE_MODULE_SERVICES_H
#define KNE_MODULE_SERVICES_H

#include "../kne_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef kne_instance (KNE_CALL *kne_get_service_fn)(kne_extension ext, kne_string name);
typedef int32_t (KNE_CALL *kne_service_exists_fn)(kne_extension ext, kne_string name);
typedef size_t (KNE_CALL *kne_service_count_fn)(kne_extension ext);
typedef kne_string (KNE_CALL *kne_service_name_at_fn)(kne_extension ext, size_t index);

typedef struct kne_services_api {
	uint32_t size;
	uint32_t version;
	kne_get_service_fn get;
	kne_service_exists_fn exists;
	kne_service_count_fn count;
	kne_service_name_at_fn name_at;
} kne_services_api;

#ifdef __cplusplus
}
#endif

#endif
