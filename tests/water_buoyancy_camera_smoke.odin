package main

import classes "../src/engine/classes"
import datatypes "../src/engine/datatypes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(v, source, "water_buoyancy_camera_smoke")
	assert(ok, err)
}
step :: proc(env: ^engine_runtime.Environment, v: ^vm.VM, frames: int) {
	for _ in 0 ..< frames {engine_runtime.Environment_Render_Step(env, v, 1.0 / 60.0)}
}

main :: proc() {
	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
	run(
		&v,
		`
workspace.FallHeightEnabled = false
pool = Instance.new("Part",workspace)
pool.Name = "Pool"; pool.Anchored = true
pool.Material = Enum.Material.Water
pool.Size = Vector3.new(80,20,80); pool.CFrame = CFrame.new(0,-6,0)
floating = Instance.new("Part",workspace)
floating.Anchored = false
floating.Size = Vector3.new(2,2,2); floating.CFrame = CFrame.new(0,-1,0)
dry = Instance.new("Part",workspace)
dry.Anchored = false
dry.Size = Vector3.new(2,2,2); dry.CFrame = CFrame.new(100,20,0)
fixed = Instance.new("Part",workspace); fixed.Anchored = true; fixed.CFrame = CFrame.new(10,-1,0)
`,
	)
	physics := cast(^services.Physics)services.Ensure_Service(&env.services, "Physics")
	workspace := services.Ensure_Service(&env.services, "Workspace")
	services.Physics_Synchronize(physics, workspace)
	water := services.Water_Context_Create(physics)
	wet, _ := services.Water_Submersion(&water, {0, -1, 0}, 1)
	assert(wet > 0.99, "submerged object not recognized")
	outside, _ := services.Water_Submersion(&water, {100, -1, 0}, 1)
	below, _ := services.Water_Submersion(&water, {0, -30, 0}, 1)
	assert(outside == 0 && below == 0, "water force escaped its volume")
	delete(water.parts)
	step(&env, &v, 240)
	run(
		&v,
		`
assert(floating.Position.Y > 1 and floating.Position.Y < 6, "body did not rise and float: "..tostring(floating.Position.Y))
assert(dry.Position.Y < 0,"dry body did not fall normally")
assert(fixed.CFrame.Position.Y == -1,"anchored body moved")
assert(pool.CFrame.Position.Y == -6,"water volume moved")
`,
	)
	step(&env, &v, 240)
	run(
		&v,
		`assert(floating.Position.Y > 1 and floating.Position.Y < 6,"buoyancy became unstable")`,
	)

	for i in 0 ..< 20 {
		x, z, t := f32(i) * 1.7, f32(i) * (-0.9), f32(i) * 0.2
		displacement := datatypes.Water_Wave_Displacement(x, z, t, 1, 1, 1, 1, 6)
		h := datatypes.Water_Wave_Height(x + displacement.x, z + displacement.z, t, 1, 1, 1, 1, 6)
		assert(abs(h - displacement.y) < 0.0001, "wave sampler missed displaced crest")
		_, velocity := datatypes.Water_Wave_Sample(x, z, t, 1, 1, 1, 1, 6)
		derivative :=
			(datatypes.Water_Wave_Height(x, z, t + 0.001, 1, 1, 1, 1, 6) -
				datatypes.Water_Wave_Height(x, z, t - 0.001, 1, 1, 1, 1, 6)) /
			0.002
		assert(abs(velocity - derivative) < 0.002, "wave velocity did not match moving surface")
	}
	assert(
		abs(
			datatypes.Water_Wave_Height(3, 4, 0, 1, 1, 1, 1, 6) -
			datatypes.Water_Wave_Height(3, 4, 2, 1, 1, 1, 1, 6),
		) >
		0.01,
	)


	run(
		&v,
		`
pool:Destroy(); floating:Destroy(); dry:Destroy(); fixed:Destroy()
local terrain = game:GetService("Terrain")
terrain:FillBlock(CFrame.new(0,6,8),Vector3.new(24,24,4),Enum.Material.Rock)
`,
	)
	camera := classes.Camera_Init()
	camera.viewport_width = 800; camera.viewport_height = 600
	resolved := services.camera_resolve_obstruction(
		env.services.data_model,
		&camera,
		{0, 6, 0},
		{0, 6, 16},
	)
	fmt.println("Terrain camera resolved:", resolved)
	assert(resolved.z > 0 && resolved.z < 7, "camera clipped through terrain")
	free := services.camera_resolve_obstruction(
		env.services.data_model,
		&camera,
		{50, 6, 0},
		{50, 6, 16},
	)
	assert(abs(free.z - 16) < 0.0001, "camera shortened an unobstructed orbit")

	run(
		&v,
		`
local terrain = game:GetService("Terrain")
terrain:Clear()
for x=-3,3 do for z=-3,3 do for y=-3,1 do terrain:SetWaterCell(x,y,z) end end end
floating = Instance.new("Part",workspace)
floating.Anchored = false
floating.Size = Vector3.new(2,2,2); floating.CFrame = CFrame.new(2,-2,2)
`,
	)
	step(&env, &v, 240)
	run(
		&v,
		`assert(floating.Position.Y > 3 and floating.Position.Y < 8,"terrain water did not float body: "..tostring(floating.Position.Y))`,
	)


	run(
		&v,
		`
game:GetService("Terrain"):Clear(); floating:Destroy()
pool = Instance.new("Part",workspace); pool.Anchored = true; pool.Material = Enum.Material.Water
pool.Size = Vector3.new(80,20,80); pool.CFrame = CFrame.new(0,-6,0)
character = Instance.new("CharacterModel",workspace)
local root = Instance.new("Part",character); root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2,5,2); root.CFrame = CFrame.new(0,-2,0); root.Anchored = true
`,
	)
	vm.GetGlobal(v.L, "character")
	character := cast(^classes.CharacterModel)classes.Object_From_Argument(v.L, -1)
	vm.Pop(v.L)
	classes.CharacterController_Build(&env.classes, v.L, character)
	cc := classes.CharacterController_From_Model(character)
	services.Physics_Synchronize(physics, workspace)
	for _ in 0 ..< 240 {
		services.CharacterController_Tick(cc, physics, v.L, 1.0 / 60.0)
		step(&env, &v, 1)
	}
	root := classes.CharacterModel_Root(character)
	fmt.println("Floating character height:", root.cframe.y)
	assert(root.cframe.y > 1 && root.cframe.y < 6, "character did not rise and float")
	fmt.println("WATER_BUOYANCY_CAMERA_SMOKE_PASSED")
}
