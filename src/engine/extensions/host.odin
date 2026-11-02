package extensions


import classes "../classes"
import datatypes "../datatypes"
import debuglog "../debuglog"
import enums "../enum"
import globals "../global"
import services "../services"
import signals "../signals"
import vm "../vm"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"


KNE_ALLOC_HEADER :: 16

Native_Function_Closure :: struct {
	record:   ^Extension_Record,
	function: KNE_VM_Native_Fn,
}

Host_State :: struct {
	ctx:            ^Context,
	host:           KNE_Host,
	core:           KNE_Core_Api,
	services:       KNE_Services_Api,
	classes:        KNE_Classes_Api,
	instances:      KNE_Instances_Api,
	vm:             KNE_VM_Api,
	datatypes:      KNE_Datatypes_Api,
	callbacks:      KNE_Callbacks_Api,
	signals:        KNE_Signals_Api,
	exports:        KNE_Exports_Api,
	engine_name:    cstring,
	engine_version: cstring,
}

host_state_create :: proc(ctx: ^Context) -> ^Host_State {
	host := new(Host_State)
	host.ctx = ctx
	host.engine_name = strings.clone_to_cstring(globals.RUNTIME_NAME)
	host.engine_version = strings.clone_to_cstring(globals.RUNTIME_VERSION_DISPLAY)

	host.core = KNE_Core_Api {
		size = u32(size_of(KNE_Core_Api)),
		version = KNE_ABI_MAJOR,
		log = kne_core_log,
		allocate = kne_core_allocate,
		reallocate = kne_core_reallocate,
		release = kne_core_release,
		last_error = kne_core_last_error,
		engine_version = KNE_String {
			data = host.engine_version,
			length = uintptr(len(globals.RUNTIME_VERSION_DISPLAY)),
		},
		abi_major = KNE_ABI_MAJOR,
		abi_minor = KNE_ABI_MINOR,
	}

	host.services = KNE_Services_Api {
		size    = u32(size_of(KNE_Services_Api)),
		version = KNE_ABI_MAJOR,
		get     = kne_services_get,
		exists  = kne_services_exists,
		count   = kne_services_count,
		name_at = kne_services_name_at,
	}

	host.classes = KNE_Classes_Api {
		size          = u32(size_of(KNE_Classes_Api)),
		version       = KNE_ABI_MAJOR,
		register      = kne_classes_register,
		is_registered = kne_classes_is_registered,
	}

	host.instances = KNE_Instances_Api {
		size          = u32(size_of(KNE_Instances_Api)),
		version       = KNE_ABI_MAJOR,
		create        = kne_instances_create,
		destroy       = kne_instances_destroy,
		get_name      = kne_instances_get_name,
		set_name      = kne_instances_set_name,
		get_parent    = kne_instances_get_parent,
		set_parent    = kne_instances_set_parent,
		child_count   = kne_instances_child_count,
		child_at      = kne_instances_child_at,
		find_child    = kne_instances_find_child,
		is_a          = kne_instances_is_a,
		class_name    = kne_instances_class_name,
		get_property  = kne_instances_get_property,
		set_property  = kne_instances_set_property,
		get_user_data = kne_instances_get_user_data,
		set_user_data = kne_instances_set_user_data,
		invoke        = kne_instance_invoke,
	}

	host.vm = KNE_VM_Api {
		size                      = u32(size_of(KNE_VM_Api)),
		version                   = KNE_ABI_MAJOR,
		arg_count                 = kne_vm_arg_count,
		kind                      = kne_vm_kind,
		get_number                = kne_vm_get_number,
		get_integer               = kne_vm_get_integer,
		get_boolean               = kne_vm_get_boolean,
		get_string                = kne_vm_get_string,
		get_instance              = kne_vm_get_instance,
		is_function               = kne_vm_is_function,
		push_nil                  = kne_vm_push_nil,
		push_boolean              = kne_vm_push_boolean,
		push_number               = kne_vm_push_number,
		push_integer              = kne_vm_push_integer,
		push_string               = kne_vm_push_string,
		push_instance             = kne_vm_push_instance,
		push_value                = kne_vm_push_value,
		get_value                 = kne_vm_get_value,
		push_stack                = kne_vm_push_stack,
		push_table                = kne_vm_push_table,
		set_field                 = kne_vm_set_field,
		set_global                = kne_vm_set_global,
		remove                    = kne_vm_remove,
		raise                     = kne_vm_raise,
		register_function         = kne_vm_register_function,
		register_library_function = kne_vm_register_library_function,
		register_global_datatype  = kne_vm_register_global_datatype,
	}

	host.datatypes = KNE_Datatypes_Api {
		size                = u32(size_of(KNE_Datatypes_Api)),
		version             = KNE_ABI_MAJOR,
		push_vector2        = kne_datatypes_push_vector2,
		push_vector3        = kne_datatypes_push_vector3,
		push_cframe         = kne_datatypes_push_cframe,
		push_color3         = kne_datatypes_push_color3,
		get_vector2         = kne_datatypes_get_vector2,
		get_vector3         = kne_datatypes_get_vector3,
		get_cframe          = kne_datatypes_get_cframe,
		get_color3          = kne_datatypes_get_color3,
		push                = kne_datatypes_push,
		get                 = kne_datatypes_get,
		construct           = kne_datatypes_construct,
		get_field           = kne_datatypes_get_field,
		set_field           = kne_datatypes_set_field,
		call                = kne_datatypes_call,
		register_datatype   = kne_register_datatype,
		unregister_datatype = kne_unregister_datatype,
		is_registered       = kne_datatype_registered,
	}

	host.callbacks = KNE_Callbacks_Api {
		size     = u32(size_of(KNE_Callbacks_Api)),
		version  = KNE_ABI_MAJOR,
		retain   = kne_callbacks_retain,
		release  = kne_callbacks_release,
		is_valid = kne_callbacks_valid,
		call     = kne_callbacks_call,
	}

	host.signals = KNE_Signals_Api {
		size             = u32(size_of(KNE_Signals_Api)),
		version          = KNE_ABI_MAJOR,
		get              = kne_signal_get,
		connect_native   = kne_signal_connect_native,
		connect_callback = kne_signal_connect_callback,
		once_native      = kne_signal_once_native,
		once_callback    = kne_signal_once_callback,
		disconnect       = kne_signal_disconnect,
		fire             = kne_signal_fire,
		is_connected     = kne_signal_connected,
	}

	host.exports = KNE_Exports_Api {
		size    = u32(size_of(KNE_Exports_Api)),
		version = KNE_ABI_MAJOR,
		exists  = kne_export_exists,
		call    = kne_export_call,
		count   = kne_export_count,
		name_at = kne_export_name_at,
	}

	host.host = KNE_Host {
		size = u32(size_of(KNE_Host)),
		abi_major = KNE_ABI_MAJOR,
		abi_minor = KNE_ABI_MINOR,
		engine_name = KNE_String {
			data = host.engine_name,
			length = uintptr(len(globals.RUNTIME_NAME)),
		},
		engine_version = KNE_String {
			data = host.engine_version,
			length = uintptr(len(globals.RUNTIME_VERSION_DISPLAY)),
		},
		core = &host.core,
		services = &host.services,
		classes = &host.classes,
		instances = &host.instances,
		vm = &host.vm,
		datatypes = &host.datatypes,
		callbacks = &host.callbacks,
		signals = &host.signals,
		exports = &host.exports,
	}

	return host
}

host_state_destroy :: proc(host: ^Host_State) {
	if host == nil {
		return
	}
	delete(host.engine_name)
	delete(host.engine_version)
	free(host)
}

@(private)
record_of :: proc(ext: KNE_Extension) -> ^Extension_Record {
	return cast(^Extension_Record)ext
}

@(private)
context_of :: proc(ext: KNE_Extension) -> ^Context {
	record := record_of(ext)
	if record == nil {
		return nil
	}
	return record.ctx
}


@(private)
kne_value_nil :: proc() -> KNE_Value {
	value: KNE_Value
	value.kind = .Nil
	return value
}

@(private)
kne_cframe_from :: proc(frame: datatypes.CFrame) -> KNE_CFrame {
	return KNE_CFrame {
		x = frame.x,
		y = frame.y,
		z = frame.z,
		r00 = frame.r00,
		r01 = frame.r01,
		r02 = frame.r02,
		r10 = frame.r10,
		r11 = frame.r11,
		r12 = frame.r12,
		r20 = frame.r20,
		r21 = frame.r21,
		r22 = frame.r22,
	}
}

@(private)
kne_cframe_to :: proc(frame: KNE_CFrame) -> datatypes.CFrame {
	return datatypes.CFrame {
		x = frame.x,
		y = frame.y,
		z = frame.z,
		r00 = frame.r00,
		r01 = frame.r01,
		r02 = frame.r02,
		r10 = frame.r10,
		r11 = frame.r11,
		r12 = frame.r12,
		r20 = frame.r20,
		r21 = frame.r21,
		r22 = frame.r22,
	}
}


@(private)
push_kne_value :: proc(L: ^vm.State, registry: ^datatypes.Registry, value: ^KNE_Value) {
	if L == nil || value == nil {
		return
	}

	switch value.kind {
	case .Nil:
		vm.PushNil(L)
	case .Boolean:
		vm.PushBoolean(L, value.data.boolean != 0)
	case .Number:
		vm.PushNumber(L, value.data.number)
	case .Integer:
		vm.PushNumber(L, f64(value.data.integer))
	case .String:
		vm.PushString(L, KNE_String_To(value.data.string))
	case .Instance:
		classes.Push_Object(L, cast(^classes.Object)value.data.instance)
	case .Vector2,
	     .Vector3,
	     .Vector2Int16,
	     .Vector3Int16,
	     .CFrame,
	     .Color3,
	     .UDim,
	     .UDim2,
	     .Ray,
	     .Rect,
	     .Region3,
	     .Region3Int16,
	     .NumberRange,
	     .NumberSequenceKeypoint,
	     .ColorSequenceKeypoint,
	     .Axes,
	     .Faces,
	     .PhysicalProperties,
	     .Quaternion,
	     .TweenInfo,
	     .DateTime,
	     .UniqueId,
	     .PathWaypoint,
	     .SecurityCapabilities,
	     .DockWidgetPluginGuiInfo:
		if !kne_push_engine_value(L, registry, value) {
			vm.PushNil(L)
		}
	case .Datatype:
		if !kne_push_datatype_handle(L, registry, value) {
			vm.PushNil(L)
		}
	case .Signal:
		if value.data.signal != nil {
			signals.Push(L, cast(^signals.Signal)value.data.signal)
		} else {
			vm.PushNil(L)
		}
	case .Callback:
		callback := cast(^Retained_Callback)value.data.callback
		if callback == nil ||
		   callback.ref <= 0 {vm.PushNil(L)} else {vm.PushRegistryReference(L, callback.ref)}
	case .Table, .Function:
		source := cast(^vm.State)value.data.stack.vm
		if source ==
		   nil {vm.PushNil(L)} else {vm.CopyValueToThread(source, L, int(value.data.stack.index))}
	}
}


@(private)
stack_kne_value :: proc(L: ^vm.State, registry: ^datatypes.Registry, index: int) -> KNE_Value {
	value := kne_value_nil()
	if L == nil {
		return value
	}

	#partial switch vm.TypeOf(L, index) {
	case .Nil:
		return value
	case .Boolean:
		value.kind = .Boolean
		value.data.boolean = vm.ArgBoolean(L, index) ? 1 : 0
	case .Number:
		value.kind = .Number
		value.data.number = vm.ArgNumber(L, index)
	case .Integer:
		value.kind = .Integer
		value.data.integer = vm.ArgInteger(L, index)
	case .String:
		text := vm.ArgString(L, index)
		value.kind = .String
		if len(text) > 0 {

			value.data.string = KNE_String {
				data   = cstring(raw_data(text)),
				length = uintptr(len(text)),
			}
		}
	case .Vector:
		x, y, z := vm.ArgVector3(L, index)
		value.kind = .Vector3
		value.data.vector3 = KNE_Vector3{x, y, z}
	case .Userdata:
		if object := classes.Object_From_Argument(L, index); object != nil {
			value.kind = .Instance
			value.data.instance = rawptr(object)
		} else if registry != nil {
			binding := vm.UserdataBindingOf(L, index)
			if entry := kne_engine_datatype_for_binding(registry, binding); entry != nil {
				if entry.kind == .Datatype {
					value.kind = .Datatype
					value.data.datatype = KNE_Datatype {
						handle       = vm.UserdataValue(L, index),
						type_name    = KNE_String_From(entry.name),
						tag          = entry.tag,
						source_vm    = L,
						source_index = i32(index if index > 0 else vm.StackTop(L) + index + 1),
					}
				} else {
					value.kind = entry.kind
					mem.copy(&value.data, vm.UserdataValue(L, index), entry.size)
				}
			} else if binding != nil && binding.tag == enums.ENUM_ITEM_TAG {
				value.kind = .Datatype
				value.data.datatype = KNE_Datatype {
					handle    = vm.UserdataValue(L, index),
					type_name = KNE_String_From("EnumItem"),
					tag       = enums.ENUM_ITEM_TAG,
				}
			} else if binding != nil && binding.tag == signals.SIGNAL_TAG {
				value.kind = .Signal
				value.data.signal = vm.UserdataValue(L, index)
			} else if codec := datatypes.Find_Extension_Codec_By_Binding(registry, binding);
			   codec != nil {
				value.kind = .Datatype
				value.data.datatype = KNE_Datatype {
					handle    = vm.UserdataValue(L, index),
					type_name = KNE_String_From(codec.type_name),
					tag       = u32(binding.tag),
				}
			}
		}
	case .Table:
		value.kind = .Table
		value.data.stack = KNE_Stack_Value {
			vm    = L,
			index = i32(index if index > 0 else vm.StackTop(L) + index + 1),
		}
	case .Function:
		value.kind = .Function
		value.data.stack = KNE_Stack_Value {
			vm    = L,
			index = i32(index if index > 0 else vm.StackTop(L) + index + 1),
		}
	case:
	}
	return value
}


kne_core_log :: proc "c" (ext: KNE_Extension, level: KNE_Log_Level, message: KNE_String) {
	context = runtime.default_context()
	record := record_of(ext)
	id := "kne"
	if record != nil && len(record.manifest.id) > 0 {
		id = record.manifest.id
	}
	level_name := "info"
	switch level {
	case .Trace:
		level_name = "trace"
	case .Debug:
		level_name = "debug"
	case .Info:
		level_name = "info"
	case .Warn:
		level_name = "warn"
	case .Error:
		level_name = "error"
	}
	debuglog.Log(fmt.tprintf("[KNE %s] %s: %s", id, level_name, KNE_String_To(message)))
}

kne_core_allocate :: proc "c" (ext: KNE_Extension, size: uintptr) -> rawptr {
	context = runtime.default_context()
	_ = ext
	if size == 0 {
		return nil
	}
	total := int(size) + KNE_ALLOC_HEADER
	base, alloc_err := mem.alloc(total, KNE_ALLOC_HEADER)
	if alloc_err != nil || base == nil {
		return nil
	}
	header := cast(^uintptr)base
	header^ = size
	return rawptr(uintptr(base) + KNE_ALLOC_HEADER)
}

kne_core_reallocate :: proc "c" (ext: KNE_Extension, ptr: rawptr, size: uintptr) -> rawptr {
	context = runtime.default_context()
	if ptr == nil {
		return kne_core_allocate(ext, size)
	}
	if size == 0 {
		kne_core_release(ext, ptr)
		return nil
	}
	base := rawptr(uintptr(ptr) - KNE_ALLOC_HEADER)
	header := cast(^uintptr)base
	old_size := header^
	resized, resize_err := mem.resize(
		base,
		int(old_size) + KNE_ALLOC_HEADER,
		int(size) + KNE_ALLOC_HEADER,
		KNE_ALLOC_HEADER,
	)
	if resize_err != nil || resized == nil {
		return nil
	}
	resized_header := cast(^uintptr)resized
	resized_header^ = size
	return rawptr(uintptr(resized) + KNE_ALLOC_HEADER)
}

kne_core_release :: proc "c" (ext: KNE_Extension, ptr: rawptr) {
	context = runtime.default_context()
	_ = ext
	if ptr == nil {
		return
	}
	mem.free(rawptr(uintptr(ptr) - KNE_ALLOC_HEADER))
}

kne_core_last_error :: proc "c" (ext: KNE_Extension) -> KNE_String {
	context = runtime.default_context()
	record := record_of(ext)
	if record == nil || len(record.last_error) == 0 {
		return KNE_String{}
	}
	return KNE_String_From(record.last_error)
}


kne_services_get :: proc "c" (ext: KNE_Extension, name: KNE_String) -> KNE_Instance {
	context = runtime.default_context()
	state := context_of(ext)
	if state == nil || state.service_registry == nil || state.vm_state == nil {
		return nil
	}
	object := services.Ensure_Service(state.service_registry, KNE_String_To(name))
	return rawptr(object)
}

kne_services_exists :: proc "c" (ext: KNE_Extension, name: KNE_String) -> i32 {
	context = runtime.default_context()
	state := context_of(ext)
	if state == nil || state.service_registry == nil {
		return 0
	}
	return 1 if services.Find_Service(state.service_registry, KNE_String_To(name)) != nil else 0
}

kne_services_count :: proc "c" (ext: KNE_Extension) -> uintptr {
	context = runtime.default_context()
	state := context_of(ext)
	if state == nil || state.service_registry == nil {
		return 0
	}
	return uintptr(len(state.service_registry.services))
}

kne_services_name_at :: proc "c" (ext: KNE_Extension, index: uintptr) -> KNE_String {
	context = runtime.default_context()
	state := context_of(ext)
	if state == nil || state.service_registry == nil {
		return KNE_String{}
	}
	if index >= uintptr(len(state.service_registry.services)) {
		return KNE_String{}
	}
	return KNE_String_From(state.service_registry.services[index].name)
}


@(private)
parse_member_list :: proc(value: KNE_String) -> [dynamic]string {
	result: [dynamic]string
	text := KNE_String_To(value)
	if len(text) == 0 {
		return result
	}

	remaining := text
	for len(remaining) > 0 {
		separator := strings.index_byte(remaining, ',')
		part := remaining
		if separator >= 0 {
			part = remaining[:separator]
			remaining = remaining[separator + 1:]
		} else {
			remaining = ""
		}
		trimmed := strings.trim_space(part)
		if len(trimmed) > 0 {
			append(&result, strings.clone(trimmed))
		}
	}
	return result
}

@(private)
register_class :: proc(record: ^Extension_Record, desc: ^KNE_Class_Desc) -> string {
	context = runtime.default_context()

	state := record.ctx
	if state == nil || state.class_registry == nil {
		return strings.clone("the extension context is unavailable")
	}
	if desc == nil {
		return strings.clone("null class description")
	}
	if desc.size < u32(size_of(KNE_Class_Desc)) {
		return fmt.aprintf(
			"kne_class_desc.size is %d bytes, this engine needs at least %d",
			desc.size,
			size_of(KNE_Class_Desc),
		)
	}

	name := KNE_String_To(desc.name)
	if len(name) == 0 {
		return strings.clone("class name must not be empty")
	}
	if classes.Find_Class(state.class_registry, name) != nil {
		return fmt.aprintf("class %q is already registered", name)
	}

	is_service := (desc.flags & KNE_CLASS_SERVICE) != 0
	if is_service &&
	   (state.service_registry == nil ||
			   services.Find_Service(state.service_registry, name) != nil) {
		return fmt.aprintf("service %q already exists", name)
	}

	base_name := KNE_String_To(desc.base)
	if len(base_name) == 0 {
		base_name = is_service ? "Service" : "Instance"
	}
	parent := classes.Find_Class(state.class_registry, base_name)
	if parent == nil {
		return fmt.aprintf("unknown base class %q", base_name)
	}


	if parent.info.name != "Instance" && parent.info.name != "Service" {
		if class_registrations[parent.info] == nil {
			return fmt.aprintf(
				"base class %q is not a KNE class; derive from Instance, Service or another KNE class",
				parent.info.name,
			)
		}
	}

	registration := new(Class_Registration)
	registration.extension = record
	registration.name = strings.clone(name)
	registration.desc = desc^
	registration.is_service = is_service
	registration.properties = parse_member_list(desc.properties)
	registration.methods = parse_member_list(desc.methods)
	registration.events = parse_member_list(desc.events)

	registration.info = new(classes.Class_Info)
	registration.info^ = classes.Class_Info {
		name   = registration.name,
		parent = parent.info,
	}

	classes.Register_Class(
		state.class_registry,
		registration.info,
		native_construct_unbound,
		native_destroy,
		creatable = (desc.flags & KNE_CLASS_CREATABLE) != 0,
		get = native_get,
		set = native_set,
		namecall = native_namecall,
		properties = registration.properties[:],
		methods = registration.methods[:],
		events = registration.events[:],
		construct_with_ctx = native_construct,
		construct_ctx = registration,
	)

	registration.descriptor = classes.Find_Class(state.class_registry, registration.name)
	registration.registered = true
	class_registrations[registration.info] = registration
	append(&record.classes, registration)

	if is_service {
		services.Register_Service(state.service_registry, registration.name, registration.name)
	}

	return ""
}

kne_classes_register :: proc "c" (ext: KNE_Extension, desc: ^KNE_Class_Desc) -> i32 {
	context = runtime.default_context()
	record := record_of(ext)
	if record == nil {
		return 0
	}
	err := register_class(record, desc)
	if err != "" {
		delete(record.last_error)
		record.last_error = err
		return 0
	}
	return 1
}

kne_classes_is_registered :: proc "c" (ext: KNE_Extension, name: KNE_String) -> i32 {
	context = runtime.default_context()
	state := context_of(ext)
	if state == nil || state.class_registry == nil {
		return 0
	}
	return 1 if classes.Find_Class(state.class_registry, KNE_String_To(name)) != nil else 0
}


@(private)
native_construct_unbound :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	debuglog.Log_Error("KNE: a native class was constructed without its registration context")
	return nil
}

@(private)
native_construct :: proc(
	ctx: rawptr,
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	context = runtime.default_context()
	registration := cast(^Class_Registration)ctx
	if registration == nil || registration.info == nil {
		return nil
	}

	object := new(classes.Object)
	object^ = classes.Object_Init(registration.info, registration.name)

	if registration.desc.on_construct != nil {
		registration.desc.on_construct(rawptr(registration.extension), rawptr(object))
	}

	return object
}

@(private)
native_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	context = runtime.default_context()
	if object == nil {
		return
	}

	registration := class_registrations[object.class]
	if registration != nil {
		if registration.desc.on_destroy != nil {
			registration.desc.on_destroy(rawptr(registration.extension), rawptr(object))
		}
		if state := registration.extension.ctx; state != nil {
			delete_key(&state.instance_data, object)
		}
	}

	classes.Object_Destroy(object)
	free(object)
}

@(private)
native_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	context = runtime.default_context()
	registration := class_registrations[object.class]
	if registration == nil || registration.desc.get == nil {
		return false
	}

	value := kne_value_nil()
	if registration.desc.get(
		   rawptr(registration.extension),
		   rawptr(object),
		   KNE_String_From(key),
		   &value,
	   ) ==
	   0 {
		return false
	}

	push_kne_value(L, datatype_registry, &value)
	return true
}

@(private)
native_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	context = runtime.default_context()
	registration := class_registrations[object.class]
	if registration == nil || registration.desc.set == nil {
		return false
	}

	value := stack_kne_value(L, datatype_registry, value_index)
	return(
		registration.desc.set(
			rawptr(registration.extension),
			rawptr(object),
			KNE_String_From(key),
			&value,
		) !=
		0 \
	)
}

@(private)
native_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	context = runtime.default_context()
	registration := class_registrations[object.class]
	if registration == nil || registration.desc.namecall == nil {
		return 0, false
	}

	count := registration.desc.namecall(
		rawptr(registration.extension),
		rawptr(object),
		KNE_String_From(method),
		rawptr(L),
		i32(vm.StackTop(L)),
	)
	if count == KNE_UNHANDLED {
		return 0, false
	}
	return count, true
}


kne_instances_create :: proc "c" (ext: KNE_Extension, class_name: KNE_String) -> KNE_Instance {
	context = runtime.default_context()
	state := context_of(ext)
	if state == nil ||
	   state.class_registry == nil ||
	   state.vm_state == nil ||
	   state.vm_state.L == nil {
		return nil
	}

	object, ok := classes.Push_New(state.class_registry, state.vm_state, KNE_String_To(class_name))
	if !ok || object == nil {
		return nil
	}
	vm.Pop(state.vm_state.L)
	return rawptr(object)
}

kne_instances_destroy :: proc "c" (ext: KNE_Extension, instance: KNE_Instance) {
	context = runtime.default_context()
	_ = ext
	object := cast(^classes.Object)instance
	if object == nil {
		return
	}
	classes.Destroy_Hierarchy(object)
}

kne_instances_get_name :: proc "c" (ext: KNE_Extension, instance: KNE_Instance) -> KNE_String {
	context = runtime.default_context()
	_ = ext
	object := cast(^classes.Object)instance
	if object == nil {
		return KNE_String{}
	}
	return KNE_String_From(classes.Get_Name(object))
}

kne_instances_set_name :: proc "c" (ext: KNE_Extension, instance: KNE_Instance, name: KNE_String) {
	context = runtime.default_context()
	_ = ext
	object := cast(^classes.Object)instance
	if object == nil {
		return
	}
	classes.Set_Name(object, KNE_String_To(name))
}

kne_instances_get_parent :: proc "c" (ext: KNE_Extension, instance: KNE_Instance) -> KNE_Instance {
	context = runtime.default_context()
	_ = ext
	object := cast(^classes.Object)instance
	if object == nil {
		return nil
	}
	return rawptr(classes.Get_Parent(object))
}

kne_instances_set_parent :: proc "c" (
	ext: KNE_Extension,
	instance: KNE_Instance,
	parent: KNE_Instance,
) {
	context = runtime.default_context()
	_ = ext
	object := cast(^classes.Object)instance
	if object == nil {
		return
	}
	classes.Set_Parent(object, cast(^classes.Object)parent)
}

kne_instances_child_count :: proc "c" (ext: KNE_Extension, instance: KNE_Instance) -> uintptr {
	context = runtime.default_context()
	_ = ext
	object := cast(^classes.Object)instance
	if object == nil {
		return 0
	}
	return uintptr(len(object.children))
}

kne_instances_child_at :: proc "c" (
	ext: KNE_Extension,
	instance: KNE_Instance,
	index: uintptr,
) -> KNE_Instance {
	context = runtime.default_context()
	_ = ext
	object := cast(^classes.Object)instance
	if object == nil || index >= uintptr(len(object.children)) {
		return nil
	}
	return rawptr(object.children[index])
}

kne_instances_find_child :: proc "c" (
	ext: KNE_Extension,
	instance: KNE_Instance,
	name: KNE_String,
) -> KNE_Instance {
	context = runtime.default_context()
	_ = ext
	object := cast(^classes.Object)instance
	if object == nil {
		return nil
	}
	return rawptr(classes.Find_First_Child(object, KNE_String_To(name)))
}

kne_instances_is_a :: proc "c" (
	ext: KNE_Extension,
	instance: KNE_Instance,
	class_name: KNE_String,
) -> i32 {
	context = runtime.default_context()
	_ = ext
	object := cast(^classes.Object)instance
	if object == nil {
		return 0
	}
	return 1 if classes.Is_A(object, KNE_String_To(class_name)) else 0
}

kne_instances_class_name :: proc "c" (ext: KNE_Extension, instance: KNE_Instance) -> KNE_String {
	context = runtime.default_context()
	_ = ext
	object := cast(^classes.Object)instance
	if object == nil {
		return KNE_String{}
	}
	return KNE_String_From(classes.Get_Class_Name(object))
}

kne_instances_get_property :: proc "c" (
	ext: KNE_Extension,
	instance: KNE_Instance,
	key: KNE_String,
	out: ^KNE_Value,
) -> i32 {
	context = runtime.default_context()
	record := record_of(ext)
	if record == nil || instance == nil || out == nil {
		return 0
	}
	state := record.ctx
	object := cast(^classes.Object)instance
	if object.destroyed {
		return 0
	}

	name := KNE_String_To(key)
	switch name {
	case "Name":
		out.kind = .String
		out.data.string = KNE_String_From(classes.Get_Name(object))
		return 1
	case "ClassName":
		out.kind = .String
		out.data.string = KNE_String_From(classes.Get_Class_Name(object))
		return 1
	case "Parent":
		if parent := classes.Get_Parent(object); parent != nil {
			out.kind = .Instance
			out.data.instance = rawptr(parent)
		} else {
			out.kind = .Nil
		}
		return 1
	}

	if registration := class_registrations[object.class];
	   registration != nil && registration.desc.get != nil {
		value := kne_value_nil()
		if registration.desc.get(
			   rawptr(registration.extension),
			   instance,
			   KNE_String_From(name),
			   &value,
		   ) !=
		   0 {
			out^ = value
			return 1
		}
	}


	if state == nil ||
	   state.class_registry == nil ||
	   state.vm_state == nil ||
	   state.vm_state.L == nil {
		return 0
	}
	descriptor := classes.Find_Class(state.class_registry, classes.Get_Class_Name(object))
	if descriptor == nil || descriptor.get == nil {
		return 0
	}

	L := state.vm_state.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)

	if !descriptor.get(L, object, state.datatype_registry, state.enum_registry, name) {
		return 0
	}
	if vm.StackTop(L) <= top {
		return 0
	}

	out^ = stack_kne_value(L, state.datatype_registry, vm.StackTop(L))
	return 1
}

kne_instances_set_property :: proc "c" (
	ext: KNE_Extension,
	instance: KNE_Instance,
	key: KNE_String,
	value: ^KNE_Value,
) -> i32 {
	context = runtime.default_context()
	record := record_of(ext)
	if record == nil || instance == nil || value == nil {
		return 0
	}
	state := record.ctx
	object := cast(^classes.Object)instance
	if object.destroyed {
		return 0
	}

	name := KNE_String_To(key)
	switch name {
	case "Name":
		classes.Set_Name(object, KNE_String_To(value.data.string))
		return 1
	case "Parent":
		classes.Set_Parent(object, cast(^classes.Object)value.data.instance)
		return 1
	case "ClassName":
		return 0
	}

	if registration := class_registrations[object.class];
	   registration != nil && registration.desc.set != nil {
		if registration.desc.set(
			   rawptr(registration.extension),
			   instance,
			   KNE_String_From(name),
			   value,
		   ) !=
		   0 {
			return 1
		}
	}

	if state == nil ||
	   state.class_registry == nil ||
	   state.vm_state == nil ||
	   state.vm_state.L == nil {
		return 0
	}
	descriptor := classes.Find_Class(state.class_registry, classes.Get_Class_Name(object))
	if descriptor == nil || descriptor.set == nil {
		return 0
	}

	L := state.vm_state.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)

	push_kne_value(L, state.datatype_registry, value)
	if !descriptor.set(
		L,
		object,
		state.datatype_registry,
		state.enum_registry,
		name,
		vm.StackTop(L),
	) {
		return 0
	}
	return 1
}

kne_instances_get_user_data :: proc "c" (ext: KNE_Extension, instance: KNE_Instance) -> rawptr {
	context = runtime.default_context()
	state := context_of(ext)
	if state == nil || instance == nil {
		return nil
	}
	return state.instance_data[cast(^classes.Object)instance]
}

kne_instances_set_user_data :: proc "c" (
	ext: KNE_Extension,
	instance: KNE_Instance,
	data: rawptr,
) {
	context = runtime.default_context()
	state := context_of(ext)
	if state == nil || instance == nil {
		return
	}
	object := cast(^classes.Object)instance
	if data == nil {
		delete_key(&state.instance_data, object)
		return
	}
	state.instance_data[object] = data
}


@(private)
state_of_vm :: proc(L: KNE_VM) -> ^vm.State {
	return cast(^vm.State)L
}

kne_native_trampoline :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	closure := cast(^Native_Function_Closure)vm.UpvaluePointer(L)
	if closure == nil || closure.record == nil {
		return vm.RaiseError(L, "invalid KNE native function")
	}
	if closure.record.state != .Running || closure.function == nil {
		return vm.RaiseError(L, "this extension is no longer loaded")
	}
	first_root := len(closure.record.result_roots)
	defer release_result_roots(closure.record, first_root)
	return closure.function(rawptr(closure.record), rawptr(L))
}

@(private)
track_global :: proc(record: ^Extension_Record, name: string) {
	for existing in record.globals {
		if existing == name {
			return
		}
	}
	append(&record.globals, strings.clone(name))
}

kne_vm_register_function :: proc "c" (
	ext: KNE_Extension,
	name: KNE_String,
	function: KNE_VM_Native_Fn,
) -> i32 {
	context = runtime.default_context()
	record := record_of(ext)
	if record == nil || record.ctx == nil || record.ctx.vm_state == nil {
		return 0
	}
	if function == nil {
		return 0
	}

	closure := new(Native_Function_Closure)
	closure.record = record
	closure.function = function
	append(&record.closures, closure)

	text := KNE_String_To(name)
	L := record.ctx.vm_state.L
	vm.PushLightUserdata(L, rawptr(closure))
	vm.PushFunction(L, text, kne_native_trampoline, 1)
	vm.SetGlobalFromStack(record.ctx.vm_state, text)
	track_global(record, text)
	return 1
}

kne_vm_register_library_function :: proc "c" (
	ext: KNE_Extension,
	library: KNE_String,
	name: KNE_String,
	function: KNE_VM_Native_Fn,
) -> i32 {
	context = runtime.default_context()
	record := record_of(ext)
	if record == nil || record.ctx == nil || record.ctx.vm_state == nil {
		return 0
	}
	if function == nil {
		return 0
	}

	library_name := KNE_String_To(library)
	if len(library_name) == 0 {
		return 0
	}

	vm_state := record.ctx.vm_state
	L := vm_state.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)

	_ = vm.GetGlobal(L, library_name)
	if !vm.IsTable(L, -1) {
		vm.Pop(L)
		vm.NewTable(L, 0, 0)
		vm.PushValue(L, -1)
		vm.SetGlobalFromStack(vm_state, library_name)
		track_global(record, library_name)
	}

	closure := new(Native_Function_Closure)
	closure.record = record
	closure.function = function
	append(&record.closures, closure)

	vm.PushLightUserdata(L, rawptr(closure))
	vm.PushFunction(L, KNE_String_To(name), kne_native_trampoline, 1)
	vm.SetField(L, -2, KNE_String_To(name))
	return 1
}

kne_vm_arg_count :: proc "c" (L: KNE_VM) -> i32 {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state == nil {
		return 0
	}
	return i32(vm.StackTop(state))
}

kne_vm_kind :: proc "c" (L: KNE_VM, index: i32) -> KNE_Value_Kind {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state == nil {
		return .Nil
	}
	#partial switch vm.TypeOf(state, int(index)) {
	case .Nil:
		return .Nil
	case .Boolean:
		return .Boolean
	case .Number:
		return .Number
	case .Integer:
		return .Integer
	case .String:
		return .String
	case .Vector:
		return .Vector3
	case .Userdata:
		if classes.Object_From_Argument(state, int(index)) != nil {
			return .Instance
		}
		return .Nil
	case .Table:
		return .Table
	case .Function:
		return .Function
	case:
		return .Nil
	}
}

kne_vm_get_number :: proc "c" (L: KNE_VM, index: i32) -> f64 {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state == nil {
		return 0
	}
	return vm.ArgNumber(state, int(index))
}

kne_vm_get_integer :: proc "c" (L: KNE_VM, index: i32) -> i64 {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state == nil {
		return 0
	}
	return vm.ArgInteger(state, int(index))
}

kne_vm_get_boolean :: proc "c" (L: KNE_VM, index: i32) -> i32 {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state == nil {
		return 0
	}
	return 1 if vm.ArgBoolean(state, int(index)) else 0
}

kne_vm_get_string :: proc "c" (L: KNE_VM, index: i32) -> KNE_String {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state == nil || vm.TypeOf(state, int(index)) != .String {
		return KNE_String{}
	}
	text := vm.ArgString(state, int(index))
	if len(text) == 0 {
		return KNE_String{data = cstring(""), length = 0}
	}
	return KNE_String{data = cstring(raw_data(text)), length = uintptr(len(text))}
}

kne_vm_get_instance :: proc "c" (L: KNE_VM, index: i32) -> KNE_Instance {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state == nil {
		return nil
	}
	return rawptr(classes.Object_From_Argument(state, int(index)))
}

kne_vm_push_nil :: proc "c" (L: KNE_VM) {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state != nil {
		vm.PushNil(state)
	}
}

kne_vm_push_boolean :: proc "c" (L: KNE_VM, value: i32) {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state != nil {
		vm.PushBoolean(state, value != 0)
	}
}

kne_vm_push_number :: proc "c" (L: KNE_VM, value: f64) {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state != nil {
		vm.PushNumber(state, value)
	}
}

kne_vm_push_integer :: proc "c" (L: KNE_VM, value: i64) {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state != nil {
		vm.PushNumber(state, f64(value))
	}
}

kne_vm_push_string :: proc "c" (L: KNE_VM, value: KNE_String) {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state != nil {
		vm.PushString(state, KNE_String_To(value))
	}
}

kne_vm_push_instance :: proc "c" (L: KNE_VM, instance: KNE_Instance) {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state != nil {
		classes.Push_Object(state, cast(^classes.Object)instance)
	}
}

kne_vm_push_value :: proc "c" (ext: KNE_Extension, L: KNE_VM, value: ^KNE_Value) {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state == nil {
		return
	}
	record := record_of(ext)
	registry: ^datatypes.Registry
	if record != nil {
		registry = record.ctx.datatype_registry
	}
	push_kne_value(state, registry, value)
}

kne_vm_push_stack :: proc "c" (L: KNE_VM, index: i32) {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state != nil {
		vm.PushValue(state, int(index))
	}
}

kne_vm_push_table :: proc "c" (L: KNE_VM) {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state != nil {
		vm.NewTable(state, 0, 0)
	}
}

kne_vm_set_field :: proc "c" (L: KNE_VM, table_index: i32, key: KNE_String) {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state != nil {
		vm.SetField(state, int(table_index), KNE_String_To(key))
	}
}

kne_vm_set_global :: proc "c" (ext: KNE_Extension, L: KNE_VM, name: KNE_String) {
	context = runtime.default_context()
	state := state_of_vm(L)
	record := record_of(ext)
	if state == nil || record == nil {
		return
	}
	text := KNE_String_To(name)
	vm.SetGlobal(state, text)
	track_global(record, text)
}

kne_vm_remove :: proc "c" (L: KNE_VM, index: i32) {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state != nil {
		vm.Remove(state, int(index))
	}
}

kne_vm_raise :: proc "c" (L: KNE_VM, message: KNE_String) -> i32 {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state == nil {
		return 0
	}
	return vm.RaiseError(state, KNE_String_To(message))
}


@(private)
datatype_registry_of :: proc(ext: KNE_Extension) -> ^datatypes.Registry {
	state := context_of(ext)
	if state == nil {
		return nil
	}
	return state.datatype_registry
}

kne_datatypes_push_vector2 :: proc "c" (ext: KNE_Extension, L: KNE_VM, value: KNE_Vector2) {
	context = runtime.default_context()
	state := state_of_vm(L)
	registry := datatype_registry_of(ext)
	if state == nil {
		return
	}
	if registry == nil {
		vm.PushNil(state)
		return
	}
	datatypes.Push_Vector2(state, registry, datatypes.Vector2{value.x, value.y})
}

kne_datatypes_push_vector3 :: proc "c" (ext: KNE_Extension, L: KNE_VM, value: KNE_Vector3) {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state == nil {
		return
	}
	vm.PushVector3(state, value.x, value.y, value.z)
}

kne_datatypes_push_cframe :: proc "c" (ext: KNE_Extension, L: KNE_VM, value: KNE_CFrame) {
	context = runtime.default_context()
	state := state_of_vm(L)
	registry := datatype_registry_of(ext)
	if state == nil {
		return
	}
	if registry == nil {
		vm.PushNil(state)
		return
	}
	datatypes.Push_CFrame(state, registry, kne_cframe_to(value))
}

kne_datatypes_push_color3 :: proc "c" (ext: KNE_Extension, L: KNE_VM, value: KNE_Color3) {
	context = runtime.default_context()
	state := state_of_vm(L)
	registry := datatype_registry_of(ext)
	if state == nil {
		return
	}
	if registry == nil {
		vm.PushNil(state)
		return
	}
	datatypes.Push_Color3(state, registry, datatypes.Color3{R = value.r, G = value.g, B = value.b})
}

kne_datatypes_get_vector2 :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32) -> KNE_Vector2 {
	context = runtime.default_context()
	state := state_of_vm(L)
	if state == nil {
		return {}
	}
	x, y, _ := vm.ArgVector3(state, int(index))
	return KNE_Vector2{x, y}
}

kne_datatypes_get_vector3 :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32) -> KNE_Vector3 {
	context = runtime.default_context()
	_ = ext
	state := state_of_vm(L)
	if state == nil {
		return {}
	}
	x, y, z := vm.ArgVector3(state, int(index))
	return KNE_Vector3{x, y, z}
}

kne_datatypes_get_cframe :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32) -> KNE_CFrame {
	context = runtime.default_context()
	state := state_of_vm(L)
	registry := datatype_registry_of(ext)
	if state == nil || registry == nil {
		return {}
	}
	if !vm.IsUserdataType(state, int(index), &registry.c_frame) {
		return {}
	}
	return kne_cframe_from(datatypes.Arg_CFrame(state, int(index), registry))
}

kne_datatypes_get_color3 :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32) -> KNE_Color3 {
	context = runtime.default_context()
	state := state_of_vm(L)
	registry := datatype_registry_of(ext)
	if state == nil || registry == nil {
		return {}
	}
	if !vm.IsUserdataType(state, int(index), &registry.color3) {
		return {}
	}
	color := datatypes.Arg_Color3(state, int(index), registry)
	return KNE_Color3{color.R, color.G, color.B}
}
