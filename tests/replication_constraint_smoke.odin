package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("replication constraint smoke setup failed")
	}
}

find_named :: proc(
	environment: ^engine_runtime.Environment,
	class_name, name: string,
) -> ^classes.Object {
	descriptor := classes.Find_Class(&environment.classes, class_name)
	if descriptor == nil {return nil}
	for object in descriptor.instances {
		if object != nil && object.name == name {return object}
	}
	return nil
}

main :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	run_script(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:StartServer("127.0.0.1", 39264))
r.RelevancyDistance = 5000
local workspace = game:GetService("Workspace")
local part_a = Instance.new("Part")
part_a.Name = "ConstraintPartA"
part_a.Anchored = true
part_a.CFrame = CFrame.new(0, 5, 0)
part_a.Parent = workspace
local part_b = Instance.new("Part")
part_b.Name = "ConstraintPartB"
part_b.Anchored = false
part_b.CFrame = CFrame.new(4, 5, 0)
part_b.Parent = workspace
local weld = Instance.new("WeldConstraint")
weld.Name = "TestWeld"
weld.Part0 = part_a
weld.Part1 = part_b
weld.Parent = workspace
local attachment_a = Instance.new("Attachment")
attachment_a.Name = "AttachA"
attachment_a.Parent = part_a
local attachment_b = Instance.new("Attachment")
attachment_b.Name = "AttachB"
attachment_b.Parent = part_b
local rope = Instance.new("RopeConstraint")
rope.Name = "TestRope"
rope.Attachment0 = attachment_a
rope.Attachment1 = attachment_b
rope.Length = 4
rope.Parent = workspace
local function newJoint(class, name, x)
	local anchor = Instance.new("Part", workspace)
	anchor.Name = name .. "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CFrame = CFrame.new(x, 12, 0)
	local moving = Instance.new("Part", workspace)
	moving.Name = name .. "Moving"
	moving.Anchored = false
	moving.CanCollide = false
	moving.CFrame = CFrame.new(x + 4, 12, 0)
	local a = Instance.new("Attachment", anchor)
	local b = Instance.new("Attachment", moving)
	a.Name, b.Name = "FirstJointAttachment", "SecondJointAttachment"
	local joint = Instance.new(class, workspace)
	joint.Name = name
	joint.Attachment0, joint.Attachment1 = a, b
	return joint
end
local socket = newJoint("BallSocketConstraint", "TestSocket", 50)
socket.Attachment0.Position = vector.create(4, 0, 0)
socket.LimitsEnabled, socket.UpperAngle = true, 65
local slider = newJoint("PrismaticConstraint", "TestSlider", 100)
slider.LimitsEnabled, slider.LowerLimit, slider.UpperLimit = true, 1, 6
local rod = newJoint("RodConstraint", "TestRod", 150)
rod.Length = 4
`,
		"replication_constraint_server_setup",
	)

	run_script(
		&client_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:ConnectClient("127.0.0.1", 39264))
`,
		"replication_constraint_client_setup",
	)

	for _ in 0 ..< 180 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
	}

	run_script(
		&client_vm,
		`
local workspace = game:GetService("Workspace")
local part_a = workspace:FindFirstChild("ConstraintPartA")
local part_b = workspace:FindFirstChild("ConstraintPartB")
assert(part_a and part_b, "constraint parts should replicate")
local attachment_a = part_a:FindFirstChild("AttachA")
local attachment_b = part_b:FindFirstChild("AttachB")
assert(attachment_a and attachment_b, "attachments should replicate")
local weld = workspace:FindFirstChild("TestWeld")
assert(weld and weld.ClassName == "WeldConstraint", "weld should replicate")
assert(weld.Part0 == part_a and weld.Part1 == part_b, "weld references should resolve")
local rope = workspace:FindFirstChild("TestRope")
assert(rope and rope.ClassName == "RopeConstraint", "rope should replicate")
assert(rope.Attachment0 == attachment_a and rope.Attachment1 == attachment_b, "rope references should resolve")
assert(rope.Length == 4, "rope length should replicate")
local function verifyJoint(class, name)
	local joint = workspace:FindFirstChild(name)
	assert(joint and joint.ClassName == class and joint.Enabled, name .. " should replicate")
	local first = workspace:FindFirstChild(name .. "Anchor")
	local second = workspace:FindFirstChild(name .. "Moving")
	assert(first and second, name .. " parts should replicate")
	local a = first:FindFirstChild("FirstJointAttachment")
	local b = second:FindFirstChild("SecondJointAttachment")
	assert(a and b and joint.Attachment0 == a and joint.Attachment1 == b,
		name .. " attachment references should resolve")
	return joint
end
local socket = verifyJoint("BallSocketConstraint", "TestSocket")
assert(socket.LimitsEnabled and socket.UpperAngle == 65)
local slider = verifyJoint("PrismaticConstraint", "TestSlider")
assert(slider.LimitsEnabled and slider.LowerLimit == 1 and slider.UpperLimit == 6)
local rod = verifyJoint("RodConstraint", "TestRod")
assert(rod.Length == 4)
`,
		"replication_constraint_client_verify",
	)

	weld_object := find_named(&server, "WeldConstraint", "TestWeld")
	assert(weld_object != nil, "server should have the weld")
	weld := cast(^classes.WeldConstraint)weld_object
	assert(
		weld.jolt_constraint != nil,
		"weld should be stepped through the generated constraint table",
	)

	rope_object := find_named(&server, "RopeConstraint", "TestRope")
	assert(rope_object != nil, "server should have the rope")
	rope := cast(^classes.RopeConstraint)rope_object
	assert(
		rope.jolt_constraint != nil,
		"rope should be stepped through the generated constraint table",
	)

	run_script(
		&server_vm,
		`
assert(workspace.TestSocket.Active and workspace.TestSlider.Active and workspace.TestRod.Active)
assert(math.abs(workspace.TestSlider.CurrentPosition - 4) < 0.05)
workspace.TestSocket.UpperAngle = 30
workspace.TestSocket.Enabled = false
workspace.TestSlider.UpperLimit = 2
workspace.TestRod.Length = 6
workspace.TestRod.Attachment1 = nil
`,
		"replication_constraint_server_update",
	)
	for _ in 0 ..< 180 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
	}
	run_script(
		&client_vm,
		`
assert(workspace.TestSocket.UpperAngle == 30 and not workspace.TestSocket.Enabled)
assert(workspace.TestSlider.UpperLimit == 2)
assert(workspace.TestRod.Length == 6 and workspace.TestRod.Attachment1 == nil)
assert(not workspace.TestRod.Active)
`,
		"replication_constraint_client_verify_update",
	)
	run_script(
		&server_vm,
		`
assert(math.abs(workspace.TestSlider.CurrentPosition - 2) < 0.05,
	tostring(workspace.TestSlider.CurrentPosition))
`,
		"replication_constraint_server_verify_new_limit",
	)

	run_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"replication_constraint_client_stop",
	)
	run_script(
		&server_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"replication_constraint_server_stop",
	)
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
	fmt.println("REPLICATION_CONSTRAINT_SMOKE_PASSED")
}
