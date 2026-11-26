package main

import k "../src/engine/bindings"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import sdl "vendor:sdl3"

Profile_Counts :: struct {
	depth, starts, ends, minimum: int,
}
profile_callback :: proc "c" (user: rawptr, phase: cstring, begin: bool) {
	state := cast(^Profile_Counts)user
	if begin {state.depth += 1; state.starts += 1} else {state.depth -= 1; state.ends += 1; state.minimum = min(state.minimum, state.depth)}
}

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.Run(v, source, "reflection_schedule")
	assert(ok, err)
}

frame :: proc(
	env: ^engine_runtime.Environment,
	v: ^vm.VM,
	view: ^renderer.RendererObject,
	dt: f32,
) {
	services.Prepare_3D(&env.services, view)
	surface := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(view.Compositor)
	assert(surface != nil)
	k.Kine_Skia_Surface_Clear(surface, 20, 30, 40, 255)
	engine_runtime.Environment_Render_3D(env, v, dt)
	k.Kine_Filament_RenderFrame(view.Filament, dt)
	assert(k.Kine_VulkanCompositor_BeginOverlay(view.Compositor) != nil)
	assert(k.Kine_VulkanCompositor_EndFrame(view.Compositor) != 0)
}

main :: proc() {
	assert(sdl.Init({.VIDEO})); defer sdl.Quit()
	window := sdl.CreateWindow(
		"Probe schedule smoke",
		192,
		128,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil); defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 192, 128)
	assert(ctx != nil); defer k.Kine_Filament_Destroy(ctx)
	mode := sdl.GetCurrentDisplayMode(sdl.GetDisplayForWindow(window))
	expected_hz: f32 = 60
	if mode != nil {
		if mode.refresh_rate_numerator > 0 && mode.refresh_rate_denominator > 0 {
			expected_hz = f32(mode.refresh_rate_numerator) / f32(mode.refresh_rate_denominator)
		} else if mode.refresh_rate > 0 {expected_hz = mode.refresh_rate}
	}
	detected_hz := k.Kine_Filament_GetDisplayRefreshRate(ctx)
	assert(abs(detected_hz - expected_hz) < 0.02, "Filament must use the display current mode")
	fmt.println("DISPLAY_REFRESH_SMOKE", detected_hz, expected_hz)
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	view := renderer.RendererObject {
		Filament        = ctx,
		Compositor      = compositor,
		HasViewportRect = true,
		ViewportRect    = {0, 0, 192, 128},
	}
	v := vm.New(); env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v, &view)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
	counts: Profile_Counts
	k.Kine_VulkanCompositor_SetFrameProfileCallback(compositor, profile_callback, &counts)
	defer k.Kine_VulkanCompositor_SetFrameProfileCallback(compositor, nil, nil)
	k.Kine_Filament_SetFrameProfileCallback(ctx, profile_callback, &counts)
	defer k.Kine_Filament_SetFrameProfileCallback(ctx, nil, nil)
	run(
		&v,
		`
local l=game:GetService("Lighting")
for _,effect in l:GetChildren() do if effect:IsA("LightingEffect") then effect.Enabled=false end end
l.GlobalShadows=false
l.DynamicResolution=false
local p=l.ReflectionProbeEffect
p.Enabled=true; p.Resolution=32; p.UpdateInterval=1; p.MaxDistance=50
workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
workspace.CurrentCamera.CFrame=CFrame.new(0,5,12)
local part=Instance.new("Part",workspace)
part.Anchored=true; part.Material=Enum.Material.Metal
`,
	)
	frame(&env, &v, &view, 0.05)
	assert(k.Kine_Filament_GetReflectionProbeCaptureCount(ctx) == 1)
	for i in 1 ..= 5 {
		run(&v, fmt.tprintf("workspace.CurrentCamera.CFrame=CFrame.new(%d,5,12)", i * 5))
		frame(&env, &v, &view, 0.05)
		assert(
			k.Kine_Filament_GetReflectionProbeCaptureCount(ctx) == 1,
			"movement must respect interval",
		)
	}
	run(&v, `game:GetService("Lighting").ReflectionProbeEffect.UpdateInterval=0.1`)
	for i in 1 ..= 6 {
		frame(&env, &v, &view, 0.05)
		expected: u64 = 1 if i < 6 else 2
		assert(
			k.Kine_Filament_GetReflectionProbeCaptureCount(ctx) == expected,
			"subsequent captures span six frames",
		)
	}
	assert(
		counts.starts > 0 &&
		counts.starts == counts.ends &&
		counts.depth == 0 &&
		counts.minimum == 0,
	)
	gpu_id: u32; gpu_ns: u64
	if k.Kine_Filament_GetLatestGpuFrameTime(ctx, &gpu_id, &gpu_ns) {
		assert(gpu_ns > 0)
		fmt.println("GPU_FRAME_SAMPLE", gpu_id, gpu_ns)
	} else {fmt.println("GPU_FRAME_SAMPLE_UNAVAILABLE")}
	fmt.println("NATIVE_PROFILE_SCOPES", counts.starts)
	fmt.println("REFLECTION_PROBE_SCHEDULE_SMOKE_PASSED")
}
