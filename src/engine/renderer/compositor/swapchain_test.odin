package compositor

import "core:testing"
import vk "vendor:vulkan"

test_caps :: proc() -> vk.SurfaceCapabilitiesKHR {
	return {
		minImageCount = 2,
		maxImageCount = 4,
		currentExtent = {max(u32), max(u32)},
		minImageExtent = {64, 64},
		maxImageExtent = {1920, 1080},
		supportedCompositeAlpha = {.OPAQUE, .PRE_MULTIPLIED},
		supportedUsageFlags = {.COLOR_ATTACHMENT, .TRANSFER_DST},
	}
}

@(test)
swapchain_selects_skia_format_and_clamps_extent :: proc(t: ^testing.T) {
	caps := test_caps()
	formats := [?]vk.SurfaceFormatKHR {
		{.R8G8B8A8_UNORM, .SRGB_NONLINEAR},
		{.B8G8R8A8_SRGB, .SRGB_NONLINEAR},
		{.B8G8R8A8_UNORM, .SRGB_NONLINEAR},
	}
	modes := [?]vk.PresentModeKHR{.FIFO, .IMMEDIATE, .MAILBOX}
	config, status := select_swapchain(caps, formats[:], modes[:], {2400, 32}, .Fast, 8)
	testing.expect(t, status == .SUCCESS)
	testing.expect(t, config.format.format == .B8G8R8A8_UNORM)
	testing.expect(t, config.extent.width == 1920 && config.extent.height == 64)
	testing.expect(t, config.images == 4 && config.mode == .MAILBOX)
	testing.expect(
		t,
		config.alpha == {.OPAQUE} && config.usage == {.COLOR_ATTACHMENT, .TRANSFER_DST},
	)
	caps.currentExtent = {800, 600}
	config, status = select_swapchain(caps, formats[:], modes[:], {2400, 32}, .Fifo, 0)
	testing.expect(
		t,
		status == .SUCCESS && config.extent.width == 800 && config.extent.height == 600,
	)
	testing.expect(t, config.images == 3 && config.mode == .FIFO)
}

@(test)
swapchain_policy_fallback_and_invalid_surface :: proc(t: ^testing.T) {
	modes := [?]vk.PresentModeKHR{.FIFO, .IMMEDIATE}
	testing.expect(t, select_present_mode(.Fast, modes[:]) == .IMMEDIATE)
	testing.expect(t, select_present_mode(.Auto, modes[:]) == .FIFO)
	testing.expect(t, select_present_mode(.Mailbox, modes[:]) == .FIFO)
	testing.expect(t, select_present_mode(.Relaxed, modes[:]) == .FIFO)
	testing.expect(t, select_present_mode(.Immediate, modes[:]) == .IMMEDIATE)
	desktop_modes := [?]vk.PresentModeKHR{.FIFO, .IMMEDIATE, .MAILBOX}
	testing.expect(t, select_present_mode(.Performance, desktop_modes[:]) == .IMMEDIATE)
	no_immediate := [?]vk.PresentModeKHR{.FIFO, .MAILBOX}
	testing.expect(t, select_present_mode(.Performance, no_immediate[:]) == .MAILBOX)
	fifo_only := [?]vk.PresentModeKHR{.FIFO}
	testing.expect(t, select_present_mode(.Performance, fifo_only[:]) == .FIFO)
	default_policy, default_valid := parse_present_policy("")
	when #config(KINE_ANDROID, false) {
		testing.expect(t, default_valid && default_policy == .Fifo)
	} else {
		testing.expect(t, default_valid && default_policy == .Performance)
	}
	policy, valid := parse_present_policy("vsync")
	testing.expect(t, valid && policy == .Fifo)
	policy, valid = parse_present_policy("invalid")
	testing.expect(t, !valid && policy == .Fifo)
	caps := test_caps()
	formats := [?]vk.SurfaceFormatKHR{{.B8G8R8A8_UNORM, .SRGB_NONLINEAR}}
	caps.currentExtent = {0, 0}
	_, status := select_swapchain(caps, formats[:], modes[:], {800, 600}, .Fast, 0)
	testing.expect(t, status == .ERROR_OUT_OF_DATE_KHR)
	caps.currentExtent = {800, 600}
	caps.supportedUsageFlags = {.TRANSFER_DST}
	_, status = select_swapchain(caps, formats[:], modes[:], {800, 600}, .Fast, 0)
	testing.expect(t, status == .ERROR_FORMAT_NOT_SUPPORTED)
	_, status = select_swapchain(caps, nil, modes[:], {800, 600}, .Fast, 0)
	testing.expect(t, status == .ERROR_FORMAT_NOT_SUPPORTED)
}
