package engine_runtime

import sdl3 "../platform"
import classes "../classes"
import datatypes "../datatypes"
import engine_enums "../enum"
import globals "../global"
import packages "../packages"
import signals "../signals"
import services "../services"
import target "../target"
import vm "../vm"
import renderer "../renderer"
import tracy "../util/odin-tracy"
import profiling "../profiling"

Environment :: struct {
	classes: classes.Registry,
	datatypes: datatypes.Registry,
	enums: engine_enums.Registry,
	services: services.Registry,
	globals: globals.Registry,
	signals: signals.Registry,
	modules: vm.Environment,
	renderer: ^renderer.RendererObject,
	packages: packages.Registry,
	// mode is the role of this runtime (Server/Client/Editor). Script execution
	// is scoped by it: Scripts belong to servers and LocalScripts to clients.
	mode: target.Mode,
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
	environment.classes = classes.Registry_Init(&environment.datatypes, &environment.enums, renderer_object, signal_registry = &environment.signals)
	environment.services = services.Registry_Init(&environment.classes, &environment.signals, mode)
	environment.modules = vm.Environment_Init()

	classes.Register_Default_Classes(&environment.classes)
	services.Register_Default_Services(&environment.services)
	globals.Register_Default_Globals(&environment.globals)
	classes.Set_Require_Resolver(&environment.classes, packages.Resolve, &environment.packages)

	vm.Environment_Add(&environment.modules, "classes", install_classes, &environment.classes)
	vm.Environment_Add(&environment.modules, "datatypes", install_datatypes, &environment.datatypes)
	vm.Environment_Add(&environment.modules, "enums", install_enums, &environment.enums)
	vm.Environment_Add(&environment.modules, "signals", install_signals, &environment.signals)
	vm.Environment_Add(&environment.modules, "services", install_services, &environment.services)
	vm.Environment_Add(&environment.modules, "globals", install_globals, &environment.globals)
	vm.Environment_Install(&environment.modules, vm_state)
	packages.Init(&environment.packages, vm_state, renderer_object)
}

// Environment_Set_Mode overrides an Environment's runtime role after it has been
// initialized. Test harnesses and tooling that host a server runtime and a
// client runtime in the same process use this to give each VM the correct
// script execution scope.
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

Environment_Update_Step :: proc(
	environment: ^Environment,
	vm_state: ^vm.VM,
	delta_time: f32,
) {
	if environment == nil ||
	   vm_state == nil ||
	   vm_state.L == nil {
		return
	}

	profiling.frame_tick(delta_time)
	profiling.frame_flush()

	{
		tracy.ZoneNC("Packages Update", 0x61AFEF)
		z := profiling.Begin("Packages Update", 0x61AFEF)
		packages.Update(
			&environment.packages,
			delta_time,
		)
	}

	{
		tracy.ZoneNC("Services Step", 0x8FB1DF)
		z := profiling.Begin("Services Step", 0x8FB1DF)
		services.Render_Step(
			&environment.services,
			vm_state.L,
			delta_time,
		)
	}

	{
		tracy.ZoneNC("Classes Step .Update", 0xD08770)
		z := profiling.Begin("Classes Step .Update", 0xD08770)
		classes.Step(
			&environment.classes,
			vm_state.L,
			delta_time,
			phase = .Update,
		)
	}

	{
		tracy.ZoneNC("Services Prepare 3D", 0xC678DD)
		z := profiling.Begin("Services Prepare 3D", 0xC678DD)
		services.Prepare_3D(
			&environment.services,
			environment.renderer,
		)
	}
}

Environment_SetEvent :: proc(
	environment: ^Environment,
	vm_state: ^vm.VM,
	event: sdl3.Event,
) {
	if environment == nil ||
	   vm_state == nil ||
	   vm_state.L == nil {
		return
	}

	packages.Set_Event(
		&environment.packages,
		event,
	)

	classes.GuiObject_Handle_Event(
		&environment.classes,
		vm_state.L,
		event,
	)

	classes.GuiButton_Handle_Event(
		&environment.classes,
		vm_state.L,
		event,
	)

	classes.TextBox_Handle_Event(
		&environment.classes,
		vm_state.L,
		event,
	)

	classes.ScrollingFrame_Handle_Event(
		&environment.classes,
		event,
	)

	services.Set_Event(
		&environment.services,
		vm_state.L,
		event,
	)

	if event.type == .MOUSE_WHEEL &&
	   environment.renderer != nil &&
	   environment.renderer.ActiveCamera != nil {
		active_camera :=
			cast(^classes.Object)environment.renderer.ActiveCamera

		if active_camera != nil &&
		   !active_camera.destroyed &&
		   classes.Is_A(active_camera, "Camera") {
			wheel_y := f32(event.wheel.y)

			when ODIN_OS != .JS {
				if event.wheel.direction == .FLIPPED {
					wheel_y = -wheel_y
				}
			}

			classes.Camera_Add_Scroll(
				cast(^classes.Camera)active_camera,
				wheel_y,
			)
		}
	}
}
Environment_Render_3D :: proc(
	environment: ^Environment,
	vm_state: ^vm.VM,
	delta_time: f32,
) {
	if environment == nil ||
	   vm_state == nil ||
	   vm_state.L == nil {
		return
	}

	{
		tracy.ZoneNC("Packages Render 3D", 0x61AFEF)
		z := profiling.Begin("Packages Render 3D", 0x61AFEF)
		packages.Render_3D(
			&environment.packages,
			delta_time,
		)
	}

	{
		tracy.ZoneNC("Classes Step .Render3D", 0xD08770)
		z := profiling.Begin("Classes Step .Render3D", 0xD08770)
		classes.Step(
			&environment.classes,
			vm_state.L,
			delta_time,
			phase = .Render_3D,
		)
	}

	{
		tracy.ZoneNC("Services Render 3D", 0x8FB1DF)
		z := profiling.Begin("Services Render 3D", 0x8FB1DF)
		services.Render_3D(
			&environment.services,
			vm_state.L,
			environment.renderer,
			delta_time,
		)
	}

	{
		tracy.ZoneNC("Packages Render 3D Above", 0x61AFEF)
		z := profiling.Begin("Packages Render 3D Above", 0x61AFEF)
		packages.Render_3D_Above(
			&environment.packages,
			delta_time,
		)
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

	{
		tracy.ZoneNC("Studio Theme Layout", 0x56B6C2)
		z := profiling.Begin("Studio Theme Layout", 0x56B6C2)
		services.StudioThemeService_Update_Layout(
			&environment.services,
			vm_state.L,
			&environment.datatypes,
			width,
			height,
		)
	}

	{
		tracy.ZoneNC("Packages Render 2D", 0x61AFEF)
		z := profiling.Begin("Packages Render 2D", 0x61AFEF)
		packages.Render_2D(
			&environment.packages,
			width,
			height,
			delta_time,
		)
	}

	{
		tracy.ZoneNC("GUI Layout", 0x56B6C2)
		z := profiling.Begin("GUI Layout", 0x56B6C2)
		classes.Update_GUI_Layout(
			&environment.classes,
			width,
			height,
		)
	}

	{
		tracy.ZoneNC("Classes Step .Render2D", 0xD08770)
		z := profiling.Begin("Classes Step .Render2D", 0xD08770)
		classes.Step(
			&environment.classes,
			vm_state.L,
			delta_time,
			width,
			height,
		)
	}

	{
		tracy.ZoneNC("Packages Render 2D Above", 0x61AFEF)
		z := profiling.Begin("Packages Render 2D Above", 0x61AFEF)
		packages.Render_2D_Above(
			&environment.packages,
			width,
			height,
			delta_time,
		)
	}
}

Environment_Render_Overlay :: proc(
	environment: ^Environment,
	vm_state: ^vm.VM,
	surface: ^renderer.Skia_Surface,
	width, height: i32,
	delta_time: f32,
) {
	if environment == nil || vm_state == nil || vm_state.L == nil ||
	   surface == nil || environment.renderer == nil {
		return
	}

	previous_surface := environment.renderer.SkiaSurface
	environment.renderer.SkiaSurface = surface
	defer environment.renderer.SkiaSurface = previous_surface

	{
		tracy.ZoneNC("Classes Step .Overlay", 0xD08770)
		z := profiling.Begin("Classes Step .Overlay", 0xD08770)
		classes.Step(
			&environment.classes,
			vm_state.L,
			delta_time,
			width,
			height,
			gui_overlay = true,
		)
	}
}
