#ifndef KNE_MODULE_CLASSES_H
#define KNE_MODULE_CLASSES_H

#include "../kne_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KNE_CLASS_CREATABLE 0x1u
#define KNE_CLASS_SERVICE 0x2u

/* Returned by a class namecall to say "I do not handle this method". The
 * host then runs the engine's own Instance behaviour, so IsA, Destroy,
 * Clone and the rest keep working on extension classes. */
#define KNE_UNHANDLED (-1)

typedef void (KNE_CALL *kne_class_construct_fn)(kne_extension ext, kne_instance instance);
typedef int32_t (KNE_CALL *kne_class_get_fn)(kne_extension ext, kne_instance instance, kne_string key, kne_value *out);
typedef int32_t (KNE_CALL *kne_class_set_fn)(kne_extension ext, kne_instance instance, kne_string key, const kne_value *value);
typedef int32_t (KNE_CALL *kne_class_namecall_fn)(kne_extension ext, kne_instance instance, kne_string method, kne_vm vm, int32_t arg_count);
typedef void (KNE_CALL *kne_class_step_fn)(kne_extension ext, kne_instance instance, double delta_time);

typedef struct kne_class_desc {
	uint32_t size;
	uint32_t version;
	kne_string name;
	kne_string base;
	uint32_t flags;
	uint32_t reserved;
	kne_string properties;
	kne_string methods;
	kne_string events;
	kne_class_construct_fn on_construct;
	kne_class_construct_fn on_destroy;
	kne_class_get_fn get;
	kne_class_set_fn set;
	kne_class_namecall_fn namecall;
	kne_class_step_fn step;
} kne_class_desc;

typedef int32_t (KNE_CALL *kne_register_class_fn)(kne_extension ext, const kne_class_desc *desc);
typedef int32_t (KNE_CALL *kne_is_class_registered_fn)(kne_extension ext, kne_string name);

typedef struct kne_classes_api {
	uint32_t size;
	uint32_t version;
	kne_register_class_fn register_class;
	kne_is_class_registered_fn is_registered;
} kne_classes_api;

#ifdef __cplusplus
}
#endif

#endif
