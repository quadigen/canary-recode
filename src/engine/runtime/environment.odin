package engine_runtime

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import engine_enums "../enum"
import extensions "../extensions"
import globals "../global"
import packages "../packages"
import sdl3 "../platform"
import profiling "../profiling"
import renderer "../renderer"
import services "../services"
import signals "../signals"
import target "../target"
import tracy "../util/odin-tracy"
import vm "../vm"

// A recorded Skia display list for one GUI pass. Replaying it skips the whole
// class traversal when nothing that feeds the pass has changed.
Gui_Display_List :: struct {
	environment:    ^Environment,
	picture:        ^kineffi.KineSkiaPicture,
	revision:       u64,
	scene_revision: u64,
	// State seen on the previous miss. Recording only starts when the same
	// state shows up twice in a row, so a GUI that changes every frame never
	// pays for building a display list it cannot reuse.
	last_revision:       u64,
	last_scene_revision: u64,
	probed:              bool,
	surface:        ^renderer.Skia_Surface,
	width:          i32,
	height:         i32,
	valid:          bool,
}

@(private)
gui_step_display_list: Gui_Display_List
@(private)
gui_overlay_display_list: Gui_Display_List


gui_display_list_stable :: proc(
	cache: ^Gui_Display_List,
	revision, scene_revision: u64,
) -> bool {
	stable :=
		cache.probed &&
		cache.last_revision == revision &&
		cache.last_scene_revision == scene_revision
	cache.probed = true
	cache.last_revision = revision
	cache.last_scene_revision = scene_revision
	return stable
}


gui_display_list_matches :: proc(
	cache: ^Gui_Display_List,
	environment: ^Environment,
	surface: ^renderer.Skia_Surface,
	width, height: i32,
	revision, scene_revision: u64,
) -> bool {
	return cache.valid &&
		cache.environment == environment &&
		cache.surface == surface &&
		cache.width == width &&
		cache.height == height &&
		cache.revision == revision &&
		cache.scene_revision == scene_revision &&
		cache.picture != nil
}


gui_display_list_store :: proc(
	cache: ^Gui_Display_List,
	environment: ^Environment,
	surface: ^renderer.Skia_Surface,
	width, height: i32,
	revision, scene_revision: u64,
	picture: ^kineffi.KineSkiaPicture,
) {
	if cache.picture != nil {kineffi.Kine_Skia_Picture_Destroy(cache.picture)}
	cache^ = {
		environment    = environment,
		picture        = picture,
		revision       = revision,
		scene_revision = scene_revision,
		surface        = surface,
		width          = width,
		height         = height,
		valid          = picture != nil,
	}
}


Environment :: struct {
	classes:    classes.Registry,
	datatypes:  datatypes.Registry,
	enums:      engine_enums.Registry,
	services:   services.Registry,
	globals:    globals.Registry,
	signals:    signals.Registry,
	modules:    vm.Environment,
	renderer:   ^renderer.RendererObject,
	packages:   packages.Registry,
	extensions: extensions.Context,
	mode:       target.Mode,

	// 3D idle tracking: the renderer only asks Filament to render when one of
	// these differs from the revision captured after the last rendered frame.
	render_3d_revision_drawn: u64,
	render_3d_drawn:          bool,
	render_3d_viewport:       [4]i32,
}


// True when the 3D scene changed since the last time the renderer drew it.
Environment_3D_Dirty :: proc(environment: ^Environment) -> bool {
	if environment == nil {return true}
	revision := classes.Render_3D_Revision()
	viewport := [4]i32{}
	if environment.renderer != nil {
		viewport = environment.renderer.ViewportRect
	}
	changed :=
		!environment.render_3d_drawn ||
		revision != environment.render_3d_revision_drawn ||
		viewport != environment.render_3d_viewport
	if changed {
		environment.render_3d_drawn = true
		environment.render_3d_revision_drawn = revision
		environment.render_3d_viewport = viewport
	}
	return changed
}

install_classes :: proc(vm_state: ^vm.VM, ctx: rawptr) {
	registry := cast(^classes.Registry)ctx
	classes.Install_Instance_Library(registry, vm_state)
}

install_datatypes :: proc(vm_state: ^vm.VM, ctx: rawptr) {
	datatypes.Install(cast(^datatypes.Registry)ctx, vm_state)
}

install_enums :: proc(vm_state: ^vm.VM, ctx: rawptr) {
	engine_enums.Install(cast(^engine_enums.Registry)ctx, vm_state)
}

install_services :: proc(vm_state: ^vm.VM, ctx: rawptr) {
	services.Install(cast(^services.Registry)ctx, vm_state)
}

install_globals :: proc(vm_state: ^vm.VM, ctx: rawptr) {
	globals.Install(cast(^globals.Registry)ctx, vm_state)
}

install_signals :: proc(vm_state: ^vm.VM, ctx: rawptr) {
	signals.Install(cast(^signals.Registry)ctx, vm_state)
}

Environment_Init :: proc(
	environment: ^Environment,
	vm_state: ^vm.VM,
	renderer_object: ^renderer.RendererObject = nil,
	mode: target.Mode = target.current_mode,
) {
	assert(environment != nil)
	environment.mode = mode
	environment.renderer = renderer_object
	engine_enums.Registry_Init(&environment.enums)
	datatypes.Registry_Init(&environment.datatypes, &environment.enums)
	signals.Registry_Init(&environment.signals)
	environment.classes = classes.Registry_Init(
		&environment.datatypes,
		&environment.enums,
		renderer_object,
		signal_registry = &environment.signals,
	)
	environment.services = services.Registry_Init(&environment.classes, &environment.signals, mode)


	services.Install_Part_Body_Access(&environment.services)
	environment.modules = vm.Environment_Init()

	classes.Register_Default_Classes(&environment.classes)
	services.Register_Default_Services(&environment.services)
	globals.Register_Default_Globals(&environment.globals)
	classes.Set_Require_Resolver(&environment.classes, packages.Resolve, &environment.packages)

	vm.Environment_Add(&environment.modules, "classes", install_classes, &environment.classes)
	vm.Environment_Add(
		&environment.modules,
		"datatypes",
		install_datatypes,
		&environment.datatypes,
	)
	vm.Environment_Add(&environment.modules, "enums", install_enums, &environment.enums)
	vm.Environment_Add(&environment.modules, "signals", install_signals, &environment.signals)
	vm.Environment_Add(&environment.modules, "services", install_services, &environment.services)
	vm.Environment_Add(&environment.modules, "globals", install_globals, &environment.globals)
	vm.Environment_Install(&environment.modules, vm_state)
	packages.Init(&environment.packages, vm_state, renderer_object)

	extensions.Context_Init(
		&environment.extensions,
		&environment.classes,
		&environment.services,
		&environment.datatypes,
		&environment.enums,
		vm_state,
	)
	extensions.Install_Luau_Api(&environment.extensions, vm_state)
}


Environment_Set_Mode :: proc(environment: ^Environment, mode: target.Mode) {
	if environment == nil {
		return
	}
	environment.mode = mode
	environment.services.mode = mode
	classes.Set_Mode(&environment.classes, mode)
}

Environment_Destroy :: proc(environment: ^Environment) {
	if environment == nil {
		return
	}
	extensions.Context_Destroy(&environment.extensions)
	packages.Destroy(&environment.packages)
	vm.Environment_Destroy(&environment.modules)
	services.Registry_Destroy(&environment.services)
	globals.Registry_Destroy(&environment.globals)
	signals.Registry_Destroy(&environment.signals)
	classes.Registry_Destroy(&environment.classes)
	engine_enums.Registry_Destroy(&environment.enums)
}

Environment_Render_Step :: proc(environment: ^Environment, vm_state: ^vm.VM, delta_time: f32) {
	if environment == nil || vm_state == nil || vm_state.L == nil {
		return
	}
	services.Render_Step(&environment.services, vm_state.L, delta_time)
	classes.Step(&environment.classes, vm_state.L, delta_time)
}

Environment_Update_Step :: proc(environment: ^Environment, vm_state: ^vm.VM, delta_time: f32) {
	if environment == nil || vm_state == nil || vm_state.L == nil {
		return
	}

	profiling.frame_tick(delta_time)
	profiling.frame_flush()

	{
		tracy.ZoneNC("Packages Update", 0x61AFEF)
		z := profiling.Begin("Packages Update", 0x61AFEF)
		packages.Update(&environment.packages, delta_time)
	}

	{
		tracy.ZoneNC("Extensions Step", 0xC792EA)
		z := profiling.Begin("Extensions Step", 0xC792EA)
		extensions.Step(&environment.extensions, delta_time)
	}

	{
		tracy.ZoneNC("Services Step", 0x8FB1DF)
		z := profiling.Begin("Services Step", 0x8FB1DF)
		services.Render_Step(&environment.services, vm_state.L, delta_time)
	}

	{
		tracy.ZoneNC("Classes Step .Update", 0xD08770)
		z := profiling.Begin("Classes Step .Update", 0xD08770)
		classes.Step(&environment.classes, vm_state.L, delta_time, phase = .Update)
	}

	{
		tracy.ZoneNC("Services Prepare 3D", 0xC678DD)
		z := profiling.Begin("Services Prepare 3D", 0xC678DD)
		services.Prepare_3D(&environment.services, environment.renderer)
	}
}

scale_event_coords :: proc(event: ^sdl3.Event) {
	scale := sdl3.UI_Scale > 1.0001 ? sdl3.UI_Scale : 1
	inset_x := sdl3.UI_Safe_Left
	inset_y := sdl3.UI_Safe_Top
	#partial switch event.type {
	case .MOUSE_MOTION:
		event.motion.x = (event.motion.x - inset_x) / scale
		event.motion.y = (event.motion.y - inset_y) / scale
		event.motion.xrel /= scale
		event.motion.yrel /= scale
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		event.button.x = (event.button.x - inset_x) / scale
		event.button.y = (event.button.y - inset_y) / scale
	case .MOUSE_WHEEL:
		event.wheel.mouse_x = (event.wheel.mouse_x - inset_x) / scale
		event.wheel.mouse_y = (event.wheel.mouse_y - inset_y) / scale
	}
}

ui_needs_transform :: proc() -> bool {
	return(
		sdl3.UI_Scale > 1.0001 ||
		sdl3.UI_Safe_Left > 0 ||
		sdl3.UI_Safe_Top > 0 ||
		sdl3.UI_Safe_Right > 0 ||
		sdl3.UI_Safe_Bottom > 0 \
	)
}


ui_metrics :: proc(width, height: i32) -> (scale: f32, inset_x, inset_y, vw, vh: i32) {
	scale = sdl3.UI_Scale > 1.0001 ? sdl3.UI_Scale : 1
	inset_x = i32(sdl3.UI_Safe_Left)
	inset_y = i32(sdl3.UI_Safe_Top)

	safe_w := width - i32(sdl3.UI_Safe_Left) - i32(sdl3.UI_Safe_Right)
	safe_h := height - i32(sdl3.UI_Safe_Top) - i32(sdl3.UI_Safe_Bottom)
	if safe_w < 1 {safe_w = width}
	if safe_h < 1 {safe_h = height}

	vw = max(i32(f32(safe_w) / scale), 1)
	vh = max(i32(f32(safe_h) / scale), 1)
	return
}

ui_scale_begin :: proc(
	surface: ^renderer.Skia_Surface,
	scale: f32,
	inset_x, inset_y: i32,
) -> bool {
	if surface == nil {return false}
	translated := inset_x != 0 || inset_y != 0
	scaled := scale > 1.0001
	if !translated && !scaled {return false}

	skia := cast(^kineffi.KineSkiaSurface)surface
	kineffi.Kine_Skia_Surface_Save(skia)
	if translated {
		kineffi.Kine_Skia_Surface_Translate(skia, f32(inset_x), f32(inset_y))
	}
	if scaled {
		kineffi.Kine_Skia_Surface_Scale(skia, scale, scale)
	}
	return true
}

ui_scale_end :: proc(surface: ^renderer.Skia_Surface, scaled: bool) {
	if scaled {
		kineffi.Kine_Skia_Surface_Restore(cast(^kineffi.KineSkiaSurface)surface)
	}
}

Environment_SetEvent :: proc(environment: ^Environment, vm_state: ^vm.VM, event: sdl3.Event) {
	if environment == nil || vm_state == nil || vm_state.L == nil {
		return
	}


	event := event
	if ui_needs_transform() {
		scale_event_coords(&event)
	}

	// Hover / focus / cursor state can change what the GUI draws without a
	// property write, so any event invalidates the cached 2D display list.
	classes.Gui_Render_Mark_Dirty()

	packages.Set_Event(&environment.packages, event)

	classes.GuiObject_Handle_Event(&environment.classes, vm_state.L, event)

	classes.GuiButton_Handle_Event(&environment.classes, vm_state.L, event)

	classes.TextBox_Handle_Event(&environment.classes, vm_state.L, event)

	classes.ScrollingFrame_Handle_Event(&environment.classes, event)

	services.Set_Event(&environment.services, vm_state.L, event)

	if event.type == .MOUSE_WHEEL &&
	   environment.renderer != nil &&
	   environment.renderer.ActiveCamera != nil {
		active_camera := cast(^classes.Object)environment.renderer.ActiveCamera

		if active_camera != nil &&
		   !active_camera.destroyed &&
		   classes.Is_A(active_camera, "Camera") {
			wheel_y := f32(event.wheel.y)

			when ODIN_OS != .JS {
				if event.wheel.direction == .FLIPPED {
					wheel_y = -wheel_y
				}
			}

			classes.Camera_Add_Scroll(cast(^classes.Camera)active_camera, wheel_y)
		}
	}
}
Environment_Render_3D :: proc(environment: ^Environment, vm_state: ^vm.VM, delta_time: f32) {
	if environment == nil || vm_state == nil || vm_state.L == nil {
		return
	}

	{
		tracy.ZoneNC("Packages Render 3D", 0x61AFEF)
		z := profiling.Begin("Packages Render 3D", 0x61AFEF)
		packages.Render_3D(&environment.packages, delta_time)
	}

	{
		tracy.ZoneNC("Classes Step .Render3D", 0xD08770)
		z := profiling.Begin("Classes Step .Render3D", 0xD08770)
		viewport_width, viewport_height := i32(0), i32(0)
		if environment.renderer.HasViewportRect {
			viewport_width = environment.renderer.ViewportRect[2]
			viewport_height = environment.renderer.ViewportRect[3]
		}
		classes.Step(
			&environment.classes,
			vm_state.L,
			delta_time,
			viewport_width,
			viewport_height,
			phase = .Render_3D,
		)
	}

	{
		tracy.ZoneNC("Services Render 3D", 0x8FB1DF)
		z := profiling.Begin("Services Render 3D", 0x8FB1DF)
		services.Render_3D(&environment.services, vm_state.L, environment.renderer, delta_time)
	}

	{
		tracy.ZoneNC("Packages Render 3D Above", 0x61AFEF)
		z := profiling.Begin("Packages Render 3D Above", 0x61AFEF)
		packages.Render_3D_Above(&environment.packages, delta_time)
	}
}

Environment_Render_2D :: proc(
	environment: ^Environment,
	vm_state: ^vm.VM,
	surface: ^renderer.Skia_Surface,
	width, height: i32,
	delta_time: f32,
) {
	if environment == nil ||
	   vm_state == nil ||
	   vm_state.L == nil ||
	   surface == nil ||
	   environment.renderer == nil {
		return
	}

	previous_surface := environment.renderer.SkiaSurface
	environment.renderer.SkiaSurface = surface
	defer environment.renderer.SkiaSurface = previous_surface

	scale, inset_x, inset_y, virtual_width, virtual_height := ui_metrics(width, height)
	ui_scaled := ui_scale_begin(surface, scale, inset_x, inset_y)
	defer ui_scale_end(surface, ui_scaled)

	{
		tracy.ZoneNC("Studio Theme Layout", 0x56B6C2)
		z := profiling.Begin("Studio Theme Layout", 0x56B6C2)
		services.StudioThemeService_Update_Layout(
			&environment.services,
			vm_state.L,
			&environment.datatypes,
			virtual_width,
			virtual_height,
		)
	}

	{
		tracy.ZoneNC("Packages Render 2D", 0x61AFEF)
		z := profiling.Begin("Packages Render 2D", 0x61AFEF)
		packages.Render_2D(&environment.packages, virtual_width, virtual_height, delta_time)
	}

	{
		tracy.ZoneNC("GUI Layout", 0x56B6C2)
		z := profiling.Begin("GUI Layout", 0x56B6C2)
		classes.Update_GUI_Layout(&environment.classes, virtual_width, virtual_height, delta_time)
	}

	{
		tracy.ZoneNC("Classes Step .Render2D", 0xD08770)
		z := profiling.Begin("Classes Step .Render2D", 0xD08770)
		classes.ViewportFrame_Prepare_All(
			&environment.classes,
			virtual_width,
			virtual_height,
			delta_time,
		)

		skia := cast(^kineffi.KineSkiaSurface)surface
		cache := &gui_step_display_list
		revision := classes.Gui_Render_Revision()
		scene_revision := classes.Render_3D_Revision()
		animated := classes.Gui_Render_Consume_Animated()
		if environment.renderer.Cache2D &&
		   !animated &&
		   gui_display_list_matches(
			cache,
			environment,
			surface,
			width,
			height,
			revision,
			scene_revision,
		) {
			kineffi.Kine_Skia_Surface_DrawPicture(skia, cache.picture)
		} else {
			recording :=
			environment.renderer.Cache2D &&
			!animated &&
			gui_display_list_stable(cache, revision, scene_revision) &&
			kineffi.Kine_Skia_Surface_BeginPicture(skia) != 0
			classes.Step(
				&environment.classes,
				vm_state.L,
				delta_time,
				virtual_width,
				virtual_height,
			)
			if recording {
				picture := kineffi.Kine_Skia_Surface_EndPicture(skia)
				// The recording frame never touched the real surface, so replay the
				// fresh display list once to draw what this frame should show.
				if picture != nil {kineffi.Kine_Skia_Surface_DrawPicture(skia, picture)}
				if picture != nil &&
				   classes.Gui_Render_Revision() == revision &&
				   classes.Render_3D_Revision() == scene_revision {
					gui_display_list_store(
						cache,
						environment,
						surface,
						width,
						height,
						revision,
						scene_revision,
						picture,
					)
				} else {
					if picture != nil {kineffi.Kine_Skia_Picture_Destroy(picture)}
					cache.valid = false
				}
			}
		}
	}

	{
		tracy.ZoneNC("Packages Render 2D Above", 0x61AFEF)
		z := profiling.Begin("Packages Render 2D Above", 0x61AFEF)
		packages.Render_2D_Above(&environment.packages, virtual_width, virtual_height, delta_time)
	}
}

Environment_Render_Overlay :: proc(
	environment: ^Environment,
	vm_state: ^vm.VM,
	surface: ^renderer.Skia_Surface,
	width, height: i32,
	delta_time: f32,
) {
	if environment == nil ||
	   vm_state == nil ||
	   vm_state.L == nil ||
	   surface == nil ||
	   environment.renderer == nil {
		return
	}

	previous_surface := environment.renderer.SkiaSurface
	environment.renderer.SkiaSurface = surface
	defer environment.renderer.SkiaSurface = previous_surface

	scale, inset_x, inset_y, virtual_width, virtual_height := ui_metrics(width, height)
	ui_scaled := ui_scale_begin(surface, scale, inset_x, inset_y)
	defer ui_scale_end(surface, ui_scaled)

	skia := cast(^kineffi.KineSkiaSurface)surface
	cache := &gui_overlay_display_list
	revision := classes.Gui_Render_Revision()
	scene_revision := classes.Render_3D_Revision()
	animated := classes.Gui_Render_Is_Animated()
	if environment.renderer.Cache2D &&
	   !animated &&
	   gui_display_list_matches(
		cache,
		environment,
		surface,
		width,
		height,
		revision,
		scene_revision,
	) {
		kineffi.Kine_Skia_Surface_DrawPicture(skia, cache.picture)
		return
	}

	recording :=
		environment.renderer.Cache2D &&
		!animated &&
		gui_display_list_stable(cache, revision, scene_revision) &&
		kineffi.Kine_Skia_Surface_BeginPicture(skia) != 0
	{
		tracy.ZoneNC("Classes Step .Overlay", 0xD08770)
		z := profiling.Begin("Classes Step .Overlay", 0xD08770)
		classes.Step(
			&environment.classes,
			vm_state.L,
			delta_time,
			virtual_width,
			virtual_height,
			gui_overlay = true,
		)
	}
	if recording {
		picture := kineffi.Kine_Skia_Surface_EndPicture(skia)
		if picture != nil {kineffi.Kine_Skia_Surface_DrawPicture(skia, picture)}
		if picture != nil &&
		   classes.Gui_Render_Revision() == revision &&
		   classes.Render_3D_Revision() == scene_revision {
			gui_display_list_store(
				cache,
				environment,
				surface,
				width,
				height,
				revision,
				scene_revision,
				picture,
			)
		} else {
			if picture != nil {kineffi.Kine_Skia_Picture_Destroy(picture)}
			cache.valid = false
		}
	}
}
