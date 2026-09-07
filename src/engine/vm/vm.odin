package luau

import "core:c"
import "core:c/libc"
import "core:strings"

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
	L: ^State,
}

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
			len(field.string_value),
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

	is_number: c.int
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
	size: c.size_t

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



Run :: proc(
	vm: ^VM,
	source: string,
	chunk_name: string = "Kinemium",
) -> (ok: bool, err: string) {
	assert_open(vm)

	c_source := strings.clone_to_cstring(source)
	defer delete(c_source)

	c_chunk := strings.clone_to_cstring(chunk_name)
	defer delete(c_chunk)

	bytecode_size: c.size_t

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
        c.size_t(len(source)),
        &options,
        &bytecode_size,
    )

	if bytecode == nil {
		return false, strings.clone("luau_compile returned nil")
	}

	defer libc.free(cast(rawptr)bytecode)

	status := luauh.luau_load(
		vm.L,
		c_chunk,
		bytecode,
		bytecode_size,
		0,
	)

	if status != 0 {
		err = get_stack_error(vm.L)
		luauh.lua_settop(vm.L, -2)
		return false, err
	}

	status = luauh.lua_pcall(
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
	size: c.size_t

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