#ifndef KNE_MODULE_INSTANCES_H
#define KNE_MODULE_INSTANCES_H

#include "../kne_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef kne_instance (KNE_CALL *kne_create_instance_fn)(kne_extension ext, kne_string class_name);
typedef void (KNE_CALL *kne_destroy_instance_fn)(kne_extension ext, kne_instance instance);
typedef kne_string (KNE_CALL *kne_instance_name_fn)(kne_extension ext, kne_instance instance);
typedef void (KNE_CALL *kne_instance_set_name_fn)(kne_extension ext, kne_instance instance, kne_string name);
typedef kne_instance (KNE_CALL *kne_instance_parent_fn)(kne_extension ext, kne_instance instance);
typedef void (KNE_CALL *kne_instance_set_parent_fn)(kne_extension ext, kne_instance instance, kne_instance parent);
typedef size_t (KNE_CALL *kne_instance_child_count_fn)(kne_extension ext, kne_instance instance);
typedef kne_instance (KNE_CALL *kne_instance_child_at_fn)(kne_extension ext, kne_instance instance, size_t index);
typedef kne_instance (KNE_CALL *kne_instance_find_child_fn)(kne_extension ext, kne_instance instance, kne_string name);
typedef int32_t (KNE_CALL *kne_instance_is_a_fn)(kne_extension ext, kne_instance instance, kne_string class_name);
typedef kne_string (KNE_CALL *kne_instance_class_name_fn)(kne_extension ext, kne_instance instance);
typedef int32_t (KNE_CALL *kne_instance_get_property_fn)(kne_extension ext, kne_instance instance, kne_string key, kne_value *out);
typedef int32_t (KNE_CALL *kne_instance_set_property_fn)(kne_extension ext, kne_instance instance, kne_string key, const kne_value *value);
typedef void *(KNE_CALL *kne_instance_get_user_data_fn)(kne_extension ext, kne_instance instance);
typedef void (KNE_CALL *kne_instance_set_user_data_fn)(kne_extension ext, kne_instance instance, void *data);

/* Calls any class method, including engine services. Arguments are marshalled
 * from `args`; up to `out_capacity` results are written to `out`. Returns the
 * number of results written, or a negative status on error. */
typedef int32_t (KNE_CALL *kne_instance_invoke_fn)(kne_extension ext, kne_instance instance, kne_string method, const kne_value *args, int32_t arg_count, kne_value *out, int32_t out_capacity);

typedef struct kne_instances_api {
	uint32_t size;
	uint32_t version;
	kne_create_instance_fn create;
	kne_destroy_instance_fn destroy;
	kne_instance_name_fn get_name;
	kne_instance_set_name_fn set_name;
	kne_instance_parent_fn get_parent;
	kne_instance_set_parent_fn set_parent;
	kne_instance_child_count_fn child_count;
	kne_instance_child_at_fn child_at;
	kne_instance_find_child_fn find_child;
	kne_instance_is_a_fn is_a;
	kne_instance_class_name_fn class_name;
	kne_instance_get_property_fn get_property;
	kne_instance_set_property_fn set_property;
	kne_instance_get_user_data_fn get_user_data;
	kne_instance_set_user_data_fn set_user_data;
	kne_instance_invoke_fn invoke;
} kne_instances_api;

#ifdef __cplusplus
}
#endif

#endif
