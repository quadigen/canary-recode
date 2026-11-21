package main

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(v, source, "world2d_editor_smoke")
	if !ok {fmt.eprintln(err); delete(err); panic("editor 2D test setup failed")}
}
pixel :: proc(s: ^renderer.Skia_Surface, x, y: i32) -> [4]u8 {
	r: [4]u8
	kineffi.Kine_Skia_Surface_GetPixel(s, x, y, &r[0], &r[1], &r[2], &r[3])
	return r
}
main :: proc() {
	v := vm.New()
	r: renderer.RendererObject
	e: runtime.Environment
	runtime.Environment_Init(&e, &v, &r, mode = .Editor)
	s := kineffi.Kine_Skia_Surface_Create(320, 240)
	assert(s != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(s)

	run(&v, "renderer:SetViewportRect(40, 32, 200, 160)")
	assert(r.ViewportRect_Host && r.HasViewportRect)
	assert(r.ViewportRect == [4]i32{40, 32, 200, 160})
	assert(!r.RenderFilament, "SetViewportRect must not enable the 3D renderer")
	png := []u8 {
		137,
		80,
		78,
		71,
		13,
		10,
		26,
		10,
		0,
		0,
		0,
		13,
		73,
		72,
		68,
		82,
		0,
		0,
		0,
		8,
		0,
		0,
		0,
		4,
		8,
		6,
		0,
		0,
		0,
		179,
		205,
		126,
		240,
		0,
		0,
		0,
		19,
		73,
		68,
		65,
		84,
		120,
		156,
		99,
		248,
		207,
		192,
		240,
		31,
		25,
		99,
		129,
		180,
		86,
		0,
		0,
		97,
		4,
		63,
		193,
		125,
		240,
		118,
		91,
		0,
		0,
		0,
		0,
		73,
		69,
		78,
		68,
		174,
		66,
		96,
		130,
	}
	classes.ImageLabel_Register_Runtime_Image("memory://editor2d.png", string(png))
	run(
		&v,
		`
workspace.Dimension = Enum.Dimension.D2
part = Instance.new("Part2D", workspace)
part.Position = UDim2.fromOffset(10,10)
part.Size = UDim2.fromOffset(40,40)
part.BackgroundColor3 = Color3.new(1,1,1)
part.BackgroundTransparency = 0
sprite = Instance.new("Sprite2D", workspace)
sprite.Image = "memory://editor2d.png"
sprite.Position = UDim2.fromOffset(70,10)
sprite.Size = UDim2.fromOffset(20,20)
sprite.FrameGrid = Vector2.new(2,1)
sprite.Frame = 1
assert(sprite.IsLoaded)
-- The Studio ScreenGui contains an opaque editor background.
studio = Instance.new("ScreenGui")
studio.DisplayOrder = 1000
studio.Parent = game.CoreGui
local background = Instance.new("Frame",studio)
background.Size = UDim2.fromScale(1,1)
background.BackgroundColor3 = Color3.new(0,0,0)
background.BackgroundTransparency = 0
-- Project-specific HUD must render over the 2D world in editor mode.
hud = Instance.new("ScreenGui")
local dot = Instance.new("Frame", hud)
dot.Position = UDim2.fromOffset(80, 15)
dot.Size = UDim2.fromOffset(10, 10)
dot.BackgroundColor3 = Color3.new(1, 0, 1)
dot.BackgroundTransparency = 0
`,
	)
	kineffi.Kine_Skia_Surface_Clear(s, 20, 28, 41, 255)
	runtime.Environment_Render_2D(&e, &v, s, 320, 240, 0)
	kineffi.Kine_Skia_Surface_Flush(s)
	assert(
		pixel(s, 15, 15) == [4]u8{0, 0, 0, 255},
		"editor background should still cover outside viewport",
	)
	assert(pixel(s, 55, 47) == [4]u8{255, 255, 255, 255}, "Part2D hidden by editor ScreenGui")
	assert(pixel(s, 115, 47) == [4]u8{0, 255, 0, 255}, "Sprite2D hidden by editor ScreenGui")
	assert(pixel(s, 85, 20) == [4]u8{255, 0, 255, 255}, "project HUD must appear over the world")
	assert(pixel(s, 260, 47) == [4]u8{0, 0, 0, 255}, "2D world not clipped to hosted viewport")

	run(
		&v,
		`
part:Destroy()
sprite:Destroy()
local physics = game:GetService("Workspace2D")
physics.Gravity = Vector2.new(0, 250)
local level = Instance.new("World2D", workspace)
local floor = Instance.new("Part2D", level)
floor.Size = UDim2.fromOffset(600, 40)
floor.Position = UDim2.fromOffset(0, 400)
floor.BackgroundColor3 = Color3.fromRGB(90, 150, 100)
local ball = Instance.new("Part2D", level)
ball.Size = UDim2.fromOffset(40, 40)
ball.AnchorPoint = Vector2.new(0.5, 0.5)
ball.Position = UDim2.fromOffset(300, 100)
ball.Anchored = false
ball.IsBall = true
ball.Elasticity = 0.7
ball.BackgroundColor3 = Color3.fromRGB(220, 120, 60)
workspace.SimulatePhysics = false
local savedCamera = Instance.new("Camera2D", level)
savedCamera.Position = UDim2.fromOffset(800, 800)
editorCamera = Instance.new("Camera2D")
assert(game:GetService("Project"):KeepEditorSceneHelper(editorCamera))
editorCamera.Parent = physics
editorCamera.Position = UDim2.new(0.5, 200, 0.5, 0)
`,
	)
	runtime.Environment_Update_Step(&e, &v, 1.0 / 60)
	run(&v, `assert(game:GetService("Workspace2D").BodyCount == 2)`)
	kineffi.Kine_Skia_Surface_Clear(s, 20, 28, 41, 255)
	runtime.Environment_Render_2D(&e, &v, s, 320, 240, 0)
	kineffi.Kine_Skia_Surface_Flush(s)
	assert(
		pixel(s, 140, 132) == [4]u8{220, 120, 60, 255},
		"nested ball should render through the Studio camera",
	)

	run(&v, `editorCamera.Position = UDim2.new(0.5, 200, 0.5, 330)`)
	kineffi.Kine_Skia_Surface_Clear(s, 20, 28, 41, 255)
	runtime.Environment_Render_2D(&e, &v, s, 320, 240, 0)
	kineffi.Kine_Skia_Surface_Flush(s)
	assert(
		pixel(s, 140, 112) == [4]u8{90, 150, 100, 255},
		"moving the Studio camera should reveal the floor",
	)

	run(&v, `renderer:SetViewportRect(0, 0, 0, 0)`)
	kineffi.Kine_Skia_Surface_Clear(s, 20, 28, 41, 255)
	runtime.Environment_Render_2D(&e, &v, s, 320, 240, 0)
	kineffi.Kine_Skia_Surface_Flush(s)
	assert(
		pixel(s, 140, 112) == [4]u8{0, 0, 0, 255},
		"a hidden Studio viewport must not draw across the window",
	)

	run(&v, `renderer:SetViewportRect(40, 32, 200, 160)`)
	run(&v, `workspace.Dimension = Enum.Dimension.D3`)
	kineffi.Kine_Skia_Surface_Clear(s, 20, 28, 41, 255)
	runtime.Environment_Render_2D(&e, &v, s, 320, 240, 0)
	kineffi.Kine_Skia_Surface_Flush(s)
	assert(pixel(s, 55, 47) == [4]u8{0, 0, 0, 255}, "scene should not draw in D3")
	vm.Close(&v)
	runtime.Environment_Destroy(&e)
	fmt.println("WORLD2D_EDITOR_SMOKE_PASSED")
}
