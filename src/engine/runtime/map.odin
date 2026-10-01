#+build !js
package engine_runtime

import "core:fmt"
import "core:os"
import "core:strings"
import assetstore "../assetstore"
import classes "../classes"
import serializer "../serializer"
import services "../services"
import vm "../vm"

map_instance_count :: proc(object: ^classes.Object) -> int {
	if object == nil || object.destroyed {return 0}
	count := 1
	for child in object.children {count += map_instance_count(child)}
	return count
}

map_content_service :: proc(name: string) -> bool {
	return services.Map_Content_Service(name)
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

	// A new map brings its own assets, so the previous map's must not linger.
	// Clearing first also keeps a stale entry from colliding with a new content
	// id and making a perfectly good stream look corrupt.
	assetstore.Clear()

	// The voxel grid rides in the format's own section rather than the tree,
	// because Terrain is a singleton service and not an Instance.
	terrain_table: serializer.Kine_Terrain
	defer serializer.Kine_Terrain_Destroy(&terrain_table)

	root, ok := serializer.Deserialize_From_Data(&environment.classes, script_vm.L, nil, data, &terrain_table)
	if !ok || root == nil {
		// Leave nothing half-published behind from a stream that did not load.
		assetstore.Clear()
		fmt.eprintf("Could not load .kine map (expected KINE version %d): %s\n", serializer.KINE_VERSION, name)
		return false
	}
	if !classes.Is_A(root, "DataModel") {
		classes.Destroy_Hierarchy(root)
		fmt.eprintf(".kine map root must be a DataModel: %s\n", name)
		return false
	}

	service_count := 0
	instance_count := 0
	for len(root.children) > 0 {
		source := root.children[len(root.children) - 1]
		if !classes.Is_A(source, "Service") || !map_content_service(source.name) {
			classes.Destroy_Hierarchy(source)
			continue
		}
		target := services.Ensure_Service(&environment.services, source.name)
		if target == nil || classes.Get_Class_Name(target) != classes.Get_Class_Name(source) {
			classes.Destroy_Hierarchy(source)
			continue
		}
		for {
			removed := false
			for child in target.children {
				if classes.Is_A(target, "Workspace") && classes.Is_A(child, "Camera") {continue}
				classes.Destroy_Hierarchy(child)
				removed = true
				break
			}
			if !removed {break}
		}
		for len(source.children) > 0 {
			child := source.children[len(source.children) - 1]
			if classes.Is_A(source, "Workspace") && classes.Is_A(child, "Camera") {
				classes.Destroy_Hierarchy(child)
			} else {
				instance_count += map_instance_count(child)
				classes.Set_Parent(child, target)
			}
		}
		service_count += 1
		classes.Destroy_Hierarchy(source)
	}
	classes.Destroy_Hierarchy(root)

	// Terrain is restored after the tree, so the grid that goes in is the one this
	// file describes rather than whatever the previous map left behind.
	cell_count := 0
	terrain_object := services.Ensure_Service(&environment.services, "Terrain")
	if terrain_object != nil {
		// The service holds the renderer object it was built with, which is the
		// one its chunk meshes belong to. Clearing it through any other renderer
		// would free meshes the live one still points at.
		terrain := cast(^services.Terrain)terrain_object
		if services.Terrain_Read_Kine_Table(terrain, terrain.renderer, &terrain_table) {
			cell_count = len(terrain_table.cells)
		}
	}

	fmt.printf(
		"Loaded .kine DataModel %s (%d services, %d instances, %d terrain cells)\n",
		name,
		service_count,
		instance_count,
		cell_count,
	)
	return true
}
