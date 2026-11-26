package compositor

import kineffi "../../bindings"
import "base:runtime"
import vk "vendor:vulkan"

wrap_surface_callback :: proc "c" (
	skia_context, image: rawptr,
	width, height, format, usage: u32,
) -> rawptr {
	context = runtime.default_context()
	if skia_context == nil ||
	   image == nil ||
	   width == 0 ||
	   height == 0 ||
	   width > u32(max(i32)) ||
	   height > u32(max(i32)) {return nil}
	info := kineffi.KineSkiaVulkanImageInfo {
		image              = image,
		format             = format,
		imageLayout        = u32(vk.ImageLayout.COLOR_ATTACHMENT_OPTIMAL),
		imageTiling        = u32(vk.ImageTiling.OPTIMAL),
		imageUsageFlags    = usage,
		sampleCount        = 1,
		levelCount         = 1,
		currentQueueFamily = max(u32),
	}
	return kineffi.Kine_Skia_Surface_CreateVulkanRenderTarget(
		cast(^kineffi.KineSkiaVulkanContext)skia_context,
		i32(width),
		i32(height),
		&info,
	)
}

release_surface_callback :: proc "c" (surface: rawptr) {
	context = runtime.default_context()
	if surface != nil {kineffi.Kine_Skia_Surface_Destroy(cast(^kineffi.KineSkiaSurface)surface)}
}

flush_surface_callback :: proc "c" (surface: rawptr) -> i32 {
	context = runtime.default_context()
	if surface == nil {return 0}
	return kineffi.Kine_Skia_Surface_FlushVulkanLayout(
		cast(^kineffi.KineSkiaSurface)surface,
		u32(vk.ImageLayout.COLOR_ATTACHMENT_OPTIMAL),
	)
}

wait_surface_callback :: proc "c" (surface, semaphore: rawptr) -> i32 {
	context = runtime.default_context()
	if surface == nil || semaphore == nil {return 0}
	return kineffi.Kine_Skia_Surface_WaitVulkanSemaphore(
		cast(^kineffi.KineSkiaSurface)surface,
		semaphore,
	)
}
