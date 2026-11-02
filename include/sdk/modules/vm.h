#ifndef KNE_MODULE_VM_H
#define KNE_MODULE_VM_H

#include "../kne_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t (KNE_CALL *kne_vm_native_fn)(kne_extension ext, kne_vm vm);

typedef int32_t (KNE_CALL *kne_vm_arg_count_fn)(kne_vm vm);
typedef kne_value_kind (KNE_CALL *kne_vm_kind_fn)(kne_vm vm, int32_t index);
typedef double (KNE_CALL *kne_vm_number_fn)(kne_vm vm, int32_t index);
typedef int64_t (KNE_CALL *kne_vm_integer_fn)(kne_vm vm, int32_t index);
typedef int32_t (KNE_CALL *kne_vm_boolean_fn)(kne_vm vm, int32_t index);
typedef kne_string (KNE_CALL *kne_vm_string_fn)(kne_vm vm, int32_t index);
typedef kne_instance (KNE_CALL *kne_vm_instance_fn)(kne_vm vm, int32_t index);
typedef int32_t (KNE_CALL *kne_vm_is_function_fn)(kne_vm vm, int32_t index);
typedef void (KNE_CALL *kne_vm_push_nil_fn)(kne_vm vm);
typedef void (KNE_CALL *kne_vm_push_boolean_fn)(kne_vm vm, int32_t value);
typedef void (KNE_CALL *kne_vm_push_number_fn)(kne_vm vm, double value);
typedef void (KNE_CALL *kne_vm_push_integer_fn)(kne_vm vm, int64_t value);
typedef void (KNE_CALL *kne_vm_push_string_fn)(kne_vm vm, kne_string value);
typedef void (KNE_CALL *kne_vm_push_instance_fn)(kne_vm vm, kne_instance instance);
typedef void (KNE_CALL *kne_vm_push_value_fn)(kne_extension ext, kne_vm vm, const kne_value *value);
typedef int32_t (KNE_CALL *kne_vm_get_value_fn)(kne_extension ext, kne_vm vm, int32_t index, kne_value *out);
typedef void (KNE_CALL *kne_vm_push_stack_fn)(kne_vm vm, int32_t index);
typedef void (KNE_CALL *kne_vm_push_table_fn)(kne_vm vm);
typedef void (KNE_CALL *kne_vm_set_field_fn)(kne_vm vm, int32_t table_index, kne_string key);
typedef void (KNE_CALL *kne_vm_set_global_fn)(kne_extension ext, kne_vm vm, kne_string name);
typedef void (KNE_CALL *kne_vm_remove_fn)(kne_vm vm, int32_t index);
typedef int32_t (KNE_CALL *kne_vm_raise_fn)(kne_vm vm, kne_string message);
typedef int32_t (KNE_CALL *kne_vm_register_function_fn)(kne_extension ext, kne_string name, kne_vm_native_fn function);
typedef int32_t (KNE_CALL *kne_vm_register_library_function_fn)(kne_extension ext, kne_string library, kne_string name, kne_vm_native_fn function);
typedef int32_t (KNE_CALL *kne_vm_register_global_datatype_fn)(kne_extension ext, kne_vm vm, kne_string library);

typedef struct kne_vm_api {
	uint32_t size;
	uint32_t version;
	kne_vm_arg_count_fn arg_count;
	kne_vm_kind_fn kind;
	kne_vm_number_fn get_number;
	kne_vm_integer_fn get_integer;
	kne_vm_boolean_fn get_boolean;
	kne_vm_string_fn get_string;
	kne_vm_instance_fn get_instance;
	kne_vm_is_function_fn is_function;
	kne_vm_push_nil_fn push_nil;
	kne_vm_push_boolean_fn push_boolean;
	kne_vm_push_number_fn push_number;
	kne_vm_push_integer_fn push_integer;
	kne_vm_push_string_fn push_string;
	kne_vm_push_instance_fn push_instance;
	kne_vm_push_value_fn push_value;
	kne_vm_get_value_fn get_value;
	kne_vm_push_stack_fn push_stack;
	kne_vm_push_table_fn push_table;
	kne_vm_set_field_fn set_field;
	kne_vm_set_global_fn set_global;
	kne_vm_remove_fn remove;
	kne_vm_raise_fn raise;
	kne_vm_register_function_fn register_function;
	kne_vm_register_library_function_fn register_library_function;
	kne_vm_register_global_datatype_fn register_global_datatype;
} kne_vm_api;

#ifdef __cplusplus
}
#endif

#endif
