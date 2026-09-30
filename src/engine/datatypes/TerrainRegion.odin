package datatypes

import "core:fmt"
import vm "../vm"

TerrainRegion :: struct {
	size:      Vector3int16,
	materials: []i64,
	occupancy: []f32,
}

terrain_region_dimensions :: proc(size: Vector3int16) -> (nx, ny, nz: int) {
	nx = max(int(size.X), 0)
	ny = max(int(size.Y), 0)
	nz = max(int(size.Z), 0)
	return
}

TerrainRegion_New :: proc(size: Vector3int16) -> TerrainRegion {
	nx, ny, nz := terrain_region_dimensions(size)
	count := nx * ny * nz

	return TerrainRegion{
		size      = size,
		materials = make([]i64, count),
		occupancy = make([]f32, count),
	}
}

TerrainRegion_Index :: proc(region: ^TerrainRegion, x, y, z: int) -> (int, bool) {
	nx, ny, nz := terrain_region_dimensions(region.size)
	if x < 0 || y < 0 || z < 0 || x >= nx || y >= ny || z >= nz {
		return 0, false
	}
	return (x*ny + y)*nz + z, true
}

push_terrain_region :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: TerrainRegion,
) {
	stored := new(TerrainRegion)
	stored^ = value
	vm.PushUserdata(&vm.VM{L = L}, stored, binding)
}

Push_TerrainRegion :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: TerrainRegion,
) {
	push_terrain_region(L, &registry.terrain_region, value)
}

Arg_TerrainRegion :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> ^TerrainRegion {
	if registry == nil || !vm.IsUserdataType(L, index, &registry.terrain_region) {
		_ = vm.RaiseError(L, "expected TerrainRegion")
		return nil
	}
	return cast(^TerrainRegion)vm.UserdataValue(L, index)
}

terrain_region_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	region := cast(^TerrainRegion)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)
	if registry == nil {
		return false
	}

	switch key {
	case "Size":
		push_vector3int16(L, &registry.vector3int16, region.size)
	case "ClassName":
		vm.PushString(L, "TerrainRegion")
	case "Destroy":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}

	return true
}

terrain_region_namecall :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	method: string,
) -> (i32, bool) {
	switch method {
	case "Destroy":
		// TerrainRegion has no native resources beyond its own slices, which the
		// userdata destructor frees.
		return 0, true
	}
	return 0, false
}

terrain_region_string :: proc(value, ctx: rawptr) -> string {
	region := cast(^TerrainRegion)value
	return fmt.tprintf("TerrainRegion(%d, %d, %d)", region.size.X, region.size.Y, region.size.Z)
}

terrain_region_destroy :: proc(value, ctx: rawptr) {
	region := cast(^TerrainRegion)value
	delete(region.materials)
	delete(region.occupancy)
	free(region)
}

TerrainRegion_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "TerrainRegion",
		get      = terrain_region_get,
		namecall = terrain_region_namecall,
		string   = terrain_region_string,
		destroy  = terrain_region_destroy,
	}
}

TerrainRegion_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	// TerrainRegion is Not Creatable; there is nothing to install.
}
