package extensions

import tracy "../util/odin-tracy"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:mem"
import "core:strings"

KNE_MAX_RESULTS :: 16

Retained_Callback :: struct {
	record: ^Extension_Record,
	L:      ^vm.State,
	ref:    i32,
}

Extension_Datatype_Value :: struct {
	owner:      ^Extension_Datatype,
	payload:    rawptr,
	references: int,
}

Extension_Datatype :: struct {
	record:    ^Extension_Record,
	desc:      KNE_Datatype_Desc,
	tag:       u32,
	type_name: string,
	library:   string,
	binding:   vm.Userdata_Binding,
}

Signal_Bridge :: struct {
	record:   ^Extension_Record,
	native:   KNE_Signal_Native_Fn,
	callback: ^Retained_Callback,
}


@(private)
kne_engine_datatype_for_kind :: proc(kind: KNE_Value_Kind) -> ^KNE_Engine_Datatype {
	for &entry in KNE_Engine_Datatypes {
		if entry.kind == kind {
			return &entry
		}
	}
	return nil
}

@(private)
kne_engine_datatype_for_binding :: proc(
	registry: ^datatypes.Registry,
	binding: ^vm.Userdata_Binding,
) -> ^KNE_Engine_Datatype {
	if registry == nil || binding == nil || binding.owner != rawptr(registry) {
		return nil
	}
	for &entry in KNE_Engine_Datatypes {
		if entry.tag == u32(binding.tag) {
			return &entry
		}
	}
	return nil
}

@(private)
kne_engine_datatype_by_name :: proc(name: string) -> ^KNE_Engine_Datatype {
	for &entry in KNE_Engine_Datatypes {
		if entry.name == name {
			return &entry
		}
	}
	return nil
}

@(private)
kne_push_engine_value :: proc(
	L: ^vm.State,
	registry: ^datatypes.Registry,
	value: ^KNE_Value,
) -> bool {
	if registry == nil {
		return false
	}
	entry := kne_engine_datatype_for_kind(value.kind)
	if entry == nil {
		return false
	}
	entry.push(L, registry, rawptr(&value.data))
	return true
}

@(private)
kne_push_datatype_handle :: proc(
	L: ^vm.State,
	registry: ^datatypes.Registry,
	value: ^KNE_Value,
) -> bool {
	if source := cast(^vm.State)value.data.datatype.source_vm; source != nil {
		index := int(value.data.datatype.source_index)
		if vm.UserdataValue(source, index) != value.data.datatype.handle {return false}
		vm.CopyValueToThread(source, L, index)
		return true
	}
	if value.data.datatype.tag == enums.ENUM_ITEM_TAG {
		item := cast(^enums.Enum_Item)value.data.datatype.handle
		if item == nil || item.enum_type == nil || registry == nil {return false}
		_ = enums.Push_Item_By_Value(L, registry.enums, item.enum_type.name, item.value)
		return true
	}
	name := KNE_String_To(value.data.datatype.type_name)
	if entry := kne_engine_datatype_by_name(name); entry != nil {
		entry.push(L, registry, value.data.datatype.handle)
		return true
	}
	wrapper := cast(^Extension_Datatype_Value)value.data.datatype.handle
	if wrapper != nil && wrapper.owner != nil {
		wrapper.references += 1
		vm.PushUserdata(&vm.VM{L = L}, wrapper, &wrapper.owner.binding)
		return true
	}
	return false
}


@(private)
extension_datatype_find :: proc(record: ^Extension_Record, name: string) -> ^Extension_Datatype {
	if record == nil {
		return nil
	}
	for datatype in record.datatypes {
		if datatype != nil && datatype.tag != 0 && datatype.type_name == name {
			return datatype
		}
	}
	return nil
}

@(private)
extension_datatype_alloc :: proc(dt: ^Extension_Datatype) -> rawptr {
	size := int(dt.desc.value_size)
	if size <= 0 {
		size = 1
	}
	payload, err := mem.alloc(size, 16)
	if err != nil {
		return nil
	}
	mem.set(payload, 0, size)
	return payload
}

@(private)
extension_datatype_push :: proc(L: ^vm.State, dt: ^Extension_Datatype, payload: rawptr) {
	wrapper := new(Extension_Datatype_Value)
	wrapper^ = Extension_Datatype_Value {
		owner      = dt,
		payload    = payload,
		references = 1,
	}
	vm.PushUserdata(&vm.VM{L = L}, wrapper, &dt.binding)
}

@(private)
extension_datatype_construct :: proc(
	dt: ^Extension_Datatype,
	L: ^vm.State,
	first: int,
	count: int,
) -> bool {
	first_root := len(dt.record.result_roots)
	defer release_result_roots(dt.record, first_root)
	payload := extension_datatype_alloc(dt)
	if payload == nil {
		return false
	}
	if dt.desc.construct != nil {
		args := make([]KNE_Value, count)
		defer delete(args)
		for index in 0 ..< count {
			args[index] = stack_kne_value(L, dt.record.ctx.datatype_registry, first + index)
		}
		if dt.desc.construct(rawptr(dt.record), payload, raw_data(args), i32(count)) == 0 {
			free(payload)
			return false
		}
	}
	extension_datatype_push(L, dt, payload)
	return true
}

@(private)
ext_datatype_destroy :: proc(value, ctx: rawptr) {
	wrapper := cast(^Extension_Datatype_Value)value
	dt := cast(^Extension_Datatype)ctx
	if wrapper == nil {
		return
	}
	wrapper.references -= 1
	if wrapper.references > 0 {return}
	if dt != nil && dt.desc.destroy != nil && wrapper.payload != nil {
		dt.desc.destroy(rawptr(dt.record), wrapper.payload)
	}
	if wrapper.payload != nil {
		free(wrapper.payload)
	}
	free(wrapper)
}

@(private)
ext_datatype_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	wrapper := cast(^Extension_Datatype_Value)value
	dt := cast(^Extension_Datatype)ctx
	if wrapper == nil || dt == nil || dt.desc.get == nil {
		return false
	}
	first_root := len(dt.record.result_roots)
	defer release_result_roots(dt.record, first_root)
	out := kne_value_nil()
	if dt.desc.get(rawptr(dt.record), wrapper.payload, KNE_String_From(key), &out) == 0 {
		return false
	}
	push_kne_value(L, dt.record.ctx.datatype_registry, &out)
	return true
}

@(private)
ext_datatype_set :: proc(L: ^vm.State, value, ctx: rawptr, key: string, value_index: int) -> bool {
	wrapper := cast(^Extension_Datatype_Value)value
	dt := cast(^Extension_Datatype)ctx
	if wrapper == nil || dt == nil || dt.desc.set == nil {
		return false
	}
	first_root := len(dt.record.result_roots)
	defer release_result_roots(dt.record, first_root)
	input := stack_kne_value(L, dt.record.ctx.datatype_registry, value_index)
	return dt.desc.set(rawptr(dt.record), wrapper.payload, KNE_String_From(key), &input) != 0
}

@(private)
ext_datatype_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	wrapper := cast(^Extension_Datatype_Value)value
	dt := cast(^Extension_Datatype)ctx
	if wrapper == nil || dt == nil || dt.desc.namecall == nil {
		return 0, false
	}
	first_root := len(dt.record.result_roots)
	defer release_result_roots(dt.record, first_root)
	count := vm.StackTop(L) - 1
	if count < 0 {
		count = 0
	}
	args := make([]KNE_Value, count)
	defer delete(args)
	for index in 0 ..< count {
		args[index] = stack_kne_value(L, dt.record.ctx.datatype_registry, index + 2)
	}
	out: [KNE_MAX_RESULTS]KNE_Value
	args_ptr := &args[0] if len(args) > 0 else nil
	result := dt.desc.namecall(
		rawptr(dt.record),
		wrapper.payload,
		KNE_String_From(method),
		args_ptr,
		i32(count),
		&out[0],
		KNE_MAX_RESULTS,
	)
	if result <= 0 {
		return 0, false
	}
	pushed: i32
	for index in 0 ..< min(int(result), KNE_MAX_RESULTS) {
		push_kne_value(L, dt.record.ctx.datatype_registry, &out[index])
		pushed += 1
	}
	return pushed, true
}

@(private)
ext_datatype_string :: proc(value, ctx: rawptr) -> string {
	wrapper := cast(^Extension_Datatype_Value)value
	dt := cast(^Extension_Datatype)ctx
	if wrapper == nil || dt == nil {
		return "userdata"
	}
	if dt.desc.tostring != nil {
		out: KNE_String
		if dt.desc.tostring(rawptr(dt.record), wrapper.payload, &out) != 0 {
			return KNE_String_To(out)
		}
	}
	return dt.type_name
}

@(private)
ext_datatype_equal :: proc(value, other, ctx: rawptr) -> bool {
	wrapper := cast(^Extension_Datatype_Value)value
	other_wrapper := cast(^Extension_Datatype_Value)other
	dt := cast(^Extension_Datatype)ctx
	if wrapper == nil || other_wrapper == nil || dt == nil || dt.desc.equal == nil {
		return false
	}
	out: i32
	if dt.desc.equal(rawptr(dt.record), wrapper.payload, other_wrapper.payload, &out) == 0 {
		return false
	}
	return out != 0
}

@(private)
ext_datatype_binary :: proc(
	L: ^vm.State,
	value, ctx: rawptr,
	self_index, other_index: int,
	fn: KNE_Ext_Datatype_Binary_Fn,
) -> bool {
	wrapper := cast(^Extension_Datatype_Value)value
	dt_binding := cast(^Extension_Datatype)ctx
	if dt_binding == nil ||
	   vm.UserdataBindingOf(L, other_index) != &dt_binding.binding {return false}
	other_wrapper := cast(^Extension_Datatype_Value)vm.UserdataValue(L, other_index)
	dt := cast(^Extension_Datatype)ctx
	if wrapper == nil || other_wrapper == nil || dt == nil || fn == nil {
		return false
	}
	first_root := len(dt.record.result_roots)
	defer release_result_roots(dt.record, first_root)
	out := kne_value_nil()
	if fn(rawptr(dt.record), wrapper.payload, other_wrapper.payload, &out) == 0 {
		return false
	}
	push_kne_value(L, dt.record.ctx.datatype_registry, &out)
	return true
}

@(private)
ext_datatype_add :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	dt := cast(^Extension_Datatype)ctx
	return ext_datatype_binary(L, value, ctx, self_index, other_index, dt.desc.add)
}

@(private)
ext_datatype_subtract :: proc(
	L: ^vm.State,
	value, ctx: rawptr,
	self_index, other_index: int,
) -> bool {
	dt := cast(^Extension_Datatype)ctx
	return ext_datatype_binary(L, value, ctx, self_index, other_index, dt.desc.subtract)
}

@(private)
ext_datatype_multiply :: proc(
	L: ^vm.State,
	value, ctx: rawptr,
	self_index, other_index: int,
) -> bool {
	dt := cast(^Extension_Datatype)ctx
	return ext_datatype_binary(L, value, ctx, self_index, other_index, dt.desc.multiply)
}

@(private)
ext_datatype_divide :: proc(
	L: ^vm.State,
	value, ctx: rawptr,
	self_index, other_index: int,
) -> bool {
	dt := cast(^Extension_Datatype)ctx
	return ext_datatype_binary(L, value, ctx, self_index, other_index, dt.desc.divide)
}

@(private)
ext_datatype_negate :: proc(L: ^vm.State, value, ctx: rawptr) -> bool {
	wrapper := cast(^Extension_Datatype_Value)value
	dt := cast(^Extension_Datatype)ctx
	if wrapper == nil || dt == nil || dt.desc.negate == nil {
		return false
	}
	first_root := len(dt.record.result_roots)
	defer release_result_roots(dt.record, first_root)
	out := kne_value_nil()
	if dt.desc.negate(rawptr(dt.record), wrapper.payload, &out) == 0 {return false}
	push_kne_value(L, dt.record.ctx.datatype_registry, &out)
	return true
}

@(private)
ext_datatype_encode :: proc(
	user: rawptr,
	payload: rawptr,
	buffer: rawptr,
	capacity: uintptr,
	out_size: ^uintptr,
) -> i32 {
	dt := cast(^Extension_Datatype)user
	if dt == nil || dt.desc.encode == nil {
		return -1
	}
	wrapper := cast(^Extension_Datatype_Value)payload
	if wrapper == nil || wrapper.owner != dt {return -1}
	return dt.desc.encode(rawptr(dt.record), wrapper.payload, buffer, capacity, out_size)
}

@(private)
ext_datatype_decode :: proc(
	user: rawptr,
	L: ^vm.State,
	registry: ^datatypes.Registry,
	data: rawptr,
	size: uintptr,
) -> bool {
	dt := cast(^Extension_Datatype)user
	if dt == nil || dt.desc.decode == nil {
		return false
	}
	payload := extension_datatype_alloc(dt)
	if payload == nil {
		return false
	}
	if dt.desc.decode(rawptr(dt.record), payload, data, size) == 0 {
		free(payload)
		return false
	}
	extension_datatype_push(L, dt, payload)
	return true
}

@(private)
kne_ext_datatype_new :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	dt := cast(^Extension_Datatype)vm.UpvaluePointer(L)
	if dt == nil || dt.tag == 0 {
		return 0
	}
	count := vm.StackTop(L)
	if !extension_datatype_construct(dt, L, 1, count) {
		return 0
	}
	return 1
}

kne_register_datatype :: proc "c" (ext: KNE_Extension, desc: ^KNE_Datatype_Desc) -> i32 {
	context = tracy.DefaultContext()
	record := record_of(ext)
	if record == nil ||
	   desc == nil ||
	   desc.size < u32(size_of(KNE_Datatype_Desc)) ||
	   desc.version != KNE_ABI_MAJOR ||
	   record.ctx == nil ||
	   record.ctx.datatype_registry == nil {
		return 0
	}
	registry := record.ctx.datatype_registry
	name := KNE_String_To(desc.type_name)
	if len(name) == 0 {
		return 0
	}
	if extension_datatype_find(record, name) != nil {
		return 0
	}
	tag := datatypes.Allocate_Extension_Tag(registry)
	if tag == 0 {
		return 0
	}

	dt := new(Extension_Datatype)
	dt^ = Extension_Datatype {
		record    = record,
		desc      = desc^,
		tag       = u32(tag),
		type_name = strings.clone(name),
		library   = strings.clone(KNE_String_To(desc.library)),
	}
	dt.binding = vm.Userdata_Binding {
		track_values = true,
		name         = dt.type_name,
		tag          = tag,
		ctx          = dt,
		owner        = registry,
		get          = ext_datatype_get,
		set          = ext_datatype_set,
		namecall     = ext_datatype_namecall,
		string       = ext_datatype_string,
		destroy      = ext_datatype_destroy,
		add          = ext_datatype_add,
		subtract     = ext_datatype_subtract,
		multiply     = ext_datatype_multiply,
		divide       = ext_datatype_divide,
		negate       = ext_datatype_negate,
		equal        = ext_datatype_equal,
	}
	datatypes.Register_Extension_Codec(
		registry,
		datatypes.Extension_Codec {
			flags = desc.flags,
			extension_id = record.manifest.id,
			type_name = dt.type_name,
			wire_version = desc.wire_version,
			binding = &dt.binding,
			encode = ext_datatype_encode,
			decode = ext_datatype_decode,
			user = dt,
		},
	)
	append(&record.datatypes, dt)
	return 1
}

@(private)
extension_datatype_release :: proc(record: ^Extension_Record, dt: ^Extension_Datatype) {
	if record == nil || dt == nil {
		return
	}
	vm.DetachBinding(&dt.binding)
	registry := record.ctx.datatype_registry
	if registry != nil {
		datatypes.Unregister_Extension_Codecs(registry, dt)
		if dt.tag != 0 {
			datatypes.Release_Extension_Tag(registry, i32(dt.tag))
		}
	}
	dt.tag = 0
}

kne_unregister_datatype :: proc "c" (ext: KNE_Extension, type_name: KNE_String) -> i32 {
	context = tracy.DefaultContext()
	record := record_of(ext)
	if record == nil {
		return 0
	}
	name := KNE_String_To(type_name)
	for dt in record.datatypes {
		if dt != nil && dt.type_name == name {
			extension_datatype_release(record, dt)
			vm.PushNil(record.ctx.vm_state.L)
			vm.SetGlobalFromStack(record.ctx.vm_state, dt.type_name)

			return 1
		}
	}
	return 0
}

kne_datatype_registered :: proc "c" (ext: KNE_Extension, type_name: KNE_String) -> i32 {
	context = tracy.DefaultContext()
	record := record_of(ext)
	if record == nil {
		return 0
	}
	name := KNE_String_To(type_name)
	if extension_datatype_find(record, name) != nil {
		return 1
	}
	if kne_engine_datatype_by_name(name) != nil {
		return 1
	}
	return 0
}

kne_datatypes_push :: proc "c" (ext: KNE_Extension, L: KNE_VM, value: ^KNE_Value) -> i32 {
	context = tracy.DefaultContext()
	record := record_of(ext)
	state := state_of_vm(L)
	if record == nil || state == nil || value == nil {
		return 0
	}
	push_kne_value(state, record.ctx.datatype_registry, value)
	return 1
}

kne_datatypes_get :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32, out: ^KNE_Value) -> i32 {
	context = tracy.DefaultContext()
	record := record_of(ext)
	state := state_of_vm(L)
	if record == nil || state == nil || out == nil {
		return 0
	}
	out^ = stack_kne_value(state, record.ctx.datatype_registry, int(index))
	return 1
}


@(private)
kne_operation :: proc(
	record: ^Extension_Record,
	source: string,
	value: ^KNE_Value,
	key: KNE_String,
	args: ^KNE_Value,
	count: i32,
	out: ^KNE_Value,
	capacity: i32,
) -> i32 {
	if record == nil ||
	   record.ctx == nil ||
	   record.ctx.vm_state == nil ||
	   count < 0 ||
	   capacity < 0 ||
	   (count > 0 && args == nil) ||
	   (capacity > 0 && out == nil) {return -1}
	parent := record.ctx.vm_state.L
	top := vm.StackTop(parent)
	defer vm.SetStackTop(parent, top)
	L := vm.NewThread(parent)
	ref := vm.RetainValue(parent, -1)
	append(&record.result_roots, ref)
	ok, err := vm.LoadSource(record.ctx.vm_state, L, source, "KNE")
	if !ok {delete(record.last_error); record.last_error = err; return -1}
	push_kne_value(L, record.ctx.datatype_registry, value)
	vm.PushString(L, KNE_String_To(key))
	values := cast([^]KNE_Value)args
	for index in 0 ..< int(count) {push_kne_value(L, record.ctx.datatype_registry, &values[index])}
	ok, err = vm.ProtectedCall(L, int(count) + 2, -1)
	if !ok {delete(record.last_error); record.last_error = strings.clone(err); return -1}
	results := min(vm.StackTop(L), int(capacity))
	outputs := cast([^]KNE_Value)out
	for index in 0 ..< results {outputs[index] = stack_kne_value(L, record.ctx.datatype_registry, index + 1)}
	return i32(results)
}

kne_datatypes_construct :: proc "c" (
	ext: KNE_Extension,
	type_name: KNE_String,
	args: ^KNE_Value,
	arg_count: i32,
	out: ^KNE_Value,
) -> i32 {
	context = tracy.DefaultContext()
	value := kne_value_nil()
	result := kne_operation(
		record_of(ext),
		"local _, name = ...; local a=table.pack(...); return getfenv()[name].new(table.unpack(a,3,a.n))",
		&value,
		type_name,
		args,
		arg_count,
		out,
		1,
	)
	return 1 if result == 1 else 0
}

kne_datatypes_get_field :: proc "c" (
	ext: KNE_Extension,
	value: ^KNE_Value,
	field: KNE_String,
	out: ^KNE_Value,
) -> i32 {
	context = tracy.DefaultContext()
	result := kne_operation(
		record_of(ext),
		"local v,k=...; return v[k]",
		value,
		field,
		nil,
		0,
		out,
		1,
	)
	return 1 if result == 1 else 0
}

kne_datatypes_set_field :: proc "c" (
	ext: KNE_Extension,
	value: ^KNE_Value,
	field: KNE_String,
	input: ^KNE_Value,
) -> i32 {
	context = tracy.DefaultContext()
	result := kne_operation(
		record_of(ext),
		"local v,k,x=...; v[k]=x; return true",
		value,
		field,
		input,
		1,
		nil,
		0,
	)
	return 1 if result >= 0 else 0
}

kne_datatypes_call :: proc "c" (
	ext: KNE_Extension,
	value: ^KNE_Value,
	method: KNE_String,
	args: ^KNE_Value,
	arg_count: i32,
	out: ^KNE_Value,
	out_capacity: i32,
) -> i32 {
	context = tracy.DefaultContext()
	return kne_operation(
		record_of(ext),
		"local v,k=...; local a=table.pack(...); return v[k](v,table.unpack(a,3,a.n))",
		value,
		method,
		args,
		arg_count,
		out,
		out_capacity,
	)
}


kne_vm_is_function :: proc "c" (L: KNE_VM, index: i32) -> i32 {
	context = tracy.DefaultContext()
	state := state_of_vm(L)
	if state == nil {
		return 0
	}
	return vm.IsFunction(state, int(index)) ? 1 : 0
}

kne_vm_get_value :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32, out: ^KNE_Value) -> i32 {
	context = tracy.DefaultContext()
	record := record_of(ext)
	state := state_of_vm(L)
	if record == nil || state == nil || out == nil {
		return 0
	}
	out^ = stack_kne_value(state, record.ctx.datatype_registry, int(index))
	return 1
}

kne_vm_register_global_datatype :: proc "c" (
	ext: KNE_Extension,
	L: KNE_VM,
	library: KNE_String,
) -> i32 {
	context = tracy.DefaultContext()
	record := record_of(ext)
	state := state_of_vm(L)
	if state == nil && record != nil && record.ctx != nil && record.ctx.vm_state != nil {
		state = record.ctx.vm_state.L
	}
	if record == nil || state == nil {
		return 0
	}
	dt := extension_datatype_find(record, KNE_String_To(library))
	if dt == nil {
		return 0
	}
	vm.NewTable(state, 0, 4)
	vm.PushLightUserdata(state, dt)
	vm.PushFunction(state, dt.type_name, kne_ext_datatype_new, 1)
	vm.SetField(state, -2, "new")
	vm.SetReadOnly(state, -1)
	vm.SetGlobalFromStack(&vm.VM{L = state}, dt.type_name)
	append(&record.globals, strings.clone(dt.type_name))
	return 1
}


kne_instance_invoke :: proc "c" (
	ext: KNE_Extension,
	instance: KNE_Instance,
	method: KNE_String,
	args: ^KNE_Value,
	arg_count: i32,
	out: ^KNE_Value,
	out_capacity: i32,
) -> i32 {
	context = tracy.DefaultContext()
	if instance == nil {return -1}
	value := kne_value_nil()
	value.kind = .Instance
	value.data.instance = rawptr(instance)
	return kne_datatypes_call(ext, &value, method, args, arg_count, out, out_capacity)
}


@(private)
call_retained_values :: proc(
	callback: ^Retained_Callback,
	args: ^KNE_Value,
	arg_count: int,
	out: ^KNE_Value,
	out_capacity: int,
) -> i32 {
	if callback == nil ||
	   callback.L == nil ||
	   callback.ref <= 0 ||
	   arg_count < 0 ||
	   out_capacity < 0 ||
	   (arg_count > 0 && args == nil) ||
	   (out_capacity > 0 && out == nil) {
		return -1
	}
	top := vm.StackTop(callback.L)
	defer vm.SetStackTop(callback.L, top)
	thread := vm.NewThread(callback.L)
	append(&callback.record.result_roots, vm.RetainValue(callback.L, -1))
	vm.PushRegistryReference(thread, callback.ref)
	arg_values := cast([^]KNE_Value)(args)
	out_values := cast([^]KNE_Value)(out)
	for index in 0 ..< arg_count {
		push_kne_value(thread, callback.record.ctx.datatype_registry, &arg_values[index])
	}
	ok, err := vm.ProtectedCall(thread, arg_count, vm.MULTIPLE_RESULTS)
	if !ok {
		delete(callback.record.last_error)
		callback.record.last_error = strings.clone(err)
		delete(err)
		return -1
	}
	results := vm.StackTop(thread)
	if results > out_capacity {
		results = out_capacity
	}
	for index in 0 ..< results {
		out_values[index] = stack_kne_value(
			thread,
			callback.record.ctx.datatype_registry,
			index + 1,
		)
	}
	return i32(results)
}

@(private)
call_retained_stack :: proc(callback: ^Retained_Callback, L: ^vm.State, first: int) -> i32 {
	if callback == nil || L == nil {
		return 0
	}
	count := vm.StackTop(L) - first + 1
	if count < 0 {count = 0}
	args := make([]KNE_Value, count)
	defer delete(args)
	registry := callback.record.ctx.datatype_registry
	for index in 0 ..< count {
		args[index] = stack_kne_value(L, registry, first + index)
	}
	out: [KNE_MAX_RESULTS]KNE_Value
	return call_retained_values(callback, raw_data(args), count, &out[0], KNE_MAX_RESULTS)
}

kne_callbacks_retain :: proc "c" (ext: KNE_Extension, L: KNE_VM, index: i32) -> KNE_Callback {
	context = tracy.DefaultContext()
	record := record_of(ext)
	state := state_of_vm(L)
	if record == nil || state == nil || !vm.IsFunction(state, int(index)) {
		return nil
	}
	ref := vm.RetainValue(state, int(index))
	if ref <= 0 {
		return nil
	}
	callback := new(Retained_Callback)
	callback^ = Retained_Callback {
		record = record,
		L      = record.ctx.vm_state.L,
		ref    = ref,
	}
	append(&record.callbacks, callback)
	return rawptr(callback)
}

kne_callbacks_release :: proc "c" (ext: KNE_Extension, callback: KNE_Callback) {
	context = tracy.DefaultContext()
	record := record_of(ext)
	target := cast(^Retained_Callback)callback
	if record == nil || target == nil {
		return
	}
	for entry in record.callbacks {
		if entry == target {
			if target.ref > 0 && target.L != nil {
				vm.ReleaseValue(target.L, target.ref)
			}
			target.ref = 0
			return
		}
	}
}

kne_callbacks_valid :: proc "c" (ext: KNE_Extension, callback: KNE_Callback) -> i32 {
	context = tracy.DefaultContext()
	record := record_of(ext)
	target := cast(^Retained_Callback)callback
	if record == nil || target == nil {
		return 0
	}
	for entry in record.callbacks {
		if entry == target && entry.ref > 0 {
			return 1
		}
	}
	return 0
}

kne_callbacks_call :: proc "c" (
	ext: KNE_Extension,
	callback: KNE_Callback,
	args: ^KNE_Value,
	arg_count: i32,
	out: ^KNE_Value,
	out_capacity: i32,
) -> i32 {
	context = tracy.DefaultContext()
	if kne_callbacks_valid(ext, callback) == 0 {return -1}
	return call_retained_values(
		cast(^Retained_Callback)callback,
		args,
		int(arg_count),
		out,
		int(out_capacity),
	)
}


@(private)
signal_bridge_trampoline :: proc "c" (ctx: rawptr, L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	bridge := cast(^Signal_Bridge)ctx
	if bridge == nil || bridge.record == nil || bridge.record.state == .Unloaded {
		return 0
	}
	first_root := len(bridge.record.result_roots)
	defer release_result_roots(bridge.record, first_root)
	if bridge.native != nil {
		bridge.native(rawptr(bridge.record), rawptr(L))
		return 0
	}
	if bridge.callback != nil {
		return call_retained_stack(bridge.callback, L, 1)
	}
	return 0
}

@(private)
signal_connect :: proc(
	record: ^Extension_Record,
	signal: ^signals.Signal,
	native: KNE_Signal_Native_Fn,
	callback: ^Retained_Callback,
	once: bool,
) -> ^signals.KinemiumConnection {
	if record == nil ||
	   signal == nil ||
	   (native == nil && (callback == nil || callback.record != record || callback.ref <= 0)) {
		return nil
	}
	bridge := new(Signal_Bridge)
	bridge^ = Signal_Bridge {
		record   = record,
		native   = native,
		callback = callback,
	}
	append(&record.bridges, bridge)
	connection := signals.Connect_Native(signal, signal_bridge_trampoline, bridge, once)
	if connection == nil {
		ordered_remove(&record.bridges, len(record.bridges) - 1)
		free(bridge)
		return nil
	}
	append(&record.connections, connection)
	return connection
}

kne_signal_get :: proc "c" (
	ext: KNE_Extension,
	instance: KNE_Instance,
	property: KNE_String,
) -> KNE_Signal {
	context = tracy.DefaultContext()
	value := kne_value_nil()
	if kne_instances_get_property(ext, instance, property, &value) == 0 {
		return nil
	}
	if value.kind != .Signal {
		return nil
	}
	return KNE_Signal(value.data.signal)
}

kne_signal_connect_native :: proc "c" (
	ext: KNE_Extension,
	signal: KNE_Signal,
	callback: KNE_Signal_Native_Fn,
) -> KNE_Connection {
	context = tracy.DefaultContext()
	return rawptr(
		signal_connect(record_of(ext), cast(^signals.Signal)signal, callback, nil, false),
	)
}

kne_signal_connect_callback :: proc "c" (
	ext: KNE_Extension,
	signal: KNE_Signal,
	callback: KNE_Callback,
) -> KNE_Connection {
	context = tracy.DefaultContext()
	return rawptr(
		signal_connect(
			record_of(ext),
			cast(^signals.Signal)signal,
			nil,
			cast(^Retained_Callback)callback,
			false,
		),
	)
}

kne_signal_once_native :: proc "c" (
	ext: KNE_Extension,
	signal: KNE_Signal,
	callback: KNE_Signal_Native_Fn,
) -> KNE_Connection {
	context = tracy.DefaultContext()
	return rawptr(signal_connect(record_of(ext), cast(^signals.Signal)signal, callback, nil, true))
}

kne_signal_once_callback :: proc "c" (
	ext: KNE_Extension,
	signal: KNE_Signal,
	callback: KNE_Callback,
) -> KNE_Connection {
	context = tracy.DefaultContext()
	return rawptr(
		signal_connect(
			record_of(ext),
			cast(^signals.Signal)signal,
			nil,
			cast(^Retained_Callback)callback,
			true,
		),
	)
}

kne_signal_disconnect :: proc "c" (ext: KNE_Extension, connection: KNE_Connection) {
	context = tracy.DefaultContext()
	_ = record_of(ext)
	signals.Disconnect_Connection(cast(^signals.KinemiumConnection)connection)
}

kne_signal_connected :: proc "c" (ext: KNE_Extension, connection: KNE_Connection) -> i32 {
	context = tracy.DefaultContext()
	_ = record_of(ext)
	return signals.Connection_Connected(cast(^signals.KinemiumConnection)connection) ? 1 : 0
}

kne_signal_fire :: proc "c" (
	ext: KNE_Extension,
	signal: KNE_Signal,
	args: ^KNE_Value,
	arg_count: i32,
) -> i32 {
	context = tracy.DefaultContext()
	record := record_of(ext)
	if record == nil || record.ctx == nil || record.ctx.vm_state == nil || signal == nil {
		return 0
	}
	L := record.ctx.vm_state.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	arg_values := cast([^]KNE_Value)(args)
	for index in 0 ..< int(arg_count) {
		push_kne_value(L, record.ctx.datatype_registry, &arg_values[index])
	}
	signals.Fire_From_Stack(L, cast(^signals.Signal)signal, int(arg_count))
	return 1
}


@(private)
export_descriptor :: proc(
	ext: KNE_Extension,
	instance: KNE_Instance,
) -> ^classes.Class_Descriptor {
	record := record_of(ext)
	if record == nil || record.ctx == nil || instance == nil {
		return nil
	}
	object := cast(^classes.Object)instance
	if object.destroyed {
		return nil
	}
	return classes.Find_Class(record.ctx.class_registry, classes.Get_Class_Name(object))
}

kne_export_exists :: proc "c" (
	ext: KNE_Extension,
	instance: KNE_Instance,
	method: KNE_String,
) -> i32 {
	context = tracy.DefaultContext()
	descriptor := export_descriptor(ext, instance)
	return classes.Find_Export(descriptor, KNE_String_To(method)) != nil ? 1 : 0
}

kne_export_count :: proc "c" (ext: KNE_Extension, instance: KNE_Instance) -> uintptr {
	context = tracy.DefaultContext()
	descriptor := export_descriptor(ext, instance)
	if descriptor == nil {
		return 0
	}
	return uintptr(len(descriptor.exports))
}

kne_export_name_at :: proc "c" (
	ext: KNE_Extension,
	instance: KNE_Instance,
	index: uintptr,
) -> KNE_String {
	context = tracy.DefaultContext()
	descriptor := export_descriptor(ext, instance)
	if descriptor == nil || index >= uintptr(len(descriptor.exports)) {
		return KNE_String{}
	}
	return KNE_String_From(descriptor.exports[index].name)
}

Export_Call :: struct {
	ctx:     classes.Class_Export_Context,
	handler: classes.Class_Export_Handler,
}

@(private)
kne_export_trampoline :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	call := cast(^Export_Call)vm.UpvaluePointer(L)
	call.ctx.L = L
	return call.handler(&call.ctx)
}

kne_export_call :: proc "c" (
	ext: KNE_Extension,
	instance: KNE_Instance,
	method: KNE_String,
	args: ^KNE_Value,
	arg_count: i32,
	out: ^KNE_Value,
	out_capacity: i32,
) -> i32 {
	context = tracy.DefaultContext()
	record := record_of(ext)
	descriptor := export_descriptor(ext, instance)
	name := KNE_String_To(method)
	export_entry := classes.Find_Export(descriptor, name)
	if record == nil || export_entry == nil || record.ctx == nil || record.ctx.vm_state == nil {
		return -1
	}
	if export_entry.handler == nil {
		return kne_instance_invoke(ext, instance, method, args, arg_count, out, out_capacity)
	}
	if arg_count < 0 ||
	   out_capacity < 0 ||
	   (arg_count > 0 && args == nil) ||
	   (out_capacity > 0 && out == nil) {return -1}
	parent := record.ctx.vm_state.L
	top := vm.StackTop(parent)
	defer vm.SetStackTop(parent, top)
	L := vm.NewThread(parent)
	append(&record.result_roots, vm.RetainValue(parent, -1))
	call := Export_Call {
		handler = export_entry.handler,
	}
	vm.PushLightUserdata(L, &call)
	vm.PushFunction(L, "KNE export", kne_export_trampoline, 1)
	arg_values := cast([^]KNE_Value)(args)
	out_values := cast([^]KNE_Value)(out)
	object := cast(^classes.Object)instance
	classes.Push_Object(L, object)
	for index in 0 ..< int(arg_count) {
		push_kne_value(L, record.ctx.datatype_registry, &arg_values[index])
	}
	call.ctx = classes.Class_Export_Context {
		L         = L,
		object    = object,
		datatypes = record.ctx.datatype_registry,
		enums     = record.ctx.enum_registry,
		method    = name,
	}
	ok, err := vm.ProtectedCall(L, int(arg_count) + 1, vm.MULTIPLE_RESULTS)
	if !ok {
		delete(record.last_error)
		record.last_error = err
		return -1
	}
	results := vm.StackTop(L)
	if results > int(out_capacity) {
		results = int(out_capacity)
	}
	for index in 0 ..< results {
		out_values[index] = stack_kne_value(L, record.ctx.datatype_registry, index + 1)
	}
	return i32(results)
}


release_extension_resources :: proc(context_state: ^Context, record: ^Extension_Record) {
	if record == nil {
		return
	}
	release_result_roots(record, 0)
	for callback in record.callbacks {
		if callback != nil && callback.ref > 0 && callback.L != nil {
			vm.ReleaseValue(callback.L, callback.ref)
			callback.ref = 0
		}
	}
	for connection in record.connections {
		signals.Disconnect_Connection(connection)
	}
	for datatype in record.datatypes {
		if datatype != nil {
			extension_datatype_release(record, datatype)
			delete(datatype.type_name)
			datatype.type_name = ""
			delete(datatype.library)
			datatype.library = ""
		}
	}
}


@(private)
release_result_roots :: proc(record: ^Extension_Record, first: int) {
	if record.ctx != nil && record.ctx.vm_state != nil && record.ctx.vm_state.L != nil {
		for index in first ..< len(record.result_roots) {vm.ReleaseValue(record.ctx.vm_state.L, record.result_roots[index])}
	}
	resize(&record.result_roots, first)
}
