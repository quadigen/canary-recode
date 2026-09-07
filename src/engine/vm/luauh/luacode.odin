// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
package luauh

import "core:c"

lua_CompileConstant :: rawptr

// return a type identifier for a global library member
// values are defined by 'enum LuauBytecodeType' in Bytecode.h
lua_LibraryMemberTypeCallback :: proc "c" (library: cstring, member: cstring) -> i32

// setup a value of a constant for a global library member
// use luau_set_compile_constant_*** set of functions for values
lua_LibraryMemberConstantCallback :: proc "c" (library: cstring, member: cstring, constant: ^lua_CompileConstant)

lua_CompileOptions :: struct {
	// 0 - no optimization
	// 1 - baseline optimization level that doesn't prevent debuggability
	// 2 - includes optimizations that harm debuggability such as inlining
	optimizationLevel: i32, // default=1

	// 0 - no debugging support
	// 1 - line info & function names only; sufficient for backtraces
	// 2 - full debug info with local & upvalue names; necessary for debugger
	debugLevel: i32, // default=1

	// type information is used to guide native code generation decisions
	// information includes testable types for function arguments, locals, upvalues and some temporaries
	// 0 - generate for native modules
	// 1 - generate for all modules
	typeInfoLevel: i32, // default=0

	// 0 - no code coverage support
	// 1 - statement coverage
	// 2 - statement and expression coverage (verbose)
	coverageLevel: i32, // default=0

	// alternative global builtin to construct vectors, in addition to default builtin 'vector.create'
	vectorLib:  cstring,
	vectorCtor: cstring,

	// alternative vector type name for type tables, in addition to default type 'vector'
	vectorType: cstring,

	// 0 - 32-bit float vector components
	// 1 - 64-bit double vector components
	vectorPrecision: i32, // default=0

	// null-terminated array of globals that are mutable; disables the import optimization for fields accessed through these
	mutableGlobals: ^cstring,

	// null-terminated array of userdata types that will be included in the type information
	userdataTypes: ^cstring,

	// null-terminated array of globals which act as libraries and have members with known type and/or constant value
	// when an import of one of these libraries is accessed, callbacks below will be called to receive that information
	librariesWithKnownMembers: ^cstring,
	libraryMemberTypeCb:       lua_LibraryMemberTypeCallback,
	libraryMemberConstantCb:   lua_LibraryMemberConstantCallback,

	// null-terminated array of library functions that should not be compiled into a built-in fastcall ("name" "lib.name")
	disabledBuiltins: ^cstring,
}

@(default_calling_convention="c")
foreign lib {
	// compile source to bytecode; when source compilation fails, the resulting bytecode contains the encoded error. use free() to destroy
	luau_compile :: proc(source: cstring, size: c.size_t, options: ^lua_CompileOptions, outsize: ^c.size_t) -> cstring ---

	// when libraryMemberConstantCb is called, these methods can be used to set a value of the opaque lua_CompileConstant struct
	// vector component 'w' is not visible to VM runtime configured with LUA_VECTOR_SIZE == 3, but can affect constant folding during compilation
	// string storage must outlive the invocation of 'luau_compile' which used the callback
	luau_set_compile_constant_nil       :: proc(constant: ^lua_CompileConstant) ---
	luau_set_compile_constant_boolean   :: proc(constant: ^lua_CompileConstant, b: i32) ---
	luau_set_compile_constant_number    :: proc(constant: ^lua_CompileConstant, n: f64) ---
	luau_set_compile_constant_integer64 :: proc(constant: ^lua_CompileConstant, l: i64) ---
	luau_set_compile_constant_vector    :: proc(constant: ^lua_CompileConstant, x: f32, y: f32, z: f32, w: f32) ---
	luau_set_compile_constant_vectord   :: proc(constant: ^lua_CompileConstant, x: f64, y: f64, z: f64, w: f64) ---
	luau_set_compile_constant_string    :: proc(constant: ^lua_CompileConstant, s: cstring, l: c.size_t) ---
}

