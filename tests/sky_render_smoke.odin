package main
import assetstore "../src/engine/assetstore"
import k "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import sdl "vendor:sdl3"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(v, source, "sky_render")
	assert(ok, err)
}
sample :: proc(env: ^runtime.Environment, v: ^vm.VM) -> [4]u8 {
	ctx := env.renderer.Filament
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	pixel: [4]u8
	for i in 0 ..< 4 {
		services.Prepare_3D(&env.services, env.renderer)
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
		assert(base != nil)
		k.Kine_Skia_Surface_Clear(base, 0, 0, 0, 255)
		runtime.Environment_Render_2D(env, v, base, 320, 240, 1.0 / 60)
		runtime.Environment_Render_3D(env, v, 1.0 / 60)
		k.Kine_Filament_RenderFrame(ctx, 1.0 / 60)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(compositor)
		assert(overlay != nil)
		runtime.Environment_Render_Overlay(env, v, overlay, 320, 240, 1.0 / 60)
		k.Kine_Skia_Surface_GetPixel(overlay, 160, 120, &pixel[0], &pixel[1], &pixel[2], &pixel[3])
		assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}
	fmt.println("SKY PIXEL", pixel)
	return pixel
}
register_face :: proc(rgb: [3]u8) -> string {
	header := "P6\n16 16\n255\n"
	blob := make([]u8, len(header) + 16 * 16 * 3)
	copy(blob, transmute([]u8)header)
	for i in 0 ..< 16 * 16 {for c in 0 ..< 3 {blob[len(header) + i * 3 + c] = rgb[c]}}
	return assetstore.Register(blob, "face.ppm", .Texture)
}
main :: proc() {
	assert(sdl.Init({.VIDEO})); defer sdl.Quit()
	window := sdl.CreateWindow("Sky regression", 320, 240, sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN)
	assert(window != nil); defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	assert(ctx != nil); defer k.Kine_Filament_Destroy(ctx)
	view := renderer.RendererObject {
		Filament        = ctx,
		HasViewportRect = true,
		ViewportRect    = {0, 0, 320, 240},
	}
	v := vm.New(); env: runtime.Environment
	runtime.Environment_Init(&env, &v, &view)
	defer {vm.Close(&v); runtime.Environment_Destroy(&env)}
	run(
		&v,
		`
local lighting=game:GetService("Lighting")
for _,effect in lighting:GetChildren() do if effect:IsA("LightingEffect") then effect.Enabled=false end end
workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
workspace.CurrentCamera.CFrame=CFrame.new(0,0,0)
sky=Instance.new("Sky",lighting)
sky.CelestialBodiesShown=false

`,
	)
	red := register_face({255, 0, 0}); defer delete(red)
	green := register_face({0, 255, 0}); defer delete(green)

	red_uri := fmt.aprintf("kineasset://%s", red); defer delete(red_uri)
	vm.PushString(v.L, red_uri); vm.SetGlobal(v.L, "redURI")
	run(
		&v,
		`for _,face in {"Right","Left","Up","Down","Back","Front"} do sky["Skybox"..face.."Content"]=Content.fromUri(redURI) end`,
	)
	r := sample(&env, &v)
	lighting := cast(^services.Lighting)services.Ensure_Service(&env.services, "Lighting")
	assert(lighting.sky_uploaded, "Sky upload failed")
	assert(
		int(r[0]) > int(r[1]) + 30 && int(r[0]) > int(r[2]) + 30,
		"red sky must actually render",
	)
	green_uri := fmt.aprintf("kineasset://%s", green); defer delete(green_uri)
	vm.PushString(v.L, green_uri); vm.SetGlobal(v.L, "greenURI")
	run(&v, `for _,face in {"Rt","Lf","Up","Dn","Bk","Ft"} do sky["Skybox"..face]=greenURI end`)
	g := sample(&env, &v)
	assert(int(g[1]) > int(g[0]) + 30 && int(g[1]) > int(g[2]) + 30, "changed sky must render")
	run(&v, `sky:Destroy()`)
	fallback := sample(&env, &v)
	assert(!lighting.sky_uploaded && fallback != g)
	fmt.println("SKY_RENDER_SMOKE_PASSED")
}
