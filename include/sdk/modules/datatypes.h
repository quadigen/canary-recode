#ifndef KNE_MODULE_DATATYPES_H
#define KNE_MODULE_DATATYPES_H

#include "../kne_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KNE_DATATYPE_PERSISTABLE 0x1u
#define KNE_DATATYPE_REPLICATED 0x2u

typedef void (KNE_CALL *kne_push_vector2_fn)(kne_extension ext, kne_vm vm, kne_vector2 value);
typedef void (KNE_CALL *kne_push_vector3_fn)(kne_extension ext, kne_vm vm, kne_vector3 value);
typedef void (KNE_CALL *kne_push_cframe_fn)(kne_extension ext, kne_vm vm, kne_cframe value);
typedef void (KNE_CALL *kne_push_color3_fn)(kne_extension ext, kne_vm vm, kne_color3 value);
typedef kne_vector2 (KNE_CALL *kne_arg_vector2_fn)(kne_extension ext, kne_vm vm, int32_t index);
typedef kne_vector3 (KNE_CALL *kne_arg_vector3_fn)(kne_extension ext, kne_vm vm, int32_t index);
typedef kne_cframe (KNE_CALL *kne_arg_cframe_fn)(kne_extension ext, kne_vm vm, int32_t index);
typedef kne_color3 (KNE_CALL *kne_arg_color3_fn)(kne_extension ext, kne_vm vm, int32_t index);
typedef int32_t (KNE_CALL *kne_datatype_push_fn)(kne_extension ext, kne_vm vm, const kne_value *value);
typedef int32_t (KNE_CALL *kne_datatype_get_value_fn)(kne_extension ext, kne_vm vm, int32_t index, kne_value *out);

typedef int32_t (KNE_CALL *kne_datatype_construct_value_fn)(kne_extension ext, kne_string type_name, const kne_value *args, int32_t arg_count, kne_value *out);
typedef int32_t (KNE_CALL *kne_datatype_get_field_value_fn)(kne_extension ext, const kne_value *value, kne_string field, kne_value *out);
typedef int32_t (KNE_CALL *kne_datatype_set_field_value_fn)(kne_extension ext, const kne_value *value, kne_string field, const kne_value *in);
typedef int32_t (KNE_CALL *kne_datatype_call_value_fn)(kne_extension ext, const kne_value *value, kne_string method, const kne_value *args, int32_t arg_count, kne_value *out, int32_t out_capacity);

typedef int32_t (KNE_CALL *kne_ext_datatype_construct_fn)(kne_extension ext, void *ctx, const kne_value *args, int32_t arg_count);
typedef void (KNE_CALL *kne_ext_datatype_destroy_fn)(kne_extension ext, void *ctx);
typedef int32_t (KNE_CALL *kne_ext_datatype_get_fn)(kne_extension ext, void *ctx, kne_string key, kne_value *out);
typedef int32_t (KNE_CALL *kne_ext_datatype_set_fn)(kne_extension ext, void *ctx, kne_string key, const kne_value *value);
typedef int32_t (KNE_CALL *kne_ext_datatype_namecall_fn)(kne_extension ext, void *ctx, kne_string method, const kne_value *args, int32_t arg_count, kne_value *out, int32_t out_capacity);
typedef int32_t (KNE_CALL *kne_ext_datatype_tostring_fn)(kne_extension ext, void *ctx, kne_string *out);
typedef int32_t (KNE_CALL *kne_ext_datatype_equal_fn)(kne_extension ext, void *ctx, void *other, int32_t *out);
typedef int32_t (KNE_CALL *kne_ext_datatype_binary_fn)(kne_extension ext, void *ctx, void *other, kne_value *out);
typedef int32_t (KNE_CALL *kne_ext_datatype_negate_fn)(kne_extension ext, void *ctx, kne_value *out);
typedef int32_t (KNE_CALL *kne_ext_datatype_encode_fn)(kne_extension ext, void *ctx, void *buffer, size_t capacity, size_t *out_size);
typedef int32_t (KNE_CALL *kne_ext_datatype_decode_fn)(kne_extension ext, void *ctx, const void *data, size_t size);

typedef struct kne_datatype_desc {
	uint32_t size;
	uint32_t version;
	kne_string library;
	kne_string type_name;
	uint32_t flags;
	uint32_t value_size;
	uint32_t wire_version;
	uint32_t reserved;
	kne_ext_datatype_construct_fn construct;
	kne_ext_datatype_destroy_fn destroy;
	kne_ext_datatype_get_fn get;
	kne_ext_datatype_set_fn set;
	kne_ext_datatype_namecall_fn namecall;
	kne_ext_datatype_tostring_fn tostring;
	kne_ext_datatype_equal_fn equal;
	kne_ext_datatype_binary_fn add;
	kne_ext_datatype_binary_fn subtract;
	kne_ext_datatype_binary_fn multiply;
	kne_ext_datatype_binary_fn divide;
	kne_ext_datatype_negate_fn negate;
	kne_ext_datatype_encode_fn encode;
	kne_ext_datatype_decode_fn decode;
} kne_datatype_desc;

typedef int32_t (KNE_CALL *kne_register_datatype_fn)(kne_extension ext, const kne_datatype_desc *desc);
typedef int32_t (KNE_CALL *kne_unregister_datatype_fn)(kne_extension ext, kne_string type_name);
typedef int32_t (KNE_CALL *kne_datatype_registered_fn)(kne_extension ext, kne_string type_name);

typedef struct kne_datatypes_api {
	uint32_t size;
	uint32_t version;
	kne_push_vector2_fn push_vector2;
	kne_push_vector3_fn push_vector3;
	kne_push_cframe_fn push_cframe;
	kne_push_color3_fn push_color3;
	kne_arg_vector2_fn get_vector2;
	kne_arg_vector3_fn get_vector3;
	kne_arg_cframe_fn get_cframe;
	kne_arg_color3_fn get_color3;
	kne_datatype_push_fn push;
	kne_datatype_get_value_fn get;
	kne_datatype_construct_value_fn construct;
	kne_datatype_get_field_value_fn get_field;
	kne_datatype_set_field_value_fn set_field;
	kne_datatype_call_value_fn call;
	kne_register_datatype_fn register_datatype;
	kne_unregister_datatype_fn unregister_datatype;
	kne_datatype_registered_fn is_registered;
} kne_datatypes_api;

#ifdef __cplusplus
}
#endif

#endif
