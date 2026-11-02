package hello_kne

import kne "../../bindings/odin"
import "base:runtime"
import "core:strings"

host: ^kne.KNE_Host
desc: kne.KNE_Extension_Desc

Item :: struct {
	label:   string,
	updates: i64,
}

Vector :: struct {
	x, y: f64,
}

calculate :: proc "c" (ext: kne.KNE_Extension, L: kne.KNE_VM) -> i32 {
	api := host.vm
	if api == nil {
		return 0
	}
	api.push_number(L, api.get_number(L, 1) + api.get_number(L, 2))
	return 1
}

greeting :: proc "c" (ext: kne.KNE_Extension, L: kne.KNE_VM) -> i32 {
	context = runtime.default_context()
	api := host.vm
	if api == nil {
		return 0
	}
	who := kne.string_to(api.get_string(L, 1))
	buffer: [256]u8
	count := copy(buffer[:], "hello ")
	count += copy(buffer[count:], who)
	api.push_string(L, kne.KNE_String{data = cstring(&buffer[0]), length = uintptr(count)})
	return 1
}

item_of :: proc (ext: kne.KNE_Extension, instance: kne.KNE_Instance) -> ^Item {
	context = runtime.default_context()
	if host == nil || host.instances == nil {
		return nil
	}
	return cast(^Item)host.instances.get_user_data(ext, instance)
}

counter_construct :: proc "c" (ext: kne.KNE_Extension, instance: kne.KNE_Instance) {
	context = runtime.default_context()
	item := new(Item)
	item.label = strings.clone("counter")
	host.instances.set_user_data(ext, instance, rawptr(item))
}

counter_destroy :: proc "c" (ext: kne.KNE_Extension, instance: kne.KNE_Instance) {
	context = runtime.default_context()
	item := item_of(ext, instance)
	if item != nil {
		delete(item.label)
		free(item)
	}
	host.instances.set_user_data(ext, instance, nil)
}

counter_get :: proc "c" (
	ext: kne.KNE_Extension,
	instance: kne.KNE_Instance,
	key: kne.KNE_String,
	out: ^kne.KNE_Value,
) -> i32 {
	context = runtime.default_context()
	item := item_of(ext, instance)
	if item == nil {
		return 0
	}
	context = runtime.default_context()
	switch kne.string_to(key) {
	case "Label":
		out.kind = .String
		out.data.string = kne.string_from(item.label)
		return 1
	case "Updates":
		out.kind = .Integer
		out.data.integer = item.updates
		return 1
	}
	return 0
}

counter_set :: proc "c" (
	ext: kne.KNE_Extension,
	instance: kne.KNE_Instance,
	key: kne.KNE_String,
	value: ^kne.KNE_Value,
) -> i32 {
	context = runtime.default_context()
	item := item_of(ext, instance)
	if item == nil {
		return 0
	}
	if kne.string_to(key) != "Label" {
		return 0
	}
	if value.kind != .String {
		return 0
	}
	delete(item.label)
	item.label = strings.clone(kne.string_to(value.data.string))
	return 1
}

counter_namecall :: proc "c" (
	ext: kne.KNE_Extension,
	instance: kne.KNE_Instance,
	method: kne.KNE_String,
	L: kne.KNE_VM,
	arg_count: i32,
) -> i32 {
	context = runtime.default_context()
	item := item_of(ext, instance)
	if item == nil {
		return 0
	}
	switch kne.string_to(method) {
	case "Bump":
		item.updates += 1
		host.vm.push_integer(L, item.updates)
		return 1
	}
	return kne.UNHANDLED
}

service_namecall :: proc "c" (
	ext: kne.KNE_Extension,
	instance: kne.KNE_Instance,
	method: kne.KNE_String,
	L: kne.KNE_VM,
	arg_count: i32,
) -> i32 {
	context = runtime.default_context()
	switch kne.string_to(method) {
	case "Ping":
		host.vm.push_integer(L, 42)
		return 1
	case "Echo":
		host.vm.push_string(L, host.vm.get_string(L, 2))
		return 1
	}
	return kne.UNHANDLED
}

vector_construct :: proc "c" (
	ext: kne.KNE_Extension,
	ctx: rawptr,
	args: ^kne.KNE_Value,
	arg_count: i32,
) -> i32 {
	if ctx == nil || args == nil || arg_count < 2 {
		return 0
	}
	values := cast([^]kne.KNE_Value)(args)
	vector := cast(^Vector)ctx
	vector.x = values[0].data.number
	vector.y = values[1].data.number
	return 1
}

vector_get :: proc "c" (
	ext: kne.KNE_Extension,
	ctx: rawptr,
	key: kne.KNE_String,
	out: ^kne.KNE_Value,
) -> i32 {
	if ctx == nil || out == nil {
		return 0
	}
	vector := cast(^Vector)ctx
	context = runtime.default_context()
	switch kne.string_to(key) {
	case "X":
		out.kind = .Number
		out.data.number = vector.x
		return 1
	case "Y":
		out.kind = .Number
		out.data.number = vector.y
		return 1
	}
	return 0
}

vector_set :: proc "c" (
	ext: kne.KNE_Extension,
	ctx: rawptr,
	key: kne.KNE_String,
	value: ^kne.KNE_Value,
) -> i32 {
	if ctx == nil || value == nil || value.kind != .Number {
		return 0
	}
	vector := cast(^Vector)ctx
	context = runtime.default_context()
	switch kne.string_to(key) {
	case "X":
		vector.x = value.data.number
		return 1
	case "Y":
		vector.y = value.data.number
		return 1
	}
	return 0
}

vector_equal :: proc "c" (
	ext: kne.KNE_Extension,
	ctx, other: rawptr,
	out: ^i32,
) -> i32 {
	if ctx == nil || other == nil || out == nil {
		return 0
	}
	left := cast(^Vector)ctx
	right := cast(^Vector)other
	out^ = (left.x == right.x && left.y == right.y) ? 1 : 0
	return 1
}

vector_add :: proc "c" (
	ext: kne.KNE_Extension,
	ctx, other: rawptr,
	out: ^kne.KNE_Value,
) -> i32 {
	if ctx == nil || other == nil || out == nil {
		return 0
	}
	left := cast(^Vector)ctx
	right := cast(^Vector)other
	args: [2]kne.KNE_Value
	args[0].kind = .Number
	args[0].data.number = left.x + right.x
	args[1].kind = .Number
	args[1].data.number = left.y + right.y
	context = runtime.default_context()
	return host.datatypes.construct(ext, kne.str("HelloVector"), &args[0], 2, out)
}

vector_negate :: proc "c" (ext: kne.KNE_Extension, ctx: rawptr, out: ^kne.KNE_Value) -> i32 {
 context = runtime.default_context()
 if ctx == nil || out == nil {return 0}
 value := cast(^Vector)ctx
 args: [2]kne.KNE_Value
 args[0].kind = .Number; args[0].data.number = -value.x
 args[1].kind = .Number; args[1].data.number = -value.y
 return host.datatypes.construct(ext, kne.str("HelloVector"), &args[0], 2, out)
}

vector_namecall :: proc "c" (ext: kne.KNE_Extension, ctx: rawptr, method: kne.KNE_String, args: ^kne.KNE_Value, count: i32, out: ^kne.KNE_Value, capacity: i32) -> i32 {
 context = runtime.default_context()
 if ctx == nil || out == nil || capacity < 1 || kne.string_to(method) != "Sum" {return 0}
 value := cast(^Vector)ctx
 out.kind = .Number; out.data.number = value.x + value.y
 return 1
}

vector_encode :: proc "c" (
	ext: kne.KNE_Extension,
	ctx: rawptr,
	buffer: rawptr,
	capacity: uintptr,
	out_size: ^uintptr,
) -> i32 {
	if ctx == nil || out_size == nil {
		return -1
	}
	out_size^ = 2 * size_of(f64)
	if buffer == nil || capacity < out_size^ {
		return 0
	}
	vector := cast(^Vector)ctx
	values := cast([^]f64)buffer
	values[0] = vector.x
	values[1] = vector.y
	return 1
}

vector_decode :: proc "c" (
	ext: kne.KNE_Extension,
	ctx: rawptr,
	data: rawptr,
	size: uintptr,
) -> i32 {
	if ctx == nil || data == nil || size < 2 * size_of(f64) {
		return 0
	}
	vector := cast(^Vector)ctx
	values := cast([^]f64)data
	vector.x = values[0]
	vector.y = values[1]
	return 1
}

new_vector :: proc "c" (ext: kne.KNE_Extension, L: kne.KNE_VM) -> i32 {
	context = runtime.default_context()
	if host == nil || host.datatypes == nil || host.vm == nil {
		return 0
	}
	args: [2]kne.KNE_Value
	args[0].kind = .Number
	args[0].data.number = host.vm.get_number(L, 1)
	args[1].kind = .Number
	args[1].data.number = host.vm.get_number(L, 2)
	out: kne.KNE_Value
	if host.datatypes.construct(ext, kne.str("HelloVector"), &args[0], 2, &out) == 0 {
		return 0
	}
	host.datatypes.push(ext, L, &out)
	return 1
}

apply_callback :: proc "c" (ext: kne.KNE_Extension, L: kne.KNE_VM) -> i32 {
	context = runtime.default_context()
	if host == nil || host.callbacks == nil || host.datatypes == nil {
		return 0
	}
	callback := host.callbacks.retain(ext, L, 1)
	if callback == nil {
		return 0
	}
	defer host.callbacks.release(ext, callback)
	arg: kne.KNE_Value
	arg.kind = .Number
	arg.data.number = host.vm.get_number(L, 2)
	out: kne.KNE_Value
	if host.callbacks.call(ext, callback, &arg, 1, &out, 1) <= 0 {
		return 0
	}
	host.datatypes.push(ext, L, &out)
	return 1
}

fire_signal :: proc "c" (ext: kne.KNE_Extension, L: kne.KNE_VM) -> i32 {
	context = runtime.default_context()
	if host == nil || host.signals == nil {
		return 0
	}
	signal: kne.KNE_Value
	if host.vm.get_value(ext, L, 1, &signal) == 0 || signal.kind != .Signal {
		return 0
	}
	arg: kne.KNE_Value
	arg.kind = .Number
	arg.data.number = host.vm.get_number(L, 2)
	host.signals.fire(ext, signal.data.signal, &arg, 1)
	return 0
}

has_export :: proc "c" (ext: kne.KNE_Extension, L: kne.KNE_VM) -> i32 {
	context = runtime.default_context()
	if host == nil || host.exports == nil {
		return 0
	}
	instance: kne.KNE_Value
	if host.vm.get_value(ext, L, 1, &instance) == 0 || instance.kind != .Instance {
		return 0
	}
	name := host.vm.get_string(L, 2)
	found := host.exports.exists(ext, cast(kne.KNE_Instance)instance.data.instance, name)
	host.vm.push_boolean(L, found)
	return 1
}

export_count :: proc "c" (ext: kne.KNE_Extension, L: kne.KNE_VM) -> i32 {
	context = runtime.default_context()
	if host == nil || host.exports == nil {
		return 0
	}
	instance: kne.KNE_Value
	if host.vm.get_value(ext, L, 1, &instance) == 0 || instance.kind != .Instance {
		return 0
	}
	count := host.exports.count(ext, cast(kne.KNE_Instance)instance.data.instance)
	host.vm.push_integer(L, i64(count))
	return 1
}

native_signal_calls: i32
native_signal :: proc "c" (ext: kne.KNE_Extension, L: kne.KNE_VM) {
 context = runtime.default_context()
 native_signal_calls += 1
}

exercise :: proc "c" (ext: kne.KNE_Extension, L: kne.KNE_VM) -> i32 {
 context = runtime.default_context()
 object, signal: kne.KNE_Value
 host.vm.get_value(ext, L, 1, &object)
 host.vm.get_value(ext, L, 2, &signal)
 args: [2]kne.KNE_Value
 args[0].kind = .Number; args[0].data.number = 3
 args[1].kind = .Number; args[1].data.number = 4
 vector, out: kne.KNE_Value
 if host.datatypes.construct(ext, kne.str("Vector2"), &args[0], 2, &vector) == 0 {return host.vm.raise(L, kne.str("engine construct"))}
 if host.datatypes.get_field(ext, &vector, kne.str("Magnitude"), &out) == 0 || out.data.number != 5 {return host.vm.raise(L, kne.str("engine get field"))}
 if host.datatypes.call(ext, &vector, kne.str("Dot"), &vector, 1, &out, 1) != 1 || out.data.number != 25 {return host.vm.raise(L, kne.str("engine method"))}
 if host.instances.invoke(ext, cast(kne.KNE_Instance)object.data.instance, kne.str("GetFullName"), nil, 0, &out, 1) != 1 || out.kind != .String {return host.vm.raise(L, kne.str("invoke"))}
 if host.instances.invoke(ext, cast(kne.KNE_Instance)object.data.instance, kne.str("MissingMethod"), nil, 0, &out, 1) >= 0 {return host.vm.raise(L, kne.str("invoke error"))}
 if host.exports.call(ext, cast(kne.KNE_Instance)object.data.instance, kne.str("Destroy"), nil, 0, &out, 1) >= 0 {return host.vm.raise(L, kne.str("export gate"))}
 params, flag: kne.KNE_Value
 if host.datatypes.construct(ext, kne.str("RaycastParams"), nil, 0, &params) == 0 {return host.vm.raise(L, kne.str("handle construct"))}
 flag.kind = .Boolean; flag.data.boolean = 1
 if host.datatypes.set_field(ext, &params, kne.str("IgnoreWater"), &flag) == 0 {return host.vm.raise(L, kne.str("handle set field"))}
 if host.datatypes.get_field(ext, &params, kne.str("IgnoreWater"), &out) == 0 || out.data.boolean != 1 {return host.vm.raise(L, kne.str("handle mutation"))}
 ray_args: [2]kne.KNE_Value
 ray_args[0].kind = .Vector3; ray_args[0].data.vector3 = kne.KNE_Vector3{0,10000,0}
 ray_args[1].kind = .Vector3; ray_args[1].data.vector3 = kne.KNE_Vector3{0,1,0}
 if host.exports.call(ext, cast(kne.KNE_Instance)object.data.instance, kne.str("Raycast"), &ray_args[0], 2, &out, 1) != 1 {return host.vm.raise(L, kne.str("typed raycast"))}
 if host.exports.call(ext, cast(kne.KNE_Instance)object.data.instance, kne.str("Raycast"), nil, 0, &out, 1) >= 0 {return host.vm.raise(L, kne.str("typed raycast error"))}
 callback := host.callbacks.retain(ext, L, 3)
 if callback == nil {return 0}
 native_signal_calls = 0
 native := host.signals.connect_native(ext, signal.data.signal, native_signal)
 once := host.signals.once_native(ext, signal.data.signal, native_signal)
 luau := host.signals.connect_callback(ext, signal.data.signal, callback)
 host.signals.fire(ext, signal.data.signal, &args[0], 1)
 host.signals.fire(ext, signal.data.signal, &args[1], 1)
 if native_signal_calls != 3 {return host.vm.raise(L, kne.str("native signals"))}
 host.signals.disconnect(ext, native)
 host.signals.disconnect(ext, once)
 host.signals.disconnect(ext, luau)
 host.callbacks.release(ext, callback)
 if host.callbacks.is_valid(ext, callback) != 0 {return host.vm.raise(L, kne.str("released callback"))}
 callback = host.callbacks.retain(ext, L, 3)
 host.signals.connect_callback(ext, signal.data.signal, callback)
 host.signals.connect_native(ext, signal.data.signal, native_signal)
 host.vm.push_boolean(L, 1)
 return 1
}

roundtrip :: proc "c" (ext: kne.KNE_Extension, L: kne.KNE_VM) -> i32 {
 context = runtime.default_context()
 value: kne.KNE_Value
 if host.vm.get_value(ext, L, 1, &value) == 0 {return 0}
 return host.datatypes.push(ext, L, &value)
}

on_load :: proc "c" (ext: kne.KNE_Extension) -> i32 {
	context = runtime.default_context()
	api := host.vm
	if api == nil || api.register_library_function == nil {
		return 0
	}
	if api.register_library_function(ext, kne.str("HelloKNE"), kne.str("Calculate"), calculate) == 0 {
		return 0
	}
	if api.register_library_function(ext, kne.str("HelloKNE"), kne.str("Greeting"), greeting) == 0 {
		return 0
	}

	if host.classes == nil || host.classes.register == nil {
		return 0
	}

	if api.register_library_function(ext, kne.str("HelloKNE"), kne.str("Exercise"), exercise) == 0 {return 0}
	if api.register_library_function(ext, kne.str("HelloKNE"), kne.str("Roundtrip"), roundtrip) == 0 {return 0}
	vector := kne.KNE_Datatype_Desc {
		size = u32(size_of(kne.KNE_Datatype_Desc)), version = kne.ABI_MAJOR,
		library = kne.str("HelloVector"), type_name = kne.str("HelloVector"),
		value_size = u32(size_of(Vector)), wire_version = 1,
		flags = kne.DATATYPE_PERSISTABLE | kne.DATATYPE_REPLICATED,
		construct = vector_construct, get = vector_get, set = vector_set,
		equal = vector_equal, add = vector_add, negate = vector_negate, namecall = vector_namecall,
		encode = vector_encode, decode = vector_decode,
	}
	if host.datatypes.register_datatype(ext, &vector) == 0 {return 0}
	if api.register_global_datatype(ext, nil, kne.str("HelloVector")) == 0 {return 0}
	if api.register_library_function(ext, kne.str("HelloKNE"), kne.str("NewVector"), new_vector) == 0 {return 0}
	if api.register_library_function(ext, kne.str("HelloKNE"), kne.str("ApplyCallback"), apply_callback) == 0 {return 0}
	if api.register_library_function(ext, kne.str("HelloKNE"), kne.str("FireSignal"), fire_signal) == 0 {return 0}
	if api.register_library_function(ext, kne.str("HelloKNE"), kne.str("HasExport"), has_export) == 0 {return 0}
	if api.register_library_function(ext, kne.str("HelloKNE"), kne.str("ExportCount"), export_count) == 0 {return 0}

	counter := kne.KNE_Class_Desc {
		size         = u32(size_of(kne.KNE_Class_Desc)),
		version      = kne.ABI_MAJOR,
		name         = kne.str("HelloCounter"),
		base         = kne.str("Instance"),
		flags        = kne.CLASS_CREATABLE,
		properties   = kne.str("Label,Updates"),
		methods      = kne.str("Bump"),
		on_construct = counter_construct,
		on_destroy   = counter_destroy,
		get          = counter_get,
		set          = counter_set,
		namecall     = counter_namecall,
	}
	if host.classes.register(ext, &counter) == 0 {
		return 0
	}

	service := kne.KNE_Class_Desc {
		size     = u32(size_of(kne.KNE_Class_Desc)),
		version  = kne.ABI_MAJOR,
		name     = kne.str("HelloService"),
		base     = kne.str("Service"),
		flags    = kne.CLASS_SERVICE,
		methods  = kne.str("Ping,Echo"),
		namecall = service_namecall,
	}
	if host.classes.register(ext, &service) == 0 {
		return 0
	}

	return 1
}

on_start :: proc "c" (ext: kne.KNE_Extension) -> i32 {
	return 1
}

on_stop :: proc "c" (ext: kne.KNE_Extension) {}

on_unload :: proc "c" (ext: kne.KNE_Extension) {}

on_update :: proc "c" (ext: kne.KNE_Extension, delta_time: f64) {}

@(export)
kne_extension_entry :: proc "c" (new_host: ^kne.KNE_Host) -> ^kne.KNE_Extension_Desc {
	context = runtime.default_context()
	host = new_host
	desc = kne.KNE_Extension_Desc {
		size      = u32(size_of(kne.KNE_Extension_Desc)),
		abi_major = kne.ABI_MAJOR,
		abi_minor = kne.ABI_MINOR,
		id        = kne.str("kne.hello"),
		name      = kne.str("Hello KNE"),
		version   = kne.str("1.0.0"),
		author    = kne.str("Kinemium"),
		on_load   = on_load,
		on_start  = on_start,
		on_stop   = on_stop,
		on_unload = on_unload,
		on_update = on_update,
	}
	return &desc
}


