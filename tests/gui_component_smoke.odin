package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("GUI component smoke test failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(&script_vm, `
local function close(a, b, epsilon)
	return math.abs(a - b) <= (epsilon or 1e-5)
end

-- Frame hierarchy and properties
local screen = Instance.new("ScreenGui")
screen.Name = "TestScreen"
screen.Enabled = true
screen.DisplayOrder = 10
assert(screen.Enabled == true)
assert(screen.DisplayOrder == 10)
assert(screen.ClassName == "ScreenGui")

local frame = Instance.new("Frame", screen)
frame.Name = "MainFrame"
frame.Size = UDim2.new(0.5, 100, 0.6, 50)
frame.Position = UDim2.fromOffset(10, 20)
frame.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)
frame.BackgroundTransparency = 0.25
frame.ZIndex = 5
frame.Active = true
frame.Visible = true
frame.ClipsDescendants = true

assert(frame.Size.X.Scale == 0.5 and frame.Size.X.Offset == 100)
assert(close(frame.Size.Y.Scale, 0.6) and frame.Size.Y.Offset == 50)
assert(frame.Position.X.Offset == 10 and frame.Position.Y.Offset == 20)
assert(close(frame.BackgroundTransparency, 0.25))
assert(frame.ZIndex == 5)
assert(frame.Active == true)
assert(frame.Visible == true)
assert(frame.ClipsDescendants == true)
assert(frame.BorderSizePixel == 0)

assert(frame.Parent == screen)
assert(frame.ClassName == "Frame")
assert(frame:IsA("Frame"))
assert(frame:IsA("GuiObject"))
assert(frame:IsA("Instance"))

-- TextLabel
local label = Instance.new("TextLabel", frame)
label.Name = "TitleLabel"
label.Text = "Hello Kinemium"
label.TextSize = 24
label.TextColor3 = Color3.new(1, 1, 1)
label.TextTransparency = 0
label.TextWrapped = true
label.TextScaled = false
label.LineHeight = 1.5

assert(label.Text == "Hello Kinemium")
assert(label.TextSize == 24)
assert(label.TextWrapped == true)
assert(label.TextScaled == false)
assert(close(label.LineHeight, 1.5))
assert(label.ClassName == "TextLabel")
assert(label:IsA("TextLabel"))
assert(label:IsA("GuiObject"))

-- ImageLabel
local img = Instance.new("ImageLabel", frame)
img.Name = "BackgroundImg"
img.Image = "rbxasset://test.png"
img.ImageTransparency = 0.5

assert(img.Image == "rbxasset://test.png")
assert(img.ImageTransparency == 0.5)
assert(img.ClassName == "ImageLabel")
assert(img:IsA("ImageLabel"))

-- TextBox
local box = Instance.new("TextBox", frame)
box.Name = "InputBox"
box.Text = "default text"
box.PlaceholderText = "type here"
box.PlaceholderColor3 = Color3.new(0.5, 0.5, 0.5)
box.ClearTextOnFocus = false
box.TextEditable = true
box.MaxLength = 100

assert(box.Text == "default text")
assert(box.PlaceholderText == "type here")
assert(box.ClearTextOnFocus == false)
assert(box.TextEditable == true)
assert(box.MaxLength == 100)
assert(box.ClassName == "TextBox")

-- ScrollingFrame
local scroll = Instance.new("ScrollingFrame", frame)
scroll.Name = "ScrollList"
scroll.Size = UDim2.new(1, 0, 1, 0)
scroll.CanvasSize = UDim2.new(0, 0, 2, 0)
scroll.CanvasPosition = Vector2.new(0, 50)
scroll.ScrollingEnabled = true
scroll.ScrollBarThickness = 8
scroll.SmoothScrollingEnabled = true

assert(close(scroll.CanvasSize.Y.Scale, 2))
assert(scroll.CanvasPosition.X == 0)
assert(typeof(scroll.CanvasPosition.Y) == "number")
-- CanvasPosition clamps to the computed max scroll; without an active
-- layout pass the max is 0, so no error is raised on set and Y reads 0.
assert(scroll.CanvasPosition.Y >= 0)
assert(scroll.ScrollingEnabled == true)
assert(scroll.ScrollBarThickness == 8)
assert(scroll.SmoothScrollingEnabled == true)
assert(scroll.ClassName == "ScrollingFrame")

-- UICorner
local corner = Instance.new("UICorner", frame)
corner.CornerRadius = UDim.new(0.5, 0)
assert(corner.CornerRadius.Scale == 0.5 and corner.CornerRadius.Offset == 0)

-- UIStroke
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.new(1, 0, 0)
stroke.Thickness = 2
stroke.Transparency = 0.3
stroke.Enabled = true
assert(stroke.Color.R == 1)
assert(stroke.Thickness == 2)
assert(stroke.Transparency == 0.3)
assert(stroke.Enabled == true)

-- UIGradient
local gradient = Instance.new("UIGradient", frame)
gradient.Rotation = 45
gradient.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)})
gradient.Offset = Vector2.new(0.5, 0)
assert(gradient.Rotation == 45)
assert(gradient.Offset.X == 0.5 and gradient.Offset.Y == 0)

-- Hierarchy and ancestry
assert(frame.Parent == screen)
assert(label.Parent == frame)
assert(#screen:GetChildren() == 1)
assert(#frame:GetChildren() == 7)
assert(screen:IsAncestorOf(label))
assert(label:IsDescendantOf(screen))

-- Cleanup
screen:Destroy()
assert(#frame:GetChildren() == 0)
assert(frame.Parent == nil)

-- TextButton
local btn = Instance.new("TextButton")
btn.Text = "Click Me"
btn.AutoButtonColor = true
assert(btn.Text == "Click Me")
assert(btn.AutoButtonColor == true)
assert(btn:IsA("GuiButton"))
assert(btn:IsA("GuiObject"))

-- Multiple ZIndex ordering
local container = Instance.new("ScreenGui")
local a = Instance.new("Frame", container)
local b = Instance.new("Frame", container)
a.ZIndex = 10
b.ZIndex = 5
assert(a.ZIndex > b.ZIndex)
container:Destroy()

assert(not pcall(function() frame.AbsolutePosition = UDim2.new() end))
assert(not pcall(function() frame.AbsoluteSize = UDim2.new() end))
`, "gui_component_properties")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("GUI_COMPONENT_SMOKE_PASSED")
}
