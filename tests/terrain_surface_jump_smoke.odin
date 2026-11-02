package main
import classes "../src/engine/classes"
import datatypes "../src/engine/datatypes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:math"

run :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "terrain_surface_regression")
	if !ok {fmt.eprintln(err); panic("script failed")}
}

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	terrain := cast(^services.Terrain)services.Ensure_Service(&env.services, "Terrain")
	physics := cast(^services.Physics)services.Ensure_Service(&env.services, "Physics")
	workspace := services.Ensure_Service(&env.services, "Workspace")
	run(
		&script_vm,
		`
local terrain = game:GetService("Terrain")
terrain:Clear()
terrain:FillBall(Vector3.new(64, 28, 28), 12, Enum.Material.Slate)
terrain:FillBall(Vector3.new(-64, 28, 28), 12, Enum.Material.Slate)
`,
	)
	for _ in 0 ..< 100 {
		services.Physics_Synchronize_Terrain(physics)
		if physics.terrain_version == terrain.geometry_version {break}
	}
	checked, missed := 0, 0
	worst: f32
	for key, _ in terrain.chunks {
		verts: [dynamic]f32
		weights: [dynamic]f32
		indices: [dynamic]u16
		if services.Terrain_Build_Chunk_Mesh(terrain, key, &verts, &weights, &indices) {
			for i := 0; i < len(indices); i += 39 {
				if i + 2 >= len(indices) {break}
				a, b, c := int(indices[i]) * 8, int(indices[i + 1]) * 8, int(indices[i + 2]) * 8
				pa := datatypes.Vector3{verts[a], verts[a + 1], verts[a + 2]}
				pb := datatypes.Vector3{verts[b], verts[b + 1], verts[b + 2]}
				pc := datatypes.Vector3{verts[c], verts[c + 1], verts[c + 2]}
				n := datatypes.Vec3_Cross(
					datatypes.Vec3_Subtract(pb, pa),
					datatypes.Vec3_Subtract(pc, pa),
				)
				len_n := datatypes.Vec3_Magnitude(n)
				if len_n < 0.0001 {continue}
				n = datatypes.Vec3_Divide(n, len_n)
				center := datatypes.Vec3_Divide(
					datatypes.Vec3_Add(datatypes.Vec3_Add(pa, pb), pc),
					3,
				)
				origin := datatypes.Vec3_Add(center, datatypes.Vec3_Multiply(n, 0.5))
				ray, hit := services.Physics_Raycast(
					physics,
					workspace,
					origin,
					datatypes.Vec3_Multiply(n, -1),
				)
				checked += 1
				if !hit {missed += 1; continue}
				worst = max(
					worst,
					datatypes.Vec3_Magnitude(datatypes.Vec3_Subtract(ray.Position, center)),
				)
			}
		}
		delete(verts); delete(weights); delete(indices)
	}
	fmt.printf("surface samples=%d missed=%d max_error=%f\n", checked, missed, worst)
	run(
		&script_vm,
		`
local terrain = game:GetService("Terrain")
terrain:Clear()
terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(200, 4, 200), Enum.Material.Grass)
local model = Instance.new("CharacterModel", workspace)
local root = Instance.new("Part", model)
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(3, 5, 3)
root.Anchored = true
root.CanCollide = false
root.CanQuery = false
root.Position = Vector3.new(20, 15, 20)
local cc = Instance.new("CharacterController", model)
Instance.new("MovementController", cc)
Instance.new("GroundDetector", cc)
Instance.new("CollisionController", cc)
`,
	)
	for _ in 0 ..< 100 {
		services.Physics_Synchronize(physics, workspace)
		if physics.terrain_version == terrain.geometry_version {break}
	}
	model := cast(^classes.CharacterModel)classes.Find_Child(workspace, "CharacterModel")
	root := classes.CharacterModel_Root(model)
	cc := classes.CharacterController_From_Model(model)
	move := cast(^classes.MovementController)classes.CharacterController_Find(
		cc,
		"MovementController",
	)
	ground := cast(^classes.GroundDetector)classes.CharacterController_Find(cc, "GroundDetector")
	for _ in 0 ..< 480 {services.CharacterController_Tick(cc, physics, script_vm.L, 1.0 / 120.0)}
	rest := root.position.y
	fmt.printf("ground rest=%f grounded=%v slope=%f\n", rest, ground.grounded, ground.slope_angle)
	classes.MovementController_Queue_Jump(move)
	peak := rest
	for _ in 0 ..< 120 {
		services.CharacterController_Tick(cc, physics, script_vm.L, 1.0 / 120.0)
		peak = max(peak, root.position.y)
	}
	fmt.printf(
		"jump rise=%f final=%f grounded=%v\n",
		peak - rest,
		root.position.y,
		ground.grounded,
	)
	assert(peak > rest + 2, "character cannot jump on terrain")
	assert(math.abs(root.position.y - rest) < 0.2, "character did not land back on terrain")
	assert(
		checked >= 30 && missed == 0 && worst < 0.002,
		"terrain collider does not match rendered surface",
	)
	move.input_direction = {1, 0, 0}
	for _ in 0 ..< 400 {services.CharacterController_Tick(cc, physics, script_vm.L, 1.0 / 120.0)}
	assert(root.position.x > 64, "character did not cross the terrain chunk boundary")
	assert(
		math.abs(root.position.y - rest) < 0.2 && ground.grounded,
		"character lost support at a chunk boundary",
	)
	move.input_direction = {}
	for _ in 0 ..< 120 {services.CharacterController_Tick(cc, physics, script_vm.L, 1.0 / 120.0)}
	classes.MovementController_Queue_Jump(move)
	second_peak := root.position.y
	for _ in 0 ..< 120 {
		services.CharacterController_Tick(cc, physics, script_vm.L, 1.0 / 120.0)
		second_peak = max(second_peak, root.position.y)
	}
	assert(
		second_peak > rest + 2 && math.abs(root.position.y - rest) < 0.2,
		"jump or landing failed after crossing terrain chunks",
	)
	fmt.printf(
		"cross-chunk walk x=%f; repeated jump rise=%f\n",
		root.position.x,
		second_peak - rest,
	)
	fmt.println("TERRAIN_SURFACE_AND_JUMP_REGRESSION_PASSED")
}
