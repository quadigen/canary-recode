package native_api

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import services "../services"
import vm "../vm"
import odin_runtime "base:runtime"
import "core:strings"

Class_Property_Max :: 32
Class_Method_Max :: 16

Class_Flags :: enum u32 {
	Creatable = 1,
	Service   = 2,
}

Property_Kind :: enum u32 {
	Boolean = 1,
	Number  = 2,
	String  = 3,
	Vector3 = 4,
	Color3  = 5,
	CFrame  = 6,
	Integer = 7,
}

Class_Property :: struct {
	name:      cstring,
	kind:      Property_Kind,
	offset:    u64,
	read_only: bool,
}

Class_Method_Fn :: proc "c" (
	ctx: ^Context,
	data: rawptr,
	argument_count: u32,
	arguments: [^]SDK_Value,
	output: ^SDK_Value,
) -> bool

Class_Method :: struct {
	name:     cstring,
	callback: Class_Method_Fn,
}

Class_Construct_Fn :: proc "c" (ctx: ^Context, data: rawptr)
Class_Step_Fn :: proc "c" (ctx: ^Context, data: rawptr, delta_seconds: f64)
Class_Get_Fn :: proc "c" (ctx: ^Context, data: rawptr, name: cstring, out: ^SDK_Value) -> bool
Class_Set_Fn :: proc "c" (ctx: ^Context, data: rawptr, name: cstring, input: ^SDK_Value) -> bool
Class_Batch_Instance :: struct {
	instance: u64,
	data:     rawptr,
}
Class_Batch_Step_Fn :: proc "c" (
	ctx: ^Context,
	instances: [^]Class_Batch_Instance,
	count: u32,
	delta_seconds: f64,
)

Class_Description :: struct {
	size:           u32,
	flags:          u32,
	name:           cstring,
	base:           cstring,
	data_size:      u64,
	property_count: u32,
	method_count:   u32,
	properties:     [Class_Property_Max]Class_Property,
	methods:        [Class_Method_Max]Class_Method,
	on_construct:   Class_Construct_Fn,
	on_destroy:     Class_Construct_Fn,
	on_step:        Class_Step_Fn,
	on_batch_step:  Class_Batch_Step_Fn,
	on_get:         Class_Get_Fn,
	on_set:         Class_Set_Fn,
}

Native_Class_Registration :: struct {
	owner:          ^Context,
	class_info:     ^classes.Class_Info,
	descriptor:     ^classes.Class_Descriptor,
	name:           string,
	description:    Class_Description,
	property_names: [dynamic]string,
	method_names:   [dynamic]string,
	instance_data:  map[^classes.Object][]u8,
}

native_class_registrations: map[^classes.Class_Info]^Native_Class_Registration

find_native_class :: proc(info: ^classes.Class_Info) -> ^Native_Class_Registration {
	if info == nil {return nil}
	return native_class_registrations[info]
}

native_class_find_property :: proc(
	reg: ^Native_Class_Registration,
	name: string,
) -> ^Class_Property {
	if reg == nil {return nil}
	for i in 0 ..< int(reg.description.property_count) {
		property := &reg.description.properties[i]
		if string(property.name) == name {return property}
	}
	return nil
}

native_class_find_method :: proc(reg: ^Native_Class_Registration, name: string) -> ^Class_Method {
	if reg == nil {return nil}
	for i in 0 ..< int(reg.description.method_count) {
		method := &reg.description.methods[i]
		if string(method.name) == name {return method}
	}
	return nil
}

native_class_data :: proc(reg: ^Native_Class_Registration, object: ^classes.Object) -> rawptr {
	if reg == nil || object == nil {return nil}
	buffer, ok := reg.instance_data[object]
	if !ok || len(buffer) == 0 {return nil}
	return raw_data(buffer)
}

native_class_create :: proc(
	context_ptr: rawptr,
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	context = odin_runtime.default_context()
	_ = renderer
	_ = data_model
	reg := cast(^Native_Class_Registration)context_ptr
	if reg == nil || reg.class_info == nil || reg.owner == nil || !reg.owner.active {return nil}
	object := new(classes.Object)
	object^ = classes.Object_Init(reg.class_info, reg.name)
	buffer := make([]u8, max(1, int(reg.description.data_size)))
	reg.instance_data[object] = buffer
	if reg.description.on_construct != nil {
		reg.description.on_construct(reg.owner, raw_data(buffer))
	}
	return object
}

native_class_unbound :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	_ = renderer
	_ = data_model
	return nil
}

native_class_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	context = odin_runtime.default_context()
	_ = renderer
	if object == nil {return}
	reg := find_native_class(object.class)
	if reg != nil {
		buffer, found := reg.instance_data[object]
		if found {
			if reg.owner != nil && reg.owner.active && reg.description.on_destroy != nil {
				reg.description.on_destroy(reg.owner, raw_data(buffer))
			}
			for i in 0 ..< int(reg.description.property_count) {
				property := &reg.description.properties[i]
				native_field_destroy(
					property.kind,
					uintptr(raw_data(buffer)) + uintptr(property.offset),
				)
			}
			delete(buffer)
			delete_key(&reg.instance_data, object)
		}
	}
	classes.Object_Destroy(object)
	free(object)
}

native_property_size :: proc(kind: Property_Kind) -> u64 {
	switch kind {
	case .Boolean:
		return u64(size_of(bool))
	case .Number:
		return u64(size_of(f64))
	case .String:
		return u64(size_of(cstring))
	case .Integer:
		return u64(size_of(i64))
	case .Vector3:
		return u64(size_of(SDK_Vector3))
	case .Color3:
		return u64(size_of(SDK_Color3))
	case .CFrame:
		return u64(size_of(SDK_CFrame))
	}
	return 0
}

native_class_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	context = odin_runtime.default_context()
	_ = enum_registry
	reg := find_native_class(object.class)
	if reg == nil || reg.owner == nil || !reg.owner.active {return false}
	prop := native_class_find_property(reg, key)
	base := native_class_data(reg, object)
	if base == nil {return false}
	if reg.description.on_get != nil {
		name := strings.clone_to_cstring(key)
		defer delete(name)
		result: SDK_Value
		if reg.description.on_get(reg.owner, base, name, &result) {
			return sdk_push_value(reg.owner, result)
		}
	}
	if prop == nil {return false}
	return native_field_get(L, datatypes_registry, prop.kind, uintptr(base) + uintptr(prop.offset))
}

native_class_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	context = odin_runtime.default_context()
	_ = enum_registry
	reg := find_native_class(object.class)
	if reg == nil || reg.owner == nil || !reg.owner.active {return false}
	prop := native_class_find_property(reg, key)
	base := native_class_data(reg, object)
	if base == nil || (prop != nil && prop.read_only) {return false}
	if reg.description.on_set != nil {
		name := strings.clone_to_cstring(key)
		defer delete(name)
		copies: [dynamic]cstring
		defer {
			for value in copies {delete(value)}
			delete(copies)
		}
		input := datatype_stack_value(L, reg.owner, index, &copies)
		if reg.description.on_set(reg.owner, base, name, &input) {return true}
	}
	if prop == nil {return false}
	return native_field_set(
		L,
		datatypes_registry,
		prop.kind,
		uintptr(base) + uintptr(prop.offset),
		index,
	)
}

native_class_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method_name: string,
) -> (
	i32,
	bool,
) {
	context = odin_runtime.default_context()
	_ = datatypes_registry
	_ = enum_registry
	reg := find_native_class(object.class)
	if reg == nil || reg.owner == nil || !reg.owner.active {return 0, false}
	method := native_class_find_method(reg, method_name)
	if method == nil || method.callback == nil {return 0, false}
	count := vm.StackTop(L) - 1
	if count < 0 || count > 32 {return 0, true}
	inputs: [32]SDK_Value
	temporary_strings: [dynamic]cstring
	defer {
		for str in temporary_strings {delete(str)}
		delete(temporary_strings)
	}
	for i in 0 ..< count {
		index := i + 2
		input := &inputs[i]
		#partial switch vm.TypeOf(L, index) {
		case .Nil:
			input.kind = .Nil
		case .Boolean:
			input.kind = .Boolean
			input.boolean = vm.ArgBoolean(L, index)
		case .Number, .Integer:
			input.kind = .Number
			input.number = vm.ArgNumber(L, index)
		case .String:
			input.kind = .String
			str := strings.clone_to_cstring(vm.ArgString(L, index))
			append(&temporary_strings, str)
			input.text = str
		case .Vector:
			input.kind = .Vector3
			input.vector.x, input.vector.y, input.vector.z = vm.ArgVector3(L, index)
		case:
			input.kind = .Other
		}
	}
	result: SDK_Value
	data := native_class_data(reg, object)
	if data == nil {return 0, true}
	if !method.callback(reg.owner, data, u32(count), &inputs[0], &result) {return 0, true}
	#partial switch result.kind {
	case .Nil:
		vm.PushNil(L)
	case .Boolean:
		vm.PushBoolean(L, result.boolean)
	case .Number:
		vm.PushNumber(L, result.number)
	case .String:
		if result.text == nil {vm.PushString(L, "")} else {vm.PushString(L, string(result.text))}
	case .Vector3:
		vm.PushVector3(L, result.vector.x, result.vector.y, result.vector.z)
	case .Instance:
		classes.Push_Object(L, resolve_handle(reg.owner, result.instance))
	case:
		vm.PushNil(L)
	}
	return 1, true
}

@(export)
Kinemium_RegisterClass :: proc "c" (ctx: ^Context, description: ^Class_Description) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   !ctx.active ||
	   ctx.classes == nil ||
	   description == nil ||
	   description.size < u32(offset_of(Class_Description, on_batch_step)) ||
	   description.name == nil ||
	   description.base == nil ||
	   description.property_count > Class_Property_Max ||
	   description.method_count > Class_Method_Max ||
	   description.data_size > 1024 * 1024 {return false}
	name := string(description.name)
	base := string(description.base)
	if name == "" || classes.Find_Class(ctx.classes, name) != nil {
		sdk_error(ctx, "class name is empty or already registered")
		return false
	}
	parent := classes.Find_Class(ctx.classes, base)
	if parent == nil {
		sdk_error(ctx, "unknown or unsupported class base")
		return false
	}
	if base != "Instance" && base != "Service" {
		parent_reg := find_native_class(parent.info)
		if parent_reg == nil || parent_reg.owner != ctx {
			sdk_error(ctx, "native classes may only derive from classes owned by the same context")
			return false
		}
	}
	if (description.flags & u32(Class_Flags.Service)) != 0 {
		service_base := false
		for info := parent.info; info != nil; info = info.parent {
			if info.name == "Service" {service_base = true; break}
		}
		if !service_base {
			sdk_error(ctx, "services must inherit from Service")
			return false
		}
	}
	for i in 0 ..< int(description.property_count) {
		prop := &description.properties[i]
		width := native_property_size(prop.kind)
		if prop.name == nil ||
		   width == 0 ||
		   prop.offset > description.data_size ||
		   width > description.data_size - prop.offset {
			sdk_error(ctx, "invalid native class property")
			return false
		}
	}
	for i in 0 ..< int(description.method_count) {
		method := &description.methods[i]
		if method.name == nil || method.callback == nil {
			sdk_error(ctx, "invalid native class method")
			return false
		}
	}
	reg := new(Native_Class_Registration)
	reg.owner = ctx
	reg.name = strings.clone(name)
	reg.description = Class_Description {
		size           = description.size,
		flags          = description.flags,
		name           = description.name,
		base           = description.base,
		data_size      = description.data_size,
		property_count = description.property_count,
		method_count   = description.method_count,
		properties     = description.properties,
		methods        = description.methods,
		on_construct   = description.on_construct,
		on_destroy     = description.on_destroy,
		on_step        = description.on_step,
	}
	if description.size >=
	   u32(offset_of(Class_Description, on_batch_step) + size_of(Class_Batch_Step_Fn)) {
		reg.description.on_batch_step = description.on_batch_step
	}
	if description.size >= u32(offset_of(Class_Description, on_get) + size_of(Class_Get_Fn)) {
		reg.description.on_get = description.on_get
	}
	if description.size >= u32(offset_of(Class_Description, on_set) + size_of(Class_Set_Fn)) {
		reg.description.on_set = description.on_set
	}
	reg.description.name = strings.clone_to_cstring(name)
	reg.description.base = strings.clone_to_cstring(base)
	reg.instance_data = make(map[^classes.Object][]u8)
	for i in 0 ..< int(description.property_count) {
		name_value := string(description.properties[i].name)
		copied := strings.clone(name_value)
		append(&reg.property_names, copied)
		reg.description.properties[i].name = strings.clone_to_cstring(name_value)
	}
	for i in 0 ..< int(description.method_count) {
		name_value := string(description.methods[i].name)
		copied := strings.clone(name_value)
		append(&reg.method_names, copied)
		reg.description.methods[i].name = strings.clone_to_cstring(name_value)
	}
	reg.class_info = new(classes.Class_Info)
	reg.class_info^ = classes.Class_Info {
		name   = reg.name,
		parent = parent.info,
	}
	exported_methods: [dynamic]classes.Class_Export
	defer delete(exported_methods)
	for method in reg.method_names {
		append(&exported_methods, classes.Class_Export{name = method})
	}
	classes.Register_Class(
		ctx.classes,
		reg.class_info,
		native_class_unbound,
		native_class_destroy,
		creatable = (description.flags & u32(Class_Flags.Creatable)) != 0,
		get = native_class_get,
		set = native_class_set,
		namecall = native_class_namecall,
		properties = reg.property_names[:],
		methods = reg.method_names[:],
		exports = exported_methods[:],
		construct_with_ctx = native_class_create,
		construct_ctx = reg,
	)
	reg.descriptor = classes.Find_Class(ctx.classes, reg.name)
	if native_class_registrations == nil {
		native_class_registrations = make(map[^classes.Class_Info]^Native_Class_Registration)
	}
	native_class_registrations[reg.class_info] = reg
	append(&ctx.native_classes, reg)
	if (description.flags & u32(Class_Flags.Service)) != 0 {
		services.Register_Service(ctx.services, reg.name, reg.name)
	}
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_RegisterService :: proc "c" (ctx: ^Context, description: ^Class_Description) -> bool {
	context = odin_runtime.default_context()
	if description == nil ||
	   description.size < u32(offset_of(Class_Description, on_batch_step)) {return false}
	copy := Class_Description {
		size           = u32(size_of(Class_Description)),
		flags          = (description.flags |
			u32(Class_Flags.Service)) & ~u32(Class_Flags.Creatable),
		name           = description.name,
		base           = description.base,
		data_size      = description.data_size,
		property_count = description.property_count,
		method_count   = description.method_count,
		properties     = description.properties,
		methods        = description.methods,
		on_construct   = description.on_construct,
		on_destroy     = description.on_destroy,
		on_step        = description.on_step,
	}
	if description.size >=
	   u32(offset_of(Class_Description, on_batch_step) + size_of(Class_Batch_Step_Fn)) {
		copy.on_batch_step = description.on_batch_step
	}
	if description.size >= u32(offset_of(Class_Description, on_get) + size_of(Class_Get_Fn)) {
		copy.on_get = description.on_get
	}
	if description.size >= u32(offset_of(Class_Description, on_set) + size_of(Class_Set_Fn)) {
		copy.on_set = description.on_set
	}
	return Kinemium_RegisterClass(ctx, &copy)
}

destroy_native_class :: proc(ctx: ^Context, reg: ^Native_Class_Registration) {
	if ctx == nil || reg == nil {return}
	if reg.descriptor != nil {
		to_destroy: [dynamic]^classes.Object
		defer delete(to_destroy)
		append(&to_destroy, ..reg.descriptor.instances[:])
		for object in to_destroy {
			if object != nil && !object.destroyed {classes.Destroy_Hierarchy(object)}
		}
		classes.Flush_Pending_Destroy(ctx.classes)
		if (reg.description.flags & u32(Class_Flags.Service)) != 0 {
			services.Unregister_Service(ctx.services, reg.name)
		}
		classes.Unregister_Class(ctx.classes, reg.descriptor)
		reg.descriptor = nil
	}
	delete_key(&native_class_registrations, reg.class_info)
	for name in reg.property_names {delete(name)}
	delete(reg.property_names)
	for name in reg.method_names {delete(name)}
	delete(reg.method_names)
	delete(reg.description.name)
	delete(reg.description.base)
	for i in 0 ..< int(reg.description.property_count) {delete(reg.description.properties[i].name)}
	for i in 0 ..< int(reg.description.method_count) {delete(reg.description.methods[i].name)}
	for _, buffer in reg.instance_data {delete(buffer)}
	delete(reg.instance_data)
	delete(reg.class_info.ancestors)
	free(reg.class_info)
	delete(reg.name)
	free(reg)
}

UnregisterOwnerClasses :: proc(ctx: ^Context) {
	if ctx == nil {return}
	for i := len(ctx.native_classes) - 1; i >= 0; i -= 1 {
		destroy_native_class(ctx, ctx.native_classes[i])
	}
	delete(ctx.native_classes)
	ctx.native_classes = nil
}

@(export)
Kinemium_UnregisterClass :: proc "c" (ctx: ^Context, name: cstring) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || name == nil {return false}
	for reg, i in ctx.native_classes {
		if reg.name == string(name) {
			for dependent in ctx.native_classes {
				if dependent != reg &&
				   dependent.class_info != nil &&
				   dependent.class_info.parent == reg.class_info {
					sdk_error(ctx, "cannot unregister a class with native subclasses")
					return false
				}
			}
			destroy_native_class(ctx, reg)
			ordered_remove(&ctx.native_classes, i)
			return true
		}
	}
	return false
}

@(export)
Kinemium_HandleGetNativeData :: proc "c" (ctx: ^Context, handle: u64) -> rawptr {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return nil}
	reg := find_native_class(object.class)
	if reg == nil || reg.owner != ctx {return nil}
	return native_class_data(reg, object)
}

StepNativeClasses :: proc(root: ^Context, delta_seconds: f64) {
	if root == nil || !root.active {return}
	for _, registration in native_class_registrations {
		if registration == nil ||
		   registration.owner == nil ||
		   !registration.owner.active ||
		   registration.owner.root != root ||
		   registration.descriptor == nil ||
		   (registration.description.on_step == nil &&
				   registration.description.on_batch_step == nil) {
			continue
		}
		snapshot := make([]^classes.Object, len(registration.descriptor.instances))
		copy(snapshot, registration.descriptor.instances[:])
		if registration.description.on_batch_step != nil {
			for start := 0; start < len(snapshot); start += 1024 {
				batch: [1024]Class_Batch_Instance
				count: u32
				for i in start ..< min(len(snapshot), start + 1024) {
					object := snapshot[i]
					if object == nil {continue}
					data := native_class_data(registration, object)
					if data == nil {continue}
					batch[count] = Class_Batch_Instance {
						instance = register_handle(registration.owner, object),
						data     = data,
					}
					count += 1
				}
				if count > 0 {
					registration.description.on_batch_step(
						registration.owner,
						&batch[0],
						count,
						delta_seconds,
					)
				}
			}
		} else {
			for object in snapshot {
				if object == nil || object.destroyed {continue}
				data := native_class_data(registration, object)
				if data != nil {
					registration.description.on_step(registration.owner, data, delta_seconds)
				}
			}
		}
		delete(snapshot)
	}
}
