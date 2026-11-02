package main

import "core:fmt"
import "core:math"

import classes "../src/engine/classes"
import datatypes "../src/engine/datatypes"
import sdl3 "../src/engine/platform"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

surface_gui_run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("SurfaceGui input smoke setup failed")
	}
}

surface_gui_mouse_down :: proc(x, y: f32) -> sdl3.Event {
	e: sdl3.Event
	e.type = .MOUSE_BUTTON_DOWN
	e.button.button = sdl3.BUTTON_LEFT
	e.button.clicks = 1
	e.button.x = x
	e.button.y = y
	return e
}

surface_gui_mouse_up :: proc(x, y: f32) -> sdl3.Event {
	e: sdl3.Event
	e.type = .MOUSE_BUTTON_UP
	e.button.button = sdl3.BUTTON_LEFT
	e.button.clicks = 1
	e.button.x = x
	e.button.y = y
	return e
}

surface_gui_approx :: proc(a, b: f32) -> bool {
	return math.abs(a - b) < 0.01
}

surface_gui_find_button :: proc(
	environment: ^engine_runtime.Environment,
	name: string,
) -> ^classes.TextButton {
	descriptor := classes.Find_Class(&environment.classes, "TextButton")
	if descriptor == nil {
		return nil
	}

	for object in descriptor.instances {
		if object != nil && !object.destroyed && object.name == name {
			return cast(^classes.TextButton)object
		}
	}

	return nil
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject

	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
	}

	renderer_object.HasViewportRect = true
	renderer_object.ViewportRect = {0, 0, 800, 600}

	surface_gui_run_script(
		&script_vm,
		`
local part = Instance.new("Part")
part.Name = "SurfacePart"
part.Size = Vector3.new(4, 2, 1)
part.CFrame = CFrame.new(0, 0, 0)
part.Parent = workspace

local surface = Instance.new("SurfaceGui")
surface.Name = "SurfaceGui"
surface.Face = Enum.NormalId.Back
surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
surface.PixelsPerStud = 100
surface.Parent = part

local box = Instance.new("TextBox")
box.Name = "SurfaceBox"
box.Position = UDim2.fromOffset(150, 75)
box.Size = UDim2.fromOffset(100, 50)
box.Text = "hello"
box.Parent = surface

local button = Instance.new("TextButton")
button.Name = "SurfaceButton"
button.Position = UDim2.fromOffset(150, 75)
button.Size = UDim2.fromOffset(100, 50)
button.Text = "Go"
button.Visible = false
button.Parent = surface

_G.activated = 0
button.Activated:Connect(function()
	_G.activated = _G.activated + 1
end)
`,
		"surface_gui_input_setup",
	)

	camera := cast(^classes.Camera)renderer_object.ActiveCamera
	if camera == nil {
		panic("workspace did not provide an active camera")
	}
	camera.CFrame = datatypes.CFrame_New_XYZ(0, 0, 10)

	surface_descriptor := classes.Find_Class(&environment.classes, "SurfaceGui")
	if surface_descriptor == nil || len(surface_descriptor.instances) != 1 {
		panic("expected exactly one SurfaceGui instance")
	}
	surface := cast(^classes.SurfaceGui)surface_descriptor.instances[0]

	box_descriptor := classes.Find_Class(&environment.classes, "TextBox")
	if box_descriptor == nil || len(box_descriptor.instances) != 1 {
		panic("expected exactly one TextBox instance")
	}
	box := cast(^classes.TextBox)box_descriptor.instances[0]

	button := surface_gui_find_button(&environment, "SurfaceButton")
	if button == nil {
		panic("expected the SurfaceGui TextButton")
	}

	classes.Update_GUI_Layout(&environment.classes, 800, 600)

	if classes.GuiObject_find_topmost(&environment.classes, 400, 300) != nil {
		panic("SurfaceGui descendants must not participate in 2D screen hit tests")
	}

	hit := classes.GuiObject_hit_test(&environment.classes, 400, 300)
	if hit.surface != surface || hit.target != &box.gui_object {
		panic("centre ray did not hit the SurfaceGui TextBox")
	}
	if !surface_gui_approx(hit.x, 200) || !surface_gui_approx(hit.y, 100) {
		panic("SurfaceGui hit did not map to the centre of the canvas")
	}

	offset_hit := classes.GuiObject_hit_test(&environment.classes, 350, 300)
	if offset_hit.surface != surface ||
	   math.abs(offset_hit.x - 291.41) > 0.1 ||
	   !surface_gui_approx(offset_hit.y, 100) {
		panic("SurfaceGui hit did not map the off-centre ray onto the canvas")
	}

	point_x, point_y, point_ok := classes.GuiObject_pointer_point(
		&environment.classes,
		&box.gui_object,
		400,
		300,
	)
	if !point_ok || !surface_gui_approx(point_x, 200) || !surface_gui_approx(point_y, 100) {
		panic("pointer point did not convert through the SurfaceGui")
	}

	engine_runtime.Environment_SetEvent(&environment, &script_vm, surface_gui_mouse_down(400, 300))

	if !box.focused {
		panic("clicking the SurfaceGui TextBox did not focus it")
	}

	engine_runtime.Environment_SetEvent(&environment, &script_vm, surface_gui_mouse_up(400, 300))

	box.gui_object.visible = false
	button.gui_object.visible = true

	engine_runtime.Environment_SetEvent(&environment, &script_vm, surface_gui_mouse_down(400, 300))
	engine_runtime.Environment_SetEvent(&environment, &script_vm, surface_gui_mouse_up(400, 300))

	activated_type := vm.GetGlobal(script_vm.L, "activated")
	if activated_type != .Number {
		panic("button Activated counter was not set")
	}

	activated, ok := vm.ToNumber(script_vm.L, -1)
	vm.Pop(script_vm.L, 1)
	if !ok || activated != 1 {
		panic("clicking the SurfaceGui TextButton did not activate it")
	}

	fmt.println("SURFACE_GUI_INPUT_SMOKE_PASSED")
}
