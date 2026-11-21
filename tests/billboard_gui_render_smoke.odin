package main
import k "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(v, source, "billboard_gui_render")
	assert(ok, err)
}
pixel :: proc(env: ^runtime.Environment, v: ^vm.VM, surface: ^k.KineSkiaSurface) -> [4]u8 {
	runtime.Environment_Update_Step(env, v, 1.0 / 60)
	k.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 255)
	runtime.Environment_Render_2D(env, v, surface, 320, 240, 1.0 / 60)
	runtime.Environment_Render_Overlay(env, v, surface, 320, 240, 1.0 / 60)
	k.Kine_Skia_Surface_Flush(surface)
	p: [4]u8
	k.Kine_Skia_Surface_GetPixel(surface, 160, 120, &p[0], &p[1], &p[2], &p[3])
	fmt.println("BILLBOARD PIXEL", p)
	return p
}
main :: proc() {
	view := renderer.RendererObject {
		HasViewportRect = true,
		ViewportRect    = {0, 0, 320, 240},
	}
	v := vm.New(); env: runtime.Environment
	runtime.Environment_Init(&env, &v, &view)
	defer {vm.Close(&v); runtime.Environment_Destroy(&env)}
	surface := k.Kine_Skia_Surface_Create(320, 240); assert(surface != nil)
	defer k.Kine_Skia_Surface_Destroy(surface)
	run(
		&v,
		`
local camera=workspace.CurrentCamera
camera.CameraType=Enum.CameraType.Scriptable
camera.CFrame=CFrame.identity
target=Instance.new("Part",workspace)
target.Position=Vector3.new(0,0,-20)
target.Anchored=true
target.Transparency=1
target.Size=Vector3.one
wall=Instance.new("Part",workspace)
wall.Size=Vector3.new(10,10,1)
wall.Position=Vector3.new(0,0,-10)
wall.Anchored=true
bill=Instance.new("BillboardGui",target)
bill.Size=UDim2.fromOffset(80,40)
bill.RenderOnTop=true
assert(bill.AlwaysOnTop)
local f=Instance.new("Frame",bill)
f.Size=UDim2.fromScale(1,1)
f.BackgroundColor3=Color3.new(1,0,0)
f.BorderSizePixel=0
`,
	)
	p := pixel(&env, &v, surface)
	assert(p[0] > 200 && p[1] < 40, "RenderOnTop must show the label")
	run(&v, `bill.AlwaysOnTop=false;assert(not bill.RenderOnTop)`)
	p = pixel(&env, &v, surface)
	assert(p[0] < 40, "wall must occlude the billboard")
	run(&v, `wall.Transparency=1`)
	p = pixel(&env, &v, surface)
	assert(p[0] > 200, "transparent wall must not occlude")
	run(&v, `bill.MaxDistance=5`)
	p = pixel(&env, &v, surface)
	assert(p[0] < 40, "distance limit must hide billboard")
	run(&v, `bill.MaxDistance=100;bill.Enabled=false`)
	p = pixel(&env, &v, surface)
	assert(p[0] < 40, "disabled billboard must be hidden")
	fmt.println("BILLBOARD_GUI_RENDER_SMOKE_PASSED")
}
