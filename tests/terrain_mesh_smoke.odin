package main

import "core:fmt"

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

terrain_service :: proc(environment: ^engine_runtime.Environment) -> ^services.Terrain {
	object := services.Ensure_Service(&environment.services, "Terrain")
	assert(object != nil, "the Terrain service must be instantiable")
	service := cast(^services.Terrain)object
	assert(service != nil)
	return service
}

run_fill :: proc(script_vm: ^vm.VM, body: string) {
	ok, err := vm.Run(script_vm, body, "terrain_mesh_fill")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("terrain mesh smoke test failed")
	}
}


main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
	}

	terrain := terrain_service(&environment)


	run_fill(
		&script_vm,
		`
local Terrain = game:GetService("Terrain")
Terrain:Clear()
Terrain:FillBall(Vector3.new(28, 28, 28), 12, Enum.Material.Slate)
assert(Terrain:CountCells() > 0, "the fill must create cells")
`,
	)

	vertex_data := make([dynamic]f32, 0)
	material_weights := make([dynamic]f32, 0)
	indices := make([dynamic]u16, 0)
	defer delete(vertex_data)
	defer delete(material_weights)
	defer delete(indices)

	ok := services.Terrain_Build_Chunk_Mesh(
		terrain,
		services.Terrain_Chunk_Key{0, 0, 0},
		&vertex_data,
		&material_weights,
		&indices,
	)
	assert(ok, "a solid ball must extract a surface")

	vertex_count := len(vertex_data) / 8
	assert(vertex_count > 0, "the mesh must have vertices")
	assert(len(material_weights) == vertex_count * 8, "one weight block per vertex")
	assert(len(indices) > 0, "the mesh must have triangles")
	assert(len(indices) % 3 == 0, "indices must be whole triangles")

	for index in indices {
		assert(int(index) < vertex_count, "every index must reference a real vertex")
	}

	triangle_count := len(indices) / 3
	assert(vertex_count < 3 * triangle_count, "triangles must share deduplicated vertices")


	edges := make(map[[2]int]int)
	defer delete(edges)
	for triangle in 0 ..< triangle_count {
		a := int(indices[triangle * 3])
		b := int(indices[triangle * 3 + 1])
		c := int(indices[triangle * 3 + 2])
		assert(a != b && b != c && a != c, "a triangle must not be degenerate")

		for pair in ([3][2]int{{a, b}, {b, c}, {c, a}}) {
			key := pair[0] < pair[1] ? pair : [2]int{pair[1], pair[0]}
			edges[key] += 1
		}
	}
	for _, count in edges {
		assert(count == 2, "a closed surface edge must bound exactly two triangles")
	}


	used := make([]bool, vertex_count)
	defer delete(used)
	for index in indices {
		used[index] = true
	}
	for index in 0 ..< vertex_count {
		assert(used[index], "every vertex must be referenced by a triangle")
	}

	run_fill(&script_vm, `
local terrain = game:GetService("Terrain")
terrain:Clear()
for x = -16, -1 do
    for z = 16, 31 do
        terrain:SetVoxel(x, 15, z, 0.5, Enum.Material.Water)
    end
end
terrain:SetCell(-16, 16, 16, Enum.Material.Rock)
`)
	surfaces: [services.Terrain_Surface_Kind]services.Terrain_Surface_Geometry
	defer {
		for surface in surfaces {
			delete(surface.vertices)
			delete(surface.indices)
		}
	}
	services.Terrain_Build_Chunk_Surfaces(terrain, {-1, 0, 1}, &surfaces)
	water := surfaces[.Water]
	exposed_cells :: 16 * 16 - 1
	assert(len(water.indices) == exposed_cells * 4 * 4 * 6)
	for i := 0; i < len(water.vertices); i += 8 {
		x, y, z := water.vertices[i], water.vertices[i + 1], water.vertices[i + 2]
		assert(x >= -64 && x <= 0 && z >= 64 && z <= 128 && y == 62)
		assert(x >= -60 || z >= 68, "the solid in the chunk above must hide the water below")
	}
	for index in water.indices {
		assert(int(index) < len(water.vertices) / 8)
	}

	fmt.println("TERRAIN_MESH_SMOKE_PASSED")
}
