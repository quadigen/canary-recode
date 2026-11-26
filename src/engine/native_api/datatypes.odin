package native_api

import classes "../classes"
import datatypes "../datatypes"
import vm "../vm"
import odin_runtime "base:runtime"
import "core:strings"

Datatype_Construct_Fn :: proc "c" (
	ctx: ^Context,
	data: rawptr,
	count: u32,
	arguments: [^]SDK_Value,
) -> bool

Datatype_Codec_Encode_Fn :: proc "c" (
	ctx: ^Context,
	data: rawptr,
	buffer: rawptr,
	capacity: u64,
	out_size: ^u64,
) -> i32

Datatype_Codec_Decode_Fn :: proc "c" (
	ctx: ^Context,
	data: rawptr,
	input: rawptr,
	size: u64,
) -> bool

Datatype_Binary_Fn :: proc "c" (ctx: ^Context, left: rawptr, right: rawptr, output: rawptr) -> bool
Datatype_Equal_Fn :: proc "c" (ctx: ^Context, left: rawptr, right: rawptr) -> bool
Datatype_String_Fn :: proc "c" (ctx: ^Context, value: rawptr) -> cstring

Datatype_Description :: struct {
	size:           u32,
	flags:          u32,
	name:           cstring,
	library:        cstring,
	data_size:      u64,
	wire_version:   u32,
	property_count: u32,
	method_count:   u32,
	properties:     [Class_Property_Max]Class_Property,
	methods:        [Class_Method_Max]Class_Method,
	on_construct:   Datatype_Construct_Fn,
	on_destroy:     Class_Construct_Fn,
	on_encode:      Datatype_Codec_Encode_Fn,
	on_decode:      Datatype_Codec_Decode_Fn,
	on_add:         Datatype_Binary_Fn,
	on_subtract:    Datatype_Binary_Fn,
	on_multiply:    Datatype_Binary_Fn,
	on_divide:      Datatype_Binary_Fn,
	on_negate:      Datatype_Binary_Fn,
	on_equal:       Datatype_Equal_Fn,
	on_string:      Datatype_String_Fn,
}

Native_Datatype_Registration :: struct {
	ctx:     ^Context,
	desc:    Datatype_Description,
	name:    string,
	library: string,
	binding: vm.Userdata_Binding,
	tag:     i32,
}

Native_Datatype_Value :: struct {
	owner:  ^Native_Datatype_Registration,
	buffer: []u8,
}

datatype_find :: proc(ctx: ^Context, name: string) -> ^Native_Datatype_Registration {
	if ctx == nil {return nil}
	for reg in ctx.native_datatypes {
		if reg != nil && reg.name == name {return reg}
	}
	return nil
}

datatype_find_property :: proc(
	reg: ^Native_Datatype_Registration,
	name: string,
) -> ^Class_Property {
	if reg == nil {return nil}
	for i in 0 ..< int(reg.desc.property_count) {
		prop := &reg.desc.properties[i]
		if string(prop.name) == name {return prop}
	}
	return nil
}

datatype_find_method :: proc(reg: ^Native_Datatype_Registration, name: string) -> ^Class_Method {
	if reg == nil {return nil}
	for i in 0 ..< int(reg.desc.method_count) {
		method := &reg.desc.methods[i]
		if string(method.name) == name {return method}
	}
	return nil
}

datatype_value_data :: proc(value: ^Native_Datatype_Value) -> rawptr {
	if value == nil || len(value.buffer) == 0 {return nil}
	return raw_data(value.buffer)
}

datatype_wrapper_new :: proc(reg: ^Native_Datatype_Registration) -> ^Native_Datatype_Value {
	if reg == nil || reg.ctx == nil || !reg.ctx.active {return nil}
	wrapper := new(Native_Datatype_Value)
	wrapper.owner = reg
	wrapper.buffer = make([]u8, max(1, int(reg.desc.data_size)))
	return wrapper
}

datatype_wrapper_destroy :: proc(value, opaque: rawptr) {
	context = odin_runtime.default_context()
	wrapper := cast(^Native_Datatype_Value)value
	reg := cast(^Native_Datatype_Registration)opaque
	if wrapper == nil {return}
	if reg != nil && reg.ctx != nil && reg.ctx.active && reg.desc.on_destroy != nil {
		reg.desc.on_destroy(reg.ctx, datatype_value_data(wrapper))
	}
	if reg != nil && len(wrapper.buffer) > 0 {
		base := uintptr(raw_data(wrapper.buffer))
		for i in 0 ..< int(reg.desc.property_count) {
			prop := &reg.desc.properties[i]
			native_field_destroy(prop.kind, base + uintptr(prop.offset))
		}
	}
	delete(wrapper.buffer)
	free(wrapper)
}

datatype_wrapper_push :: proc(
	L: ^vm.State,
	reg: ^Native_Datatype_Registration,
	wrapper: ^Native_Datatype_Value,
) {
	vm.PushUserdata(&vm.VM{L = L}, wrapper, &reg.binding)
}

datatype_stack_value :: proc(
	L: ^vm.State,
	ctx: ^Context,
	index: int,
	copies: ^[dynamic]cstring,
) -> SDK_Value {
	result: SDK_Value
	#partial switch vm.TypeOf(L, index) {
	case .Nil:
		result.kind = .Nil
	case .Boolean:
		result.kind = .Boolean
		result.boolean = vm.ArgBoolean(L, index)
	case .Number, .Integer:
		result.kind = .Number
		result.number = vm.ArgNumber(L, index)
	case .String:
		result.kind = .String
		str := strings.clone_to_cstring(vm.ArgString(L, index))
		append(copies, str)
		result.text = str
		result.text_length = u64(len(string(str)))
	case .Vector:
		result.kind = .Vector3
		result.vector.x, result.vector.y, result.vector.z = vm.ArgVector3(L, index)
	case .Userdata:
		binding := vm.UserdataBindingOf(L, index)
		if binding != nil && binding.name == "Instance" {
			result.kind = .Instance
			result.instance = register_handle(ctx, cast(^classes.Object)vm.UserdataValue(L, index))
		} else {
			result.kind = .Other
		}
	case:
		result.kind = .Other
	}
	return result
}

datatype_new :: proc "c" (L: ^vm.State) -> i32 {
	context = odin_runtime.default_context()
	reg := cast(^Native_Datatype_Registration)vm.UpvaluePointer(L)
	if reg == nil || reg.ctx == nil || !reg.ctx.active {return 0}
	count := vm.StackTop(L)
	if count > 32 {return vm.RaiseError(L, "too many native datatype arguments")}
	wrapper := datatype_wrapper_new(reg)
	if wrapper == nil {return 0}
	if reg.desc.on_construct != nil {
		arguments: [32]SDK_Value
		copies: [dynamic]cstring
		defer {
			for string_value in copies {delete(string_value)}
			delete(copies)
		}
		for i in 0 ..< count {
			arguments[i] = datatype_stack_value(L, reg.ctx, i + 1, &copies)
		}
		if !reg.desc.on_construct(
			reg.ctx,
			datatype_value_data(wrapper),
			u32(count),
			&arguments[0],
		) {
			datatype_wrapper_destroy(wrapper, reg)
			return vm.RaiseError(L, "native datatype construction failed")
		}
	}
	datatype_wrapper_push(L, reg, wrapper)
	return 1
}

datatype_get :: proc(L: ^vm.State, value, opaque: rawptr, key: string) -> bool {
	context = odin_runtime.default_context()
	reg := cast(^Native_Datatype_Registration)opaque
	wrapper := cast(^Native_Datatype_Value)value
	if reg == nil ||
	   reg.ctx == nil ||
	   !reg.ctx.active ||
	   wrapper == nil ||
	   wrapper.owner != reg {return false}
	prop := datatype_find_property(reg, key)
	if prop == nil {return false}
	return native_field_get(
		L,
		reg.ctx.datatypes,
		prop.kind,
		uintptr(datatype_value_data(wrapper)) + uintptr(prop.offset),
	)
}

datatype_set :: proc(L: ^vm.State, value, opaque: rawptr, key: string, index: int) -> bool {
	context = odin_runtime.default_context()
	reg := cast(^Native_Datatype_Registration)opaque
	wrapper := cast(^Native_Datatype_Value)value
	if reg == nil ||
	   reg.ctx == nil ||
	   !reg.ctx.active ||
	   wrapper == nil ||
	   wrapper.owner != reg {return false}
	prop := datatype_find_property(reg, key)
	if prop == nil || prop.read_only {return false}
	return native_field_set(
		L,
		reg.ctx.datatypes,
		prop.kind,
		uintptr(datatype_value_data(wrapper)) + uintptr(prop.offset),
		index,
	)
}

datatype_namecall :: proc(L: ^vm.State, value, opaque: rawptr, name: string) -> (i32, bool) {
	context = odin_runtime.default_context()
	reg := cast(^Native_Datatype_Registration)opaque
	wrapper := cast(^Native_Datatype_Value)value
	if reg == nil ||
	   reg.ctx == nil ||
	   !reg.ctx.active ||
	   wrapper == nil ||
	   wrapper.owner != reg {return 0, false}
	method := datatype_find_method(reg, name)
	if method == nil || method.callback == nil {return 0, false}
	count := vm.StackTop(L) - 1
	if count < 0 || count > 32 {return 0, true}
	args: [32]SDK_Value
	copies: [dynamic]cstring
	defer {
		for string_value in copies {delete(string_value)}
		delete(copies)
	}
	for i in 0 ..< count {
		args[i] = datatype_stack_value(L, reg.ctx, i + 2, &copies)
	}
	result: SDK_Value
	if !method.callback(reg.ctx, datatype_value_data(wrapper), u32(count), &args[0], &result) {
		return 0, true
	}
	if !sdk_push_value(reg.ctx, result) {vm.PushNil(L)}
	return 1, true
}

datatype_string :: proc(value, opaque: rawptr) -> string {
	context = odin_runtime.default_context()
	reg := cast(^Native_Datatype_Registration)opaque
	wrapper := cast(^Native_Datatype_Value)value
	if reg == nil {return "NativeDatatype"}
	if reg.ctx != nil &&
	   reg.ctx.active &&
	   wrapper != nil &&
	   wrapper.owner == reg &&
	   reg.desc.on_string != nil {
		result := reg.desc.on_string(reg.ctx, datatype_value_data(wrapper))
		if result != nil {return string(result)}
	}
	return reg.name
}

native_datatype_binary :: proc(
	L: ^vm.State,
	value, opaque: rawptr,
	self_index, other_index: int,
	callback: Datatype_Binary_Fn,
) -> bool {
	context = odin_runtime.default_context()
	_ = self_index
	reg := cast(^Native_Datatype_Registration)opaque
	left := cast(^Native_Datatype_Value)value
	if reg == nil ||
	   reg.ctx == nil ||
	   !reg.ctx.active ||
	   callback == nil ||
	   left == nil ||
	   left.owner != reg ||
	   vm.UserdataBindingOf(L, other_index) != &reg.binding {return false}
	right := cast(^Native_Datatype_Value)vm.UserdataValue(L, other_index)
	if right == nil || right.owner != reg {return false}
	result := datatype_wrapper_new(reg)
	if result == nil {return false}
	if !callback(
		reg.ctx,
		datatype_value_data(left),
		datatype_value_data(right),
		datatype_value_data(result),
	) {
		datatype_wrapper_destroy(result, reg)
		return false
	}
	datatype_wrapper_push(L, reg, result)
	return true
}

native_datatype_add :: proc(
	L: ^vm.State,
	value, opaque: rawptr,
	self_index, other_index: int,
) -> bool {
	reg := cast(^Native_Datatype_Registration)opaque
	return native_datatype_binary(L, value, opaque, self_index, other_index, reg.desc.on_add)
}

native_datatype_subtract :: proc(
	L: ^vm.State,
	value, opaque: rawptr,
	self_index, other_index: int,
) -> bool {
	reg := cast(^Native_Datatype_Registration)opaque
	return native_datatype_binary(L, value, opaque, self_index, other_index, reg.desc.on_subtract)
}

native_datatype_multiply :: proc(
	L: ^vm.State,
	value, opaque: rawptr,
	self_index, other_index: int,
) -> bool {
	reg := cast(^Native_Datatype_Registration)opaque
	return native_datatype_binary(L, value, opaque, self_index, other_index, reg.desc.on_multiply)
}

native_datatype_divide :: proc(
	L: ^vm.State,
	value, opaque: rawptr,
	self_index, other_index: int,
) -> bool {
	reg := cast(^Native_Datatype_Registration)opaque
	return native_datatype_binary(L, value, opaque, self_index, other_index, reg.desc.on_divide)
}

native_datatype_negate :: proc(L: ^vm.State, value, opaque: rawptr) -> bool {
	context = odin_runtime.default_context()
	reg := cast(^Native_Datatype_Registration)opaque
	operand := cast(^Native_Datatype_Value)value
	if reg == nil ||
	   reg.ctx == nil ||
	   !reg.ctx.active ||
	   reg.desc.on_negate == nil ||
	   operand == nil ||
	   operand.owner != reg {return false}
	result := datatype_wrapper_new(reg)
	if result == nil {return false}
	if !reg.desc.on_negate(
		reg.ctx,
		datatype_value_data(operand),
		nil,
		datatype_value_data(result),
	) {
		datatype_wrapper_destroy(result, reg)
		return false
	}
	datatype_wrapper_push(L, reg, result)
	return true
}

native_datatype_equal :: proc(value, other, opaque: rawptr) -> bool {
	context = odin_runtime.default_context()
	reg := cast(^Native_Datatype_Registration)opaque
	left := cast(^Native_Datatype_Value)value
	right := cast(^Native_Datatype_Value)other
	if reg == nil ||
	   reg.ctx == nil ||
	   !reg.ctx.active ||
	   reg.desc.on_equal == nil ||
	   left == nil ||
	   right == nil ||
	   left.owner != reg ||
	   right.owner != reg {return false}
	return reg.desc.on_equal(reg.ctx, datatype_value_data(left), datatype_value_data(right))
}

datatype_codec_encode :: proc(
	user: rawptr,
	payload: rawptr,
	buffer: rawptr,
	capacity: uintptr,
	out_size: ^uintptr,
) -> i32 {
	context = odin_runtime.default_context()
	reg := cast(^Native_Datatype_Registration)user
	wrapper := cast(^Native_Datatype_Value)payload
	if reg == nil ||
	   reg.ctx == nil ||
	   !reg.ctx.active ||
	   reg.desc.on_encode == nil ||
	   wrapper == nil ||
	   wrapper.owner != reg {return -1}
	return reg.desc.on_encode(
		reg.ctx,
		datatype_value_data(wrapper),
		buffer,
		u64(capacity),
		cast(^u64)out_size,
	)
}

datatype_codec_decode :: proc(
	user: rawptr,
	L: ^vm.State,
	registry: ^datatypes.Registry,
	buffer: rawptr,
	size: uintptr,
) -> bool {
	context = odin_runtime.default_context()
	_ = registry
	reg := cast(^Native_Datatype_Registration)user
	if reg == nil || reg.ctx == nil || !reg.ctx.active || reg.desc.on_decode == nil {return false}
	wrapper := datatype_wrapper_new(reg)
	if wrapper == nil {return false}
	if !reg.desc.on_decode(reg.ctx, datatype_value_data(wrapper), buffer, u64(size)) {
		datatype_wrapper_destroy(wrapper, reg)
		return false
	}
	datatype_wrapper_push(L, reg, wrapper)
	return true
}

remove_datatype :: proc(reg: ^Native_Datatype_Registration) {
	if reg == nil || reg.ctx == nil {return}
	ctx := reg.ctx
	if ctx.datatypes != nil {
		vm.DetachBinding(&reg.binding)
		datatypes.Unregister_Extension_Codecs(ctx.datatypes, reg)
		datatypes.Release_Extension_Tag(ctx.datatypes, reg.tag)
	}
	if ctx.script_vm != nil && ctx.script_vm.L != nil {
		vm.PushNil(ctx.script_vm.L)
		vm.SetGlobal(ctx.script_vm.L, reg.name)
	}
	delete(reg.binding.name)
	for i in 0 ..< int(reg.desc.property_count) {delete(reg.desc.properties[i].name)}
	for i in 0 ..< int(reg.desc.method_count) {delete(reg.desc.methods[i].name)}
	delete(reg.name)
	delete(reg.library)
	reg.ctx = nil
	reg.tag = 0
	if ctx.root != nil {
		append(&ctx.root.retired_datatypes, reg)
	} else {
		free(reg)
	}
}

UnregisterOwnerDatatypes :: proc(ctx: ^Context) {
	if ctx == nil {return}
	for i := len(ctx.native_datatypes) - 1; i >= 0; i -= 1 {
		remove_datatype(ctx.native_datatypes[i])
	}
	delete(ctx.native_datatypes)
	ctx.native_datatypes = nil
}

@(export)
Kinemium_RegisterDatatype :: proc "c" (ctx: ^Context, description: ^Datatype_Description) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   !ctx.active ||
	   ctx.datatypes == nil ||
	   ctx.script_vm == nil ||
	   description == nil ||
	   description.size < u32(offset_of(Datatype_Description, on_add)) ||
	   description.name == nil ||
	   description.data_size == 0 ||
	   description.data_size > 1024 * 1024 ||
	   description.property_count > Class_Property_Max ||
	   description.method_count > Class_Method_Max {
		return false
	}
	name := string(description.name)
	if name == "" || datatype_find(ctx, name) != nil {return false}
	if description.flags != 0 && (description.on_encode == nil || description.on_decode == nil) {
		sdk_error(ctx, "persistable datatype needs encode and decode callbacks")
		return false
	}
	for i in 0 ..< int(description.property_count) {
		prop := &description.properties[i]
		size := native_property_size(prop.kind)
		if prop.name == nil ||
		   size == 0 ||
		   prop.offset > description.data_size ||
		   size > description.data_size - prop.offset {
			sdk_error(ctx, "invalid datatype field")
			return false
		}
	}
	for i in 0 ..< int(description.method_count) {
		method := &description.methods[i]
		if method.name == nil || method.callback == nil {
			sdk_error(ctx, "invalid datatype method")
			return false
		}
	}
	L := ctx.script_vm.L
	_ = vm.GetGlobal(L, name)
	exists := vm.TypeOf(L, -1) != .Nil
	vm.Pop(L)
	if exists {sdk_error(ctx, "datatype name already defined"); return false}

	tag := datatypes.Allocate_Extension_Tag(ctx.datatypes)
	if tag == 0 {sdk_error(ctx, "no datatype tags available"); return false}
	reg := new(Native_Datatype_Registration)
	reg.ctx = ctx
	reg.tag = tag
	reg.name = strings.clone(name)
	if description.library != nil {
		reg.library = strings.clone(string(description.library))
	}
	reg.desc = Datatype_Description {
		size           = description.size,
		flags          = description.flags,
		name           = description.name,
		library        = description.library,
		data_size      = description.data_size,
		wire_version   = description.wire_version,
		property_count = description.property_count,
		method_count   = description.method_count,
		properties     = description.properties,
		methods        = description.methods,
		on_construct   = description.on_construct,
		on_destroy     = description.on_destroy,
		on_encode      = description.on_encode,
		on_decode      = description.on_decode,
	}
	if description.size >=
	   u32(offset_of(Datatype_Description, on_add) + size_of(Datatype_Binary_Fn)) {
		reg.desc.on_add = description.on_add
	}
	if description.size >=
	   u32(offset_of(Datatype_Description, on_subtract) + size_of(Datatype_Binary_Fn)) {
		reg.desc.on_subtract = description.on_subtract
	}
	if description.size >=
	   u32(offset_of(Datatype_Description, on_multiply) + size_of(Datatype_Binary_Fn)) {
		reg.desc.on_multiply = description.on_multiply
	}
	if description.size >=
	   u32(offset_of(Datatype_Description, on_divide) + size_of(Datatype_Binary_Fn)) {
		reg.desc.on_divide = description.on_divide
	}
	if description.size >=
	   u32(offset_of(Datatype_Description, on_negate) + size_of(Datatype_Binary_Fn)) {
		reg.desc.on_negate = description.on_negate
	}
	if description.size >=
	   u32(offset_of(Datatype_Description, on_equal) + size_of(Datatype_Equal_Fn)) {
		reg.desc.on_equal = description.on_equal
	}
	if description.size >=
	   u32(offset_of(Datatype_Description, on_string) + size_of(Datatype_String_Fn)) {
		reg.desc.on_string = description.on_string
	}
	for i in 0 ..< int(description.property_count) {
		reg.desc.properties[i].name = strings.clone_to_cstring(
			string(description.properties[i].name),
		)
	}
	for i in 0 ..< int(description.method_count) {
		reg.desc.methods[i].name = strings.clone_to_cstring(string(description.methods[i].name))
	}
	reg.binding = vm.Userdata_Binding {
		name         = strings.clone(reg.name),
		tag          = tag,
		ctx          = reg,
		owner        = ctx.datatypes,
		track_values = true,
		get          = datatype_get,
		set          = datatype_set,
		namecall     = datatype_namecall,
		string       = datatype_string,
		destroy      = datatype_wrapper_destroy,
		add          = native_datatype_add if reg.desc.on_add != nil else nil,
		subtract     = native_datatype_subtract if reg.desc.on_subtract != nil else nil,
		multiply     = native_datatype_multiply if reg.desc.on_multiply != nil else nil,
		divide       = native_datatype_divide if reg.desc.on_divide != nil else nil,
		negate       = native_datatype_negate if reg.desc.on_negate != nil else nil,
		equal        = native_datatype_equal if reg.desc.on_equal != nil else nil,
	}
	if description.flags != 0 {
		if !datatypes.Register_Extension_Codec(
			ctx.datatypes,
			datatypes.Extension_Codec {
				flags = description.flags,
				extension_id = ctx.plugin_id,
				type_name = reg.name,
				wire_version = description.wire_version,
				binding = &reg.binding,
				encode = datatype_codec_encode,
				decode = datatype_codec_decode,
				user = reg,
			},
		) {
			remove_datatype(reg)
			return false
		}
	}
	vm.NewTable(L, 0, 1)
	vm.PushLightUserdata(L, reg)
	vm.PushFunction(L, reg.name, datatype_new, 1)
	vm.SetField(L, -2, "new")
	vm.SetReadOnly(L, -1)
	vm.SetGlobalFromStack(ctx.script_vm, reg.name)
	append(&ctx.native_datatypes, reg)
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_UnregisterDatatype :: proc "c" (ctx: ^Context, name: cstring) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || name == nil {return false}
	for reg, i in ctx.native_datatypes {
		if reg.name == string(name) {
			remove_datatype(reg)
			ordered_remove(&ctx.native_datatypes, i)
			return true
		}
	}
	return false
}
