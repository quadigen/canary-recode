package main

import "core:fmt"
import kineffi "../src/engine/bindings"
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

	// Three overlay screens created in a deliberately "wrong" order: the
	// highest DisplayOrder is created first, so creation order alone would draw
	// it underneath. Sorting by DisplayOrder must reorder them regardless.
	ok, err := vm.Run(&script_vm, `
local top = Instance.new("ScreenGui")
top.Name = "Topmost"
top.DisplayOrder = 500
top.RenderOnTop = true

local middle = Instance.new("ScreenGui")
middle.Name = "Middle"
middle.DisplayOrder = 100
middle.RenderOnTop = true

local bottom = Instance.new("ScreenGui")
bottom.Name = "Bottom"
bottom.DisplayOrder = -50
bottom.RenderOnTop = true

-- All three live in CoreGui so none of them are StarterGui children, which
-- would otherwise force them into the overlay pass for a different reason.
for _, gui in ipairs({top, middle, bottom}) do
	gui.Parent = game.CoreGui
end

assert(top.DisplayOrder == 500, "DisplayOrder did not round-trip")
`, "screen_gui_display_order")

	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("screen gui display order probe failed")
	}

	// Drive both render passes so Step actually sorts and draws the screens.
	width: i32 = 800
	height: i32 = 600
	surface := kineffi.Kine_Skia_Surface_Create(width, height)
	assert(surface != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(surface)

	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 255)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0 / 60.0)
	engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, width, height, 1.0 / 60.0)

	// Each screen carries a full-bleed frame of a distinct colour, so the pixel
	// that survives is the one drawn last. With DisplayOrder respected the
	// highest value must win regardless of creation order.
	paint, paint_err := vm.Run(&script_vm, `
local function full(gui, r, g, b)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.new(r, g, b)
	frame.BorderSizePixel = 0
	frame.Parent = gui
end

full(game.CoreGui:FindFirstChild("Bottom"), 1, 0, 0)
full(game.CoreGui:FindFirstChild("Middle"), 0, 1, 0)
full(game.CoreGui:FindFirstChild("Topmost"), 0, 0, 1)
`, "screen_gui_display_order_paint")
	if !paint {
		fmt.eprintln(paint_err)
		delete(paint_err)
		panic("screen gui paint probe failed")
	}

	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0 / 60.0)
	engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, width, height, 1.0 / 60.0)
	kineffi.Kine_Skia_Surface_Flush(surface)

	r, g, b, a: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, 400, 300, &r, &g, &b, &a)

	// Topmost has the highest DisplayOrder, so blue must be the surviving colour.
	if r > 40 || g > 40 || b < 200 {
		fmt.eprintf("expected the DisplayOrder=500 screen on top, got r=%d g=%d b=%d\n", int(r), int(g), int(b))
		panic("ScreenGui DisplayOrder is not honoured")
	}

	fmt.println("SCREEN_GUI_DISPLAY_ORDER_SMOKE_PASSED")
	_ = renderer_object
}