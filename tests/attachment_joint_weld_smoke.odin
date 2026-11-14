package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	defer engine_runtime.Environment_Destroy(&environment)
	defer vm.Close(&script_vm)

	ok, err := vm.Run(&script_vm, `
local function part(x, y)
	local result = Instance.new("Part", workspace)
	result.Size = vector.create(2, 2, 2)
	result.CFrame = CFrame.new(x, y, 0)
	result.Anchored = true
	return result
end

for i, class in ipairs({"BallSocketConstraint", "PrismaticConstraint", "RodConstraint"}) do
	local y = i * 20
	local first, neighbor, outsider = part(0, y), part(2, y), part(-2, y)
	local weld = Instance.new("WeldConstraint", neighbor)
	weld.Part0, weld.Part1 = first, neighbor

	local joint = Instance.new(class, workspace)
	joint.Attachment0 = Instance.new("Attachment", first)
	joint.Attachment1 = Instance.new("Attachment", outsider)
	workspace:JoinToOutsiders({first, neighbor}, Enum.JointCreationMode.Surface)
	assert(not first:FindFirstChildOfClass("WeldConstraint"), class .. " should protect its endpoints from auto-welding")

	outsider.Position = vector.create(4, y, 0)
	workspace:JoinToOutsiders({neighbor}, Enum.JointCreationMode.Surface)
	assert(neighbor:FindFirstChildOfClass("WeldConstraint") == weld)
	assert(#neighbor:GetChildren() == 1, class .. " should protect both welded components")

	joint.Enabled = false
	workspace:JoinToOutsiders({neighbor}, Enum.JointCreationMode.Surface)
	local count = 0
	for _, child in neighbor:GetChildren() do
		if child:IsA("WeldConstraint") then
			count += 1
			if child ~= weld then
				assert(child.Part0 == neighbor and child.Part1 == outsider)
			end
		end
	end
	assert(count == 2, class .. " should allow auto-welding when disabled")
end
`, "attachment_joint_weld_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("attachment joint weld smoke failed")
	}
	fmt.println("ATTACHMENT_JOINT_WELD_SMOKE_PASSED")
}
