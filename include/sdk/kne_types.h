#ifndef KNE_TYPES_H
#define KNE_TYPES_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define KNE_CALL __cdecl
#define KNE_EXPORT __declspec(dllexport)
#else
#define KNE_CALL
#define KNE_EXPORT __attribute__((visibility("default")))
#endif

typedef void *kne_extension;
typedef void *kne_instance;
typedef void *kne_vm;
typedef void *kne_callback;
typedef void *kne_signal;
typedef void *kne_connection;
typedef void *kne_datatype_handle;

typedef struct kne_string {
	const char *data;
	size_t length;
} kne_string;

typedef enum kne_log_level {
	KNE_LOG_TRACE = 0,
	KNE_LOG_DEBUG = 1,
	KNE_LOG_INFO = 2,
	KNE_LOG_WARN = 3,
	KNE_LOG_ERROR = 4
} kne_log_level;

typedef enum kne_value_kind {
	KNE_VALUE_NIL = 0,
	KNE_VALUE_BOOLEAN = 1,
	KNE_VALUE_NUMBER = 2,
	KNE_VALUE_INTEGER = 3,
	KNE_VALUE_STRING = 4,
	KNE_VALUE_INSTANCE = 5,
	KNE_VALUE_TABLE = 6,
	KNE_VALUE_FUNCTION = 7,

	KNE_VALUE_VECTOR2 = 20,
	KNE_VALUE_VECTOR3 = 21,
	KNE_VALUE_VECTOR2INT16 = 22,
	KNE_VALUE_VECTOR3INT16 = 23,
	KNE_VALUE_CFRAME = 24,
	KNE_VALUE_COLOR3 = 25,
	KNE_VALUE_UDIM = 26,
	KNE_VALUE_UDIM2 = 27,
	KNE_VALUE_RAY = 28,
	KNE_VALUE_RECT = 29,
	KNE_VALUE_REGION3 = 30,
	KNE_VALUE_REGION3INT16 = 31,
	KNE_VALUE_NUMBER_RANGE = 32,
	KNE_VALUE_NUMBER_SEQUENCE_KEYPOINT = 33,
	KNE_VALUE_COLOR_SEQUENCE_KEYPOINT = 34,
	KNE_VALUE_AXES = 35,
	KNE_VALUE_FACES = 36,
	KNE_VALUE_PHYSICAL_PROPERTIES = 37,
	KNE_VALUE_QUATERNION = 38,
	KNE_VALUE_TWEEN_INFO = 39,
	KNE_VALUE_DATE_TIME = 40,
	KNE_VALUE_UNIQUE_ID = 41,
	KNE_VALUE_PATH_WAYPOINT = 42,
	KNE_VALUE_SECURITY_CAPABILITIES = 43,
	KNE_VALUE_DOCK_WIDGET_PLUGIN_GUI_INFO = 44,

	/* Any datatype without a fixed struct, including extension datatypes. */
	KNE_VALUE_DATATYPE = 60,
	KNE_VALUE_CALLBACK = 61,
	KNE_VALUE_SIGNAL = 62
} kne_value_kind;

typedef struct kne_vector2 {
	float x, y;
} kne_vector2;

typedef struct kne_vector3 {
	float x, y, z;
} kne_vector3;

typedef struct kne_vector2int16 {
	int16_t x, y;
} kne_vector2int16;

typedef struct kne_vector3int16 {
	int16_t x, y, z;
} kne_vector3int16;

typedef struct kne_color3 {
	float r, g, b;
} kne_color3;

typedef struct kne_cframe {
	float x, y, z;
	float r00, r01, r02;
	float r10, r11, r12;
	float r20, r21, r22;
} kne_cframe;

typedef struct kne_udim {
	float scale, offset;
} kne_udim;

typedef struct kne_udim2 {
	float x_scale, x_offset;
	float y_scale, y_offset;
} kne_udim2;

typedef struct kne_ray {
	kne_vector3 origin;
	kne_vector3 direction;
} kne_ray;

typedef struct kne_rect {
	kne_vector2 min;
	kne_vector2 max;
} kne_rect;

typedef struct kne_region3 {
	kne_vector3 min;
	kne_vector3 max;
} kne_region3;

typedef struct kne_region3int16 {
	kne_vector3int16 min;
	kne_vector3int16 max;
} kne_region3int16;

typedef struct kne_number_range {
	float min, max;
} kne_number_range;

typedef struct kne_number_sequence_keypoint {
	float time, value, envelope;
} kne_number_sequence_keypoint;

typedef struct kne_color_sequence_keypoint {
	float time;
	kne_color3 value;
} kne_color_sequence_keypoint;

typedef struct kne_axes {
	uint8_t x, y, z;
} kne_axes;

typedef struct kne_faces {
	uint8_t top, bottom, left, right, front, back;
} kne_faces;

typedef struct kne_physical_properties {
	float density, friction, elasticity;
	float friction_weight, elasticity_weight;
} kne_physical_properties;

typedef struct kne_quaternion {
	float x, y, z, w;
} kne_quaternion;

typedef struct kne_tween_info {
	float time;
	intptr_t easing_style;
	intptr_t easing_direction;
	int32_t repeat_count;
	uint8_t reverses;
	float delay_time;
} kne_tween_info;

typedef struct kne_date_time {
	double unix_timestamp_millis;
} kne_date_time;

typedef struct kne_unique_id {
	int64_t random;
	uint32_t time;
	uint32_t index;
} kne_unique_id;

typedef struct kne_path_waypoint {
	kne_vector3 position;
	intptr_t action;
	kne_string label;
} kne_path_waypoint;

typedef struct kne_security_capabilities {
	uint64_t bits_low;
	uint64_t bits_high;
} kne_security_capabilities;

typedef struct kne_dock_widget_plugin_gui_info {
	intptr_t initial_dock_state;
	uint8_t initial_enabled;
	uint8_t override_enabled_restore;
	int32_t floating_x_size;
	int32_t floating_y_size;
	int32_t min_width;
	int32_t min_height;
} kne_dock_widget_plugin_gui_info;

/* A datatype without a fixed C layout. The handle is a live engine userdata
 * pointer and is only valid for the callback that produced it unless it was
 * retained by the extension's own datatype. `type_name` is host-owned and
 * NUL-terminated for the callback duration. */
typedef struct kne_datatype {
	kne_datatype_handle handle;
	kne_string type_name;
	uint32_t tag;
	uint32_t reserved;
	void *source_vm;
	int32_t source_index, source_reserved;
} kne_datatype;

/* Borrowed stack slot. Do not retain beyond the native callback. */
typedef struct kne_stack_value {
 void *vm;
 int32_t index, reserved;
} kne_stack_value;

typedef union kne_value_data {
 kne_stack_value stack;
	int32_t boolean;
	double number;
	int64_t integer;
	kne_string string;
	void *instance;
	kne_vector2 vector2;
	kne_vector3 vector3;
	kne_vector2int16 vector2int16;
	kne_vector3int16 vector3int16;
	kne_cframe cframe;
	kne_color3 color3;
	kne_udim udim;
	kne_udim2 udim2;
	kne_ray ray;
	kne_rect rect;
	kne_region3 region3;
	kne_region3int16 region3int16;
	kne_number_range number_range;
	kne_number_sequence_keypoint number_sequence_keypoint;
	kne_color_sequence_keypoint color_sequence_keypoint;
	kne_axes axes;
	kne_faces faces;
	kne_physical_properties physical_properties;
	kne_quaternion quaternion;
	kne_tween_info tween_info;
	kne_date_time date_time;
	kne_unique_id unique_id;
	kne_path_waypoint path_waypoint;
	kne_security_capabilities security_capabilities;
	kne_dock_widget_plugin_gui_info dock_widget_plugin_gui_info;
	kne_datatype datatype;
	kne_callback callback;
	kne_signal signal;
	uint64_t alignment;
} kne_value_data;

typedef struct kne_value {
	int32_t kind;
	int32_t reserved;
	kne_value_data data;
} kne_value;

#ifdef __cplusplus
}
#endif

#endif
