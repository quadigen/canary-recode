package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"

run_script :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "spring_constraint_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("SpringConstraint smoke failed")
	}
}

step :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM, count: int) {
	for _ in 0 ..< count {
		engine_runtime.Environment_Update_Step(environment, script_vm, 1.0 / 60.0)
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(&script_vm, `
workspace.Gravity = 0
base = Instance.new("Part", workspace)
base.Name = "SpringBase"
base.Anchored = true
base.CanCollide = false
base.Size = vector.create(1, 1, 1)
base.CFrame = CFrame.new(0, 10, 0)
top = Instance.new("Part", workspace)
top.Name = "SpringTop"
top.Anchored = false
top.CanCollide = false
top.Size = base.Size
top.CFrame = CFrame.new(3, 14, 0) * CFrame.Angles(0, 0, 0.8)
a = Instance.new("Attachment", base)
b = Instance.new("Attachment", top)

spring = Instance.new("SpringConstraint", base)
assert(spring:IsA("Constraint") and spring.Enabled)
assert(not spring.Active and not spring.Stand and not spring.Visible and not spring.LimitsEnabled)
assert(spring.Attachment0 == nil and spring.Attachment1 == nil and spring.CurrentLength == 0)
assert(spring.FreeLength == 1 and spring.MinLength == 0 and spring.MaxLength == 5)
assert(spring.Stiffness == 0 and spring.Damping == 0 and spring.MaxForce == math.huge)
assert(spring.Coils == 3 and math.abs(spring.Radius - 0.4) < 1e-6)
assert(spring.Color == BrickColor.new(200) and spring.Color.Name == "Lemon metalic",
	tostring(spring.Color.Number) .. " " .. tostring(spring.Color.Name))
assert(math.abs(spring.Thickness - 0.1) < 1e-6)
assert(not pcall(function() spring.CurrentLength = 2 end))
assert(not pcall(function() spring.Active = true end))

spring.Attachment0 = a
spring.Attachment1 = b
spring.Coils = 4.5
assert(spring.Coils == 4.5)
spring.Coils = 20
assert(spring.Coils == 8)
assert(math.abs(spring.CurrentLength - 5) < 1e-5)
`)
	step(&environment, &script_vm, 1)
	run_script(&script_vm, `
assert(spring.Active and math.abs(top.Position.X - 3) < 1e-5)
assert(top.CFrame.UpVector.Y < 0.8, "ordinary springs should let the top rotate")
spring.FreeLength = 2
spring.Stiffness = 16000
spring.Damping = 8000
spring.MaxForce = 3
`)
	step(&environment, &script_vm, 3)
	run_script(&script_vm, `
local force = spring:GetDebugAppliedForce(1)
assert(math.abs(vector.magnitude(force) - 3) < 1e-4, tostring(force))
assert(force.X < 0 and force.Y < 0)
assert(spring.CurrentLength < 5, "normal spring should pull the parts together")
spring.Stand = true
spring.Visible = true
spring.Color = BrickColor.new("Bright blue")
spring.Radius = 0.5
spring.Thickness = 0.125
spring.MaxForce = math.huge
local clone = spring:Clone()
assert(clone.Stand and clone.Visible and not clone.Active and clone.Attachment1 == b)
assert(clone.Coils == 8 and clone.Radius == 0.5 and clone.Thickness == 0.125)
clone:Destroy()
`)
	step(&environment, &script_vm, 120)
	run_script(&script_vm, `
assert(spring.Active)
assert(math.abs(top.Position.X) < 0.03 and math.abs(top.Position.Z) < 0.03, tostring(top.Position))
assert(top.CFrame.UpVector.Y > 0.995, tostring(top.CFrame.UpVector))
assert(math.abs(spring.CurrentLength - 2) < 0.08, tostring(spring.CurrentLength))
spring.LimitsEnabled = true
spring.MinLength = 1.25
spring.MaxLength = 2.75
spring.FreeLength = 5
`)
	step(&environment, &script_vm, 60)
	run_script(&script_vm, `
assert(math.abs(spring.CurrentLength - 2.75) < 0.04, tostring(spring.CurrentLength))
spring.Stand = false
spring.FreeLength = 0
`)
	step(&environment, &script_vm, 60)
	run_script(&script_vm, `
assert(math.abs(spring.CurrentLength - 1.25) < 0.04, tostring(spring.CurrentLength))
spring.Enabled = false
assert(not spring.Active)
spring.Enabled = true
spring.Stand = true
spring.Parent = nil
`)
	step(&environment, &script_vm, 1)
	run_script(&script_vm, `assert(not spring.Active); spring.Parent = base`)
	step(&environment, &script_vm, 1)
	run_script(&script_vm, `assert(spring.Active)`)

	{
		previous := vm.GetThreadSecurityCapabilities(script_vm.L)
		vm.SetThreadSecurityCapabilities(script_vm.L, vm.THREAD_SECURITY_ALL)
		defer vm.SetThreadSecurityCapabilities(script_vm.L, previous)
		run_script(&script_vm, `assert(game:GetService("ExportService"):ExportToFile("build/spring_smoke.kine"))`)
	}
	defer _ = os.remove("build/spring_smoke.kine")
	assert(engine_runtime.Load_Map(&environment, &script_vm, "build/spring_smoke.kine"))
	step(&environment, &script_vm, 1)
	run_script(&script_vm, `
local base = assert(workspace:FindFirstChild("SpringBase"))
local top = assert(workspace:FindFirstChild("SpringTop"))
local loaded = assert(base:FindFirstChild("SpringConstraint"))
assert(loaded.Attachment0 == base:FindFirstChild("Attachment"))
assert(loaded.Attachment1 == top:FindFirstChild("Attachment"))
assert(loaded.Active and loaded.Stand and loaded.Visible and loaded.LimitsEnabled)
assert(loaded.MaxForce == math.huge and loaded.Color.Number == BrickColor.new("Bright blue").Number)
top:Destroy()
assert(not loaded.Active and loaded.Attachment1 == nil)
`)
	step(&environment, &script_vm, 1)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("SPRING_CONSTRAINT_SMOKE_PASSED")
}
