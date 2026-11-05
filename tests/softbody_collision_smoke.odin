package main

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "softbody_collision_smoke")
	assert(ok, err)
}

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	defer {vm.Close(&script_vm); engine_runtime.Environment_Destroy(&env)}
	run(&script_vm, `
workspace.Gravity = 0
local function soft(x, z)
    local b = Instance.new("SoftBody", workspace)
    b.MeshId = "src/engine/assets/shapes/Block.glb"
    b.CFrame = CFrame.new(x, 0, z)
    b.ShapeRetention = 0.8
    return b
end
local function ball(x, z)
    local b = Instance.new("Part", workspace)
    b.Shape = Enum.PartType.Ball
    b.Size = Vector3.new(1, 1, 1)
    b.CFrame = CFrame.new(x, 0, z)
    b.Anchored = false
    return b
end
a, b = soft(-4, 0), soft(0, 0)
anchor = soft(0, 10)
anchor.Anchored = true
anchor.Material = Enum.Material.Wood
anchor.MaterialVariant = "Fabric"
anchor.Transparency = 0.5
local clone = anchor:Clone()
assert(clone.Anchored and clone.Material == Enum.Material.Wood)
assert(clone.MaterialVariant == "Fabric" and clone.Transparency == 0.5)
clone:Destroy()
ballAtAnchor = ball(-4, 10)
moving = soft(0, 20)
ballAtMoving = ball(-4, 20)
softAtAnchor, fixed = soft(-4, 30), soft(0, 30)
fixed.Anchored = true
`)
	physics := cast(^services.Physics)services.Ensure_Service(&env.services, "Physics")
	dt :: f32(1.0 / 60.0)
	services.Physics_Step(physics, dt)
	run(&script_vm, `
a:ApplyImpulse(Vector3.new(12, 0, 0))
anchor:ApplyImpulse(Vector3.new(30, 0, 0))
ballAtAnchor.AssemblyLinearVelocity = Vector3.new(12, 0, 0)
ballAtMoving.AssemblyLinearVelocity = Vector3.new(12, 0, 0)
softAtAnchor:ApplyImpulse(Vector3.new(12, 0, 0))
`)
	for _ in 0 ..< 50 {services.Physics_Step(physics, dt)}
	run(&script_vm, `
assert(b:GetSimulationCFrame().Position.X > 0.8, "moving SoftBody failed to push its target")
assert(a:GetSimulationCFrame().Position.X < b:GetSimulationCFrame().Position.X, "the SoftBodies passed through one another")
assert(math.abs(anchor:GetSimulationCFrame().Position.X) < 0.001, "anchored SoftBody moved")
assert(ballAtAnchor.Position.X < -0.4, "ball passed through the anchored SoftBody")
assert(moving:GetSimulationCFrame().Position.X > 0.5, "ball failed to push the moving SoftBody")
assert(softAtAnchor:GetSimulationCFrame().Position.X < -0.5, "moving SoftBody passed through the anchored SoftBody")
assert(math.abs(fixed:GetSimulationCFrame().Position.X) < 0.001, "moving SoftBody pushed the anchored SoftBody")
anchor.Anchored = false
anchor:ApplyImpulse(Vector3.new(6, 0, 0))
`)
	for _ in 0 ..< 10 {services.Physics_Step(physics, dt)}
	run(&script_vm, `assert(anchor:GetSimulationCFrame().Position.X > 0.2, "unanchoring did not resume physics")`)
	fmt.println("SOFTBODY_COLLISION_SMOKE_PASSED")
}
