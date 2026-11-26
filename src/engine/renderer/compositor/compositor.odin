package compositor

import kineffi "../../bindings"
import "base:runtime"
import vk "vendor:vulkan"

Backend :: struct {
	legacy:       ^kineffi.KineVulkanCompositor,
	device:       vk.Device,
	acquire_proc: vk.ProcAcquireNextImageKHR,
	presentation: Present_State,
	attached:     bool,
}

attach :: proc(
	state: ^Backend,
	legacy: ^kineffi.KineVulkanCompositor,
	allow_async := true,
) -> bool {
	if state == nil || legacy == nil || state.attached {return false}
	dispatch: kineffi.KineVulkanWsiDispatch
	if kineffi.Kine_VulkanCompositor_GetWsiDispatch(legacy, &dispatch) == 0 {return false}
	state.legacy = legacy
	state.device = cast(vk.Device)dispatch.device
	state.acquire_proc = cast(vk.ProcAcquireNextImageKHR)dispatch.acquire
	state.presentation.queue = cast(vk.Queue)dispatch.queue
	state.presentation.present_proc = cast(vk.ProcQueuePresentKHR)dispatch.present
	if state.device == nil || state.acquire_proc == nil {return false}
	asynchronous := allow_async && dispatch.dedicated_queue != 0
	if !present_start(&state.presentation, asynchronous) {
		if !asynchronous || !present_start(&state.presentation, false) {return false}
		asynchronous = false
	}
	callbacks := kineffi.KineVulkanWsiBackend {
		user         = state,
		acquire      = acquire_callback,
		present      = present_callback,
		drain        = drain_callback,
		asynchronous = u32(asynchronous),
	}
	if kineffi.Kine_VulkanCompositor_SetWsiBackend(legacy, &callbacks) == 0 {
		present_stop(&state.presentation)
		return false
	}
	state.attached = true
	return true
}

detach :: proc(state: ^Backend) {
	if state == nil || !state.attached {return}
	_ = kineffi.Kine_VulkanCompositor_SetWsiBackend(state.legacy, nil)
	present_stop(&state.presentation)
	state.attached = false
	state.legacy = nil
}

acquire_callback :: proc "c" (
	user: rawptr,
	swapchain, timeout, semaphore, fence: u64,
	image: ^u32,
) -> i32 {
	state := cast(^Backend)user
	return i32(
		state.acquire_proc(
			state.device,
			vk.SwapchainKHR(swapchain),
			timeout,
			vk.Semaphore(semaphore),
			vk.Fence(fence),
			image,
		),
	)
}

present_callback :: proc "c" (user: rawptr, swapchain, semaphore: u64, image: u32) -> i32 {
	context = runtime.default_context()
	state := cast(^Backend)user
	return i32(
		present_submit(
			&state.presentation,
			{vk.SwapchainKHR(swapchain), vk.Semaphore(semaphore), image},
		),
	)
}

drain_callback :: proc "c" (user: rawptr, wait_ns: ^u64) -> i32 {
	context = runtime.default_context()
	state := cast(^Backend)user
	return i32(present_drain(&state.presentation, wait_ns))
}
