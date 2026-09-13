// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#+build !js
package luauh

when ODIN_OS == .Windows {
	foreign import lib "../../../../vendor/build/vendor/luau/Luau.CodeGen.lib"
} else when #config(KINE_ANDROID, false) {
	foreign import lib "../../../../build/android-native/luau/libLuau.CodeGen.a"
} else {
	foreign import lib {
		"../../../../vendor/build/vendor/luau/libLuau.CodeGen.a",
		"../../../../vendor/build/vendor/luau/libLuau.VM.a",
		"../../../../vendor/build/vendor/luau/libLuau.Common.a",
	}
}

@(default_calling_convention="c")
foreign lib {
	// returns 1 if Luau code generator is supported, 0 otherwise
	luau_codegen_supported :: proc() -> i32 ---

	// create an instance of Luau code generator. you must check that this feature is supported using luau_codegen_supported().
	luau_codegen_create :: proc(L: ^lua_State) ---

	// build target function and all inner functions
	luau_codegen_compile :: proc(L: ^lua_State, idx: i32) ---
}

