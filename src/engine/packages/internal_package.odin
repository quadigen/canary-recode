package packages

import vm "../vm"
import "core:fmt"
import "core:strings"


internal_package_u32 :: proc(data: []u8, pos: ^int) -> (u32, bool) {
	if pos^ > len(data) - 4 {return 0, false}
	d := data[pos^:][:4]
	pos^ += 4
	return u32(d[0]) | u32(d[1]) << 8 | u32(d[2]) << 16 | u32(d[3]) << 24, true
}
internal_package_string :: proc(data: []u8, pos: ^int) -> (string, bool) {
	n, ok := internal_package_u32(data, pos)
	if !ok || u64(n) > u64(len(data) - pos^) {return "", false}
	value := string(data[pos^:pos^ + int(n)])
	pos^ += int(n)
	return value, true
}
Load_Internal_Modules_From_Package :: proc(registry: ^Registry, data: []u8) -> bool {
	if registry == nil || len(data) < 8 || string(data[:4]) != "KEMP" {return false}
	pos := 4
	count, ok := internal_package_u32(data, &pos)
	if !ok || count > 100000 {return false}
	loaded: [dynamic]Internal_Module
	keep := false
	defer if !keep {destroy_internal_modules(&loaded)}
	names: map[string]bool
	defer delete(names)
	for _ in 0 ..< int(count) {
		name, valid_name := internal_package_string(data, &pos)
		source, valid_source := internal_package_string(data, &pos)
		if !valid_name ||
		   !valid_source ||
		   name == "" ||
		   strings.contains(name, "..") ||
		   strings.contains(name, "\\") ||
		   strings.contains(name, "\"") ||
		   names[name] {return false}
		names[name] = true
		append(
			&loaded,
			Internal_Module {
				name = strings.clone(name),
				source = strings.clone(source),
				owned = true,
			},
		)
	}
	if pos != len(data) || !names["editor_ui"] {return false}
	L: ^vm.State
	if registry.vm_state != nil {L = registry.vm_state.L}
	destroy_internal_modules(&registry.internal_modules, L)
	registry.internal_modules = loaded
	keep = true
	fmt.eprintf("[EditorModules] loaded %d packaged modules\n", count)
	return true
}
