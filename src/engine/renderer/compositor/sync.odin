package compositor

import "base:runtime"
import vk "vendor:vulkan"

create_root_callback :: proc "c" (
	d: ^Frame_Dispatch,
	family: u32,
	pool_out, fence_out: ^u64,
) -> i32 {
	context = runtime.default_context()
	if d == nil ||
	   pool_out == nil ||
	   fence_out == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	pool_out^ = 0
	fence_out^ = 0
	create := device_proc(d, "vkCreateCommandPool", vk.ProcCreateCommandPool)
	destroy := device_proc(d, "vkDestroyCommandPool", vk.ProcDestroyCommandPool)
	create_fence := device_proc(d, "vkCreateFence", vk.ProcCreateFence)
	if create == nil ||
	   destroy == nil ||
	   create_fence == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	device := cast(vk.Device)d.device
	info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = family,
	}
	pool: vk.CommandPool
	if status := create(device, &info, nil, &pool); status != .SUCCESS {return i32(status)}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
	}
	fence: vk.Fence
	if status := create_fence(device, &fence_info, nil, &fence); status != .SUCCESS {
		destroy(device, pool, nil)
		return i32(status)
	}
	pool_out^ = u64(pool)
	fence_out^ = u64(fence)
	return i32(vk.Result.SUCCESS)
}

destroy_root_callback :: proc "c" (d: ^Frame_Dispatch, pool, fence: u64) {
	context = runtime.default_context()
	if d == nil {return}
	device := cast(vk.Device)d.device
	destroy_fence := device_proc(d, "vkDestroyFence", vk.ProcDestroyFence)
	destroy_pool := device_proc(d, "vkDestroyCommandPool", vk.ProcDestroyCommandPool)
	if fence != 0 && destroy_fence != nil {destroy_fence(device, vk.Fence(fence), nil)}
	if pool != 0 && destroy_pool != nil {destroy_pool(device, vk.CommandPool(pool), nil)}
}

destroy_sync_callback :: proc "c" (d: ^Frame_Dispatch, semaphore, consumed, prefetched: u64) {
	context = runtime.default_context()
	if d == nil {return}
	device := cast(vk.Device)d.device
	destroy_sem := device_proc(d, "vkDestroySemaphore", vk.ProcDestroySemaphore)
	destroy_fence := device_proc(d, "vkDestroyFence", vk.ProcDestroyFence)
	if semaphore != 0 && destroy_sem != nil {destroy_sem(device, vk.Semaphore(semaphore), nil)}
	if consumed != 0 && destroy_fence != nil {destroy_fence(device, vk.Fence(consumed), nil)}
	if prefetched != 0 && destroy_fence != nil {destroy_fence(device, vk.Fence(prefetched), nil)}
}

create_sync_callback :: proc "c" (
	d: ^Frame_Dispatch,
	semaphore, consumed, prefetched: ^u64,
) -> i32 {
	context = runtime.default_context()
	if d == nil || semaphore == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	semaphore^ = 0
	if consumed != nil {consumed^ = 0}
	if prefetched != nil {prefetched^ = 0}
	create_sem := device_proc(d, "vkCreateSemaphore", vk.ProcCreateSemaphore)
	create_fence := device_proc(d, "vkCreateFence", vk.ProcCreateFence)
	if create_sem == nil || create_fence == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	device := cast(vk.Device)d.device
	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
	}
	sem: vk.Semaphore
	fences: [2]vk.Fence
	if status := create_sem(device, &sem_info, nil, &sem); status != .SUCCESS {return i32(status)}
	success := false
	defer if !success {destroy_sync_callback(d, u64(sem), u64(fences[0]), u64(fences[1]))}
	if consumed != nil {
		if status := create_fence(device, &fence_info, nil, &fences[0]);
		   status != .SUCCESS {return i32(status)}
	}
	if prefetched != nil {
		if status := create_fence(device, &fence_info, nil, &fences[1]);
		   status != .SUCCESS {return i32(status)}
	}
	semaphore^ = u64(sem)
	if consumed != nil {consumed^ = u64(fences[0])}
	if prefetched != nil {prefetched^ = u64(fences[1])}
	success = true
	return i32(vk.Result.SUCCESS)
}

retire_fence_callback :: proc "c" (d: ^Frame_Dispatch, fence: u64, wait: u32) -> i32 {
	context = runtime.default_context()
	if d == nil || fence == 0 {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	device := cast(vk.Device)d.device
	handle := vk.Fence(fence)
	if wait != 0 {
		proc_wait := device_proc(d, "vkWaitForFences", vk.ProcWaitForFences)
		if proc_wait == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
		return i32(proc_wait(device, 1, &handle, true, max(u64)))
	}
	status := device_proc(d, "vkGetFenceStatus", vk.ProcGetFenceStatus)
	if status == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	return i32(status(device, handle))
}
