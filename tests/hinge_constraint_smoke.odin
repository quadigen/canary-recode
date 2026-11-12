package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"

run_script :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "hinge_constraint_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("hinge constraint smoke failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(
		&script_vm,
		`
workspace.Gravity = 0
base = Instance.new("Part", workspace)
base.Anchored = true
base.CanCollide = false
base.Size = vector.create(2, 2, 2)
wheel = Instance.new("Part", workspace)
wheel.Anchored = false
wheel.CanCollide = false
wheel.Size = vector.create(2, 2, 2)
base.CFrame = CFrame.new(0, 10, 0)
wheel.CFrame = CFrame.new(0, 14, 0)
a = Instance.new("Attachment", base)
b = Instance.new("Attachment", wheel)
a.Axis = vector.create(0, 1, 0)
a.Position = vector.create(0, 4, 0)
b.Axis = a.Axis
hinge = Instance.new("HingeConstraint", base)
assert(hinge:IsA("Constraint") and hinge.ActuatorType == Enum.ActuatorType.None)
assert(not hinge.Active and hinge.CurrentAngle == 0)
assert(not hinge.Visible)
hinge.Visible = true
hinge.Color = BrickColor.new("Bright red")
hinge.Radius = 1.5
assert(not pcall(function() hinge.CurrentAngle = 5 end))
assert(not pcall(function() hinge.Active = true end))
hinge.Attachment0 = a
hinge.Attachment1 = b
hinge.ActuatorType = Enum.ActuatorType.Motor
hinge.AngularVelocity = 4
hinge.MotorMaxTorque = 1000000
local clone = hinge:Clone()
assert(clone.ActuatorType == Enum.ActuatorType.Motor and clone.Attachment1 == b)
assert(clone.Visible and clone.Color.Number == hinge.Color.Number and clone.Radius == 1.5)
clone:Destroy()
`,
	)
	for _ in 0 ..< 30 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}
	run_script(
		&script_vm,
		`
assert(hinge.Active and hinge.CurrentAngle > 70, tostring(hinge.CurrentAngle))
assert(math.abs(wheel.CFrame.Y - base.CFrame.Y - 4) < 0.02,
	"hinge must keep the attachment points together")
hinge.ActuatorType = Enum.ActuatorType.None
`,
	)
	for _ in 0 ..< 10 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}
	run_script(
		&script_vm,
		`
assert(hinge.CurrentAngle > 125, "wheel should coast with the actuator off")
hinge.ActuatorType = Enum.ActuatorType.Servo
hinge.LimitsEnabled = true
hinge.LowerAngle = 10
hinge.UpperAngle = 70
hinge.AngularSpeed = 5
hinge.ServoMaxTorque = 1000000
hinge.TargetAngle = 35
`,
	)
	for _ in 0 ..< 90 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}
	run_script(
		&script_vm,
		`
assert(math.abs(hinge.CurrentAngle - 35) < 1, tostring(hinge.CurrentAngle))
hinge.TargetAngle = 100
`,
	)
	for _ in 0 ..< 60 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}
	run_script(
		&script_vm,
		`
assert(math.abs(hinge.CurrentAngle - 70) < 1, tostring(hinge.CurrentAngle))
hinge.Enabled = false
assert(not hinge.Active)
hinge.Enabled = true
hinge.Parent = nil
`,
	)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	run_script(&script_vm, `assert(not hinge.Active); hinge.Parent = base`)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	run_script(&script_vm, `assert(hinge.Active); wheel:Destroy()`)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	run_script(&script_vm, `assert(not hinge.Active and hinge.Attachment1 == nil); base:Destroy()`)

	// A wheel and axle can overlap when their physical collision is disabled.
	run_script(
		&script_vm,
		`
workspace.Gravity = 196.2
base = Instance.new("Part", workspace)
base.Size = vector.create(2, 2, 2)
base.CFrame = CFrame.new(0, 10, 0)
base.CanCollide = false
wheel = Instance.new("Part", workspace)
wheel.Size = base.Size
wheel.CFrame = base.CFrame
wheel.Anchored = false
a = Instance.new("Attachment", base)
b = Instance.new("Attachment", wheel)
hinge = Instance.new("HingeConstraint", base)
hinge.Attachment0 = a
hinge.Attachment1 = b
hinge.ActuatorType = Enum.ActuatorType.Motor
hinge.AngularVelocity = 4
hinge.MotorMaxTorque = 1000000
`,
	)
	for _ in 0 ..< 30 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}
	run_script(
		&script_vm,
		`
assert(hinge.Active and hinge.CurrentAngle > 70, "overlapping axle must allow wheel rotation")
assert(wheel.Parent == workspace and math.abs(wheel.CFrame.Y - 10) < 0.02,
	"the hinge must hold the wheel at the axle under gravity")
base.Name = "Axle"
wheel.Name = "Wheel"
hinge.Visible = true
hinge.Radius = 0.75
`,
	)
	{
		previous := vm.GetThreadSecurityCapabilities(script_vm.L)
		vm.SetThreadSecurityCapabilities(script_vm.L, vm.THREAD_SECURITY_ALL)
		defer vm.SetThreadSecurityCapabilities(script_vm.L, previous)
		run_script(
			&script_vm,
			`assert(game:GetService("ExportService"):ExportToFileSync("build/hinge_playtest.kine", ""))`,
		)
	}
	defer _ = os.remove("build/hinge_playtest.kine")
	assert(engine_runtime.Load_Map(&environment, &script_vm, "build/hinge_playtest.kine"))
	run_script(
		&script_vm,
		`
local axle = assert(workspace:FindFirstChild("Axle"))
local loadedWheel = assert(workspace:FindFirstChild("Wheel"))
local loadedHinge = assert(axle:FindFirstChild("HingeConstraint"))
assert(loadedHinge.Attachment0 == axle:FindFirstChild("Attachment"))
assert(loadedHinge.Attachment1 == loadedWheel:FindFirstChild("Attachment"))
assert(loadedHinge.Visible and loadedHinge.Radius == 0.75)
assert(loadedHinge.ActuatorType == Enum.ActuatorType.Motor and loadedHinge.AngularVelocity == 4)
hinge = loadedHinge
`,
	)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	run_script(
		&script_vm,
		`
assert(hinge.Active, "a hinge restored from the playtest map should engage")
workspace.Wheel:Destroy()
workspace.Axle:Destroy()
`,
	)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("HINGE_CONSTRAINT_SMOKE_PASSED")
}
