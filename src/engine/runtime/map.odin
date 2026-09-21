#+build !js
package engine_runtime

import "core:fmt"
import "core:os"
import "core:strings"
import classes "../classes"
import serializer "../serializer"
import services "../services"
import vm "../vm"

map_part_count :: proc(object: ^classes.Object) -> int {
	if object == nil || object.destroyed {return 0}
	count := classes.Is_A(object, "Part") ? 1 : 0
	for child in object.children {count += map_part_count(child)}
	return count
}

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
	workspace := cast(^services.Workspace)services.Ensure_Service(&environment.services, "Workspace")
	if workspace == nil {return false}
	root, ok := serializer.Deserialize_From_File(&environment.classes, script_vm.L, nil, path)
	if !ok || root == nil {
		fmt.eprintf("Could not load .kine map (expected native KINE version 1): %s\n", path)
		return false
	}

	source := root
	if classes.Is_A(root, "DataModel") {
		source = classes.Find_First_Child(root, "Workspace")
		if source != nil && !classes.Is_A(source, "Workspace") {source = nil}
	}
	if source == nil {
		classes.Destroy_Hierarchy(root)
		fmt.eprintf(".kine map has no Workspace: %s\n", path)
		return false
	}
	if !classes.Is_A(source, "Workspace") &&
	   !classes.Is_A(source, "Model") &&
	   !classes.Is_A(source, "Folder") &&
	   !classes.Is_A(source, "Part") {
		classes.Destroy_Hierarchy(root)
		fmt.eprintf(".kine map root must be a Workspace, Model, Folder, or Part: %s\n", path)
		return false
	}

	count := map_part_count(source)
	if classes.Is_A(source, "Workspace") {
		for len(source.children) > 0 {
			child := source.children[len(source.children) - 1]
			if classes.Is_A(child, "Camera") {
				classes.Destroy_Hierarchy(child)
			} else {
				classes.Set_Parent(child, &workspace.object)
			}
		}
		classes.Destroy_Hierarchy(root)
	} else {
		classes.Set_Parent(root, &workspace.object)
	}
	fmt.printf("Loaded .kine map %s (%d parts)\n", path, count)
	return true
}
