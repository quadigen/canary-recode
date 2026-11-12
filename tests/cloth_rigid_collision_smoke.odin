package main

import "core:fmt"
import "core:math"
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	defer vm.Close(&script_vm)
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	defer engine_runtime.Environment_Destroy(&env)

	run(&script_vm, `
workspace.SimulatePhysics = true
workspace.Gravity = 80
local template = Instance.new("Model", game:GetService("ReplicatedStorage"))
local mount = Instance.new("Part", template)
mount.Name = "Mount"
mount.CanCollide = false
mount.Position = Vector3.new(0, 5, 0)
local anchor = Instance.new("Attachment", mount)
anchor.CFrame = CFrame.Angles(math.pi / 2, 0, 0)
local cloth = Instance.new("Cloth", template)
cloth.Name = "Curtain"
cloth.Size = Vector2.new(4, 4)
cloth.Attachment0 = anchor
local assembly = template:Clone()
Curtain = assembly.Curtain
assert(Curtain.Attachment0.Parent == assembly.Mount)
assembly.Parent = workspace
Shelf = Instance.new("Part", workspace)
Shelf.Size = Vector3.new(12, 1, 12)
Shelf.Position = Vector3.new(0, 4, 0)
Shelf.Anchored = true
ClothHits, ShelfHits = 0, 0
Curtain.Touched:Connect(function(body)
	if body == Shelf then ClothHits += 1 end
end)
Shelf.Touched:Connect(function(body)
	if body == Curtain then ShelfHits += 1 end
end)
`, "cloth_rigid_setup")
	vm.GetGlobal(script_vm.L, "Curtain")
	cloth := cast(^classes.Cloth)classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	physics := cast(^services.Physics)services.Ensure_Service(&env.services, "Physics")
	for _ in 0 ..< 35 {services.Physics_Step(physics, 1.0 / 60.0)}
	assert(cloth.initialized)
	assert(lowest(cloth) >= 4.52 && lowest(cloth) < 4.65,
	       fmt.tprintf("cloth must rest on the shelf, lowest Y = %v", lowest(cloth)))
	run(&script_vm, `
assert(ClothHits > 0 and ShelfHits == ClothHits)
workspace.Gravity = 0
Shelf.Anchored = false
Shelf.Position += Vector3.new(0, 0.4, 0)
`, "cloth_rigid_move_shelf")
	services.Physics_Step(physics, 1.0 / 60.0)
	assert(lowest(cloth) >= 4.90,
	       fmt.tprintf("the moved shelf must push intersecting cloth out, lowest Y = %v", lowest(cloth)))

	run(&script_vm, `Shelf.CanCollide = false; workspace.Gravity = 80`, "cloth_rigid_disable_shelf")
	for _ in 0 ..< 35 {services.Physics_Step(physics, 1.0 / 60.0)}
	assert(lowest(cloth) < 4.4, "cloth should pass through a noncollidable shelf")
	fmt.println("CLOTH_RIGID_COLLISION_SMOKE_PASSED")
}

lowest :: proc(cloth: ^classes.Cloth) -> f32 {
	y := math.inf_f32(1)
	for particle in cloth.particles {y = min(y, particle.position.y)}
	return y
}

run :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(script_vm, source, name)
	defer delete(err)
	if !ok {panic(err)}
}
