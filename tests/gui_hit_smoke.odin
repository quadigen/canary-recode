package main

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

hit_name :: proc(env: ^engine_runtime.Environment, x, y: f32, require_paint: bool) -> string {
	found := classes.GuiObject_find_topmost(&env.classes, x, y, require_paint, false)
	if found == nil {
		return ""
	}
	return string(found.name)
}

expect :: proc(label, got, want: string) {
	if got != want {
		fmt.eprintf("FAIL %s: got %q want %q\n", label, got, want)
		panic("gui_hit_smoke failed")
	}
	fmt.printf("ok %-34s -> %q\n", label, got)
}

main :: proc() {
	script_vm := vm.New()
	renderer_object: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)

	ok, err := vm.Run(
		&script_vm,
		`
local screen = Instance.new("ScreenGui")

local function place(inst, x)
	inst.Parent = screen
	inst.Size = UDim2.fromOffset(150, 150)
	inst.Position = UDim2.fromOffset(x, 0)
	return inst
end

local f = place(Instance.new("Frame"), 0)
f.Name = "TransparentFrame"
f.BackgroundTransparency = 1
f.Active = true
f.InputSink = true

local tb = place(Instance.new("TextButton"), 160)
tb.Name = "EmptyTextButton"
tb.Text = ""
tb.BackgroundTransparency = 1

local tbx = place(Instance.new("TextButton"), 320)
tbx.Name = "TextButtonWithText"
tbx.Text = "X"
tbx.BackgroundTransparency = 1

local ib = place(Instance.new("ImageButton"), 480)
ib.Name = "EmptyImageButton"
ib.BackgroundTransparency = 1

local op = place(Instance.new("Frame"), 640)
op.Name = "OpaqueFrame"
op.Active = true
`,
		"gui_hit_smoke",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("gui_hit_smoke setup failed")
	}

	surface := kineffi.Kine_Skia_Surface_Create(800, 150)
	if surface == nil {panic("Skia surface creation failed")}
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, 800, 150, 1.0 / 60.0)
	kineffi.Kine_Skia_Surface_Destroy(surface)

	expect("transparent frame covers nothing", hit_name(&environment, 75, 75, true), "")
	expect(
		"transparent frame still routes clicks",
		hit_name(&environment, 75, 75, false),
		"TransparentFrame",
	)
	expect("empty text button covers nothing", hit_name(&environment, 235, 75, true), "")
	expect(
		"empty text button still routes clicks",
		hit_name(&environment, 235, 75, false),
		"EmptyTextButton",
	)
	expect(
		"text button with text covers",
		hit_name(&environment, 395, 75, true),
		"TextButtonWithText",
	)
	expect("empty image button covers nothing", hit_name(&environment, 555, 75, true), "")
	expect("opaque frame covers", hit_name(&environment, 715, 75, true), "OpaqueFrame")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("GUI_HIT_SMOKE_PASSED")
}
