package main

import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import "core:strings"

check_script :: proc(script_vm: ^vm.VM, directory, filename: string) {
	path := fmt.aprintf("%s/%s", directory, filename)
	defer delete(path)
	bytes, read_err := os.read_entire_file_from_path(path, context.allocator)
	if read_err != nil {
		panic(fmt.tprintf("Could not read editor source %s: %v", path, read_err))
	}
	defer delete(bytes)
	ok, err := vm.LoadSource(script_vm, script_vm.L, string(bytes), filename)
	if !ok {
		fmt.eprintf("%s: %s\n", filename, err)
		delete(err)
		panic("editor debugger Luau compile failed")
	}
	vm.Pop(script_vm.L)
}

main :: proc() {
	dir := os.get_env_alloc("KINEMIUM_EDITOR_ROOT", context.allocator)
	if dir == "" {
		delete(dir)
		dir = strings.clone("../kinemium-editor/internal", context.allocator)
		if !os.exists(dir) {
			delete(dir)
			fmt.println("LUAU_DEBUGGER_EDITOR_COMPILE_SKIPPED (set KINEMIUM_EDITOR_ROOT)")
			return
		}
	}
	defer delete(dir)
	script_vm := vm.New()
	defer vm.Close(&script_vm)
	filenames := []string{"debugger.luau", "topbar_script.luau", "code_editor.luau"}
	for filename in filenames {
		check_script(&script_vm, strings.trim_right(dir, "/"), filename)
	}
	fmt.println("LUAU_DEBUGGER_EDITOR_COMPILE_PASSED")
}
