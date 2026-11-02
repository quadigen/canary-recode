package kne

import "core:strings"

ABI_MAJOR :: u32(2)
ABI_MINOR :: u32(0)
ENTRY_SYMBOL :: "kne_extension_entry"
// UNHANDLED is returned by a class namecall to decline a method; the host
// then runs the engine's own Instance behaviour for it.
UNHANDLED :: i32(-1)
CLASS_CREATABLE :: u32(1)
CLASS_SERVICE :: u32(1 << 1)
DATATYPE_PERSISTABLE :: u32(1)
DATATYPE_REPLICATED :: u32(1 << 1)

KNE_String :: struct {
	data:   cstring,
	length: uintptr,
}

KNE_Log_Level :: enum i32 {
	Trace = 0,
	Debug = 1,
	Info  = 2,
	Warn  = 3,
	Error = 4,
}

KNE_Value_Kind :: enum i32 {
	Nil      = 0,
	Boolean  = 1,
	Number   = 2,
	Integer  = 3,
	String   = 4,
	Instance = 5,
	Table    = 6,
	Function = 7,

	Vector2                      = 20,
	Vector3                      = 21,
	Vector2Int16                 = 22,
	Vector3Int16                 = 23,
	CFrame                       = 24,
	Color3                       = 25,
	UDim                         = 26,
	UDim2                        = 27,
	Ray                          = 28,
	Rect                         = 29,
	Region3                      = 30,
	Region3Int16                 = 31,
	NumberRange                  = 32,
	NumberSequenceKeypoint       = 33,
	ColorSequenceKeypoint        = 34,
	Axes                         = 35,
	Faces                        = 36,
	PhysicalProperties           = 37,
	Quaternion                   = 38,
	TweenInfo                    = 39,
	DateTime                     = 40,
	UniqueId                     = 41,
	PathWaypoint                 = 42,
	SecurityCapabilities         = 43,
	DockWidgetPluginGuiInfo      = 44,

	Datatype = 60,
	Callback = 61,
	Signal   = 62,
}

KNE_Vector2 :: struct {
	x, y: f32,
}

KNE_Vector3 :: struct {
	x, y, z: f32,
}

KNE_Vector2Int16 :: struct {
	x, y: i16,
}

KNE_Vector3Int16 :: struct {
	x, y, z: i16,
}

KNE_Color3 :: struct {
	r, g, b: f32,
}

KNE_CFrame :: struct {
	x, y, z:       f32,
	r00, r01, r02: f32,
	r10, r11, r12: f32,
	r20, r21, r22: f32,
}

KNE_UDim :: struct {
	scale, offset: f32,
}

KNE_UDim2 :: struct {
	x_scale, x_offset: f32,
	y_scale, y_offset: f32,
}

KNE_Ray :: struct {
	origin:    KNE_Vector3,
	direction: KNE_Vector3,
}

KNE_Rect :: struct {
	min: KNE_Vector2,
	max: KNE_Vector2,
}

KNE_Region3 :: struct {
	min: KNE_Vector3,
	max: KNE_Vector3,
}

KNE_Region3Int16 :: struct {
	min: KNE_Vector3Int16,
	max: KNE_Vector3Int16,
}

KNE_NumberRange :: struct {
	min, max: f32,
}

KNE_NumberSequenceKeypoint :: struct {
	time, value, envelope: f32,
}

KNE_ColorSequenceKeypoint :: struct {
	time:  f32,
	value: KNE_Color3,
}

KNE_Axes :: struct {
	x, y, z: u8,
}

KNE_Faces :: struct {
	top, bottom, left, right, front, back: u8,
}

KNE_PhysicalProperties :: struct {
	density, friction, elasticity:      f32,
	friction_weight, elasticity_weight: f32,
}

KNE_Quaternion :: struct {
	x, y, z, w: f32,
}

KNE_TweenInfo :: struct {
	time:            f32,
	easing_style:    int,
	easing_direction: int,
	repeat_count:    i32,
	reverses:        u8,
	delay_time:      f32,
}

KNE_DateTime :: struct {
	unix_timestamp_millis: f64,
}

KNE_UniqueId :: struct {
	random: i64,
	time:   u32,
	index:  u32,
}

KNE_PathWaypoint :: struct {
	position: KNE_Vector3,
	action:   int,
	label:    KNE_String,
}

KNE_SecurityCapabilities :: struct {
	bits_low:  u64,
	bits_high: u64,
}

KNE_DockWidgetPluginGuiInfo :: struct {
	initial_dock_state:      int,
	initial_enabled:         u8,
	override_enabled_restore: u8,
	floating_x_size:         i32,
	floating_y_size:         i32,
	min_width:               i32,
	min_height:              i32,
}

KNE_Datatype :: struct {
	handle:    rawptr,
	type_name: KNE_String,
	tag:       u32,
	reserved:  u32,
	source_vm: rawptr,
	source_index: i32,
	source_reserved: i32,
}

// Borrowed VM stack slot, valid during the native callback that produced it.
KNE_Stack_Value :: struct {
 vm: rawptr,
 index: i32,
 reserved: i32,
}

KNE_Value_Data :: struct #raw_union {
 stack: KNE_Stack_Value,
	boolean:                  i32,
	number:                   f64,
	integer:                  i64,
	string:                   KNE_String,
	instance:                 rawptr,
	vector2:                  KNE_Vector2,
	vector3:                  KNE_Vector3,
	vector2int16:             KNE_Vector2Int16,
	vector3int16:             KNE_Vector3Int16,
	cframe:                   KNE_CFrame,
	color3:                   KNE_Color3,
	udim:                     KNE_UDim,
	udim2:                    KNE_UDim2,
	ray:                      KNE_Ray,
	rect:                     KNE_Rect,
	region3:                  KNE_Region3,
	region3int16:             KNE_Region3Int16,
	number_range:             KNE_NumberRange,
	number_sequence_keypoint: KNE_NumberSequenceKeypoint,
	color_sequence_keypoint:  KNE_ColorSequenceKeypoint,
	axes:                     KNE_Axes,
	faces:                    KNE_Faces,
	physical_properties:      KNE_PhysicalProperties,
	quaternion:               KNE_Quaternion,
	tween_info:               KNE_TweenInfo,
	date_time:                KNE_DateTime,
	unique_id:                KNE_UniqueId,
	path_waypoint:            KNE_PathWaypoint,
	security_capabilities:    KNE_SecurityCapabilities,
	dock_widget_plugin_gui_info: KNE_DockWidgetPluginGuiInfo,
	datatype:                 KNE_Datatype,
	callback:                 rawptr,
	signal:                   rawptr,
	alignment:                u64,
}

KNE_Value :: struct {
	kind:     KNE_Value_Kind,
	reserved: i32,
	data:     KNE_Value_Data,
}

KNE_Extension :: rawptr
KNE_Instance :: rawptr
KNE_VM :: rawptr
KNE_Callback :: rawptr
KNE_Signal :: rawptr
KNE_Connection :: rawptr

KNE_Log_Fn :: proc "c" (ext: KNE_Extension, level: KNE_Log_Level, message: KNE_String)
KNE_Alloc_Fn :: proc "c" (ext: KNE_Extension, size: uintptr) -> rawptr
KNE_Realloc_Fn :: proc "c" (ext: KNE_Extension, ptr: rawptr, size: uintptr) -> rawptr
KNE_Free_Fn :: proc "c" (ext: KNE_Extension, ptr: rawptr)
KNE_Last_Error_Fn :: proc "c" (ext: KNE_Extension) -> KNE_String

KNE_Core_Api :: struct {
	size:           u32,
	version:        u32,
	log:            KNE_Log_Fn,
	allocate:       KNE_Alloc_Fn,
	reallocate:     KNE_Realloc_Fn,
	release:        KNE_Free_Fn,
	last_error:     KNE_Last_Error_Fn,
	engine_version: KNE_String,
	abi_major:      u32,
	abi_minor:      u32,
}

KNE_Get_Service_Fn :: proc "c" (ext: KNE_Extension, name: KNE_String) -> KNE_Instance
KNE_Service_Exists_Fn :: proc "c" (ext: KNE_Extension, name: KNE_String) -> i32
KNE_Service_Count_Fn :: proc "c" (ext: KNE_Extension) -> uintptr
KNE_Service_Name_At_Fn :: proc "c" (ext: KNE_Extension, index: uintptr) -> KNE_String

KNE_Services_Api :: struct {
	size:    u32,
	version: u32,
	get:     KNE_Get_Service_Fn,
	exists:  KNE_Service_Exists_Fn,
	count:   KNE_Service_Count_Fn,
	name_at: KNE_Service_Name_At_Fn,
}

KNE_Class_Construct_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance)
KNE_Class_Get_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, key: KNE_String, out: ^KNE_Value) -> i32
KNE_Class_Set_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, key: KNE_String, value: ^KNE_Value) -> i32
KNE_Class_Namecall_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, method: KNE_String, L: KNE_VM, arg_count: i32) -> i32
KNE_Class_Step_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, delta_time: f64)

KNE_Class_Desc :: struct {
	size:         u32,
	version:      u32,
	name:         KNE_String,
	base:         KNE_String,
	flags:        u32,
	reserved:     u32,
	properties:   KNE_String,
	methods:      KNE_String,
	events:       KNE_String,
	on_construct: KNE_Class_Construct_Fn,
	on_destroy:   KNE_Class_Construct_Fn,
	get:          KNE_Class_Get_Fn,
	set:          KNE_Class_Set_Fn,
	namecall:     KNE_Class_Namecall_Fn,
	step:         KNE_Class_Step_Fn,
}

KNE_Register_Class_Fn :: proc "c" (ext: KNE_Extension, desc: ^KNE_Class_Desc) -> i32
KNE_Is_Class_Registered_Fn :: proc "c" (ext: KNE_Extension, name: KNE_String) -> i32

KNE_Classes_Api :: struct {
	size:          u32,
	version:       u32,
	register:      KNE_Register_Class_Fn,
	is_registered: KNE_Is_Class_Registered_Fn,
}

KNE_Create_Instance_Fn :: proc "c" (ext: KNE_Extension, class_name: KNE_String) -> KNE_Instance
KNE_Destroy_Instance_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance)
KNE_Instance_Name_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance) -> KNE_String
KNE_Instance_Set_Name_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, name: KNE_String)
KNE_Instance_Parent_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance) -> KNE_Instance
KNE_Instance_Set_Parent_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, parent: KNE_Instance)
KNE_Instance_Child_Count_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance) -> uintptr
KNE_Instance_Child_At_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, index: uintptr) -> KNE_Instance
KNE_Instance_Find_Child_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, name: KNE_String) -> KNE_Instance
KNE_Instance_Is_A_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, class_name: KNE_String) -> i32
KNE_Instance_Class_Name_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance) -> KNE_String
KNE_Instance_Get_Property_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, key: KNE_String, out: ^KNE_Value) -> i32
KNE_Instance_Set_Property_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, key: KNE_String, value: ^KNE_Value) -> i32
KNE_Instance_Get_User_Data_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance) -> rawptr
KNE_Instance_Set_User_Data_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, data: rawptr)
KNE_Instance_Invoke_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, method: KNE_String, args: ^KNE_Value, arg_count: i32, out: ^KNE_Value, out_capacity: i32) -> i32

KNE_Instances_Api :: struct {
	size:          u32,
	version:       u32,
	create:        KNE_Create_Instance_Fn,
	destroy:       KNE_Destroy_Instance_Fn,
	get_name:      KNE_Instance_Name_Fn,
	set_name:      KNE_Instance_Set_Name_Fn,
	get_parent:    KNE_Instance_Parent_Fn,
	set_parent:    KNE_Instance_Set_Parent_Fn,
	child_count:   KNE_Instance_Child_Count_Fn,
	child_at:      KNE_Instance_Child_At_Fn,
	find_child:    KNE_Instance_Find_Child_Fn,
	is_a:          KNE_Instance_Is_A_Fn,
	class_name:    KNE_Instance_Class_Name_Fn,
	get_property:  KNE_Instance_Get_Property_Fn,
	set_property:  KNE_Instance_Set_Property_Fn,
	get_user_data: KNE_Instance_Get_User_Data_Fn,
	set_user_data: KNE_Instance_Set_User_Data_Fn,
	invoke:        KNE_Instance_Invoke_Fn,
}

KNE_VM_Native_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM) -> i32

KNE_VM_Arg_Count_Fn :: proc "c" (L: KNE_VM) -> i32
KNE_VM_Kind_Fn :: proc "c" (L: KNE_VM, index: i32) -> KNE_Value_Kind
KNE_VM_Number_Fn :: proc "c" (L: KNE_VM, index: i32) -> f64
KNE_VM_Integer_Fn :: proc "c" (L: KNE_VM, index: i32) -> i64
KNE_VM_Boolean_Fn :: proc "c" (L: KNE_VM, index: i32) -> i32
KNE_VM_String_Fn :: proc "c" (L: KNE_VM, index: i32) -> KNE_String
KNE_VM_Instance_Fn :: proc "c" (L: KNE_VM, index: i32) -> KNE_Instance
KNE_VM_Is_Function_Fn :: proc "c" (L: KNE_VM, index: i32) -> i32
KNE_VM_Push_Nil_Fn :: proc "c" (L: KNE_VM)
KNE_VM_Push_Boolean_Fn :: proc "c" (L: KNE_VM, value: i32)
KNE_VM_Push_Number_Fn :: proc "c" (L: KNE_VM, value: f64)
KNE_VM_Push_Integer_Fn :: proc "c" (L: KNE_VM, value: i64)
KNE_VM_Push_String_Fn :: proc "c" (L: KNE_VM, value: KNE_String)
KNE_VM_Push_Instance_Fn :: proc "c" (L: KNE_VM, instance: KNE_Instance)
KNE_VM_Push_Value_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, value: ^KNE_Value)
KNE_VM_Get_Value_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32, out: ^KNE_Value) -> i32
KNE_VM_Push_Stack_Fn :: proc "c" (L: KNE_VM, index: i32)
KNE_VM_Push_Table_Fn :: proc "c" (L: KNE_VM)
KNE_VM_Set_Field_Fn :: proc "c" (L: KNE_VM, table_index: i32, key: KNE_String)
KNE_VM_Set_Global_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, name: KNE_String)
KNE_VM_Remove_Fn :: proc "c" (L: KNE_VM, index: i32)
KNE_VM_Raise_Fn :: proc "c" (L: KNE_VM, message: KNE_String) -> i32
KNE_VM_Register_Function_Fn :: proc "c" (ext: KNE_Extension, name: KNE_String, function: KNE_VM_Native_Fn) -> i32
KNE_VM_Register_Library_Function_Fn :: proc "c" (ext: KNE_Extension, library: KNE_String, name: KNE_String, function: KNE_VM_Native_Fn) -> i32
KNE_VM_Register_Global_Datatype_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, library: KNE_String) -> i32

KNE_VM_Api :: struct {
	size:                      u32,
	version:                   u32,
	arg_count:                 KNE_VM_Arg_Count_Fn,
	kind:                      KNE_VM_Kind_Fn,
	get_number:                KNE_VM_Number_Fn,
	get_integer:               KNE_VM_Integer_Fn,
	get_boolean:               KNE_VM_Boolean_Fn,
	get_string:                KNE_VM_String_Fn,
	get_instance:              KNE_VM_Instance_Fn,
	is_function:               KNE_VM_Is_Function_Fn,
	push_nil:                  KNE_VM_Push_Nil_Fn,
	push_boolean:              KNE_VM_Push_Boolean_Fn,
	push_number:               KNE_VM_Push_Number_Fn,
	push_integer:              KNE_VM_Push_Integer_Fn,
	push_string:               KNE_VM_Push_String_Fn,
	push_instance:             KNE_VM_Push_Instance_Fn,
	push_value:                KNE_VM_Push_Value_Fn,
	get_value:                 KNE_VM_Get_Value_Fn,
	push_stack:                KNE_VM_Push_Stack_Fn,
	push_table:                KNE_VM_Push_Table_Fn,
	set_field:                 KNE_VM_Set_Field_Fn,
	set_global:                KNE_VM_Set_Global_Fn,
	remove:                    KNE_VM_Remove_Fn,
	raise:                     KNE_VM_Raise_Fn,
	register_function:         KNE_VM_Register_Function_Fn,
	register_library_function: KNE_VM_Register_Library_Function_Fn,
	register_global_datatype:  KNE_VM_Register_Global_Datatype_Fn,
}

KNE_Push_Vector2_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, value: KNE_Vector2)
KNE_Push_Vector3_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, value: KNE_Vector3)
KNE_Push_CFrame_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, value: KNE_CFrame)
KNE_Push_Color3_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, value: KNE_Color3)
KNE_Arg_Vector2_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32) -> KNE_Vector2
KNE_Arg_Vector3_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32) -> KNE_Vector3
KNE_Arg_CFrame_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32) -> KNE_CFrame
KNE_Arg_Color3_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32) -> KNE_Color3

KNE_Datatype_Push_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, value: ^KNE_Value) -> i32
KNE_Datatype_Get_Value_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32, out: ^KNE_Value) -> i32
KNE_Datatype_Construct_Value_Fn :: proc "c" (ext: KNE_Extension, type_name: KNE_String, args: ^KNE_Value, arg_count: i32, out: ^KNE_Value) -> i32
KNE_Datatype_Get_Field_Value_Fn :: proc "c" (ext: KNE_Extension, value: ^KNE_Value, field: KNE_String, out: ^KNE_Value) -> i32
KNE_Datatype_Set_Field_Value_Fn :: proc "c" (ext: KNE_Extension, value: ^KNE_Value, field: KNE_String, input: ^KNE_Value) -> i32
KNE_Datatype_Call_Value_Fn :: proc "c" (ext: KNE_Extension, value: ^KNE_Value, method: KNE_String, args: ^KNE_Value, arg_count: i32, out: ^KNE_Value, out_capacity: i32) -> i32

KNE_Ext_Datatype_Construct_Fn :: proc "c" (ext: KNE_Extension, ctx: rawptr, args: ^KNE_Value, arg_count: i32) -> i32
KNE_Ext_Datatype_Destroy_Fn :: proc "c" (ext: KNE_Extension, ctx: rawptr)
KNE_Ext_Datatype_Get_Fn :: proc "c" (ext: KNE_Extension, ctx: rawptr, key: KNE_String, out: ^KNE_Value) -> i32
KNE_Ext_Datatype_Set_Fn :: proc "c" (ext: KNE_Extension, ctx: rawptr, key: KNE_String, value: ^KNE_Value) -> i32
KNE_Ext_Datatype_Namecall_Fn :: proc "c" (ext: KNE_Extension, ctx: rawptr, method: KNE_String, args: ^KNE_Value, arg_count: i32, out: ^KNE_Value, out_capacity: i32) -> i32
KNE_Ext_Datatype_ToString_Fn :: proc "c" (ext: KNE_Extension, ctx: rawptr, out: ^KNE_String) -> i32
KNE_Ext_Datatype_Equal_Fn :: proc "c" (ext: KNE_Extension, ctx: rawptr, other: rawptr, out: ^i32) -> i32
KNE_Ext_Datatype_Binary_Fn :: proc "c" (ext: KNE_Extension, ctx: rawptr, other: rawptr, out: ^KNE_Value) -> i32
KNE_Ext_Datatype_Negate_Fn :: proc "c" (ext: KNE_Extension, ctx: rawptr, out: ^KNE_Value) -> i32
KNE_Ext_Datatype_Encode_Fn :: proc "c" (ext: KNE_Extension, ctx: rawptr, buffer: rawptr, capacity: uintptr, out_size: ^uintptr) -> i32
KNE_Ext_Datatype_Decode_Fn :: proc "c" (ext: KNE_Extension, ctx: rawptr, data: rawptr, size: uintptr) -> i32

KNE_Datatype_Desc :: struct {
	size:          u32,
	version:       u32,
	library:       KNE_String,
	type_name:     KNE_String,
	flags:         u32,
	value_size:    u32,
	wire_version:  u32,
	reserved:      u32,
	construct:     KNE_Ext_Datatype_Construct_Fn,
	destroy:       KNE_Ext_Datatype_Destroy_Fn,
	get:           KNE_Ext_Datatype_Get_Fn,
	set:           KNE_Ext_Datatype_Set_Fn,
	namecall:      KNE_Ext_Datatype_Namecall_Fn,
	tostring:      KNE_Ext_Datatype_ToString_Fn,
	equal:         KNE_Ext_Datatype_Equal_Fn,
	add:           KNE_Ext_Datatype_Binary_Fn,
	subtract:      KNE_Ext_Datatype_Binary_Fn,
	multiply:      KNE_Ext_Datatype_Binary_Fn,
	divide:        KNE_Ext_Datatype_Binary_Fn,
	negate:        KNE_Ext_Datatype_Negate_Fn,
	encode:        KNE_Ext_Datatype_Encode_Fn,
	decode:        KNE_Ext_Datatype_Decode_Fn,
}

KNE_Register_Datatype_Fn :: proc "c" (ext: KNE_Extension, desc: ^KNE_Datatype_Desc) -> i32
KNE_Unregister_Datatype_Fn :: proc "c" (ext: KNE_Extension, type_name: KNE_String) -> i32
KNE_Datatype_Registered_Fn :: proc "c" (ext: KNE_Extension, type_name: KNE_String) -> i32

KNE_Datatypes_Api :: struct {
	size:               u32,
	version:            u32,
	push_vector2:       KNE_Push_Vector2_Fn,
	push_vector3:       KNE_Push_Vector3_Fn,
	push_cframe:        KNE_Push_CFrame_Fn,
	push_color3:        KNE_Push_Color3_Fn,
	get_vector2:        KNE_Arg_Vector2_Fn,
	get_vector3:        KNE_Arg_Vector3_Fn,
	get_cframe:         KNE_Arg_CFrame_Fn,
	get_color3:         KNE_Arg_Color3_Fn,
	push:               KNE_Datatype_Push_Fn,
	get:                KNE_Datatype_Get_Value_Fn,
	construct:          KNE_Datatype_Construct_Value_Fn,
	get_field:          KNE_Datatype_Get_Field_Value_Fn,
	set_field:          KNE_Datatype_Set_Field_Value_Fn,
	call:               KNE_Datatype_Call_Value_Fn,
	register_datatype:  KNE_Register_Datatype_Fn,
	unregister_datatype: KNE_Unregister_Datatype_Fn,
	is_registered:      KNE_Datatype_Registered_Fn,
}

KNE_Callbacks_Retain_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32) -> KNE_Callback
KNE_Callbacks_Release_Fn :: proc "c" (ext: KNE_Extension, callback: KNE_Callback)
KNE_Callbacks_Valid_Fn :: proc "c" (ext: KNE_Extension, callback: KNE_Callback) -> i32
KNE_Callbacks_Call_Fn :: proc "c" (ext: KNE_Extension, callback: KNE_Callback, args: ^KNE_Value, arg_count: i32, out: ^KNE_Value, out_capacity: i32) -> i32

KNE_Callbacks_Api :: struct {
	size:     u32,
	version:  u32,
	retain:   KNE_Callbacks_Retain_Fn,
	release:  KNE_Callbacks_Release_Fn,
	is_valid: KNE_Callbacks_Valid_Fn,
	call:     KNE_Callbacks_Call_Fn,
}

KNE_Signal_Native_Fn :: proc "c" (ext: KNE_Extension, L: KNE_VM)
KNE_Get_Signal_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, property: KNE_String) -> KNE_Signal
KNE_Signal_Connect_Native_Fn :: proc "c" (ext: KNE_Extension, signal: KNE_Signal, callback: KNE_Signal_Native_Fn) -> KNE_Connection
KNE_Signal_Connect_Callback_Fn :: proc "c" (ext: KNE_Extension, signal: KNE_Signal, callback: KNE_Callback) -> KNE_Connection
KNE_Signal_Once_Native_Fn :: proc "c" (ext: KNE_Extension, signal: KNE_Signal, callback: KNE_Signal_Native_Fn) -> KNE_Connection
KNE_Signal_Once_Callback_Fn :: proc "c" (ext: KNE_Extension, signal: KNE_Signal, callback: KNE_Callback) -> KNE_Connection
KNE_Signal_Disconnect_Fn :: proc "c" (ext: KNE_Extension, connection: KNE_Connection)
KNE_Signal_Fire_Fn :: proc "c" (ext: KNE_Extension, signal: KNE_Signal, args: ^KNE_Value, arg_count: i32) -> i32
KNE_Signal_Connected_Fn :: proc "c" (ext: KNE_Extension, connection: KNE_Connection) -> i32

KNE_Signals_Api :: struct {
	size:             u32,
	version:          u32,
	get:              KNE_Get_Signal_Fn,
	connect_native:   KNE_Signal_Connect_Native_Fn,
	connect_callback: KNE_Signal_Connect_Callback_Fn,
	once_native:      KNE_Signal_Once_Native_Fn,
	once_callback:    KNE_Signal_Once_Callback_Fn,
	disconnect:       KNE_Signal_Disconnect_Fn,
	fire:             KNE_Signal_Fire_Fn,
	is_connected:     KNE_Signal_Connected_Fn,
}

KNE_Export_Exists_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, method: KNE_String) -> i32
KNE_Export_Call_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, method: KNE_String, args: ^KNE_Value, arg_count: i32, out: ^KNE_Value, out_capacity: i32) -> i32
KNE_Export_Count_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance) -> uintptr
KNE_Export_Name_At_Fn :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, index: uintptr) -> KNE_String

KNE_Exports_Api :: struct {
	size:    u32,
	version: u32,
	exists:  KNE_Export_Exists_Fn,
	call:    KNE_Export_Call_Fn,
	count:   KNE_Export_Count_Fn,
	name_at: KNE_Export_Name_At_Fn,
}

KNE_Host :: struct {
	size:           u32,
	abi_major:      u32,
	abi_minor:      u32,
	reserved:       u32,
	engine_name:    KNE_String,
	engine_version: KNE_String,
	core:           ^KNE_Core_Api,
	services:       ^KNE_Services_Api,
	classes:        ^KNE_Classes_Api,
	instances:      ^KNE_Instances_Api,
	vm:             ^KNE_VM_Api,
	datatypes:      ^KNE_Datatypes_Api,
	callbacks:      ^KNE_Callbacks_Api,
	signals:        ^KNE_Signals_Api,
	exports:        ^KNE_Exports_Api,
}

KNE_Extension_Load_Fn :: proc "c" (ext: KNE_Extension) -> i32
KNE_Extension_Start_Fn :: proc "c" (ext: KNE_Extension) -> i32
KNE_Extension_Stop_Fn :: proc "c" (ext: KNE_Extension)
KNE_Extension_Unload_Fn :: proc "c" (ext: KNE_Extension)
KNE_Extension_Update_Fn :: proc "c" (ext: KNE_Extension, delta_time: f64)

KNE_Extension_Desc :: struct {
	size:      u32,
	abi_major: u32,
	abi_minor: u32,
	flags:     u32,
	id:        KNE_String,
	name:      KNE_String,
	version:   KNE_String,
	author:    KNE_String,
	on_load:   KNE_Extension_Load_Fn,
	on_start:  KNE_Extension_Start_Fn,
	on_stop:   KNE_Extension_Stop_Fn,
	on_unload: KNE_Extension_Unload_Fn,
	on_update: KNE_Extension_Update_Fn,
}

KNE_Entry_Fn :: proc "c" (host: ^KNE_Host) -> ^KNE_Extension_Desc

str :: proc (value: string) -> KNE_String {
	if len(value) == 0 {
		return KNE_String{data = cstring(""), length = 0}
	}
	return KNE_String{data = cstring(raw_data(value)), length = uintptr(len(value))}
}

string_from :: proc (value: string) -> KNE_String {
	return str(value)
}

string_to :: proc (value: KNE_String) -> string {
	if value.data == nil {
		return ""
	}
	if value.length == 0 {
		return string(value.data)
	}
	return strings.string_from_ptr(cast(^u8)value.data, int(value.length))
}

string_clone :: proc (value: string) -> string {
	return strings.clone(value)
}

