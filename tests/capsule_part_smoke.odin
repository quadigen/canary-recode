package main

import kineffi "../src/engine/bindings"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "capsule_part")
	if !ok {fmt.eprintln(err); panic("capsule script failed")}
}

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	physics := cast(^services.Physics)services.Ensure_Service(&env.services, "Physics")
	run_script(
		&script_vm,
		`
p = Instance.new("Part", workspace)
p.Name = "CapsuleTest"
p.Position = Vector3.new(0, 50, 0)
`,
	)
	engine_runtime.Environment_Update_Step(&env, &script_vm, 1.0 / 60.0)
	fmt.println("Changing default-sized Part to Capsule")
	run_script(&script_vm, `p.Shape = Enum.PartType.Capsule`)
	engine_runtime.Environment_Update_Step(&env, &script_vm, 1.0 / 60.0)
	assert(len(physics.bodies) == 1 && physics.bodies[0].shape == .Capsule)
	// The native factory must also safely handle degenerate capsules when
	// called directly (including character-controller users of the binding).
	shape := kineffi.JPH_CapsuleShape_Create(0, 1, 0)
	assert(shape != nil)
	lo, hi: kineffi.JPH_Vec3
	kineffi.JPH_Shape_GetLocalBounds(shape, &lo, &hi)
	assert(abs(lo.y + 1) < 0.001 && abs(hi.y - 1) < 0.001)
	kineffi.JPH_Shape_Destroy(shape)
	assert(kineffi.JPH_CapsuleShape_Create(-1, 1, 0) == nil)
	assert(kineffi.JPH_CapsuleShape_Create(1, 0, 0) == nil)
	sizes := [?]string{"2, 2, 2", "2, 6, 2", "4, 0.1, 2", "0.002, 0.002, 0.002", "3, 5, 1"}
	for size in sizes {
		run_script(&script_vm, fmt.tprintf("p.Size = Vector3.new(%s)", size))
		engine_runtime.Environment_Update_Step(&env, &script_vm, 1.0 / 60.0)
		assert(
			len(physics.bodies) == 1 && physics.bodies[0].body_id != kineffi.JPH_BODY_ID_INVALID,
		)
		body := physics.bodies[0]
		collider := kineffi.JPH_BodyInterface_GetShape(physics.system.body_interface, body.body_id)
		assert(collider != nil)
		kineffi.JPH_Shape_GetLocalBounds(collider, &lo, &hi)
		assert(hi.y > 0 && abs(hi.y - body.size.y * 0.5) < 0.001)
		assert(kineffi.JPH_Shape_GetVolume(collider) > 0)
	}
	run_script(&script_vm, `p.Size = Vector3.new(2, 2, 2); p.Anchored = false`)
	for _ in 0 ..< 20 {engine_runtime.Environment_Update_Step(&env, &script_vm, 1.0 / 60.0)}
	run_script(&script_vm, `assert(p.Position.Y < 50 and p.Shape == Enum.PartType.Capsule)`)
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&env)
	fmt.println("CAPSULE_PART_SMOKE_PASSED")
}
