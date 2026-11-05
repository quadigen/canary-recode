package main

import classes "../src/engine/classes"
import kineffi "../src/engine/bindings"
import datatypes "../src/engine/datatypes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:math"
import "core:math/linalg"

run :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "softbody_smoke")
	assert(ok, err)
}

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	defer {vm.Close(&script_vm); engine_runtime.Environment_Destroy(&env)}
	run(&script_vm, `
floor = Instance.new("Part", workspace)
floor.Anchored = true
floor.Size = Vector3.new(100, 1, 100)
floor.CFrame = CFrame.new(0, -0.5, 0)
body = Instance.new("SoftBody", workspace)
body.MeshId = "src/engine/assets/shapes/Block.glb"
body.CFrame = CFrame.new(0, 5, 0)
body.SpringCompliance = 0.002
body.BendCompliance = 0.005
body.SolverIterations = 8
assert(not pcall(function() body.Mass = 0 end))
assert(not pcall(function() body.SolverIterations = 1.5 end))
`)
	vm.GetGlobal(script_vm.L, "body")
	body := cast(^classes.SoftBody)classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	physics := cast(^services.Physics)services.Ensure_Service(&env.services, "Physics")
	dt :: f32(1.0 / 60.0)
	services.Physics_Step(physics, dt)
	assert(body.system != nil && body.last_error == "", body.last_error)
	assert(body.closed_surface && len(body.rest_positions) == 8, "cube seams were not welded")
	id := body.body_id

	max_deformation := f32(0)
	for _ in 0 ..< 55 {
		services.Physics_Step(physics, dt)
		for i := 0; i < len(body.faces); i += 3 {
			a, b := body.faces[i], body.faces[i + 1]
			p, q := body.positions[a], body.positions[b]
			r, s := body.rest_positions[a], body.rest_positions[b]
			length := linalg.length([3]f32{p.x - q.x, p.y - q.y, p.z - q.z})
			rest := linalg.length([3]f32{r.x - s.x, r.y - s.y, r.z - s.z})
			max_deformation = max(max_deformation, abs(length - rest))
		}
	}
	assert(max_deformation > 0.01, "soft body did not deform on impact")
	assert(body.simulation_cframe.y < 3, "soft body did not fall")
	for p in body.positions {
		world := datatypes.CFrame_PointToWorldSpace(body.simulation_cframe, {p.x, p.y, p.z})
		assert(world.y > -0.2, "soft body penetrated the floor")
	}

	run(&script_vm, `
body.SpringCompliance = 0.0001
body.Pressure = 2
body.Damping = 0.25
body.Mass = 2
body:ApplyImpulse(Vector3.new(10, 14, 0))
`)
	for _ in 0 ..< 8 {services.Physics_Step(physics, dt)}
	assert(body.body_id == id && body.last_error == "", "tuning rebuilt or invalidated the body")
	assert(body.simulation_cframe.x > 0.2, "soft body did not receive the impulse")

	data, err := serializer.Serialize(&env.classes, script_vm.L, &body.object)
	assert(serializer.Error_Is_None(err))
	defer delete(data)
	loaded, load_err := serializer.Deserialize(&env.classes, script_vm.L, nil, data)
	assert(serializer.Error_Is_None(load_err))
	saved := cast(^classes.SoftBody)loaded
	assert(saved.mesh_id != "" && saved.settings == body.settings && saved.cframe.y == 5)

	run(&script_vm, `
handles = Instance.new("Handles")
arcs = Instance.new("ArcHandles")
handles.Adornee = body
arcs.Adornee = body
assert(handles.Adornee == body and arcs.Adornee == body)
`)
	live_frame := body.simulation_cframe
	axis :: kineffi.KINE_GIZMO_AXIS_X
	classes.Handles_Apply_SoftBody_Axis(body, axis, 3, .Movement)
	services.Physics_Step(physics, 0)
	assert(body.body_id == id && abs(body.simulation_cframe.x - live_frame.x - 3) < 1e-4)
	classes.Handles_Apply_SoftBody_Axis(body, kineffi.KINE_GIZMO_AXIS_Y, f32(math.PI / 2), .Rotation)
	services.Physics_Step(physics, 0)
	assert(body.body_id == id && abs(body.simulation_cframe.r02 - 1) < 1e-4)
	classes.Handles_Apply_SoftBody_Axis(body, axis, 1, .Resize, centered = true)
	services.Physics_Step(physics, 0)
	assert(body.body_id != id && body.system != nil && body.scale.x > 1)
	assert(abs(body.simulation_cframe.x - live_frame.x - 3) < 0.1, "resize moved the body back to its spawn")

	run(&script_vm, `
body.Enabled = false
mesh = Instance.new("EditableMesh")
local a = mesh:AddVertex(Vector3.new(0, 0, 0))
local b = mesh:AddVertex(Vector3.new(1, 0, 0))
local c = mesh:AddVertex(Vector3.new(0, 1, 0))
mesh:AddTriangle(a, b, c)
sheet = Instance.new("SoftBody", workspace)
sheet.MeshContent = Content.fromObject(mesh)
sheet.CFrame = CFrame.new(0, 10, 0)
sheet.Pressure = 2
`)
	services.Physics_Step(physics, dt)
	assert(body.system == nil, "disabled soft body retained its Jolt body")
	vm.GetGlobal(script_vm.L, "sheet")
	sheet := cast(^classes.SoftBody)classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	assert(sheet.system != nil && len(sheet.positions) == 3 && !sheet.closed_surface)
	assert(sheet.last_error == "Pressure requires a closed mesh with consistent winding")
	run(&script_vm, `sheet.Parent = nil`)
	services.Physics_Step(physics, dt)
	assert(sheet.system == nil, "detached soft body retained its Jolt body")
	run(&script_vm, `body:Destroy()`)
	classes.Flush_Pending_Destroy(&env.classes)
	run(&script_vm, `assert(handles.Adornee == nil and arcs.Adornee == nil)`)
	check_shape_retention(&script_vm, physics)
	fmt.println("SOFTBODY_SMOKE_PASSED")
}

check_shape_retention :: proc(script_vm: ^vm.VM, physics: ^services.Physics) {
	run(script_vm, `
local function spawn(x)
    local b = Instance.new("SoftBody", workspace)
    b.MeshId = "src/engine/assets/shapes/Block.glb"
    b.CFrame = CFrame.new(x, 5, 0) * CFrame.Angles(0.2, 0, 0.3)
    b.SpringCompliance = 0.03
    b.BendCompliance = 0.03
    return b
end
unassisted = spawn(-5)
retained = spawn(5)
assert(retained.ShapeRetention == 0)
assert(not pcall(function() retained.ShapeRetention = 1.5 end))
`)
	vm.GetGlobal(script_vm.L, "unassisted")
	unassisted := cast(^classes.SoftBody)classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	vm.GetGlobal(script_vm.L, "retained")
	retained := cast(^classes.SoftBody)classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	dt :: f32(1.0 / 60.0)
	services.Physics_Step(physics, dt)
	id := retained.body_id
	run(script_vm, `
retained.ShapeRetention = 0.8
local clone = retained:Clone()
assert(math.abs(clone.ShapeRetention - 0.8) < 1e-6)
clone:Destroy()
`)
	for _ in 0 ..< 90 {services.Physics_Step(physics, dt)}
	assert(retained.body_id == id, "changing shape retention rebuilt the body")
	assert(retained.simulation_cframe.y < 3, "shape retention prevented the body from falling")
	assert(shape_error(retained) < shape_error(unassisted) * 0.65, "shape retention did not help restore the mesh")
}

shape_error :: proc(body: ^classes.SoftBody) -> f32 {
	error := f32(0)
	for a, i in body.positions {
		rest_a := body.rest_positions[i]
		for j in i + 1 ..< len(body.positions) {
			b, rest_b := body.positions[j], body.rest_positions[j]
			distance := linalg.length([3]f32{a.x - b.x, a.y - b.y, a.z - b.z})
			rest := linalg.length([3]f32{rest_a.x - rest_b.x, rest_a.y - rest_b.y, rest_a.z - rest_b.z})
			error += abs(distance - rest)
		}
	}
	return error
}
