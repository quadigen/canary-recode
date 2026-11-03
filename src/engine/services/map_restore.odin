#+build !js
package services

import "core:fmt"
import "core:strings"
import "core:slice"
import assetstore "../assetstore"
import classes "../classes"
import serializer "../serializer"
import vm "../vm"
map_instance_count :: proc(object: ^classes.Object) -> int {
	if object == nil || object.destroyed {return 0}
	count := 1
	for child in object.children {count += map_instance_count(child)}
	return count
}

map_keep_child :: proc(parent, child: ^classes.Object) -> bool {
	return child.editor_scene_helper || (classes.Is_A(parent, "Workspace") && classes.Is_A(child, "Camera"))
}

clear_editor_selection :: proc(registry: ^Registry, L: ^vm.State) {
	if registry.mode != .Editor {return}
	if descriptor := Find_Service(registry, "Selection"); descriptor != nil && descriptor.object != nil {
		Selection_Set(cast(^Selection)descriptor.object, L, nil)
	}
}

map_is_saved_editor_helper :: proc(kept: []^classes.Object, child: ^classes.Object) -> bool {
	for live in kept {
		if live.editor_scene_helper && live.name == child.name && live.class == child.class {return true}
	}
	return false
}

Restore_Map :: proc(registry: ^Registry, L: ^vm.State, data: []u8, name: string, clear_assets := true) -> bool {
	// A new map brings its own assets, so the previous map's must not linger.
	// Clearing first also keeps a stale entry from colliding with a new content
	// id and making a perfectly good stream look corrupt.
	if clear_assets {assetstore.Clear()}

	// The voxel grid rides in the format's own section rather than the tree,
	// because Terrain is a singleton service and not an Instance.
	terrain_table: serializer.Kine_Terrain
	defer serializer.Kine_Terrain_Destroy(&terrain_table)

	root, err := serializer.Deserialize_From_Data(registry.classes, L, nil, data, &terrain_table)
	if root == nil || !serializer.Error_Is_None(err) {
		// Leave nothing half-published behind from a stream that did not load.
		if clear_assets {assetstore.Clear()}
		// The serializer names the section, instance, or byte offset that broke,
		// so a rejected map can be diagnosed without guessing which part of it is
		// at fault. Cloned because fmt.tprintf allocates from the temp arena,
		// whose memory must never be freed.
		prefix := strings.clone(fmt.tprintf("Could not load .kine map %s: ", name))
		defer delete(prefix)
		serializer.Error_Print(err, prefix)
		serializer.Error_Delete(&err)
		return false
	}
	serializer.Error_Delete(&err)
	if !classes.Is_A(root, "DataModel") {
		classes.Destroy_Hierarchy(root)
		fmt.eprintf(".kine map root must be a DataModel: %s\n", name)
		return false
	}

	clear_editor_selection(registry, L)

	service_count := 0
	instance_count := 0
	for len(root.children) > 0 {
		source := root.children[len(root.children) - 1]
		if !classes.Is_A(source, "Service") || !Map_Content_Service(source.name) {
			classes.Destroy_Hierarchy(source)
			continue
		}
		target := Ensure_Service(registry, source.name)
		if target == nil || classes.Get_Class_Name(target) != classes.Get_Class_Name(source) {
			classes.Destroy_Hierarchy(source)
			continue
		}
		for {
			removed := false
			for child in target.children {
				if map_keep_child(target, child) {continue}
				classes.Destroy_Hierarchy(child)
				removed = true
				break
			}
			if !removed {break}
		}
		kept := slice.clone(target.children[:], context.temp_allocator)
		children := slice.clone(source.children[:], context.temp_allocator)
		for child in children {
			if map_keep_child(source, child) || map_is_saved_editor_helper(kept, child) {
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
	terrain_object := Ensure_Service(registry, "Terrain")
	if terrain_object != nil {
		// The service holds the renderer object it was built with, which is the
		// one its chunk meshes belong to. Clearing it through any other renderer
		// would free meshes the live one still points at.
		terrain := cast(^Terrain)terrain_object
		if Terrain_Read_Kine_Table(terrain, terrain.renderer, &terrain_table) {
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
