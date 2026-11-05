package luauh

TYPECHECK_AVAILABLE :: ODIN_OS != .JS && !#config(KINE_ANDROID, false)

when TYPECHECK_AVAILABLE {
	when ODIN_OS == .Windows {
		foreign import analysis {"../../../../vendor/build/lib/kine_luau.lib", "../../../../vendor/build/vendor/luau/Luau.Analysis.lib", "../../../../vendor/build/vendor/luau/Luau.Config.lib"}
	} else {
		foreign import analysis {"../../../../vendor/build/lib/kine_luau.a", "../../../../vendor/build/vendor/luau/libLuau.Analysis.a", "../../../../vendor/build/vendor/luau/libLuau.Config.a", "system:stdc++", "system:m"}
	}

	foreign analysis {
		@(link_name = "kine_luau_typecheck")
		luau_typecheck :: proc "c" (L: ^lua_State, source: cstring, size: uintptr, resolver: i32) -> i32 ---
		@(link_name = "kine_luau_exported_types")
		luau_exported_types :: proc "c" (L: ^lua_State, source: cstring, size: uintptr) -> i32 ---
		@(link_name = "kine_luau_lint_rules")
		luau_lint_rules :: proc "c" (L: ^lua_State) -> i32 ---
	}
}
