package main

import classes "../src/engine/classes"
import sdl3 "../src/engine/platform"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import sdl "vendor:sdl3"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("gui hit test smoke test setup failed")
	}
}

make_mouse_down :: proc(x, y: f32) -> sdl3.Event {
	e: sdl3.Event
	e.type = .MOUSE_BUTTON_DOWN
	e.button.button = sdl3.BUTTON_LEFT
	e.button.clicks = 1
	e.button.x = x
	e.button.y = y
	return e
}

make_mouse_up :: proc(x, y: f32) -> sdl3.Event {
	e: sdl3.Event
	e.type = .MOUSE_BUTTON_UP
	e.button.button = sdl3.BUTTON_LEFT
	e.button.clicks = 1
	e.button.x = x
	e.button.y = y
	return e
}

make_mouse_motion :: proc(x, y: f32) -> sdl3.Event {
	e: sdl3.Event
	e.type = .MOUSE_MOTION
	e.motion.x = x
	e.motion.y = y
	e.motion.xrel = 0
	e.motion.yrel = 0
	return e
}

assert_hit_log :: proc(vm_state: ^vm.VM, expected: string, label: string) {
	value_type := vm.GetGlobal(vm_state.L, "hitLog")
	if value_type != .String {
		panic("hitLog global is not a string")
	}

	log, ok := vm.ToString(vm_state.L, -1)
	if !ok {
		panic("hitLog tostring failed")
	}

	vm.Pop(vm_state.L, 1)

	if log != expected {
		fmt.eprintfln("hit log mismatch %s: expected %q, got %q", label, expected, log)
		panic("gui hit log mismatch")
	}
}

main :: proc() {
	ok := sdl3.Init(sdl3.INIT_VIDEO | sdl3.INIT_EVENTS)
	if !ok {
		fmt.eprintln("SDL_Init failed: ", sdl3.GetError())
		panic("SDL init failure")
	}

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(
		&script_vm,
		`
local box = Instance.new("TextBox")
box.Name = "HitBox"
box.Position = UDim2.fromOffset(50, 50)
box.Size = UDim2.fromOffset(200, 60)
box.Text = "hello"
box.ZIndex = 1
_G.box = box

local button = Instance.new("TextButton")
button.Name = "HitButton"
button.Position = UDim2.fromOffset(80, 60)
button.Size = UDim2.fromOffset(120, 40)
button.Text = "Go"
button.ZIndex = 2
_G.button = button

_G.hitLog = ""
box.MouseEnter:Connect(function() _G.hitLog = _G.hitLog .. "E:box;" end)
box.MouseLeave:Connect(function() _G.hitLog = _G.hitLog .. "L:box;" end)
button.MouseEnter:Connect(function() _G.hitLog = _G.hitLog .. "E:button;" end)
button.MouseLeave:Connect(function() _G.hitLog = _G.hitLog .. "L:button;" end)
`,
		"gui_hit_setup",
	)

	descriptor := classes.Find_Class(&environment.classes, "TextBox")
	if descriptor == nil || len(descriptor.instances) != 1 {
		panic("expected exactly one TextBox instance")
	}
	box := cast(^classes.TextBox)descriptor.instances[0]

	button_descriptor := classes.Find_Class(&environment.classes, "TextButton")
	if button_descriptor == nil || len(button_descriptor.instances) != 1 {
		panic("expected exactly one TextButton instance")
	}
	button := cast(^classes.TextButton)button_descriptor.instances[0]

	classes.Update_GUI_Layout(&environment.classes, 800, 600)


	down := make_mouse_down(120, 80)
	engine_runtime.Environment_SetEvent(&environment, &script_vm, down)

	if box.focused {
		panic("button on top of textbox focused the textbox")
	}

	up := make_mouse_up(120, 80)
	engine_runtime.Environment_SetEvent(&environment, &script_vm, up)


	motion := make_mouse_motion(120, 80)
	engine_runtime.Environment_SetEvent(&environment, &script_vm, motion)

	if !button.mouse_inside {
		panic("topmost button should be hovered")
	}
	if box.mouse_inside {
		panic("covered textbox should not be hovered")
	}
	assert_hit_log(&script_vm, "E:button;", "after hovering button")


	down2 := make_mouse_down(55, 55)
	engine_runtime.Environment_SetEvent(&environment, &script_vm, down2)

	if !box.focused {
		panic("clicking uncovered textbox failed to focus it")
	}

	up2 := make_mouse_up(55, 55)
	engine_runtime.Environment_SetEvent(&environment, &script_vm, up2)


	motion2 := make_mouse_motion(55, 55)
	engine_runtime.Environment_SetEvent(&environment, &script_vm, motion2)

	if !box.mouse_inside {
		panic("textbox should be hovered when its region is topmost")
	}
	if button.mouse_inside {
		panic("button should lose hover when the textbox is topmost")
	}
	assert_hit_log(&script_vm, "E:button;L:button;E:box;", "after hovering textbox")


	motion3 := make_mouse_motion(400, 400)
	engine_runtime.Environment_SetEvent(&environment, &script_vm, motion3)

	if box.mouse_inside || button.mouse_inside {
		panic("hover should clear when moving off the guis")
	}
	assert_hit_log(&script_vm, "E:button;L:button;E:box;L:box;", "after leaving all guis")


	run_script(
		&script_vm,
		`
local underGui = Instance.new("ScreenGui")
underGui.Name = "UnderGui"

local underBox = Instance.new("TextBox")
underBox.Name = "UnderBox"
underBox.Position = UDim2.fromOffset(0, 0)
underBox.Size = UDim2.new(0, 800, 0, 300)
underBox.Text = "under"
underBox.Parent = underGui

local overlayGui = Instance.new("ScreenGui")
overlayGui.Name = "OverlayGui"
overlayGui.RenderOnTop = true

local host = Instance.new("Frame")
host.Name = "Host"
host.Position = UDim2.fromOffset(0, 0)
host.Size = UDim2.fromScale(1, 1)
host.BackgroundTransparency = 1
host.Active = false
host.ZIndex = 200000
host.Parent = overlayGui

local behindBox = Instance.new("TextBox")
behindBox.Name = "BehindBox"
behindBox.Position = UDim2.fromOffset(150, 70)
behindBox.Size = UDim2.fromOffset(260, 120)
behindBox.Text = "behind"
behindBox.Parent = host

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Text = ""
backdrop.Position = UDim2.fromOffset(0, 0)
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundTransparency = 0.5
backdrop.InputSink = true
backdrop.ZIndex = 200000
backdrop.Parent = host

local panel = Instance.new("Frame")
panel.Name = "PromptPanel"
panel.Position = UDim2.fromOffset(200, 100)
panel.Size = UDim2.fromOffset(440, 260)
panel.ZIndex = 200001
panel.Parent = host

local field = Instance.new("TextBox")
field.Name = "PromptInput"
field.Position = UDim2.fromOffset(20, 60)
field.Size = UDim2.fromOffset(400, 30)
field.Text = ""
field.Active = true
field.InputSink = true
field.Parent = panel

_G.hitLog = ""
field.MouseEnter:Connect(function() _G.hitLog = _G.hitLog .. "E:field;" end)
field.MouseLeave:Connect(function() _G.hitLog = _G.hitLog .. "L:field;" end)
_G.promptField = field
`,
		"gui_hit_prompt_setup",
	)

	prompt_descriptor := classes.Find_Class(&environment.classes, "TextBox")
	if prompt_descriptor == nil {
		panic("expected TextBox descriptor for prompt scene")
	}

	field_tracker: ^classes.TextBox = nil
	for object in prompt_descriptor.instances {
		textbox := cast(^classes.TextBox)object
		if textbox.object.name == "PromptInput" {
			field_tracker = textbox
		}
	}
	if field_tracker == nil {
		panic("PromptInput TextBox not found")
	}

	classes.Update_GUI_Layout(&environment.classes, 800, 600)


	down3 := make_mouse_down(300, 175)
	engine_runtime.Environment_SetEvent(&environment, &script_vm, down3)
	up3 := make_mouse_up(300, 175)
	engine_runtime.Environment_SetEvent(&environment, &script_vm, up3)

	if !field_tracker.focused {
		panic("input inside raised-ZIndex panel failed to focus")
	}


	behind_tracker: ^classes.TextBox = nil
	for object in prompt_descriptor.instances {
		textbox := cast(^classes.TextBox)object
		if textbox.object.name == "BehindBox" {
			behind_tracker = textbox
		}
	}
	if behind_tracker == nil {
		panic("BehindBox TextBox not found")
	}
	if behind_tracker.focused {
		panic("covered sibling textbox was focused")
	}

	under_tracker: ^classes.TextBox = nil
	for object in prompt_descriptor.instances {
		textbox := cast(^classes.TextBox)object
		if textbox.object.name == "UnderBox" {
			under_tracker = textbox
		}
	}
	if under_tracker == nil {
		panic("UnderBox TextBox not found")
	}


	engine_runtime.Environment_SetEvent(&environment, &script_vm, make_mouse_motion(300, 175))

	if !field_tracker.mouse_inside {
		panic("prompt input should hover")
	}
	if behind_tracker.mouse_inside {
		panic("covered sibling textbox should not hover")
	}
	assert_hit_log(&script_vm, "E:field;", "after hovering prompt input")


	engine_runtime.Environment_SetEvent(&environment, &script_vm, make_mouse_motion(50, 50))

	if under_tracker.mouse_inside {
		panic("normal-screen textbox under an overlay should not hover")
	}
	if behind_tracker.mouse_inside {
		panic("textbox behind overlay backdrop should not hover")
	}
	assert_hit_log(&script_vm, "E:field;L:field;", "after hovering overlay backdrop")


	engine_runtime.Environment_SetEvent(&environment, &script_vm, make_mouse_down(160, 80))
	engine_runtime.Environment_SetEvent(&environment, &script_vm, make_mouse_up(160, 80))

	if field_tracker.focused {
		panic("clicking backdrop (outside panel) should blur the prompt input")
	}
	if behind_tracker.focused {
		panic("clicking backdrop should not focus a covered textbox")
	}


	run_script(
		&script_vm,
		`
local screen = Instance.new("ScreenGui")
screen.DisplayOrder = 500000
screen.RenderOnTop = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local card = Instance.new("CanvasGroup", screen)
card.Size = UDim2.fromOffset(80, 80)
card.Position = UDim2.fromOffset(500, 400)
local clicker = Instance.new("TextButton", card)
clicker.Name = "ConstructClickDetector"
clicker.Size = UDim2.fromScale(1, 1)
clicker.BackgroundTransparency = 1
clicker.TextTransparency = 1
clicker.Active = false
clicker.ZIndex = 3
local preview = Instance.new("ViewportFrame", card)
preview.Size = UDim2.fromScale(1, 1)
preview.Active = true
preview.ZIndex = 1
local disabled = Instance.new("TextButton", card)
disabled.Size = UDim2.fromScale(1, 1)
disabled.ZIndex = 4
disabled.Interactable = false
constructClicks = 0
clicker.MouseButton1Click:Connect(function()
    constructClicks += 1
end)
`,
		"construct_click_detector_setup",
	)
	classes.Update_GUI_Layout(&environment.classes, 800, 600)
	hit := classes.GuiObject_find_topmost(&environment.classes, 540, 440)
	assert(hit != nil && hit.name == "ConstructClickDetector")
	engine_runtime.Environment_SetEvent(&environment, &script_vm, make_mouse_down(540, 440))
	engine_runtime.Environment_SetEvent(&environment, &script_vm, make_mouse_up(540, 440))
	run_script(
		&script_vm,
		`assert(constructClicks == 1, tostring(constructClicks))`,
		"construct_click_detector_result",
	)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("GUI_HIT_TEST_SMOKE_PASSED")
}
