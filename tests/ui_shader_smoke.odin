package main

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import "core:strings"
import sdl3 "vendor:sdl3"

run_script :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "ui_shader_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("UIShader script failed")
	}
}

pixel :: proc(surface: ^kineffi.KineSkiaSurface, x, y: i32) -> [4]u8 {
	rgba: [4]u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, x, y, &rgba[0], &rgba[1], &rgba[2], &rgba[3])
	return rgba
}

render :: proc(
	environment: ^engine_runtime.Environment,
	script_vm: ^vm.VM,
	surface: ^kineffi.KineSkiaSurface,
) {
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
	engine_runtime.Environment_Render_2D(environment, script_vm, surface, 160, 110, 1.0 / 60.0)
	kineffi.Kine_Skia_Surface_Flush(surface)
}

main :: proc() {
	script_vm := vm.New()
	renderer_object: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)

	run_script(&script_vm, `
local screen = Instance.new("ScreenGui")
local function frame(parent, x, y, w, h, color)
	local object = Instance.new("Frame", parent)
	object.Position = UDim2.fromOffset(x, y)
	object.Size = UDim2.fromOffset(w, h)
	object.BackgroundColor3 = color or Color3.new(1, 1, 1)
	return object
end

local gradient = frame(screen, 12, 8, 48, 26, Color3.new(1, 0, 0))
fill = Instance.new("UIShader", gradient)
fill.Source = [[
	uniform float2 size;
	uniform float4 backgroundColor;
	uniform float3 endColor;
	half4 main(float2 p) {
		return half4(mix(backgroundColor.rgb, endColor, p.x / size.x), 1);
	}
]]
fill:SetUniform("endColor", {0, 0, 1})
local copy = fill:Clone()
assert(copy.Enabled and copy.Source == fill.Source and not copy.Compiled)
assert(copy:GetUniform("endColor")[3] == 1)
copy:Destroy()

local rounded = frame(screen, 76, 20, 42, 26)
rounded.Rotation = 90
rounded.BackgroundTransparency = 1
frame(rounded, 0, 0, 42, 26, Color3.new(0, 1, 0))
mask = Instance.new("UIShader", rounded)
mask.Source = [[
	uniform shader content;
	uniform float2 size;
	half4 main(float2 p) {
		float2 q = (p - size * 0.5) / (size * 0.5);
		return content.eval(p) * (1 - smoothstep(0.9, 1.0, length(q)));
	}
]]

local blurred = frame(screen, 12, 62, 40, 24)
blurred.BackgroundTransparency = 1
frame(blurred, 0, 0, 20, 24)
blur = Instance.new("UIShader", blurred)
blur.SampleRadius = 4
blur.Source = [[
	uniform shader content;
	half4 main(float2 p) {
		return (content.eval(p - float2(4, 0)) + content.eval(p) +
		        content.eval(p + float2(4, 0))) / 3;
	}
]]

frame(screen, 72, 62, 24, 24, Color3.new(0, 1, 1))
local glass = frame(screen, 80, 66, 36, 16)
backdrop = Instance.new("UIShader", glass)
backdrop.Source = [[
	uniform shader backdrop;
	half4 main(float2 p) { return backdrop.eval(p - float2(4, 0)); }
]]
`)

	surface := kineffi.Kine_Skia_Surface_Create(160, 110)
	assert(surface != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(surface)
	render(&environment, &script_vm, surface)

	left, right := pixel(surface, 15, 16), pixel(surface, 56, 16)
	assert(left[0] > 225 && right[2] > 225, "gradient should use object-local coordinates")
	assert(pixel(surface, 97, 33) == [4]u8{0, 255, 0, 255}, "mask should preserve the child at the center")
	assert(pixel(surface, 86, 14)[3] == 0, "mask should remove the rotated corner")
	assert(pixel(surface, 97, 15)[3] > 200, "mask should rotate with the object")
	blurred_edge := pixel(surface, 34, 74)[3]
	assert(blurred_edge > 50 && blurred_edge < 120, "blur should sample neighboring content")
	assert(pixel(surface, 98, 74) == [4]u8{0, 255, 255, 255}, "backdrop should sample previously drawn pixels")
	assert(pixel(surface, 110, 74)[3] == 0, "shader should preserve transparent backdrop samples")

	run_script(&script_vm, `
assert(fill.Compiled and fill.LastError == "", fill.LastError)
assert(mask.Compiled and mask.LastError == "", mask.LastError)
assert(blur.Compiled, blur.LastError)
assert(backdrop.Compiled, backdrop.LastError)
fill:SetUniform("endColor", {0, 1, 0})
`)
	render(&environment, &script_vm, surface)
	assert(pixel(surface, 56, 16)[1] > 225, "uniform updates should affect the next render")

	run_script(&script_vm, `fill.Source = "invalid SkSL"`)
	render(&environment, &script_vm, surface)
	run_script(&script_vm, `assert(not fill.Compiled and #fill.LastError > 0, "compile error should be reported")`)
	assert(pixel(surface, 56, 16) == [4]u8{255, 0, 0, 255}, "invalid shader should use the ordinary fill")

	run_script(&script_vm, `
	fill.Source = [[
		uniform float3 endColor;
		half4 main(float2 p) { return half4(0, 0, endColor.g, 1); }
	]]
	mask.Enabled = false
`)
	render(&environment, &script_vm, surface)
	run_script(&script_vm, `assert(fill.Compiled and fill.LastError == "", fill.LastError)`)
	assert(pixel(surface, 56, 16) == [4]u8{0, 0, 255, 255}, "valid source should replace an invalid shader")
	assert(pixel(surface, 86, 14)[3] == 255, "disabling the mask should restore ordinary drawing")

	run_script(&script_vm, `
local screen = Instance.new("ScreenGui")
window = Instance.new("Frame", screen)
window.Position = UDim2.fromOffset(112, 44)
window.Size = UDim2.fromOffset(40, 40)
window.BackgroundColor3 = Color3.new(1, 0, 0)
local child = Instance.new("Frame", window)
child.Position = UDim2.fromOffset(20, 0)
child.Size = UDim2.fromOffset(20, 40)
child.BackgroundColor3 = Color3.new(0, 1, 0)
warp = Instance.new("UIShader", window)
warp.Source = [[
	uniform shader content;
	uniform float4 guiTransform;
	half4 main(float2 p) {
		return content.eval(p) * half(clamp(guiTransform.x * 2, 0, 1));
	}
]]
assert(warp:GetUniform("guiTransform")[1] == 1)
assert(not pcall(function() warp:SetUniform("guiTransform", {1, 1}) end))
assert(not pcall(function() warp:SetUniform("guiTransform", {1, 1, math.huge, 0}) end))
warp:SetUniform("guiTransform", {0.5, 0.5, 20, 10})
local clone = warp:Clone()
assert(clone:GetUniform("guiTransform")[3] == 20)
clone:Destroy()
`)
	renderer_object.Cache2D = true
	render(&environment, &script_vm, surface)
	assert(pixel(surface, 136, 58) == [4]u8{255, 0, 0, 255}, "warp should move and scale the window")
	assert(pixel(surface, 146, 58) == [4]u8{0, 255, 0, 255}, "warp should move and scale the child")
	assert(pixel(surface, 120, 58)[3] == 0, "warp should vacate the original rectangle")
	assert(pixel(surface, 146, 76)[3] == 0, "warp should scale the window height")
	run_script(&script_vm, `
assert(warp.Compiled and warp.LastError == "")
assert(window.AbsolutePosition.X == 112 and window.AbsoluteSize.X == 40)
warp:SetUniform("guiTransform", {0, 0, 20, 10})
`)
	render(&environment, &script_vm, surface)
	assert(pixel(surface, 136, 58)[3] == 0, "a collapsed window should disappear")
	run_script(&script_vm, `warp:SetUniform("guiTransform", nil)`)
	render(&environment, &script_vm, surface)
	assert(pixel(surface, 120, 58) == [4]u8{255, 0, 0, 255}, "reset should restore the window")
	assert(pixel(surface, 146, 78) == [4]u8{0, 255, 0, 255}, "reset should restore the child")

	genie_source, read_error := os.read_entire_file("examples/ui_shader_genie.luau", context.allocator)
	assert(read_error == nil)
	defer delete(genie_source)
	genie_setup := strings.concatenate({
		"local createGenie = (function()\n",
		string(genie_source),
		"\nend)()\n",
		`
warp:Destroy()
genie, setGenieProgress = createGenie(window, Vector2.new(60, 95), Vector2.new(16, 12))
`,
	})
	defer delete(genie_setup)
	run_script(&script_vm, genie_setup)
	render(&environment, &script_vm, surface)
	assert(pixel(surface, 120, 58) == [4]u8{255, 0, 0, 255}, "genie should start at the window")
	assert(pixel(surface, 146, 78) == [4]u8{0, 255, 0, 255}, "genie should preserve child content")
	run_script(&script_vm, `assert(genie.Compiled and genie.LastError == "", genie.LastError); setGenieProgress(0.5)`)
	render(&environment, &script_vm, surface)
	assert(pixel(surface, 118, 74)[3] > 240, "upper row should remain near the window")
	assert(pixel(surface, 86, 94)[3] > 240, "lower row should bend toward the dock")
	assert(pixel(surface, 118, 94)[3] == 0, "the rows should have different offsets")
	run_script(&script_vm, `setGenieProgress(1)`)
	render(&environment, &script_vm, surface)
	assert(pixel(surface, 64, 101) == [4]u8{255, 0, 0, 255}, "genie should end at the dock")
	assert(pixel(surface, 72, 101) == [4]u8{0, 255, 0, 255}, "genie should carry the child into the dock")
	assert(pixel(surface, 120, 58)[3] == 0, "genie should vacate the window")

	wobbly_source, wobbly_read_error := os.read_entire_file("examples/ui_shader_wobbly_window.luau", context.allocator)
	assert(wobbly_read_error == nil)
	defer delete(wobbly_source)
	wobbly_setup := strings.concatenate({
		"local createWobblyWindow = (function()\n",
		string(wobbly_source),
		"\nend)()\n",
		`
genie:Destroy()
wobble, destroyWobble = createWobblyWindow(window)
`,
	})
	defer delete(wobbly_setup)
	run_script(&script_vm, wobbly_setup)
	render(&environment, &script_vm, surface)
	run_script(&script_vm, `assert(wobble.Compiled and wobble.LastError == "", wobble.LastError)`)
	assert(pixel(surface, 120, 58) == [4]u8{255, 0, 0, 255}, "idle wobble should preserve the window")
	event: sdl3.Event
	event.type = .MOUSE_BUTTON_DOWN
	event.button.button = sdl3.BUTTON_LEFT
	event.button.x, event.button.y = 116, 48
	engine_runtime.Environment_SetEvent(&environment, &script_vm, event)
	event = {}
	event.type = .MOUSE_MOTION
	event.motion.x, event.motion.y = 96, 48
	engine_runtime.Environment_SetEvent(&environment, &script_vm, event)
	run_script(&script_vm, `
assert(window.Position.X.Offset == 92, "mouse drag did not move the window")
assert(wobble:GetUniform("d22")[1] > wobble:GetUniform("d00")[1], "corners should wobble by different amounts")
-- Use a known displacement profile to check the warp independently of timing.
for _, name in {"d00", "d10", "d20", "d01", "d11", "d21"} do
	wobble:SetUniform(name, {0, 0})
end
for _, name in {"d02", "d12", "d22"} do
	wobble:SetUniform(name, {0.2, 0})
end
`)
	render(&environment, &script_vm, surface)
	warped_rows: [2][60][4]u8
	for x in 0..<60 {
		warped_rows[0][x] = pixel(surface, i32(x) + 85, 49)
		warped_rows[1][x] = pixel(surface, i32(x) + 85, 81)
	}
	run_script(&script_vm, `
for _, name in {"d02", "d12", "d22"} do wobble:SetUniform(name, {0, 0}) end
`)
	render(&environment, &script_vm, surface)
	changed_bottom := false
	for x in 0..<60 {
		assert(warped_rows[0][x] == pixel(surface, i32(x) + 85, 49), "upper row should stay in place")
		changed_bottom = changed_bottom || warped_rows[1][x] != pixel(surface, i32(x) + 85, 81)
	}
	assert(changed_bottom, "the lower row should warp independently")
	event = {}
	event.type = .MOUSE_BUTTON_UP
	event.button.button = sdl3.BUTTON_LEFT
	event.button.x, event.button.y = 96, 48
	engine_runtime.Environment_SetEvent(&environment, &script_vm, event)
	run_script(&script_vm, `destroyWobble(); assert(not window.Active and window:FindFirstChildOfClass("UIShader") == nil)`)

	run_script(&script_vm, `
local part = Instance.new("Part", workspace)
local canvas = Instance.new("SurfaceGui", part)
canvas.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
canvas.CanvasSize = Vector2.new(40, 20)
local image = Instance.new("ImageLabel", canvas)
image.Size = UDim2.fromScale(1, 1)
image.BackgroundTransparency = 1
image.Image = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="20" height="20" fill="#ff0000"/><rect x="20" width="20" height="20" fill="#0000ff"/></svg>'
imageShader = Instance.new("UIShader", image)
imageShader.Source = [[
	uniform shader content;
	uniform float2 size;
	half4 main(float2 p) { return content.eval(float2(size.x - p.x, p.y)); }
]]
imageShader.FullContentSampling = true
canvasShader = Instance.new("UIShader", canvas)
canvasShader.Source = [[
	uniform shader content;
	uniform float brightness;
	half4 main(float2 p) { return content.eval(p) * half(brightness); }
]]
canvasShader:SetUniform("brightness", 1)
`)
	canvas_descriptor := classes.Find_Class(&environment.classes, "SurfaceGui")
	assert(len(canvas_descriptor.instances) == 1)
	canvas := cast(^classes.SurfaceGui)canvas_descriptor.instances[0]
	canvas_ctx := classes.Class_Step_Context{renderer = &renderer_object, L = script_vm.L}
	texture_size := classes.SurfaceGui_Texture_Size{width = 20, height = 10, scale = 0.5}
	assert(classes.SurfaceGui_Render_Surface(canvas, &canvas_ctx, texture_size, 40, 20))
	run_script(&script_vm, `assert(imageShader.Compiled and canvasShader.Compiled)`)
	assert(pixel(canvas.surface, 4, 5) == [4]u8{0, 0, 255, 255}, "shader should sample the right half of the image")
	assert(pixel(canvas.surface, 16, 5) == [4]u8{255, 0, 0, 255}, "shader should sample the left half of the image")
	canvas.render_dirty = false
	run_script(&script_vm, `canvasShader:SetUniform("brightness", 0)`)
	assert(canvas.render_dirty, "a canvas shader uniform should invalidate the texture")
	assert(classes.SurfaceGui_Render_Surface(canvas, &canvas_ctx, texture_size, 40, 20))
	assert(pixel(canvas.surface, 4, 5)[3] == 0, "a shader on SurfaceGui should shade the whole canvas")

	assert(!classes.Gui_Overlay_Needs_Backdrop(&environment.classes))
	run_script(&script_vm, `
local screen = Instance.new("ScreenGui")
screen.RenderOnTop = true
overlay = Instance.new("Frame", screen)
overlay.Size = UDim2.fromOffset(30, 30)
overlayShader = Instance.new("UIShader", overlay)
overlayShader.Source = [[
	uniform shader backdrop;
	half4 main(float2 p) { return backdrop.eval(p); }
]]
`)
	assert(classes.Gui_Overlay_Needs_Backdrop(&environment.classes))
	renderer_object.Cache2D = true
	backdrop_surface := kineffi.Kine_Skia_Surface_Create(160, 110)
	assert(backdrop_surface != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(backdrop_surface)
	for i in 0 ..< 4 {
		color := [4]u8{255, 0, 0, 255} if i % 2 == 0 else [4]u8{0, 255, 0, 255}
		kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
		kineffi.Kine_Skia_Surface_Clear(backdrop_surface, color[0], color[1], color[2], color[3])
		kineffi.Kine_Skia_Surface_SetBackdropFromSurface(surface, backdrop_surface)
		engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, 160, 110, 1.0 / 60.0)
		kineffi.Kine_Skia_Surface_ClearBackdrop(surface)
		assert(pixel(surface, 5, 5) == color, "the overlay should sample the current backdrop")
	}
	run_script(&script_vm, `overlay.Visible = false`)
	assert(!classes.Gui_Overlay_Needs_Backdrop(&environment.classes))
	run_script(&script_vm, `overlay.Visible = true; overlayShader.Enabled = false`)
	assert(!classes.Gui_Overlay_Needs_Backdrop(&environment.classes))
	run_script(&script_vm, `overlayBackdrop = Instance.new("UIBackdrop", overlay)`)
	assert(classes.Gui_Overlay_Needs_Backdrop(&environment.classes))
	run_script(&script_vm, `overlayBackdrop.Enabled = false; Instance.new("UIMagnifier", overlay)`)
	assert(classes.Gui_Overlay_Needs_Backdrop(&environment.classes))

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("UI_SHADER_SMOKE_PASSED")
}
