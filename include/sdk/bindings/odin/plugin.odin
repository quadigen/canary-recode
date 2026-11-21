package kne


Log_Level :: KNE_Log_Level
Value_Kind :: KNE_Value_Kind
Vector2 :: KNE_Vector2
Vector3 :: KNE_Vector3
Vector2Int16 :: KNE_Vector2Int16
Vector3Int16 :: KNE_Vector3Int16
Color3 :: KNE_Color3
CFrame :: KNE_CFrame
UDim :: KNE_UDim
UDim2 :: KNE_UDim2
Ray :: KNE_Ray
Rect :: KNE_Rect
Region3 :: KNE_Region3
Region3Int16 :: KNE_Region3Int16
NumberRange :: KNE_NumberRange
NumberSequenceKeypoint :: KNE_NumberSequenceKeypoint
ColorSequenceKeypoint :: KNE_ColorSequenceKeypoint
Axes :: KNE_Axes
Faces :: KNE_Faces
PhysicalProperties :: KNE_PhysicalProperties
Quaternion :: KNE_Quaternion
TweenInfo :: KNE_TweenInfo
DateTime :: KNE_DateTime
UniqueId :: KNE_UniqueId
PathWaypoint :: KNE_PathWaypoint
SecurityCapabilities :: KNE_SecurityCapabilities
DockWidgetPluginGuiInfo :: KNE_DockWidgetPluginGuiInfo
Value :: KNE_Value
Extension_Handle :: KNE_Extension
Instance :: KNE_Instance
Lua_State :: KNE_VM
Callback :: KNE_Callback
Signal :: KNE_Signal
Connection :: KNE_Connection
Class_Descriptor :: KNE_Class_Desc
Datatype_Descriptor :: KNE_Datatype_Desc
Host :: KNE_Host
Extension_Descriptor :: KNE_Extension_Desc

Plugin :: struct {
	host:   ^Host,
	handle: Extension_Handle,
}

plugin :: proc(host: ^Host, handle: Extension_Handle) -> Plugin {
	return {host, handle}
}

extension_descriptor :: proc(id, name, version, author: string) -> Extension_Descriptor {
	return {
		size = u32(size_of(Extension_Descriptor)),
		abi_major = ABI_MAJOR,
		abi_minor = ABI_MINOR,
		id = str(id),
		name = str(name),
		version = str(version),
		author = str(author),
	}
}

class_descriptor :: proc(name, base: string, flags: u32 = CLASS_CREATABLE) -> Class_Descriptor {
	return {
		size = u32(size_of(Class_Descriptor)),
		version = ABI_MAJOR,
		name = str(name),
		base = str(base),
		flags = flags,
	}
}


value_nil :: proc() -> Value {return {kind = .Nil}}
value_bool :: proc(v: bool) -> Value {return {kind = .Boolean, data = {boolean = i32(v)}}}
value_number :: proc(v: f64) -> Value {return {kind = .Number, data = {number = v}}}
value_integer :: proc(v: i64) -> Value {return {kind = .Integer, data = {integer = v}}}
value_string :: proc(v: string) -> Value {return {kind = .String, data = {string = str(v)}}}
value_instance :: proc(v: Instance) -> Value {if v == nil {return value_nil()}; return {
		kind = .Instance,
		data = {instance = v},
	}}
value_vector2 :: proc(v: Vector2) -> Value {return {kind = .Vector2, data = {vector2 = v}}}
value_vector3 :: proc(v: Vector3) -> Value {return {kind = .Vector3, data = {vector3 = v}}}
value_color3 :: proc(v: Color3) -> Value {return {kind = .Color3, data = {color3 = v}}}
value_cframe :: proc(v: CFrame) -> Value {return {kind = .CFrame, data = {cframe = v}}}

as_string :: proc(v: Value) -> (string, bool) {if v.kind != .String {return "", false}
	return string_to(v.data.string), true}
as_number :: proc(v: Value) -> (f64, bool) {#partial switch v.kind {case .Number:
		return v.data.number, true; case .Integer:
		return f64(v.data.integer), true; case:
		return 0, false}}
as_instance :: proc(v: Value) -> (Instance, bool) {if v.kind != .Instance {return nil, false}
	return v.data.instance, true}


get_service :: proc(p: Plugin, name: string) -> Instance {return p.host.services.get(
		p.handle,
		str(name),
	)}
has_service :: proc(p: Plugin, name: string) -> bool {return(
		p.host.services.exists(p.handle, str(name)) !=
		0 \
	)}
service_count :: proc(p: Plugin) -> int {return int(p.host.services.count(p.handle))}
service_name :: proc(p: Plugin, index: int) -> string {if index < 0 {return ""}; return string_to(
		p.host.services.name_at(p.handle, uintptr(index)),
	)}
new_instance :: proc(p: Plugin, class_name: string) -> Instance {return p.host.instances.create(
		p.handle,
		str(class_name),
	)}
destroy_instance :: proc(p: Plugin, object: Instance) {p.host.instances.destroy(p.handle, object)}
get_name :: proc(p: Plugin, object: Instance) -> string {return string_to(
		p.host.instances.get_name(p.handle, object),
	)}
set_name :: proc(p: Plugin, object: Instance, name: string) {p.host.instances.set_name(
		p.handle,
		object,
		str(name),
	)}
get_parent :: proc(p: Plugin, object: Instance) -> Instance {return p.host.instances.get_parent(
		p.handle,
		object,
	)}
set_parent :: proc(p: Plugin, object, parent: Instance) {p.host.instances.set_parent(
		p.handle,
		object,
		parent,
	)}
child_count :: proc(p: Plugin, object: Instance) -> int {return int(
		p.host.instances.child_count(p.handle, object),
	)}
child_at :: proc(p: Plugin, object: Instance, index: int) -> Instance {if index < 0 {return nil}
	return p.host.instances.child_at(p.handle, object, uintptr(index))}
find_child :: proc(
	p: Plugin,
	object: Instance,
	name: string,
) -> Instance {return p.host.instances.find_child(p.handle, object, str(name))}
is_a :: proc(p: Plugin, object: Instance, class_name: string) -> bool {return(
		p.host.instances.is_a(p.handle, object, str(class_name)) !=
		0 \
	)}
class_name :: proc(p: Plugin, object: Instance) -> string {return string_to(
		p.host.instances.class_name(p.handle, object),
	)}
get_property :: proc(p: Plugin, object: Instance, name: string) -> (value: Value, ok: bool) {ok =
		p.host.instances.get_property(p.handle, object, str(name), &value) != 0
	return}
set_property :: proc(p: Plugin, object: Instance, name: string, value: Value) -> bool {v := value
	return p.host.instances.set_property(p.handle, object, str(name), &v) != 0}
get_user_data :: proc(
	p: Plugin,
	object: Instance,
) -> rawptr {return p.host.instances.get_user_data(p.handle, object)}
set_user_data :: proc(p: Plugin, object: Instance, data: rawptr) {p.host.instances.set_user_data(
		p.handle,
		object,
		data,
	)}
call_method :: proc(
	p: Plugin,
	object: Instance,
	method: string,
	args: []Value = nil,
	results: []Value = nil,
) -> int {
	return int(
		p.host.instances.invoke(
			p.handle,
			object,
			str(method),
			raw_data(args),
			i32(len(args)),
			raw_data(results),
			i32(len(results)),
		),
	)
}
register_class :: proc(p: Plugin, descriptor: ^Class_Descriptor) -> bool {return(
		p.host.classes.register(p.handle, descriptor) !=
		0 \
	)}
has_class :: proc(p: Plugin, name: string) -> bool {return(
		p.host.classes.is_registered(p.handle, str(name)) !=
		0 \
	)}
register_function :: proc(p: Plugin, name: string, fn: KNE_VM_Native_Fn) -> bool {return(
		p.host.vm.register_function(p.handle, str(name), fn) !=
		0 \
	)}
register_library_function :: proc(
	p: Plugin,
	library, name: string,
	fn: KNE_VM_Native_Fn,
) -> bool {return p.host.vm.register_library_function(p.handle, str(library), str(name), fn) != 0}
argument_count :: proc(p: Plugin, L: Lua_State) -> int {return int(p.host.vm.arg_count(L))}
get_argument :: proc(p: Plugin, L: Lua_State, index: int) -> (value: Value, ok: bool) {ok =
		p.host.vm.get_value(p.handle, L, i32(index), &value) != 0
	return}
push_result :: proc(p: Plugin, L: Lua_State, value: Value) {v := value; p.host.vm.push_value(
		p.handle,
		L,
		&v,
	)}
raise_error :: proc(p: Plugin, L: Lua_State, message: string) -> i32 {return p.host.vm.raise(
		L,
		str(message),
	)}
run_luau :: proc(p: Plugin, source: string, args: []Value = nil, results: []Value = nil) -> int {
	if p.host.abi_minor < 1 ||
	   p.host.vm.size < u32(size_of(KNE_VM_Api)) ||
	   p.host.vm.execute == nil {return -1}
	return int(
		p.host.vm.execute(
			p.handle,
			str(source),
			raw_data(args),
			i32(len(args)),
			raw_data(results),
			i32(len(results)),
		),
	)
}
last_error :: proc(p: Plugin) -> string {return string_to(p.host.core.last_error(p.handle))}
log :: proc(p: Plugin, level: Log_Level, message: string) {p.host.core.log(
		p.handle,
		level,
		str(message),
	)}
get_signal :: proc(
	p: Plugin,
	object: Instance,
	event: string,
) -> Signal {return p.host.signals.get(p.handle, object, str(event))}
connect :: proc(
	p: Plugin,
	signal: Signal,
	fn: KNE_Signal_Native_Fn,
) -> Connection {return p.host.signals.connect_native(p.handle, signal, fn)}
connect_once :: proc(
	p: Plugin,
	signal: Signal,
	fn: KNE_Signal_Native_Fn,
) -> Connection {return p.host.signals.once_native(p.handle, signal, fn)}
disconnect :: proc(p: Plugin, connection: Connection) {p.host.signals.disconnect(
		p.handle,
		connection,
	)}
is_connected :: proc(p: Plugin, connection: Connection) -> bool {return(
		p.host.signals.is_connected(p.handle, connection) !=
		0 \
	)}
fire_signal :: proc(p: Plugin, signal: Signal, args: []Value = nil) -> bool {return(
		p.host.signals.fire(p.handle, signal, raw_data(args), i32(len(args))) !=
		0 \
	)}
retain_callback :: proc(
	p: Plugin,
	L: Lua_State,
	index: int,
) -> Callback {return p.host.callbacks.retain(p.handle, L, i32(index))}
release_callback :: proc(p: Plugin, callback: Callback) {p.host.callbacks.release(
		p.handle,
		callback,
	)}
call_callback :: proc(
	p: Plugin,
	callback: Callback,
	args: []Value = nil,
	results: []Value = nil,
) -> int {return int(
		p.host.callbacks.call(
			p.handle,
			callback,
			raw_data(args),
			i32(len(args)),
			raw_data(results),
			i32(len(results)),
		),
	)}
new_datatype :: proc(
	p: Plugin,
	name: string,
	args: []Value = nil,
) -> (
	value: Value,
	ok: bool,
) {ok =
		p.host.datatypes.construct(p.handle, str(name), raw_data(args), i32(len(args)), &value) !=
		0
	return}
get_field :: proc(p: Plugin, value: Value, field: string) -> (result: Value, ok: bool) {v := value
	ok = p.host.datatypes.get_field(p.handle, &v, str(field), &result) != 0
	return}
set_field :: proc(p: Plugin, value: Value, field: string, input: Value) -> bool {v, x :=
		value, input
	return p.host.datatypes.set_field(p.handle, &v, str(field), &x) != 0}
call_datatype_method :: proc(
	p: Plugin,
	value: Value,
	method: string,
	args: []Value = nil,
	results: []Value = nil,
) -> int {v := value; return int(
		p.host.datatypes.call(
			p.handle,
			&v,
			str(method),
			raw_data(args),
			i32(len(args)),
			raw_data(results),
			i32(len(results)),
		),
	)}
register_datatype :: proc(p: Plugin, descriptor: ^Datatype_Descriptor) -> bool {return(
		p.host.datatypes.register_datatype(p.handle, descriptor) !=
		0 \
	)}
has_export :: proc(p: Plugin, object: Instance, method: string) -> bool {return(
		p.host.exports.exists(p.handle, object, str(method)) !=
		0 \
	)}
call_export :: proc(
	p: Plugin,
	object: Instance,
	method: string,
	args: []Value = nil,
	results: []Value = nil,
) -> int {return int(
		p.host.exports.call(
			p.handle,
			object,
			str(method),
			raw_data(args),
			i32(len(args)),
			raw_data(results),
			i32(len(results)),
		),
	)}


get_buffer :: proc(p: Plugin, L: Lua_State, index: int) -> (bytes: []u8, ok: bool) {
	if p.host.abi_minor < 1 ||
	   p.host.vm.size < u32(size_of(KNE_VM_Api)) ||
	   p.host.vm.get_buffer == nil {return nil, false}
	v, found := get_argument(p, L, index)
	if !found || v.kind != .Buffer {return nil, false}
	size: uintptr
	data := cast([^]u8)p.host.vm.get_buffer(L, i32(index), &size)
	return data[:int(size)], true
}
push_buffer :: proc(p: Plugin, L: Lua_State, bytes: []u8) -> bool {
	if p.host.abi_minor < 1 ||
	   p.host.vm.size < u32(size_of(KNE_VM_Api)) ||
	   p.host.vm.push_buffer == nil {return false}
	return p.host.vm.push_buffer(L, raw_data(bytes), uintptr(len(bytes))) != 0
}
connect_callback :: proc(
	p: Plugin,
	signal: Signal,
	callback: Callback,
) -> Connection {return p.host.signals.connect_callback(p.handle, signal, callback)}
connect_callback_once :: proc(
	p: Plugin,
	signal: Signal,
	callback: Callback,
) -> Connection {return p.host.signals.once_callback(p.handle, signal, callback)}
is_callback_valid :: proc(p: Plugin, callback: Callback) -> bool {return(
		p.host.callbacks.is_valid(p.handle, callback) !=
		0 \
	)}
has_datatype :: proc(p: Plugin, name: string) -> bool {return(
		p.host.datatypes.is_registered(p.handle, str(name)) !=
		0 \
	)}
unregister_datatype :: proc(p: Plugin, name: string) -> bool {return(
		p.host.datatypes.unregister_datatype(p.handle, str(name)) !=
		0 \
	)}
