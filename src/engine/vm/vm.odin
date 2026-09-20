package luau

import "core:strings"
import "base:runtime"

import luauh "luauh"

State     :: luauh.lua_State
CFunction :: luauh.lua_CFunction

Compile_Options :: struct {
	optimization_level: i32,
	debug_level:        i32,
	type_info_level:    i32,
	coverage_level:     i32,
	vector_precision:   i32
}

VM :: struct {
	L:               ^State,
	compile_options: Compile_Options,
}

Value_Type :: enum i32 {
	None          = -1,
	Nil           = 0,
	Boolean       = 1,
	LightUserdata = 2,
	Number        = 3,
	Integer       = 4,
	Vector        = 5,
	String        = 6,
	Table         = 7,
	Function      = 8,
	Userdata      = 9,
	Thread        = 10,
	Buffer        = 11,
	Class         = 12,
	Object        = 13,
}

Userdata_Get_Proc      :: proc(L: ^State, value, ctx: rawptr, key: string) -> bool
Userdata_Set_Proc      :: proc(L: ^State, value, ctx: rawptr, key: string, value_index: int) -> bool
Userdata_Namecall_Proc :: proc(L: ^State, value, ctx: rawptr, method: string) -> (result_count: i32, handled: bool)
Userdata_String_Proc   :: proc(value, ctx: rawptr) -> string
Userdata_Destroy_Proc  :: proc(value, ctx: rawptr)
Userdata_Binary_Proc   :: proc(L: ^State, value, ctx: rawptr, self_index, other_index: int) -> bool
Userdata_Unary_Proc    :: proc(L: ^State, value, ctx: rawptr) -> bool
Userdata_Equal_Proc    :: proc(value, other, ctx: rawptr) -> bool

Userdata_Binding :: struct {
	name:     string,
	tag:      i32,
	ctx:      rawptr,
	owner:    rawptr,
	get:      Userdata_Get_Proc,
	set:      Userdata_Set_Proc,
	namecall: Userdata_Namecall_Proc,
	string:   Userdata_String_Proc,
	destroy:  Userdata_Destroy_Proc,
	add:      Userdata_Binary_Proc,
	subtract: Userdata_Binary_Proc,
	multiply: Userdata_Binary_Proc,
	divide:   Userdata_Binary_Proc,
	negate:   Userdata_Unary_Proc,
	equal:    Userdata_Equal_Proc,
}

Userdata_Header :: struct {
	value:   rawptr,
	binding: ^Userdata_Binding,
}

NATIVE_USERDATA_TAG :: 42
NATIVE_USERDATA_MAX_TAG :: 127

Struct_Field_Kind :: enum {
	Nil,
	Number,
	Integer,
	Boolean,
	String,
	Function,
}

Struct_Field :: struct {
	name:          string,
	kind:          Struct_Field_Kind,
	number:        f64,
	integer:       i64,
	boolean:       bool,
	string_value:  string,
	function:      CFunction,
}

New :: proc(open_libraries := true) -> VM {
	L := luauh.luaL_newstate()
	if L == nil {
		panic("Failed to create Luau VM")
	}

	if open_libraries {
		luauh.luaL_openlibs(L)
	}

	return VM{
		L = L,
		compile_options = Compile_Options{
			optimization_level = 1,
			debug_level        = 1,
			vector_precision = 1
		},
	}
}

Close :: proc(vm: ^VM) {
	if vm == nil || vm.L == nil {
		return
	}

	luauh.lua_close(vm.L)
	vm.L = nil
}

RawState :: proc(vm: ^VM) -> ^State {
	assert_open(vm)
	return vm.L
}

assert_open :: proc(vm: ^VM) {
	if vm == nil || vm.L == nil {
		panic("Luau VM is closed")
	}
}


set_global_from_stack :: proc(vm: ^VM, name: string) {
	c_name := strings.clone_to_cstring(name)
	defer delete(c_name)

	luauh.lua_setfield(
		vm.L,
		luauh.LUA_GLOBALSINDEX,
		c_name,
	)
}

SetGlobalFromStack :: proc(vm: ^VM, name: string) {
	assert_open(vm)
	set_global_from_stack(vm, name)
}

GetGlobal :: proc(L: ^State, name: string) -> Value_Type {
	c_name := strings.clone_to_cstring(name)
	defer delete(c_name)
	return Value_Type(luauh.lua_getfield(L, luauh.LUA_GLOBALSINDEX, c_name))
}

SetGlobal :: proc(L: ^State, name: string) {
	c_name := strings.clone_to_cstring(name)
	defer delete(c_name)
	luauh.lua_setfield(L, luauh.LUA_GLOBALSINDEX, c_name)
}

push_struct_field :: proc(L: ^State, field: Struct_Field) {
	switch field.kind {
	case .Nil:
		luauh.lua_pushnil(L)

	case .Number:
		luauh.lua_pushnumber(L, field.number)

	case .Integer:
		luauh.lua_pushinteger64(L, field.integer)

	case .Boolean:
		value: i32 = 0
		if field.boolean {
			value = 1
		}

		luauh.lua_pushboolean(L, value)

	case .String:
		value := strings.clone_to_cstring(field.string_value)
		defer delete(value)

		luauh.lua_pushlstring(
			L,
			value,
			uintptr(len(field.string_value)),
		)

	case .Function:
		debug_name := strings.clone_to_cstring(field.name)
		defer delete(debug_name)

		luauh.lua_pushcclosurek(
			L,
			field.function,
			debug_name,
			0,
			nil,
		)
	}
}


AddGlobal_Number :: proc(vm: ^VM, name: string, value: f64) {
	assert_open(vm)

	luauh.lua_pushnumber(vm.L, value)
	set_global_from_stack(vm, name)
}

AddGlobal_Integer :: proc(vm: ^VM, name: string, value: int) {
	assert_open(vm)

	luauh.lua_pushinteger64(vm.L, i64(value))
	set_global_from_stack(vm, name)
}

AddGlobal_Boolean :: proc(vm: ^VM, name: string, value: bool) {
	assert_open(vm)

	raw_value: i32 = 0
	if value {
		raw_value = 1
	}

	luauh.lua_pushboolean(vm.L, raw_value)
	set_global_from_stack(vm, name)
}

AddGlobal_String :: proc(vm: ^VM, name: string, value: string) {
	assert_open(vm)

	c_value := strings.clone_to_cstring(value)
	defer delete(c_value)

	luauh.lua_pushstring(vm.L, c_value)
	set_global_from_stack(vm, name)
}

Field_Number :: proc(name: string, value: f64) -> Struct_Field {
	return Struct_Field{
		name   = name,
		kind   = .Number,
		number = value,
	}
}

Field_Integer :: proc(name: string, value: int) -> Struct_Field {
	return Struct_Field{
		name    = name,
		kind    = .Integer,
		integer = i64(value),
	}
}

Field_Boolean :: proc(name: string, value: bool) -> Struct_Field {
	return Struct_Field{
		name    = name,
		kind    = .Boolean,
		boolean = value,
	}
}

Field_String :: proc(name: string, value: string) -> Struct_Field {
	return Struct_Field{
		name         = name,
		kind         = .String,
		string_value = value,
	}
}

Field_Function :: proc(name: string, value: CFunction) -> Struct_Field {
	return Struct_Field{
		name     = name,
		kind     = .Function,
		function = value,
	}
}

Field_Nil :: proc(name: string) -> Struct_Field {
	return Struct_Field{
		name = name,
		kind = .Nil,
	}
}

Field :: proc {
	Field_Number,
	Field_Integer,
	Field_Boolean,
	Field_String,
	Field_Function,
	Field_Nil,
}

AddGlobal_Nil :: proc(vm: ^VM, name: string) {
	assert_open(vm)

	luauh.lua_pushnil(vm.L)
	set_global_from_stack(vm, name)
}

AddGlobal_Function :: proc(
	vm: ^VM,
	name: string,
	fn: CFunction,
) {
	assert_open(vm)

	c_name := strings.clone_to_cstring(name)
	defer delete(c_name)

	// lua_pushcfunction is also a C macro.
	luauh.lua_pushcclosurek(
		vm.L,
		fn,
		c_name,
		0,
		nil,
	)

	set_global_from_stack(vm, name)
}

AddGlobal :: proc {
	AddGlobal_Number,
	AddGlobal_Integer,
	AddGlobal_Boolean,
	AddGlobal_String,
	AddGlobal_Nil,
	AddGlobal_Function,
}

AddFunction :: AddGlobal_Function

RemoveGlobal :: proc(vm: ^VM, name: string) {
	AddGlobal_Nil(vm, name)
}



GetGlobalNumber :: proc(
	vm: ^VM,
	name: string,
) -> (value: f64, ok: bool) {
	assert_open(vm)

	c_name := strings.clone_to_cstring(name)
	defer delete(c_name)

	luauh.lua_getfield(
		vm.L,
		luauh.LUA_GLOBALSINDEX,
		c_name,
	)

	is_number: i32
	value = luauh.lua_tonumberx(
		vm.L,
		-1,
		&is_number,
	)

	// pop value
	luauh.lua_settop(vm.L, -2)

	return value, is_number != 0
}


ArgNumber :: proc(L: ^State, index: int) -> f64 {
	return luauh.luaL_checknumber(L, i32(index))
}

ArgInteger :: proc(L: ^State, index: int) -> i64 {
	return luauh.luaL_checkinteger64(L, i32(index))
}

ArgBoolean :: proc(L: ^State, index: int) -> bool {
	return luauh.luaL_checkboolean(L, i32(index)) != 0
}

SetCompileOptions :: proc(vm: ^VM, options: Compile_Options) {
	assert_open(vm)
	vm.compile_options = options
}

SetOptimizationLevel :: proc(vm: ^VM, level: i32) {
	assert(level >= 0 && level <= 2)
	vm.compile_options.optimization_level = level
}

SetDebugLevel :: proc(vm: ^VM, level: i32) {
	assert(level >= 0 && level <= 2)
	vm.compile_options.debug_level = level
}

SetTypeInfoLevel :: proc(vm: ^VM, level: i32) {
	assert(level >= 0 && level <= 1)
	vm.compile_options.type_info_level = level
}

SetCoverageLevel :: proc(vm: ^VM, level: i32) {
	assert(level >= 0 && level <= 2)
	vm.compile_options.coverage_level = level
}

SetVectorPrecision :: proc(vm: ^VM, use_f64: bool) {
	vm.compile_options.vector_precision = use_f64 ? 1 : 0
}

ArgString :: proc(L: ^State, index: int) -> string {
	size: uintptr

	ptr := luauh.luaL_checklstring(
		L,
		i32(index),
		&size,
	)

	return strings.string_from_ptr(
		cast(^u8)ptr,
		int(size),
	)
}

AddStruct :: proc(
	vm: ^VM,
	name: string,
	fields: ..Struct_Field,
) {
	assert_open(vm)

	luauh.lua_createtable(
		vm.L,
		0,
		i32(len(fields)),
	)

	for field in fields {
		push_struct_field(vm.L, field)

		field_name := strings.clone_to_cstring(field.name)

		luauh.lua_setfield(
			vm.L,
			-2,
			field_name,
		)

		delete(field_name)
	}

	set_global_from_stack(vm, name)
}

PushNumber :: proc(L: ^State, value: f64) {
	luauh.lua_pushnumber(L, value)
}

PushInteger :: proc(L: ^State, value: i64) {
	luauh.lua_pushinteger64(L, value)
}

PushBoolean :: proc(L: ^State, value: bool) {
	raw_value: i32 = 0
	if value {
		raw_value = 1
	}

	luauh.lua_pushboolean(L, raw_value)
}

PushString :: proc(L: ^State, value: string) {
	c_value := strings.clone_to_cstring(value)
	defer delete(c_value)

	luauh.lua_pushstring(L, c_value)
}

PushNil :: proc(L: ^State) {
	luauh.lua_pushnil(L)
}

PushVector3 :: proc(L: ^State, x, y, z: f32) {
	luauh.lua_pushvector(L, x, y, z)
}

PushValue :: proc(L: ^State, index: int) {
	luauh.lua_pushvalue(L, i32(index))
}

PushLightUserdata :: proc(L: ^State, value: rawptr, tag: i32 = 0) {
	luauh.lua_pushlightuserdatatagged(L, value, tag)
}

PushFunction :: proc(L: ^State, name: string, function: CFunction, upvalue_count: int = 0) {
	c_name := strings.clone_to_cstring(name)
	defer delete(c_name)
	luauh.lua_pushcclosurek(L, function, c_name, i32(upvalue_count), nil)
}

UpvalueIndex :: proc(index: int) -> i32 {
	return luauh.LUA_GLOBALSINDEX-i32(index)
}

UpvaluePointer :: proc(L: ^State, index: int = 1) -> rawptr {
	return luauh.lua_tolightuserdata(L, UpvalueIndex(index))
}

ArgVector3 :: proc(L: ^State, index: int) -> (x, y, z: f32) {
	value := luauh.luaL_checkvector(L, i32(index))
	components := cast([^]f32)value
	return components[0], components[1], components[2]
}

StackTop :: proc(L: ^State) -> int {
	return int(luauh.lua_gettop(L))
}

SetStackTop :: proc(L: ^State, index: int) {
	luauh.lua_settop(L, i32(index))
}

Pop :: proc(L: ^State, count: int = 1) {
	if count > 0 {
		luauh.lua_settop(L, -i32(count)-1)
	}
}

NewThread :: proc(L: ^State) -> ^State {
	return luauh.lua_newthread(L)
}

ThreadFromArgument :: proc(L: ^State, index: int) -> ^State {
	return luauh.lua_tothread(L, i32(index))
}

PushCurrentThread :: proc(L: ^State) {
	_ = luauh.lua_pushthread(L)
}

CopyValueToThread :: proc(from, to: ^State, index: int) {
	luauh.lua_xpush(from, to, i32(index))
}

IsYieldable :: proc(L: ^State) -> bool {
	return luauh.lua_isyieldable(L) != 0
}

YieldThread :: proc(L: ^State, result_count: int = 0) -> i32 {
	return luauh.lua_yield(L, i32(result_count))
}

ResumeThread :: proc(thread, from: ^State, argument_count: int = 0) -> (finished, yielded: bool, err: string) {
	status := luauh.lua_Status(luauh.lua_resume(thread, from, i32(argument_count)))
	#partial switch status {
	case .OK:
		luauh.lua_resetthread(thread)
		return true, false, ""
	case .YIELD:
		return false, true, ""
	case:
		err = get_stack_error(thread)
		luauh.lua_resetthread(thread)
		return false, false, err
	}
}

ClearStack :: proc(L: ^State) {
	luauh.lua_settop(L, 0)
}

PushGlobals :: proc(L: ^State) {
	luauh.lua_pushvalue(
		L,
		luauh.LUA_GLOBALSINDEX,
	)
}

SetMetatable :: proc(
	L: ^State,
	index: int,
) -> bool {
	return luauh.lua_setmetatable(
		L,
		i32(index),
	) != 0
}

SetFunctionEnvironment :: proc(
	L: ^State,
	function_index: int,
) -> bool {
	return luauh.lua_setfenv(
		L,
		i32(function_index),
	) != 0
}

ProtectedCall :: proc(L: ^State, argument_count: int, result_count: int = 0) -> (ok: bool, err: string) {
	status := luauh.lua_pcall(L, i32(argument_count), i32(result_count), 0)
	if status == 0 {
		return true, ""
	}

	err = get_stack_error(L)
	Pop(L)
	return false, err
}

DisplayString :: proc(L: ^State, index: i32, depth: i32 = 0) -> string {
	if depth >= 8 {
		return "{ ... }"
	}

	if !IsTable(L, int(index)) {
		cstr := luauh.luaL_tolstring(L, index, nil)

		if cstr == nil {
			return TypeName(L, int(index))
		}

		result := strings.clone(string(cstr))
		Pop(L)

		return result
	}

	table_index := luauh.lua_absindex(L, index)

	parts: [dynamic]string
	defer delete(parts)

	indent := strings.repeat("    ", int(depth))
	child_indent := strings.repeat("    ", int(depth + 1))

	append(&parts, "{")

	luauh.lua_pushnil(L)

	has_entries := false

	for luauh.lua_next(L, table_index) != 0 {
		has_entries = true

		key := DisplayString(L, -2, depth + 1)
		value := DisplayString(L, -1, depth + 1)

		append(&parts, "\n")
		append(&parts, child_indent)
		append(&parts, "[")
		append(&parts, key)
		append(&parts, "] = ")
		append(&parts, value)
		append(&parts, ",")

		Pop(L)
	}

	if has_entries {
		append(&parts, "\n")
		append(&parts, indent)
	}

	append(&parts, "}")

	result := strings.concatenate(parts[:])

	delete(indent)
	delete(child_indent)

	return result
}

TypeOf :: proc(L: ^State, index: int) -> Value_Type {
	return Value_Type(luauh.lua_type(L, i32(index)))
}

TypeName :: proc(L: ^State, index: int) -> string {
	name := luauh.lua_typename(L, luauh.lua_type(L, i32(index)))
	if name == nil {
		return "none"
	}
	return string(name)
}

IsNil :: proc(L: ^State, index: int) -> bool {
	return TypeOf(L, index) == .Nil
}

IsNoneOrNil :: proc(L: ^State, index: int) -> bool {
	type := TypeOf(L, index)
	return type == .None || type == .Nil
}

IsBoolean :: proc(L: ^State, index: int) -> bool {
	return TypeOf(L, index) == .Boolean
}

IsNumber :: proc(L: ^State, index: int) -> bool {
	return luauh.lua_isnumber(L, i32(index)) != 0
}

IsString :: proc(L: ^State, index: int) -> bool {
	return luauh.lua_isstring(L, i32(index)) != 0
}

IsTable :: proc(L: ^State, index: int) -> bool {
	return TypeOf(L, index) == .Table
}

IsFunction :: proc(L: ^State, index: int) -> bool {
	return TypeOf(L, index) == .Function
}

ArgOptionalString :: proc(L: ^State, index: int, default: string = "") -> string {
	if IsNoneOrNil(L, index) {
		return default
	}
	return ArgString(L, index)
}

ArgOptionalNumber :: proc(L: ^State, index: int, default: f64 = 0) -> f64 {
	if IsNoneOrNil(L, index) {
		return default
	}
	return ArgNumber(L, index)
}

ArgOptionalInteger :: proc(L: ^State, index: int, default: i64 = 0) -> i64 {
	if IsNoneOrNil(L, index) {
		return default
	}
	return ArgInteger(L, index)
}

ArgOptionalBoolean :: proc(L: ^State, index: int, default: bool = false) -> bool {
	if IsNoneOrNil(L, index) {
		return default
	}
	return ArgBoolean(L, index)
}

ToNumber :: proc(L: ^State, index: int) -> (f64, bool) {
	is_number: i32
	value := luauh.lua_tonumberx(L, i32(index), &is_number)
	return value, is_number != 0
}

ToString :: proc(L: ^State, index: int) -> (string, bool) {
	if TypeOf(L, index) != .String {
		return "", false
	}
	size: uintptr
	ptr := luauh.lua_tolstring(L, i32(index), &size)
	if ptr == nil {
		return "", false
	}
	return strings.string_from_ptr(cast(^u8)ptr, int(size)), true
}

NewTable :: proc(L: ^State, array_capacity: int = 0, field_capacity: int = 0) {
	luauh.lua_createtable(L, i32(array_capacity), i32(field_capacity))
}

GetField :: proc(L: ^State, index: int, name: string) -> Value_Type {
	c_name := strings.clone_to_cstring(name)
	defer delete(c_name)
	return Value_Type(luauh.lua_getfield(L, i32(index), c_name))
}

SetField :: proc(L: ^State, index: int, name: string) {
	c_name := strings.clone_to_cstring(name)
	defer delete(c_name)
	luauh.lua_setfield(L, i32(index), c_name)
}

SetReadOnly :: proc(L: ^State, index: int, read_only := true) {
	luauh.lua_setreadonly(L, i32(index), read_only ? 1 : 0)
}

SetArrayValue :: proc(L: ^State, table_index, array_index: int) {
	luauh.lua_rawseti(L, i32(table_index), i32(array_index))
}

RawLen :: proc(L: ^State, index: int) -> int {
	return int(luauh.lua_objlen(L, i32(index)))
}

RawGetIndex :: proc(L: ^State, table_index, array_index: int) -> Value_Type {
	return Value_Type(luauh.lua_rawgeti(L, i32(table_index), i32(array_index)))
}

RawSetIndex :: proc(L: ^State, table_index, array_index: int) {
	luauh.lua_rawseti(L, i32(table_index), i32(array_index))
}

Next :: proc(L: ^State, table_index: int) -> bool {
	return luauh.lua_next(L, i32(table_index)) != 0
}

PushRegistryReference :: proc(L: ^State, reference: i32) {
	luauh.lua_rawgeti(L, luauh.LUA_REGISTRYINDEX, reference)
}

RetainValue :: proc(L: ^State, index: int = -1) -> i32 {
	return luauh.lua_ref(L, i32(index))
}

ReleaseValue :: proc(L: ^State, reference: i32) {
	if reference > 0 {
		_ = luauh.lua_unref(L, reference)
	}
}

RaiseError :: proc(L: ^State, message: string) -> i32 {
    c_message := strings.clone_to_cstring(message, context.temp_allocator)
    return luauh.luaL_error(L, c_message)
}

RaiseOwnedError :: proc(L: ^State, message: ^string) -> i32 {
	if message == nil { return RaiseError(L, "Unknown Luau error") }
	luauh.lua_pushlstring(L, cast(cstring)raw_data(message^), uintptr(len(message^)))
	delete(message^)
	message^ = ""
	luauh.lua_error(L)
	return 0
}

userdata_header :: proc(L: ^State, index: int) -> ^Userdata_Header {
	if TypeOf(L, index) != .Userdata {
		return nil
	}
	actual_tag := luauh.lua_userdatatag(L, i32(index))
	if actual_tag < NATIVE_USERDATA_TAG || actual_tag > NATIVE_USERDATA_MAX_TAG {
		return nil
	}
	header := cast(^Userdata_Header)luauh.lua_touserdata(L, i32(index))
	if header == nil || header.binding == nil {
		return nil
	}
	tag := header.binding.tag
	if tag == 0 {
		tag = NATIVE_USERDATA_TAG
	}
	if actual_tag != tag {
		return nil
	}
	return header
}

IsNativeUserdata :: proc(L: ^State, index: int) -> bool {
	return userdata_header(L, index) != nil
}

DetachUserdata :: proc(L: ^State, index: int) {
	header := userdata_header(L, index)
	if header != nil {
		header.value = nil
	}
}

UserdataValue :: proc(L: ^State, index: int) -> rawptr {
	header := userdata_header(L, index)
	if header == nil {
		return nil
	}
	return header.value
}

UserdataBindingOf :: proc(L: ^State, index: int) -> ^Userdata_Binding {
	header := userdata_header(L, index)
	if header == nil {
		return nil
	}
	return header.binding
}

IsUserdataType :: proc(L: ^State, index: int, binding: ^Userdata_Binding) -> bool {
	return binding != nil && UserdataBindingOf(L, index) == binding
}

userdata_index :: proc "c" (L: ^State) -> i32 {
	context = runtime.default_context()
	header := userdata_header(L, 1)
	if header == nil || header.binding == nil {
		return RaiseError(L, "invalid native instance")
	}

	key := ArgString(L, 2)
	if header.binding.get != nil && header.binding.get(L, header.value, header.binding.ctx, key) {
		return 1
	}

	PushNil(L)
	return 1
}

userdata_newindex :: proc "c" (L: ^State) -> i32 {
	context = runtime.default_context()
	header := userdata_header(L, 1)
	if header == nil || header.binding == nil {
		return RaiseError(L, "invalid native instance")
	}

	key := ArgString(L, 2)
	if header.binding.set != nil && header.binding.set(L, header.value, header.binding.ctx, key, 3) {
		return 0
	}

	return RaiseError(L, "property cannot be assigned")
}

userdata_namecall :: proc "c" (L: ^State) -> i32 {
	context = runtime.default_context()
	header := userdata_header(L, 1)
	if header == nil || header.binding == nil {
		return RaiseError(L, "invalid native instance")
	}

	atom: i32
	method_value := luauh.lua_namecallatom(L, &atom)
	if method_value == nil {
		return RaiseError(L, "missing method name")
	}
	method := string(method_value)

	if header.binding.namecall != nil {
		result_count, handled := header.binding.namecall(L, header.value, header.binding.ctx, method)
		if handled {
			return result_count
		}
	}

	return RaiseError(L, "unknown method")
}

userdata_method :: proc "c" (L: ^State) -> i32 {
	context = runtime.default_context()
	header := userdata_header(L, 1)
	if header == nil || header.binding == nil || header.binding.namecall == nil {
		return RaiseError(L, "invalid native method receiver")
	}
	method := ArgString(L, int(UpvalueIndex(1)))
	result_count, handled := header.binding.namecall(L, header.value, header.binding.ctx, method)
	if handled {
		return result_count
	}
	return RaiseError(L, "unknown method")
}

PushUserdataMethod :: proc(L: ^State, name: string) {
	PushString(L, name)
	PushFunction(L, name, userdata_method, 1)
}

userdata_binary :: proc(L: ^State, operation: Userdata_Binary_Proc) -> i32 {
	header := userdata_header(L, 1)
	self_index, other_index := 1, 2
	if header == nil {
		header = userdata_header(L, 2)
		self_index, other_index = 2, 1
	}
	if header == nil || operation == nil || !operation(L, header.value, header.binding.ctx, self_index, other_index) {
		return RaiseError(L, "unsupported datatype operation")
	}
	return 1
}

userdata_add :: proc "c" (L: ^State) -> i32 {
	context = runtime.default_context()
	header := userdata_header(L, 1)
	if header == nil {
		header = userdata_header(L, 2)
	}
	return userdata_binary(L, header != nil ? header.binding.add : nil)
}

userdata_subtract :: proc "c" (L: ^State) -> i32 {
	context = runtime.default_context()
	header := userdata_header(L, 1)
	if header == nil {
		header = userdata_header(L, 2)
	}
	return userdata_binary(L, header != nil ? header.binding.subtract : nil)
}

userdata_multiply :: proc "c" (L: ^State) -> i32 {
	context = runtime.default_context()
	header := userdata_header(L, 1)
	if header == nil {
		header = userdata_header(L, 2)
	}
	return userdata_binary(L, header != nil ? header.binding.multiply : nil)
}

userdata_divide :: proc "c" (L: ^State) -> i32 {
	context = runtime.default_context()
	header := userdata_header(L, 1)
	if header == nil {
		header = userdata_header(L, 2)
	}
	return userdata_binary(L, header != nil ? header.binding.divide : nil)
}

userdata_negate :: proc "c" (L: ^State) -> i32 {
	context = runtime.default_context()
	header := userdata_header(L, 1)
	if header == nil || header.binding.negate == nil || !header.binding.negate(L, header.value, header.binding.ctx) {
		return RaiseError(L, "unsupported datatype operation")
	}
	return 1
}

userdata_equal :: proc "c" (L: ^State) -> i32 {
	context = runtime.default_context()
	left := userdata_header(L, 1)
	right := userdata_header(L, 2)
	if left == nil || right == nil || left.binding != right.binding || left.binding.equal == nil {
		PushBoolean(L, false)
		return 1
	}
	PushBoolean(L, left.binding.equal(left.value, right.value, left.binding.ctx))
	return 1
}

userdata_tostring :: proc "c" (L: ^State) -> i32 {
	context = runtime.default_context()
	header := userdata_header(L, 1)
	if header == nil || header.binding == nil {
		PushString(L, "native instance")
		return 1
	}

	if header.binding.string != nil {
		PushString(L, header.binding.string(header.value, header.binding.ctx))
	} else {
		PushString(L, header.binding.name)
	}
	return 1
}

userdata_destroy :: proc "c" (L: ^State, userdata: rawptr) {
	context = runtime.default_context()
	header := cast(^Userdata_Header)userdata
	if header != nil && header.binding != nil && header.binding.destroy != nil && header.value != nil {
		header.binding.destroy(header.value, header.binding.ctx)
		header.value = nil
	}
}

ensure_userdata_support :: proc(vm: ^VM, binding: ^Userdata_Binding) {
	tag := binding.tag
	if tag == 0 {
		tag = NATIVE_USERDATA_TAG
	}
	luauh.lua_getuserdatametatable(vm.L, tag)
	if TypeOf(vm.L, -1) == .Table {
		Pop(vm.L)
		return
	}
	Pop(vm.L)

	NewTable(vm.L, 0, 11)
	PushString(vm.L, binding.name)
	SetField(vm.L, -2, "__type")
	PushFunction(vm.L, "__index", userdata_index)
	SetField(vm.L, -2, "__index")
	PushFunction(vm.L, "__newindex", userdata_newindex)
	SetField(vm.L, -2, "__newindex")
	PushFunction(vm.L, "__namecall", userdata_namecall)
	SetField(vm.L, -2, "__namecall")
	PushFunction(vm.L, "__tostring", userdata_tostring)
	SetField(vm.L, -2, "__tostring")
	if binding.add != nil {
		PushFunction(vm.L, "__add", userdata_add)
		SetField(vm.L, -2, "__add")
	}
	if binding.subtract != nil {
		PushFunction(vm.L, "__sub", userdata_subtract)
		SetField(vm.L, -2, "__sub")
	}
	if binding.multiply != nil {
		PushFunction(vm.L, "__mul", userdata_multiply)
		SetField(vm.L, -2, "__mul")
	}
	if binding.divide != nil {
		PushFunction(vm.L, "__div", userdata_divide)
		SetField(vm.L, -2, "__div")
	}
	if binding.negate != nil {
		PushFunction(vm.L, "__unm", userdata_negate)
		SetField(vm.L, -2, "__unm")
	}
	if binding.equal != nil {
		PushFunction(vm.L, "__eq", userdata_equal)
		SetField(vm.L, -2, "__eq")
	}

	luauh.lua_setuserdatametatable(vm.L, tag)
	luauh.lua_setuserdatadtor(vm.L, tag, userdata_destroy)
}

PushUserdata :: proc(vm: ^VM, value: rawptr, binding: ^Userdata_Binding) {
	assert_open(vm)
	assert(value != nil)
	assert(binding != nil)
	ensure_userdata_support(vm, binding)
	tag := binding.tag
	if tag == 0 {
		tag = NATIVE_USERDATA_TAG
	}

	header := cast(^Userdata_Header)luauh.lua_newuserdatataggedwithmetatable(
		vm.L,
		size_of(Userdata_Header),
		tag,
	)
	header^ = Userdata_Header{
		value   = value,
		binding = binding,
	}
}

LoadSource :: proc(
	vm: ^VM,
	L: ^State,
	source: string,
	chunk_name: string = "Kinemium",
) -> (ok: bool, err: string) {
	assert_open(vm)
	assert(L != nil)

	c_source := strings.clone_to_cstring(source)
	defer delete(c_source)

	c_chunk := strings.clone_to_cstring(chunk_name)
	defer delete(c_chunk)

	bytecode_size: uintptr

    options := luauh.lua_CompileOptions{
        optimizationLevel = vm.compile_options.optimization_level,
        debugLevel        = vm.compile_options.debug_level,
        typeInfoLevel     = vm.compile_options.type_info_level,
        coverageLevel     = vm.compile_options.coverage_level,
        vectorPrecision   = vm.compile_options.vector_precision,

        vectorLib                = nil,
        vectorCtor               = nil,
        vectorType               = nil,
        mutableGlobals           = nil,
        userdataTypes            = nil,
        librariesWithKnownMembers = nil,
        libraryMemberTypeCb      = nil,
        libraryMemberConstantCb  = nil,
        disabledBuiltins         = nil,
    }

    bytecode := luauh.luau_compile(
        c_source,
        uintptr(len(source)),
        &options,
        &bytecode_size,
    )

	if bytecode == nil {
		return false, strings.clone("luau_compile returned nil")
	}

	defer luauh.luau_free(cast(rawptr)bytecode)

	status := luauh.luau_load(
		L,
		c_chunk,
		bytecode,
		bytecode_size,
		0,
	)

	if status != 0 {
		err = get_stack_error(L)
		luauh.lua_settop(L, -2)
		return false, err
	}
	return true, ""
}

Run :: proc(
	vm: ^VM,
	source: string,
	chunk_name: string = "Kinemium",
) -> (ok: bool, err: string) {
	assert_open(vm)

	ok, err = LoadSource(vm, vm.L, source, chunk_name)
	if !ok {
		return
	}

	status := luauh.lua_pcall(
		vm.L,
		0,
		0,
		0,
	)

	if status != 0 {
		err = get_stack_error(vm.L)
		luauh.lua_settop(vm.L, -2)
		return false, err
	}

	return true, ""
}

get_stack_error :: proc(L: ^State) -> string {
	size: uintptr

	ptr := luauh.lua_tolstring(
		L,
		-1,
		&size,
	)

	if ptr == nil {
		return strings.clone("Unknown Luau error")
	}

	return strings.clone_from_ptr(
		cast(^u8)ptr,
		int(size),
	)
}
