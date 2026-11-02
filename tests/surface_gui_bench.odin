package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:time"

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import guilib "../src/engine/gui"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

SURFACE_GUI_BENCH_ELEMENTS :: 1000
SURFACE_GUI_BENCH_FRAMES :: 120
SURFACE_GUI_BENCH_WARMUP :: 20
SURFACE_GUI_BENCH_CANVAS_WIDTH :: 400
SURFACE_GUI_BENCH_CANVAS_HEIGHT :: 200

surface_gui_bench_run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("SurfaceGui benchmark setup failed")
	}
}

surface_gui_bench_unpremultiply :: proc(surface: ^kineffi.KineSkiaSurface) {
	pixels := kineffi.Kine_Skia_Surface_GetPixels(surface)
	row_bytes := kineffi.Kine_Skia_Surface_GetRowBytes(surface)
	width := kineffi.Kine_Skia_Surface_GetWidth(surface)
	height := kineffi.Kine_Skia_Surface_GetHeight(surface)

	if pixels == nil || row_bytes == 0 || width <= 0 || height <= 0 {
		return
	}

	data := cast([^]u8)pixels

	for y in 0 ..< int(height) {
		row := y * int(row_bytes)

		for x in 0 ..< int(width) {
			index := row + x * 4
			alpha := int(data[index + 3])

			if alpha == 0 || alpha == 255 {
				continue
			}

			data[index + 0] = u8(min(255, int(data[index + 0]) * 255 / alpha))
			data[index + 1] = u8(min(255, int(data[index + 1]) * 255 / alpha))
			data[index + 2] = u8(min(255, int(data[index + 2]) * 255 / alpha))
		}
	}
}

main :: proc() {
	elements := SURFACE_GUI_BENCH_ELEMENTS
	frames := SURFACE_GUI_BENCH_FRAMES

	if len(os.args) > 1 {
		if value, ok := strconv.parse_int(os.args[1]); ok && value > 0 {
			elements = value
		}
	}

	if len(os.args) > 2 {
		if value, ok := strconv.parse_int(os.args[2]); ok && value > 0 {
			frames = value
		}
	}

	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject

	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
	}

	surface_gui_bench_run_script(
		&script_vm,
		fmt.tprintf(
			`
local part = Instance.new("Part")
part.Name = "BenchPart"
part.Size = Vector3.new(4, 2, 1)
part.CFrame = CFrame.new(0, 0, 0)
part.Parent = workspace

local surface = Instance.new("SurfaceGui")
surface.Name = "BenchSurface"
surface.Face = Enum.NormalId.Back
surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
surface.CanvasSize = Vector2.new(%d, %d)
surface.Parent = part

local columns = 50
for i = 0, %d - 1 do
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset((i %% columns) * 8, math.floor(i / columns) * 10)
	label.Size = UDim2.fromOffset(8, 10)
	label.BackgroundTransparency = 1
	label.TextSize = 8
	label.Text = tostring(i)
	label.Parent = surface
end
`,
			SURFACE_GUI_BENCH_CANVAS_WIDTH,
			SURFACE_GUI_BENCH_CANVAS_HEIGHT,
			elements,
		),
		"surface_gui_bench_setup",
	)

	descriptor := classes.Find_Class(&environment.classes, "SurfaceGui")
	if descriptor == nil || len(descriptor.instances) != 1 {
		panic("expected exactly one benchmark SurfaceGui")
	}
	surface := cast(^classes.SurfaceGui)descriptor.instances[0]

	skia_surface := kineffi.Kine_Skia_Surface_Create(
		SURFACE_GUI_BENCH_CANVAS_WIDTH,
		SURFACE_GUI_BENCH_CANVAS_HEIGHT,
	)
	if skia_surface == nil {
		panic("Skia surface creation failed")
	}
	defer kineffi.Kine_Skia_Surface_Destroy(skia_surface)

	renderer_object.SkiaSurface = skia_surface
	ctx := classes.Class_Step_Context {
		L               = script_vm.L,
		delta_time      = 1.0 / 60.0,
		renderer        = &renderer_object,
		viewport_width  = SURFACE_GUI_BENCH_CANVAS_WIDTH,
		viewport_height = SURFACE_GUI_BENCH_CANVAS_HEIGHT,
	}

	frame :: proc(
		environment: ^engine_runtime.Environment,
		surface: ^classes.SurfaceGui,
		skia_surface: ^kineffi.KineSkiaSurface,
		ctx: ^classes.Class_Step_Context,
	) {
		classes.Update_GUI_Layout(&environment.classes, 800, 600, 1.0 / 60.0)

		kineffi.Kine_Skia_Surface_Clear(skia_surface, 0, 0, 0, 0)

		guilib.save(skia_surface)
		guilib.clipRect(
			skia_surface,
			guilib.Rect {
				width = SURFACE_GUI_BENCH_CANVAS_WIDTH,
				height = SURFACE_GUI_BENCH_CANVAS_HEIGHT,
			},
		)
		classes.ScreenGui_RenderChildren(&surface.object, ctx)
		guilib.restore(skia_surface)
		kineffi.Kine_Skia_Surface_Flush(skia_surface)

		surface_gui_bench_unpremultiply(skia_surface)
	}

	for _ in 0 ..< SURFACE_GUI_BENCH_WARMUP {
		frame(&environment, surface, skia_surface, &ctx)
	}

	start := time.now()

	for _ in 0 ..< frames {
		frame(&environment, surface, skia_surface, &ctx)
	}

	elapsed := time.duration_seconds(time.since(start))
	ms_per_frame := elapsed * 1000.0 / f64(frames)
	fps := f64(frames) / elapsed

	layout_start := time.now()

	for _ in 0 ..< frames {
		classes.Update_GUI_Layout(&environment.classes, 800, 600, 1.0 / 60.0)
	}

	layout_elapsed := time.duration_seconds(time.since(layout_start))
	layout_ms := layout_elapsed * 1000.0 / f64(frames)
	layout_fps := f64(frames) / layout_elapsed

	fmt.printf(
		"SurfaceGui %d elements, %dx%d canvas\n",
		elements,
		SURFACE_GUI_BENCH_CANVAS_WIDTH,
		SURFACE_GUI_BENCH_CANVAS_HEIGHT,
	)
	fmt.printf(
		"  full redraw: %.2f ms/frame, %.1f FPS (layout + Skia + unpremultiply)\n",
		ms_per_frame,
		fps,
	)
	fmt.printf(
		"  cached frame: %.2f ms/frame, %.1f FPS (layout only, no repaint)\n",
		layout_ms,
		layout_fps,
	)
}
