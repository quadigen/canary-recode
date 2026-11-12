package kineffi

Csg_Input :: struct {
	bytes:      rawptr,
	length:     uintptr,
	hint:       cstring,
	path:       cstring,
	mesh_index: u32,
	size:       [3]f32,
	transform:  [12]f32,
	shape:      i32,
	negative:   i32,
}

Csg_Output :: struct {
	center: [3]f32,
	size:   [3]f32,
	data:   [^]u8,
	length: uintptr,
}

when ODIN_OS != .JS && !#config(KINE_ANDROID, false) {
	when ODIN_OS == .Windows {
		foreign import csg_lib {
			"../../../vendor/build/lib/kine_csg.lib",
			"../../../vendor/build/lib/kine_manifold.lib",
			"../../../vendor/build/lib/kine_assimp.lib",
		}
	} else {
		foreign import csg_lib "../../../vendor/build/lib/KinemiumLibs.a"
	}

	foreign csg_lib {
		Kine_Csg_Apply :: proc "c" (inputs: [^]Csg_Input, count, operation: u32, output: ^Csg_Output) -> i32 ---
		Kine_Csg_Free :: proc "c" (output: ^Csg_Output) ---
	}
}
