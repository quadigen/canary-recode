package compositor

import kineffi "../../bindings"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strconv"
import vk "vendor:vulkan"

Present_Policy :: enum u32 {
	Fast,
	Auto,
	Fifo,
	Mailbox,
	Immediate,
	Relaxed,
	Performance,
}

Swapchain_Config :: struct {
	format: vk.SurfaceFormatKHR,
	extent: vk.Extent2D,
	images: u32,
	usage:  vk.ImageUsageFlags,
	alpha:  vk.CompositeAlphaFlagsKHR,
	mode:   vk.PresentModeKHR,
}

parse_present_policy :: proc(value: string) -> (Present_Policy, bool) {
	switch value {
	case "":
		when #config(KINE_ANDROID, false) {return .Fifo, true}
		return .Performance, true
	case "fast", "low-latency":
		return .Fast, true
	case "auto":
		return .Auto, true
	case "fifo", "vsync", "on":
		return .Fifo, true
	case "mailbox", "triple":
		return .Mailbox, true
	case "immediate", "off", "nosync":
		return .Immediate, true
	case "relaxed", "fifo-relaxed":
		return .Relaxed, true
	case:
		return .Fifo, false
	}
}

select_present_mode :: proc(
	policy: Present_Policy,
	modes: []vk.PresentModeKHR,
) -> vk.PresentModeKHR {
	requested := vk.PresentModeKHR.FIFO
	switch policy {
	case .Performance:
		for mode in modes {if mode == .IMMEDIATE {return .IMMEDIATE}}
		requested = .MAILBOX
	case .Fast:
		for mode in modes {if mode == .MAILBOX {return .MAILBOX}}
		requested = .IMMEDIATE
	case .Auto, .Mailbox:
		requested = .MAILBOX
	case .Immediate:
		requested = .IMMEDIATE
	case .Relaxed:
		requested = .FIFO_RELAXED
	case .Fifo:
		return .FIFO
	}
	for mode in modes {if mode == requested {return requested}}
	return .FIFO
}

select_swapchain :: proc(
	caps: vk.SurfaceCapabilitiesKHR,
	formats: []vk.SurfaceFormatKHR,
	modes: []vk.PresentModeKHR,
	requested_extent: vk.Extent2D,
	policy: Present_Policy,
	image_override: u32,
) -> (
	config: Swapchain_Config,
	result: vk.Result,
) {
	preferred := [?]vk.Format{.B8G8R8A8_UNORM, .R8G8B8A8_UNORM, .R8G8B8A8_SRGB}
	found := false
	for format in preferred {
		for candidate in formats {
			if candidate.format == format && candidate.colorSpace == .SRGB_NONLINEAR {
				config.format = candidate
				found = true
				break
			}
		}
		if found {break}
	}
	if !found {return config, .ERROR_FORMAT_NOT_SUPPORTED}

	config.extent = caps.currentExtent
	if config.extent.width == max(u32) {
		config.extent.width = clamp(
			requested_extent.width,
			caps.minImageExtent.width,
			caps.maxImageExtent.width,
		)
		config.extent.height = clamp(
			requested_extent.height,
			caps.minImageExtent.height,
			caps.maxImageExtent.height,
		)
	}
	if config.extent.width == 0 ||
	   config.extent.height == 0 {return config, .ERROR_OUT_OF_DATE_KHR}
	config.images = caps.minImageCount + 1
	if image_override >= 2 &&
	   image_override <= 8 {config.images = max(config.images, image_override)}
	if caps.maxImageCount > 0 {config.images = min(config.images, caps.maxImageCount)}

	config.usage = caps.supportedUsageFlags & {.COLOR_ATTACHMENT, .TRANSFER_DST, .TRANSFER_SRC}
	if .COLOR_ATTACHMENT not_in config.usage {return config, .ERROR_FORMAT_NOT_SUPPORTED}
	alpha_order := [?]vk.CompositeAlphaFlagKHR {
		.OPAQUE,
		.PRE_MULTIPLIED,
		.POST_MULTIPLIED,
		.INHERIT,
	}
	for alpha in alpha_order {
		if alpha in caps.supportedCompositeAlpha {
			config.alpha = {alpha}
			break
		}
	}
	if config.alpha == {} {return config, .ERROR_INITIALIZATION_FAILED}
	config.mode = select_present_mode(policy, modes)
	return config, .SUCCESS
}

register_swapchain :: proc(window_id: u32, offscreen := false) -> bool {
	mode, valid := parse_present_policy(os.get_env("KINE_VULKAN_PRESENT", context.temp_allocator))
	if !valid {fmt.eprintln("[Kine] Invalid Vulkan present mode; using FIFO")}
	image_override: u32
	images := os.get_env("KINE_VULKAN_IMAGES", context.temp_allocator)
	if len(images) > 0 {
		value, ok := strconv.parse_int(images)
		if ok && value >= 2 && value <= 8 {
			image_override = u32(value)
		} else {
			fmt.eprintln("[Kine] Invalid Vulkan image count; using surface default")
		}
	}
	backend := kineffi.KineVulkanSwapchainBackend {
		create            = create_swapchain_callback,
		destroy           = destroy_swapchain_callback,
		mode_policy       = u32(mode),
		image_override    = image_override,
		create_frame      = create_frame_callback,
		destroy_frame     = destroy_frame_callback,
		record_transition = record_transition_callback,
		submit            = submit_callback,
		wrap_surface      = wrap_surface_callback,
		next_slot         = next_slot_callback,
		create_root       = create_root_callback,
		destroy_root      = destroy_root_callback,
		create_sync       = create_sync_callback,
		destroy_sync      = destroy_sync_callback,
		create_color      = create_color_callback,
		destroy_color     = destroy_color_callback,
		copy_color        = copy_color_callback,
		offscreen         = u32(offscreen),
		release_surface   = release_surface_callback,
		flush_surface     = flush_surface_callback,
		wait_surface      = wait_surface_callback,
		retire_fence      = retire_fence_callback,
		create_depth      = create_depth_callback,
		create_surface    = create_surface_callback,
		destroy_surface   = destroy_surface_callback,
		destroy_device    = destroy_device_callback,
		destroy_instance  = destroy_instance_callback,
		select_ready      = select_ready_callback,
		submit_copy       = submit_copy_callback,
		create_provider   = create_provider_callback,
		destroy_provider  = destroy_provider_callback,
		provider_action   = provider_action_callback,
		frame_flow        = frame_flow_callback,
	}
	return kineffi.Kine_VulkanCompositor_RegisterSwapchainBackend(window_id, &backend) != 0
}

unregister_swapchain :: proc(window_id: u32) {
	_ = kineffi.Kine_VulkanCompositor_RegisterSwapchainBackend(window_id, nil)
}

create_swapchain_callback :: proc "c" (
	dispatch: ^kineffi.KineVulkanSwapchainDispatch,
	output: ^kineffi.KineVulkanSwapchainResult,
) -> i32 {
	context = runtime.default_context()
	if dispatch == nil || output == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	output^ = {}
	get_caps := cast(vk.ProcGetPhysicalDeviceSurfaceCapabilitiesKHR)dispatch.get_capabilities
	get_formats := cast(vk.ProcGetPhysicalDeviceSurfaceFormatsKHR)dispatch.get_formats
	get_modes := cast(vk.ProcGetPhysicalDeviceSurfacePresentModesKHR)dispatch.get_present_modes
	create := cast(vk.ProcCreateSwapchainKHR)dispatch.create
	if get_caps == nil || get_formats == nil || get_modes == nil || create == nil {
		return i32(vk.Result.ERROR_INITIALIZATION_FAILED)
	}
	physical := cast(vk.PhysicalDevice)dispatch.physical_device
	device := cast(vk.Device)dispatch.device
	surface := vk.SurfaceKHR(dispatch.surface)
	if physical == nil ||
	   device == nil ||
	   surface == 0 {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	caps: vk.SurfaceCapabilitiesKHR
	if status := get_caps(physical, surface, &caps); status != .SUCCESS {return i32(status)}
	formats: [256]vk.SurfaceFormatKHR
	format_count: u32
	if status := get_formats(physical, surface, &format_count, nil);
	   status != .SUCCESS {return i32(status)}
	if format_count == 0 ||
	   format_count > len(formats) {return i32(vk.Result.ERROR_FORMAT_NOT_SUPPORTED)}
	if status := get_formats(physical, surface, &format_count, &formats[0]);
	   status != .SUCCESS {return i32(status)}
	modes: [32]vk.PresentModeKHR
	mode_count: u32
	if dispatch.mode_policy >
	   u32(Present_Policy.Performance) {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	policy := Present_Policy(dispatch.mode_policy)
	if policy != .Fifo {
		if status := get_modes(physical, surface, &mode_count, nil);
		   status != .SUCCESS {return i32(status)}
		if mode_count == 0 ||
		   mode_count > len(modes) {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
		if status := get_modes(physical, surface, &mode_count, &modes[0]);
		   status != .SUCCESS {return i32(status)}
	}
	config, status := select_swapchain(
		caps,
		formats[:format_count],
		modes[:mode_count],
		{dispatch.width, dispatch.height},
		policy,
		dispatch.image_override,
	)
	if status != .SUCCESS {return i32(status)}
	info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = surface,
		minImageCount    = config.images,
		imageFormat      = config.format.format,
		imageColorSpace  = config.format.colorSpace,
		imageExtent      = config.extent,
		imageArrayLayers = 1,
		imageUsage       = config.usage,
		imageSharingMode = .EXCLUSIVE,
		preTransform     = caps.currentTransform,
		compositeAlpha   = config.alpha,
		presentMode      = config.mode,
		clipped          = true,
	}
	swapchain: vk.SwapchainKHR
	status = create(device, &info, nil, &swapchain)
	if status != .SUCCESS {return i32(status)}
	output^ = {
		swapchain        = u64(swapchain),
		width            = config.extent.width,
		height           = config.extent.height,
		format           = u32(config.format.format),
		color_space      = u32(config.format.colorSpace),
		usage            = transmute(u32)config.usage,
		present_mode     = u32(config.mode),
		requested_images = config.images,
	}
	return i32(vk.Result.SUCCESS)
}

destroy_swapchain_callback :: proc "c" (device, destroy_proc: rawptr, swapchain: u64) {
	destroy := cast(vk.ProcDestroySwapchainKHR)destroy_proc
	if destroy != nil && device != nil && swapchain != 0 {
		destroy(cast(vk.Device)device, vk.SwapchainKHR(swapchain), nil)
	}
}
