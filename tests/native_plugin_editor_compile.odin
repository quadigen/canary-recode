package main

import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	state := vm.New()
	defer vm.Close(&state)
	editor_root := os.get_env_alloc("KINEMIUM_EDITOR_ROOT", context.allocator)
	if editor_root == "" {
		delete(editor_root)
		editor_root = strings.clone("../kinemium-editor/internal")
	}
	defer delete(editor_root)
	if !os.is_directory(editor_root) {
		fmt.println("NATIVE_PLUGIN_EDITOR_LUAU_COMPILE_SKIPPED (set KINEMIUM_EDITOR_ROOT)")
		return
	}
	files := []string{"native_plugins.luau", "home.luau", "topbar_plugins.luau"}
	for name in files {
		path := fmt.aprintf("%s/%s", editor_root, name)
		defer delete(path)
		data, read_err := os.read_entire_file_from_path(path, context.allocator)
		if read_err != nil {panic("failed to read editor Luau source")}
		ok, compile_err := vm.LoadSource(&state, state.L, string(data), name)
		delete(data)
		if !ok {
			fmt.eprintf("%s failed: %s\n", name, compile_err)
			panic("native plugin editor Luau compilation failed")
		}
		vm.Pop(state.L)
	}
	fmt.println("NATIVE_PLUGIN_EDITOR_LUAU_COMPILE_PASSED")
}
