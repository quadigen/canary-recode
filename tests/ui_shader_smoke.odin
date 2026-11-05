package main

import kineffi "../src/engine/bindings"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

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

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("UI_SHADER_SMOKE_PASSED")
}
