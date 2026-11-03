#+build !js
package engine_runtime

import "core:fmt"
import "core:os"
import "core:strings"
import services "../services"
import vm "../vm"

Load_Map :: proc(environment: ^Environment, script_vm: ^vm.VM, path: string) -> bool {
	if environment == nil || script_vm == nil || script_vm.L == nil || path == "" {return false}
	if !strings.has_suffix(path, ".kine") && !strings.has_suffix(path, ".KINE") {
		fmt.eprintf("Map path must end in .kine: %s\n", path)
		return false
	}
	if !os.exists(path) {
		fmt.eprintf("Map file does not exist: %s\n", path)
		return false
	}
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintf("Map file could not be read: %s\n", path)
		return false
	}
	defer delete(data)
	return Load_Map_From_Data(environment, script_vm, data, path)
}

// Load_Map_From_Data restores a DataModel from an in-memory .KINE byte stream.
// name is used in messages and suffix/version reporting.
Load_Map_From_Data :: proc(
	environment: ^Environment,
	script_vm: ^vm.VM,
	data: []u8,
	name: string,
) -> bool {
	if environment == nil || script_vm == nil || script_vm.L == nil || data == nil {return false}

	return services.Restore_Map(&environment.services, script_vm.L, data, name)
}
