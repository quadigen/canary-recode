package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import sandbox "../src/sandboxed"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject

	sandbox.init(&script_vm, &environment, &renderer_object)
	defer sandbox.shutdown()
	defer vm.Close(&script_vm)

	ok, err := vm.Run(&script_vm, `
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- GetFocusedTextBox is a real method and reports nil when nothing has focus.
assert(type(UserInputService.GetFocusedTextBox) == "function", "GetFocusedTextBox is not exposed")
assert(UserInputService:GetFocusedTextBox() == nil, "expected no focused TextBox at rest")

-- The reparent rules the explorer relies on.
local function isDescendantOf(candidate, ancestor)
	local current = candidate
	while current ~= nil do
		if current == ancestor then
			return true
		end
		current = current.Parent
	end
	return false
end

local function canReparent(instance, newParent)
	if instance == nil or newParent == nil then
		return false
	end
	if instance:IsA("DataModel") or newParent:IsA("DataModel") then
		return false
	end
	if instance == newParent then
		return false
	end
	if isDescendantOf(newParent, instance) then
		return false
	end
	return true
end

local parent = Instance.new("Folder")
parent.Name = "Parent"
local child = Instance.new("Folder")
child.Name = "Child"
child.Parent = parent
local grandchild = Instance.new("Folder")
grandchild.Name = "Grandchild"
grandchild.Parent = child

-- A folder may be dropped into an unrelated container.
local other = Instance.new("Folder")
assert(canReparent(parent, other) == true, "unrelated reparent should be allowed")

-- Dropping a node onto itself is a no-op.
assert(canReparent(parent, parent) == false, "self reparent must be rejected")

-- Dropping a node into its own descendant would orphan the subtree.
assert(canReparent(parent, grandchild) == false, "descendant reparent must be rejected")
assert(canReparent(parent, child) == false, "child reparent must be rejected")

-- The DataModel root can never be reparented or used as a parent.
assert(canReparent(game, workspace) == false, "game must not be reparentable")
assert(canReparent(parent, game) == false, "game must not accept children")

-- An actual move works and updates the tree.
child.Parent = other
assert(child.Parent == other, "reparent did not take effect")
assert(isDescendantOf(grandchild, other), "descendant chain broke after reparent")

-- Destroy removes an instance from its parent. Reading any property on a
-- destroyed Instance raises, so assert against the parent's child count.
local beforeCount = #other:GetChildren()
local doomed = Instance.new("Folder")
doomed.Name = "Doomed"
doomed.Parent = other
assert(#other:GetChildren() == beforeCount + 1, "child was not added")
doomed:Destroy()
assert(#other:GetChildren() == beforeCount, "Destroy did not detach the instance")

-- TweenService can animate a GUI property, which is what the drop animation
-- uses for its fade-out.
local ghost = Instance.new("Frame")
ghost.Name = "DragGhost"
ghost.Parent = game.CoreGui
ghost.BackgroundTransparency = 0.2
local tween = TweenService:Create(
	ghost,
	TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	{ BackgroundTransparency = 1 }
)
assert(tween ~= nil, "tween creation failed")
local completed = false
tween.Completed:Once(function()
	completed = true
end)
tween:Play()
`, "explorer_drag_setup")

	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("explorer drag/delete probe failed")
	}

	// Step far enough for the 0.1s fade to finish, then confirm the tween both
	// completed and actually drove the property to its goal.
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 0.5)

	settled, settled_err := vm.Run(&script_vm, `
local ghost = game:GetService("TweenService")
assert(ghost ~= nil)

-- Re-find the animated frame by walking the global CoreGui.
local function findGui(root)
	if root == nil then
		return nil
	end
	if root.ClassName == "Frame" and root.Name == "DragGhost" then
		return root
	end
	for _, child in ipairs(root:GetChildren()) do
		local hit = findGui(child)
		if hit ~= nil then
			return hit
		end
	end
	return nil
end

local frame = findGui(game.CoreGui)
assert(frame ~= nil, "animated frame not found")
assert(math.abs(frame.BackgroundTransparency - 1) < 0.01, "tween did not reach its goal, got " .. tostring(frame.BackgroundTransparency))
`, "explorer_drag_tween_settled")

	if !settled {
		fmt.eprintln(settled_err)
		delete(settled_err)
		panic("explorer drop animation did not settle")
	}

	_ = renderer_object
	fmt.println("EXPLORER_DRAG_SMOKE_PASSED")
}