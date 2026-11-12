package services

import assetstore "../assetstore"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"

TERRAIN_HEIGHTFIELD_MAX_SEGMENTS :: 256

terrain_bake_heightfield :: proc(
	L: ^vm.State,
	size: datatypes.Vector2,
	segments_x, segments_z: int,
	origin_y: f32,
) -> (
	uri: string,
	center_y, height: f32,
	err: string,
) {
	width := segments_x + 1
	heights := make([]f32, width * (segments_z + 1))
	defer delete(heights)
	low, high := max(f32), -max(f32)
	for row in 0 ..= segments_z {
		z := (f64(row) / f64(segments_z) - 0.5) * f64(size.Y)
		for col in 0 ..= segments_x {
			x := (f64(col) / f64(segments_x) - 0.5) * f64(size.X)
			vm.PushValue(L, 5)
			vm.PushNumber(L, x)
			vm.PushNumber(L, z)
			if ok, callback_error := vm.ProtectedCall(L, 2, 1); !ok {
				return "", 0, 0, callback_error
			}
			if !vm.IsNumber(L, -1) {
				vm.Pop(L)
				return "", 0, 0, strings.clone("heightAt must return a finite number")
			}
			y := f32(vm.ArgNumber(L, -1))
			vm.Pop(L)
			if !physics_finite_f32(y) || !physics_finite_f32(origin_y + y) {
				return "", 0, 0, strings.clone(
					"heightAt must return a finite height within world bounds",
				)
			}
			heights[row * width + col] = y
			low = min(low, y)
			high = max(high, y)
		}
	}

	center_y = low + (high - low) * 0.5
	height = max(high - low, 0.002)
	builder: strings.Builder
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "o Heightfield\n")
	for row in 0 ..= segments_z {
		v := f64(row) / f64(segments_z)
		for col in 0 ..= segments_x {
			u := f64(col) / f64(segments_x)
			y := f64(heights[row * width + col] - center_y) * 2 / f64(height)
			fmt.sbprintf(&builder, "v %.9g %.9g %.9g\n", u * 2 - 1, y, v * 2 - 1)
			fmt.sbprintf(&builder, "vt %.9g %.9g\n", u, v)

			left, right := max(col - 1, 0), min(col + 1, segments_x)
			front, back := max(row - 1, 0), min(row + 1, segments_z)
			dx :=
				f64(heights[row * width + left] - heights[row * width + right]) *
				f64(segments_x) /
				(f64(right - left) * f64(height))
			dz :=
				f64(heights[front * width + col] - heights[back * width + col]) *
				f64(segments_z) /
				(f64(back - front) * f64(height))
			inv_length := 1 / math.sqrt(dx * dx + 1 + dz * dz)
			fmt.sbprintf(
				&builder,
				"vn %.9g %.9g %.9g\n",
				dx * inv_length,
				inv_length,
				dz * inv_length,
			)
		}
	}
	for row in 0 ..< segments_z {
		for col in 0 ..< segments_x {
			a := row * width + col + 1
			b, c := a + 1, a + width
			d := c + 1
			fmt.sbprintf(&builder, "f %d/%d/%d %d/%d/%d %d/%d/%d\n", a, a, a, c, c, c, b, b, b)
			fmt.sbprintf(&builder, "f %d/%d/%d %d/%d/%d %d/%d/%d\n", b, b, b, c, c, c, d, d, d)
		}
	}
	obj := strings.to_string(builder)
	id := assetstore.Register(slice.clone(transmute([]u8)obj), "heightfield.obj", .Mesh)
	if id == "" {
		return "", 0, 0, strings.clone("could not register the heightfield mesh")
	}
	defer delete(id)
	return assetstore.Make_Uri(id), center_y, height, ""
}

terrain_create_heightfield :: proc(
	L: ^vm.State,
	service: ^Terrain,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
) -> string {
	if datatype_registry == nil || service.data_model == nil {
		return strings.clone("Terrain:CreateHeightfield requires a world")
	}
	origin := datatypes.Arg_Vector3(L, 2)
	size := datatypes.Arg_Vector2(L, 3, datatype_registry)
	material := terrain_arg_material(L, 4, enum_registry, .Grass)
	spacing := vm.ArgOptionalNumber(L, 6, 1)
	if !vm.IsFunction(L, 5) {
		return strings.clone("Terrain:CreateHeightfield expects a heightAt(x, z) function")
	}
	if material == .Air || material == .Water {
		return strings.clone("Terrain:CreateHeightfield expects a surface material")
	}
	if !physics_finite_f32(origin.x) ||
	   !physics_finite_f32(origin.y) ||
	   !physics_finite_f32(origin.z) ||
	   !physics_finite_f32(size.X) ||
	   !physics_finite_f32(size.Y) ||
	   size.X < 0.002 ||
	   size.Y < 0.002 ||
	   !(spacing > 0) ||
	   math.is_inf(spacing) {
		return strings.clone(
			"Terrain:CreateHeightfield expects a finite origin, positive size, and positive spacing",
		)
	}
	nx := math.ceil(f64(size.X) / spacing)
	nz := math.ceil(f64(size.Y) / spacing)
	if nx > TERRAIN_HEIGHTFIELD_MAX_SEGMENTS || nz > TERRAIN_HEIGHTFIELD_MAX_SEGMENTS {
		return strings.clone(
			"Terrain:CreateHeightfield allows at most 256 segments per axis. Increase the spacing or use a smaller area",
		)
	}
	uri, center_y, height, err := terrain_bake_heightfield(
		L,
		size,
		max(1, int(nx)),
		max(1, int(nz)),
		origin.y,
	)
	if err != "" {return err}

	workspace := Service_Get_Service(&service.service, "Workspace")
	registry := service.data_model.registry.classes
	object, ok := classes.Push_New(registry, &vm.VM{L = L}, "MeshPart")
	if !ok {
		delete(uri)
		return strings.clone("Terrain:CreateHeightfield could not create the mesh part")
	}
	part := cast(^classes.MeshPart)object
	part.mesh_id = uri
	part.material = material
	part.collision_fidelity = .TriangleMesh
	part.size = {size.X, height, size.Y}
	part.position = {origin.x, origin.y + center_y, origin.z}
	part.cframe.x, part.cframe.y, part.cframe.z = part.position.x, part.position.y, part.position.z
	classes.Set_Name(object, "Heightfield")
	classes.Set_Parent(object, workspace)
	return ""
}
