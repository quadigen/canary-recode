package main

import k "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import tracy "../src/engine/util/odin-tracy"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:time"
import sdl "vendor:sdl3"

Native_Profile :: struct {
	zones: [16]tracy.ZoneCtx,
	depth: int,
}

native_profile_callback :: proc "c" (user: rawptr, phase: cstring, begin: bool) {
	context = tracy.DefaultContext()
	state := cast(^Native_Profile)user
	if begin {
		if state.depth < len(state.zones) {
			state.zones[state.depth] = tracy.ZoneBegin(true, 0, string(phase), 0xC678DD)
		}
		state.depth += 1
	} else if state.depth > 0 {
		state.depth -= 1
		if state.depth < len(state.zones) {tracy.ZoneEnd(state.zones[state.depth])}
	}
}

Bench_Overlay_Preparation :: struct {
	registry: ^classes.Registry,
	backdrop: int,
	required: bool,
	calls:    int,
}

prepare_overlay :: proc "c" (user: rawptr) {
	context = tracy.DefaultContext()
	p := cast(^Bench_Overlay_Preparation)user
	p.required =
		p.backdrop == 1 || (p.backdrop == -1 && classes.Gui_Overlay_Needs_Backdrop(p.registry))
	p.calls += 1
}

FRAMES :: 600
WARMUP :: 120

Phase :: enum {
	Events,
	Update,
	Acquire,
	Draw2D,
	Draw3D,
	Filament,
	Overlay,
	Present,
}

bench_int :: proc(key: string, fallback, minimum: int) -> int {
	value := os.get_env_alloc(key, context.allocator)
	defer delete(value)
	if len(value) == 0 {return fallback}
	parsed, ok := strconv.parse_int(value)
	assert(ok && parsed >= minimum)
	return parsed
}

main :: proc() {
	when tracy.TRACY_ENABLE {context.allocator = tracy.InitDefaultAllocator(callstack_size = 0)}
	tracy.SetThreadName("Desktop benchmark")
	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	width := i32(bench_int("BENCH_WIDTH", 640, 1))
	height := i32(bench_int("BENCH_HEIGHT", 480, 1))
	part_count := bench_int("BENCH_PARTS", 800, 0)
	frames := bench_int("BENCH_FRAMES", FRAMES, 1)
	render_world := bench_int("BENCH_WORLD", 1, 0) != 0
	backdrop := bench_int("BENCH_BACKDROP", -1, -1)
	overlap := bench_int("BENCH_HANDOFF_OVERLAP", 1, 0) != 0
	preparation: Bench_Overlay_Preparation
	animate := bench_int("BENCH_ANIMATE", 1, 0) != 0
	diverse := bench_int("BENCH_DIVERSE", 0, 0) != 0
	shadows := bench_int("BENCH_SHADOWS", 1, 0) != 0
	post_processing := bench_int("BENCH_POST_PROCESS", 1, 0) != 0
	effects_off := os.get_env_alloc("BENCH_EFFECTS_OFF", context.allocator)
	defer delete(effects_off)
	assert(backdrop <= 1)
	window := sdl.CreateWindow("3d bench", width, height, sdl.WINDOW_VULKAN)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	assert(sdl.GetWindowSizeInPixels(window, &width, &height))
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, width, height)
	assert(ctx != nil)
	defer k.Kine_Filament_Destroy(ctx)
	view := renderer.RendererObject {
		Filament        = ctx,
		Window          = window,
		HasViewportRect = true,
		ViewportRect    = {0, 0, width, height},
		RenderFilament  = true,
		Cache2D         = true,
	}
	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v, &view)
	defer {
		vm.Close(&v)
		engine_runtime.Environment_Destroy(&env)
	}

	setup := fmt.aprintf(
		`
workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
workspace.CurrentCamera.CFrame = CFrame.new(60, 45, 60) * CFrame.Angles(-0.6, 0.75, 0)
workspace.CurrentCamera.FieldOfView = 70
for i = 1, %d do
    local part = Instance.new("Part", workspace)
    part.Name = "Bench" .. i
    part.Anchored = true
    part.Size = Vector3.new(2, 2, 2)
    part.CFrame = CFrame.new((i %% 32) * 3, (i %% 7) * 2, math.floor(i / 32) * 3)
    if %v then
        part.Material = Enum.Material.Glass
        part.Transparency = i / (%d + 1)
    end
end
`,
		part_count,
		diverse,
		part_count,
	)
	ok, err := vm.Run(&v, setup, "3d_bench")
	delete(setup)
	if !ok {
		fmt.eprintln(err)
		panic("setup failed")
	}
	if !shadows || len(effects_off) > 0 {
		ok, err := vm.Run(
			&v,
			fmt.tprintf(
				`
local lighting = game:GetService("Lighting")
lighting.GlobalShadows = %v
local disabled = %q
for _, effect in lighting:GetChildren() do
    if disabled == "*" or string.find("," .. disabled .. ",", "," .. effect.Name .. ",", 1, true) then
        effect.Enabled = false
    end
end
`,
				shadows,
				effects_off,
			),
			"3d_bench_lighting",
		)
		assert(ok, err)
	}

	workspace := cast(^services.Workspace)services.Ensure_Service(&env.services, "Workspace")
	parts: [dynamic]^classes.Part
	defer delete(parts)
	for child in workspace.object.children {
		if child != nil && classes.Is_A_Class(child, &classes.Part_Class) {
			append(&parts, cast(^classes.Part)child)
		}
	}
	fmt.printfln(
		"%dx%d parts=%d world=%v backdrop=%d animate=%v shadows=%v post=%v effects_off=%q",
		width,
		height,
		len(parts),
		render_world,
		backdrop,
		animate,
		shadows,
		post_processing,
		effects_off,
	)

	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	view.Compositor = compositor
	samples := make([]time.Duration, frames)
	defer delete(samples)
	native_profile: Native_Profile
	when tracy.TRACY_ENABLE {
		k.Kine_Filament_SetFrameProfileCallback(ctx, native_profile_callback, &native_profile)
		defer k.Kine_Filament_SetFrameProfileCallback(ctx, nil, nil)
	}
	totals: [Phase]time.Duration
	total: time.Duration
	previous := time.tick_now()

	for frame in -WARMUP ..< frames {
		ticks: [len(Phase) + 1]time.Tick
		ticks[0] = time.tick_now()
		dt := min(f32(time.duration_seconds(time.tick_diff(previous, ticks[0]))), 0.1)
		previous = ticks[0]
		event: sdl.Event
		for sdl.PollEvent(&event) {
			assert(event.type != .QUIT && event.type != .WINDOW_CLOSE_REQUESTED)
			engine_runtime.Environment_SetEvent(&env, &v, event)
		}
		ticks[int(Phase.Update)] = time.tick_now()
		if animate {

			for part, index in parts {
				part.cframe.x += f64(index % 3 - 1) * 0.005 * f64(1 - 2 * (frame & 1))
			}
		}
		engine_runtime.Environment_Update_Step(&env, &v, dt)
		if !post_processing {k.Kine_Filament_SetPostProcessing(ctx, false)}

		ticks[int(Phase.Acquire)] = time.tick_now()
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
		assert(base != nil, string(k.Kine_VulkanCompositor_GetLastError(compositor)))
		view.SkiaSurface = base
		ticks[int(Phase.Draw2D)] = time.tick_now()
		k.Kine_Skia_Surface_Clear(base, 20, 28, 41, 255)
		engine_runtime.Environment_Render_2D(&env, &v, base, width, height, dt)
		ticks[int(Phase.Draw3D)] = time.tick_now()
		engine_runtime.Environment_Render_3D(&env, &v, dt)
		view.SkiaSurface = nil
		renderer.apply_viewport_rect(&view)
		ticks[int(Phase.Filament)] = time.tick_now()
		rendered_3d := render_world || k.Kine_Filament_Viewport_HasWork(ctx)
		if rendered_3d {
			preparation = {
				registry = &env.classes,
				backdrop = backdrop,
			}
			if overlap {
				k.Kine_Filament_Viewport_RenderFrameWithCpuWork(
					ctx,
					dt,
					render_world,
					prepare_overlay,
					&preparation,
				)
				assert(preparation.calls == 1)
			} else {
				k.Kine_Filament_Viewport_RenderFrame(ctx, dt, render_world)
			}
		}
		ticks[int(Phase.Overlay)] = time.tick_now()
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(compositor)
		assert(overlay != nil, string(k.Kine_VulkanCompositor_GetLastError(compositor)))
		needs_backdrop :=
			rendered_3d &&
			(preparation.required if overlap else (backdrop == 1 || (backdrop == -1 && classes.Gui_Overlay_Needs_Backdrop(&env.classes))))
		if needs_backdrop {k.Kine_Skia_Surface_SetBackdropFromSurface(overlay, overlay)}
		engine_runtime.Environment_Render_Overlay(&env, &v, overlay, width, height, dt)
		if needs_backdrop {k.Kine_Skia_Surface_ClearBackdrop(overlay)}
		ticks[int(Phase.Present)] = time.tick_now()
		assert(
			k.Kine_VulkanCompositor_EndFrame(compositor) != 0,
			string(k.Kine_VulkanCompositor_GetLastError(compositor)),
		)
		ticks[len(Phase)] = time.tick_now()
		tracy.FrameMark()

		if frame >= 0 {
			samples[frame] = time.tick_diff(ticks[0], ticks[len(Phase)])
			total += samples[frame]
			for phase in Phase {
				totals[phase] += time.tick_diff(ticks[int(phase)], ticks[int(phase) + 1])
			}
		}
	}
	slice.sort(samples)
	mean_ms := time.duration_milliseconds(total) / f64(frames)
	fmt.printfln(
		"items=%d mean=%.3f ms (%.1f FPS) p50=%.3f ms p95=%.3f ms p99=%.3f ms",
		len(workspace.draw_items),
		mean_ms,
		1000 / mean_ms,
		time.duration_milliseconds(samples[(frames * 50 - 1) / 100]),
		time.duration_milliseconds(samples[(frames * 95 - 1) / 100]),
		time.duration_milliseconds(samples[(frames * 99 - 1) / 100]),
	)
	for phase in Phase {
		fmt.printfln(
			"  %v %.3f ms",
			phase,
			time.duration_milliseconds(totals[phase]) / f64(frames),
		)
	}
	fmt.println("TMP_3D_BENCH_DONE")
}
