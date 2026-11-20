package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("attachment joint smoke failed")
	}
}

step :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM, frames: int) {
	for _ in 0 ..< frames {
		engine_runtime.Environment_Update_Step(environment, script_vm, 1.0 / 60.0)
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	defer engine_runtime.Environment_Destroy(&environment)
	defer vm.Close(&script_vm)

	run_script(&script_vm, `
JointTestGravity = Vector3.new(0, -40, 0)
function part(x, y, z, anchored)
	local result = Instance.new("Part", workspace)
	result.Size = vector.create(2, 2, 2)
	result.CFrame = CFrame.new(x, y, z)
	result.Anchored = anchored
	result.Gravity = JointTestGravity
	result.CanCollide = false
	return result
end

function joint(class, first, second, firstOffset, secondOffset)
	local result = Instance.new(class, workspace)
	local a = Instance.new("Attachment", first)
	local b = Instance.new("Attachment", second)
	a.Position, b.Position = firstOffset, secondOffset
	result.Attachment0, result.Attachment1 = a, b
	return result
end

local zero = vector.create(0, 0, 0)
rail = part(0, 20, 0, true)
carriage = part(2, 20, 0, false)
payload = part(2, 20, 2, false)
weld = Instance.new("WeldConstraint", carriage)
weld.Part0, weld.Part1 = carriage, payload

slider = joint("PrismaticConstraint", rail, carriage, zero, zero)
slider.LimitsEnabled, slider.LowerLimit, slider.UpperLimit = true, 1, 3
local clone = slider:Clone()
assert(clone:IsA("Constraint") and not clone.Active)
assert(clone.Attachment0 == slider.Attachment0 and clone.Attachment1 == slider.Attachment1)
assert(clone.LimitsEnabled and clone.LowerLimit == 1 and clone.UpperLimit == 3)
clone:Destroy()
assert(not pcall(function() slider.Attachment1 = carriage end))
assert(not pcall(function() slider.Attachment1 = "invalid" end))
assert(slider.Attachment1.Parent == carriage)
assert(not pcall(function() slider.Active = true end))
assert(not pcall(function() slider.CurrentPosition = 1 end))

arm = part(2, 17, 2, false)
socket = joint("BallSocketConstraint", payload, arm, zero, vector.create(0, 3, 0))
socket.LimitsEnabled, socket.UpperAngle = true, 25

weight = part(2, 14, 2, false)
rod = joint("RodConstraint", arm, weight, zero, zero)
rod.Length = 3
assert(not pcall(function() rod.Length = -1 end))
assert(not pcall(function() rod.Length = 0 / 0 end))
`, "setup a prismatic, weld, ball-socket and rod chain")

	step(&environment, &script_vm, 45)
	run_script(&script_vm, `
assert(slider.Active and socket.Active and rod.Active)
assert(math.abs(slider.CurrentPosition - 2) < 0.05, tostring(slider.CurrentPosition))
payload.AssemblyLinearVelocity = vector.create(20, 0, 0)
`, "drive the carriage through its welded payload")

	step(&environment, &script_vm, 100)
	run_script(&script_vm, `
assert(math.abs(slider.CurrentPosition - 3) < 0.06, tostring(slider.CurrentPosition))
assert(vector.magnitude(carriage.Position - vector.create(3, 20, 0)) < 0.08)
local payloadOffset = carriage.CFrame:PointToObjectSpace(payload.Position)
assert(vector.magnitude(payloadOffset - vector.create(0, 0, 2)) < 0.08)
local pivot = arm.CFrame:PointToWorldSpace(socket.Attachment1.Position)
assert(vector.magnitude(pivot - payload.Position) < 0.12)
assert(math.abs(vector.magnitude(weight.Position - arm.Position) - 3) < 0.08)
rod.Length = 2
slider.LowerLimit, slider.UpperLimit = 0.5, 0.5
`, "verify combined constraints and change limits at runtime")

	step(&environment, &script_vm, 100)
	run_script(&script_vm, `
assert(math.abs(slider.CurrentPosition - 0.5) < 0.06, tostring(slider.CurrentPosition))
assert(math.abs(vector.magnitude(weight.Position - arm.Position) - 2) < 0.08)
slider.Enabled = false
assert(not slider.Active)
socket.Parent = nil
`, "disable the slider and detach the ball-socket")

	step(&environment, &script_vm, 10)
	run_script(&script_vm, `
assert(not slider.Active and not socket.Active and rod.Active)
assert(carriage.Position.y < 19.9, tostring(carriage.Position))
slider.Enabled = true
socket.Parent = workspace
`, "re-enable both joints")

	step(&environment, &script_vm, 50)
	run_script(&script_vm, `
assert(slider.Active and socket.Active and rod.Active)
weight:Destroy()
`, "release the joint when a part is destroyed")

	step(&environment, &script_vm, 2)
	run_script(&script_vm, `
assert(rod.Attachment1 == nil and not rod.Active)

-- A separate ball-socket starts outside its angular limit.
JointTestGravity = Vector3.zero
for _, p in workspace:GetDescendants() do
	if p:IsA("BasePart") then p.Gravity = JointTestGravity end
end
local base = part(20, 20, 0, true)
ball = part(20, 20, 0, false)
ball.CFrame = ball.CFrame * CFrame.Angles(0, 0, math.rad(70))
local center = vector.create(0, 0, 0)
limited = joint("BallSocketConstraint", base, ball, center, center)
limited.LimitsEnabled, limited.UpperAngle = true, 20

-- Start compressed in zero gravity so the rod must push its endpoints apart.
local fixed = part(40, 20, 0, true)
tip = part(41, 20, 0, false)
spacer = joint("RodConstraint", fixed, tip, center, center)
spacer.Parent = limited
spacer.Length = 3
`, "set up an angular limit")

	step(&environment, &script_vm, 90)
	run_script(&script_vm, `
assert(ball.CFrame.RightVector.x > math.cos(math.rad(22)), tostring(ball.CFrame.RightVector))
assert(spacer.Active and math.abs(tip.Position.x - 43) < 0.05, tostring(tip.Position))
spacer.Length = 0
limited.LimitsEnabled = false
ball.CFrame = CFrame.new(20, 20, 0) * CFrame.Angles(math.rad(70), 0, 0)
`, "remove the angular limit and rotate the ball freely")

	step(&environment, &script_vm, 45)
	run_script(&script_vm, `
assert(limited.Active and ball.CFrame.UpVector.y < 0.5, tostring(ball.CFrame.UpVector))
assert(vector.magnitude(ball.Position - vector.create(20, 20, 0)) < 0.02)
assert(vector.magnitude(tip.Position - vector.create(40, 20, 0)) < 0.02)
`, "verify the free ball-socket keeps its pivot")

	fmt.println("ATTACHMENT_JOINT_SMOKE_PASSED")
}
