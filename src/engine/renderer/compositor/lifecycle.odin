package compositor

import "base:runtime"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"

create_surface_callback :: proc "c" (window, instance: rawptr, output: ^u64) -> i32 {
	context = runtime.default_context()
	if window == nil ||
	   instance == nil ||
	   output == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	output^ = 0
	surface: vk.SurfaceKHR
	if !sdl.Vulkan_CreateSurface(
		cast(^sdl.Window)window,
		cast(vk.Instance)instance,
		nil,
		&surface,
	) {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	output^ = u64(surface)
	return i32(vk.Result.SUCCESS)
}

destroy_surface_callback :: proc "c" (instance: rawptr, surface: u64) {
	context = runtime.default_context()
	if instance != nil &&
	   surface !=
		   0 {sdl.Vulkan_DestroySurface(cast(vk.Instance)instance, vk.SurfaceKHR(surface), nil)}
}

destroy_device_callback :: proc "c" (d: ^Frame_Dispatch) {
	context = runtime.default_context()
	if d == nil || d.device == nil {return}
	destroy := device_proc(d, "vkDestroyDevice", vk.ProcDestroyDevice)
	if destroy != nil {destroy(cast(vk.Device)d.device, nil)}
}

destroy_instance_callback :: proc "c" (instance, get_instance_proc: rawptr) {
	context = runtime.default_context()
	if instance == nil || get_instance_proc == nil {return}
	get := cast(vk.ProcGetInstanceProcAddr)get_instance_proc
	destroy := cast(vk.ProcDestroyInstance)get(cast(vk.Instance)instance, "vkDestroyInstance")
	if destroy != nil {destroy(cast(vk.Instance)instance, nil)}
}

create_depth_callback :: proc "c" (
	d: ^Frame_Dispatch,
	instance, physical, get_instance_proc: rawptr,
	width, height: u32,
	image_out, memory_out: ^u64,
	format_out: ^u32,
) -> i32 {
	context = runtime.default_context()
	if d == nil ||
	   instance == nil ||
	   physical == nil ||
	   get_instance_proc == nil ||
	   image_out == nil ||
	   memory_out == nil ||
	   format_out == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	image_out^ = 0
	memory_out^ = 0
	format_out^ = 0
	get := cast(vk.ProcGetInstanceProcAddr)get_instance_proc
	get_format := cast(vk.ProcGetPhysicalDeviceFormatProperties)get(
		cast(vk.Instance)instance,
		"vkGetPhysicalDeviceFormatProperties",
	)
	get_memory := cast(vk.ProcGetPhysicalDeviceMemoryProperties)get(
		cast(vk.Instance)instance,
		"vkGetPhysicalDeviceMemoryProperties",
	)
	if get_format == nil || get_memory == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	properties: vk.PhysicalDeviceMemoryProperties
	get_memory(cast(vk.PhysicalDevice)physical, &properties)
	formats := [?]vk.Format{.D32_SFLOAT, .D24_UNORM_S8_UINT, .D16_UNORM}
	for format in formats {
		support: vk.FormatProperties
		get_format(cast(vk.PhysicalDevice)physical, format, &support)
		if .DEPTH_STENCIL_ATTACHMENT not_in support.optimalTilingFeatures {continue}
		target: Offscreen_Target
		result := allocate_offscreen_target(
			d,
			&properties,
			{width, height},
			format,
			&target,
			{.DEPTH_STENCIL_ATTACHMENT},
		)
		if result != .SUCCESS {return i32(result)}
		image_out^ = u64(target.image)
		memory_out^ = u64(target.memory)
		format_out^ = u32(format)
		return i32(vk.Result.SUCCESS)
	}
	return i32(vk.Result.ERROR_FORMAT_NOT_SUPPORTED)
}
