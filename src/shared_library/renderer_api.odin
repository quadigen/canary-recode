package shared_library

import kineffi "../engine/bindings"
import native_api "../engine/native_api"
import sdl3 "../engine/platform"
import native_compositor "../engine/renderer/compositor"
import engine_runtime "../engine/runtime"
import target "../engine/target"
import vm "../engine/vm"
import odin_runtime "base:runtime"
import "core:os"

@(export)
Kinemium_CreateHeadlessRenderer :: proc "c" (width, height: i32, mode: i32) -> ^Context {
	context = odin_runtime.default_context()
	if width < 1 || height < 1 || width > 8192 || height > 8192 {return nil}
	if mode < i32(target.Mode.Editor) || mode > i32(target.Mode.Singleplayer) {return nil}
	filament := kineffi.Kine_Filament_Create(width, height)
	if filament == nil {return nil}
	return create_owned(target.Mode(mode), filament, nil, width, height)
}

native_sdk_cpu_work :: proc "c" (user: rawptr) {
	_ = user
}

@(export)
Kinemium_RenderFrame :: proc "c" (ctx: ^Context, delta_seconds: f32) -> bool {
	context = odin_runtime.default_context()
	owned := owned_context(ctx)
	if owned == nil ||
	   owned.sdk_renderer.Filament == nil ||
	   delta_seconds < 0 ||
	   delta_seconds > 1 {return false}
	compositor := owned.sdk_renderer.Compositor
	if compositor != nil {
		if kineffi.Kine_VulkanCompositor_NeedsResize(compositor) != 0 {
			width, height: i32
			if owned.sdk_renderer.Window != nil {
				_ = sdl3.GetWindowSizeInPixels(owned.sdk_renderer.Window, &width, &height)
			}
			if width <= 0 || height <= 0 {return true}
			if !Kinemium_ResizeRenderer(ctx, width, height) {return false}
		}
		surface := kineffi.Kine_VulkanCompositor_BeginFrame(compositor)
		if surface == nil {
			if kineffi.Kine_VulkanCompositor_NeedsResize(compositor) != 0 {return true}
			native_api.SetError(
				ctx,
				string(kineffi.Kine_VulkanCompositor_GetLastError(compositor)),
			)
			return false
		}
		skia_surface := cast(^kineffi.KineSkiaSurface)surface
		kineffi.Kine_Skia_Surface_Clear(skia_surface, 20, 28, 41, 255)
		width := owned.sdk_renderer.ViewportRect[2]
		height := owned.sdk_renderer.ViewportRect[3]
		engine_runtime.Environment_Render_2D(
			&owned.environment,
			ctx.script_vm,
			skia_surface,
			width,
			height,
			delta_seconds,
		)
	}
	engine_runtime.Environment_Render_3D(&owned.environment, ctx.script_vm, delta_seconds)
	if compositor != nil {
		kineffi.Kine_Filament_Viewport_RenderFrameWithCpuWork(
			owned.sdk_renderer.Filament,
			delta_seconds,
			true,
			native_sdk_cpu_work,
			nil,
		)

		overlay_surface := kineffi.Kine_VulkanCompositor_BeginOverlay(compositor)
		if overlay_surface != nil {
			engine_runtime.Environment_Render_Overlay(
				&owned.environment,
				ctx.script_vm,
				cast(^kineffi.KineSkiaSurface)overlay_surface,
				owned.sdk_renderer.ViewportRect[2],
				owned.sdk_renderer.ViewportRect[3],
				delta_seconds,
			)
		}
	} else {
		kineffi.Kine_Filament_RenderFrame(owned.sdk_renderer.Filament, delta_seconds)
	}
	if compositor != nil && kineffi.Kine_VulkanCompositor_EndFrame(compositor) == 0 {
		if kineffi.Kine_VulkanCompositor_NeedsResize(compositor) != 0 {return true}
		native_api.SetError(ctx, string(kineffi.Kine_VulkanCompositor_GetLastError(compositor)))
		return false
	}
	native_api.ClearError(ctx)
	return true
}

@(export)
Kinemium_ResizeRenderer :: proc "c" (ctx: ^Context, width, height: i32) -> bool {
	context = odin_runtime.default_context()
	owned := owned_context(ctx)
	if owned == nil || owned.sdk_renderer.Filament == nil {return false}
	if width < 1 || height < 1 || width > 8192 || height > 8192 {return false}
	kineffi.Kine_Filament_Resize(owned.sdk_renderer.Filament, width, height)
	owned.sdk_renderer.ViewportRect = [4]i32{0, 0, width, height}
	return true
}

@(export)
Kinemium_GetRendererSize :: proc "c" (ctx: ^Context, width, height: ^i32) -> bool {
	context = odin_runtime.default_context()
	owned := owned_context(ctx)
	if owned == nil ||
	   owned.sdk_renderer.Filament == nil ||
	   width == nil ||
	   height == nil {return false}
	width^ = kineffi.Kine_Filament_GetWidth(owned.sdk_renderer.Filament)
	height^ = kineffi.Kine_Filament_GetHeight(owned.sdk_renderer.Filament)
	return true
}

@(export)
Kinemium_GetNativeRenderer :: proc "c" (ctx: ^Context) -> rawptr {
	context = odin_runtime.default_context()
	owned := owned_context(ctx)
	if owned == nil || owned.sdk_renderer.Filament == nil {return nil}
	return owned.sdk_renderer.Filament
}

@(export)
Kinemium_CreateForSDLWindow :: proc "c" (window: rawptr, width, height, mode: i32) -> ^Context {
	context = odin_runtime.default_context()
	if window == nil || width < 1 || height < 1 || width > 8192 || height > 8192 {return nil}
	if mode < i32(target.Mode.Editor) || mode > i32(target.Mode.Singleplayer) {return nil}
	use_native := !#config(KINE_ANDROID, false)
	window_id := u32(sdl3.GetWindowID(cast(^sdl3.Window)window))
	registered :=
		use_native &&
		native_compositor.register_swapchain(
			window_id,
			os.get_env("KINE_VULKAN_OFFSCREEN", context.temp_allocator) == "1",
		)
	filament := kineffi.Kine_Filament_CreateForVulkanCompositorWindow(
		cast(^sdl3.Window)window,
		width,
		height,
	)
	if registered {native_compositor.unregister_swapchain(window_id)}
	if filament == nil {return nil}
	compositor := cast(^kineffi.KineVulkanCompositor)kineffi.Kine_Filament_GetVulkanCompositor(
		filament,
	)
	if compositor == nil || kineffi.Kine_VulkanCompositor_IsReady(compositor) == 0 {
		kineffi.Kine_Filament_Destroy(filament)
		return nil
	}
	result := create_owned(target.Mode(mode), filament, cast(^sdl3.Window)window, width, height)
	owned := owned_context(result)
	if owned != nil {
		owned.sdk_renderer.Compositor = compositor
		if use_native {_ = native_compositor.attach(&owned.compositor_backend, compositor)}
	}
	return result
}

@(export)
Kinemium_ProcessSDLEvent :: proc "c" (ctx: ^Context, event: rawptr) -> bool {
	context = odin_runtime.default_context()
	owned := owned_context(ctx)
	if owned == nil || event == nil {return false}
	engine_runtime.Environment_SetEvent(
		&owned.environment,
		ctx.script_vm,
		(cast(^sdl3.Event)event)^,
	)
	return true
}
