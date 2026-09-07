// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
package luauh

lua_State :: struct {}

@(default_calling_convention="c")
foreign lib {
	// returns 1 if Luau code generator is supported, 0 otherwise
	luau_codegen_supported :: proc() -> i32 ---

	// create an instance of Luau code generator. you must check that this feature is supported using luau_codegen_supported().
	luau_codegen_create :: proc(L: ^lua_State) ---

	// build target function and all inner functions
	luau_codegen_compile :: proc(L: ^lua_State, idx: i32) ---
}

