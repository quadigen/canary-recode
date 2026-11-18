package kineffi

KINE_SHADER_COMPILER_LINKED ::
	ODIN_OS == .Windows || (ODIN_OS == .Linux && !#config(KINE_ANDROID, false))

when KINE_SHADER_COMPILER_LINKED {
	when ODIN_OS == .Windows {
		foreign import kine_shader_compiler {"../../../vendor/build/lib/KinemiumLibs.lib", "../../../vendor/build/lib/kine_filament_filamat.lib"}
	} else {
		foreign import kine_shader_compiler {"../../../vendor/build/lib/KinemiumLibs.a", "system:c++", "system:pthread"}
	}
	@(default_calling_convention = "c")
	foreign kine_shader_compiler {
		Kine_Shader_Compile :: proc(source: rawptr, length: uint, words: ^^u32, word_count: ^uint, error_data: ^u8, error_capacity: uint) -> i32 ---
		Kine_Shader_Free :: proc(words: ^u32) ---
	}
}
