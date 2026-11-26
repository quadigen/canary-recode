package main

import kineffi "../src/engine/bindings"
import native "../src/engine/renderer/compositor"
import "core:fmt"
import "core:os"
import "core:time"
import sdl3 "vendor:sdl3"
import vk "vendor:vulkan"

render_frame :: proc(
	filament: ^kineffi.KineFilamentContext,
	compositor: ^kineffi.KineVulkanCompositor,
) -> bool {
	base := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginFrame(compositor)
	if base == nil {
		if kineffi.Kine_VulkanCompositor_NeedsResize(compositor) != 0 {return false}
		fmt.eprintln("Vulkan acquire:", kineffi.Kine_VulkanCompositor_GetLastError(compositor))
		panic("Vulkan image acquisition failed")
	}
	kineffi.Kine_Skia_Surface_Clear(base, 32, 40, 48, 255)
	kineffi.Kine_Filament_RenderFrame(filament, 1.0 / 60.0)
	overlay := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginOverlay(compositor)
	assert(overlay != nil, "Vulkan overlay acquisition failed")
	kineffi.Kine_Skia_Surface_Flush(overlay)
	if kineffi.Kine_VulkanCompositor_EndFrame(compositor) == 0 {
		if kineffi.Kine_VulkanCompositor_NeedsResize(compositor) != 0 {return false}
		fmt.eprintln("Vulkan present:", kineffi.Kine_VulkanCompositor_GetLastError(compositor))
		panic("Vulkan presentation failed")
	}
	return true
}

main :: proc() {
	assert(sdl3.Init({.VIDEO}), "SDL init failed")
	defer sdl3.Quit()
	window := sdl3.CreateWindow(
		"Kinemium Odin WSI smoke",
		320,
		240,
		sdl3.WINDOW_VULKAN | sdl3.WINDOW_HIDDEN | sdl3.WINDOW_RESIZABLE,
	)
	assert(window != nil, "SDL window failed")
	defer sdl3.DestroyWindow(window)
	use_native := true
	window_id := u32(sdl3.GetWindowID(window))
	offscreen := os.get_env("KINE_VULKAN_OFFSCREEN", context.temp_allocator) == "1"
	if use_native {assert(native.register_swapchain(window_id, offscreen))}
	filament := kineffi.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	if use_native {native.unregister_swapchain(window_id)}
	assert(filament != nil, "Filament startup failed")
	defer kineffi.Kine_Filament_Destroy(filament)
	compositor := cast(^kineffi.KineVulkanCompositor)kineffi.Kine_Filament_GetVulkanCompositor(
		filament,
	)
	assert(compositor != nil && kineffi.Kine_VulkanCompositor_IsReady(compositor) != 0)
	assert(kineffi.Kine_VulkanCompositor_UsesOdinBackend(compositor) != 0)
	assert((kineffi.Kine_VulkanCompositor_IsOffscreen(compositor) != 0) == offscreen)
	state: native.Backend
	if use_native {
		assert(native.attach(&state, compositor), "Odin WSI attachment failed")
		fmt.println("ODIN_WSI_ENABLED", "async", state.presentation.worker != nil)
	}
	defer native.detach(&state)
	sizes := [3][2]i32{{320, 240}, {480, 320}, {640, 360}}
	for size in sizes {
		assert(sdl3.SetWindowSize(window, size[0], size[1]))
		assert(sdl3.SyncWindow(window))
		sdl3.PumpEvents()
		width, height: i32
		assert(sdl3.GetWindowSizeInPixels(window, &width, &height))
		kineffi.Kine_Filament_Resize(filament, width, height)
		assert(kineffi.Kine_VulkanCompositor_IsReady(compositor) != 0)
		assert(kineffi.Kine_VulkanCompositor_UsesOdinBackend(compositor) != 0)
		depth: rawptr
		depth_format: u32
		assert(
			kineffi.Kine_VulkanCompositor_GetDepthAttachment(compositor, &depth, &depth_format) !=
			0,
		)
		assert(depth != nil && depth_format != 0)
		started := time.tick_now()
		frames := 0
		for _ in 0 ..< 160 {
			sdl3.PumpEvents()
			assert(sdl3.GetWindowSizeInPixels(window, &width, &height))
			kineffi.Kine_Filament_Resize(filament, width, height)
			if !render_frame(filament, compositor) {
				sdl3.Delay(10)
				continue
			}
			frames += 1
			if frames == 40 {break}
		}
		assert(frames == 40, "swapchain did not stabilize")
		if os.get_env("KINE_VULKAN_GPU_TIMING", context.temp_allocator) != "0" {
			serial, total, stage_serial, base, render: u64
			assert(
				kineffi.Kine_VulkanCompositor_GetLatestQueueTiming(compositor, &serial, &total) !=
				0,
			)
			assert(
				kineffi.Kine_VulkanCompositor_GetLatestQueueStages(
					compositor,
					&stage_serial,
					&base,
					&render,
				) !=
				0,
			)
			assert(stage_serial == serial && base + render <= total && total - base - render <= 2)
			fmt.printf("QUEUE_STAGES base=%d render=%d total=%d\n", base, render, total)
			if os.get_env("KINE_VULKAN_GPU_TIMING_DETAIL", context.temp_allocator) == "1" {
				detail_serial, scene, overlay: u64
				assert(
					kineffi.Kine_VulkanCompositor_GetLatestQueueDetail(
						compositor,
						&detail_serial,
						&scene,
						&overlay,
					) !=
					0,
				)
				assert(
					detail_serial == serial &&
					scene + overlay <= render &&
					render - scene - overlay <= 2,
				)
				fmt.printf("QUEUE_DETAIL scene=%d overlay=%d\n", scene, overlay)
			}
		}
		if state.attached {
			result := native.present_drain(&state.presentation)
			assert(result == .SUCCESS || result == .SUBOPTIMAL_KHR)
		}
		fmt.printf(
			"ODIN_WSI_STAGE %dx%d frames=40 mean_ms=%.3f\n",
			width,
			height,
			time.duration_milliseconds(time.tick_since(started)) / 40,
		)
	}
	if state.attached {
		native.detach(&state)
		assert(render_frame(filament, compositor))
		assert(native.attach(&state, compositor, false))
		assert(state.presentation.worker == nil)
		assert(render_frame(filament, compositor))
	}
	for _ in 0 ..< 12 {
		base := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginFrame(compositor)
		assert(base != nil)
		kineffi.Kine_Skia_Surface_Clear(base, 255, 0, 0, 255)
		assert(kineffi.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}
	for _ in 0 ..< 12 {
		base := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginFrame(compositor)
		assert(base != nil)
		kineffi.Kine_Skia_Surface_Clear(base, 0, 255, 0, 255)
		kineffi.Kine_Filament_RenderFrame(filament, 1.0 / 60.0)
		assert(kineffi.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}
	fmt.println("ODIN_2D_AND_NO_OVERLAY_PASSED")
	assert(kineffi.Kine_VulkanCompositor_WaitForQueueIdle(compositor) != 0)
	offscreen_smoke(compositor)
	fmt.println("ODIN_WSI_SMOKE_PASSED")
}

offscreen_smoke :: proc(compositor: ^kineffi.KineVulkanCompositor) {
	info: kineffi.KineVulkanCompositorInfo
	assert(kineffi.Kine_VulkanCompositor_GetInfo(compositor, &info) != 0)
	instance := cast(vk.Instance)info.instance
	device := cast(vk.Device)info.device
	get := cast(vk.ProcGetInstanceProcAddr)sdl3.Vulkan_GetVkGetInstanceProcAddr()
	get_memory := cast(vk.ProcGetPhysicalDeviceMemoryProperties)get(
		instance,
		"vkGetPhysicalDeviceMemoryProperties",
	)
	properties: vk.PhysicalDeviceMemoryProperties
	get_memory(cast(vk.PhysicalDevice)info.physicalDevice, &properties)
	d := native.Frame_Dispatch {
		device          = info.device,
		get_device_proc = cast(rawptr)get(instance, "vkGetDeviceProcAddr"),
	}
	pool: native.Offscreen_Pool
	assert(
		native.create_offscreen_pool(&d, &properties, {16, 16}, .R8G8B8A8_UNORM, &pool) ==
		.SUCCESS,
	)
	defer assert(native.destroy_offscreen_pool(&d, &pool))
	a, ok := native.claim_offscreen(&pool.scheduler)
	assert(ok)
	b, ok2 := native.claim_offscreen(&pool.scheduler)
	assert(ok2 && a.index != b.index)
	assert(!native.destroy_offscreen_pool(&d, &pool))
	create_pool := native.device_proc(&d, "vkCreateCommandPool", vk.ProcCreateCommandPool)
	destroy_pool := native.device_proc(&d, "vkDestroyCommandPool", vk.ProcDestroyCommandPool)
	pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = info.graphicsQueueFamilyIndex,
	}
	command_pool: vk.CommandPool
	assert(create_pool(device, &pool_info, nil, &command_pool) == .SUCCESS)
	defer destroy_pool(device, command_pool, nil)
	d.command_pool = u64(command_pool)
	allocate := native.device_proc(&d, "vkAllocateCommandBuffers", vk.ProcAllocateCommandBuffers)
	cmd_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	cmd: vk.CommandBuffer
	assert(allocate(device, &cmd_info, &cmd) == .SUCCESS)
	create_buffer := native.device_proc(&d, "vkCreateBuffer", vk.ProcCreateBuffer)
	destroy_buffer := native.device_proc(&d, "vkDestroyBuffer", vk.ProcDestroyBuffer)
	free_memory := native.device_proc(&d, "vkFreeMemory", vk.ProcFreeMemory)
	buffer: vk.Buffer
	memory: vk.DeviceMemory
	defer {if buffer != 0 {destroy_buffer(device, buffer, nil)}
		if memory != 0 {free_memory(device, memory, nil)}}
	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = 16 * 16 * 4,
		usage       = {.TRANSFER_DST},
		sharingMode = .EXCLUSIVE,
	}
	assert(create_buffer(device, &buffer_info, nil, &buffer) == .SUCCESS)
	req: vk.MemoryRequirements
	native.device_proc(&d, "vkGetBufferMemoryRequirements", vk.ProcGetBufferMemoryRequirements)(
		device,
		buffer,
		&req,
	)
	index, memory_ok := native.memory_type(
		&properties,
		req.memoryTypeBits,
		{.HOST_VISIBLE, .HOST_COHERENT},
	)
	assert(memory_ok)
	mem_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = req.size,
		memoryTypeIndex = index,
	}
	assert(
		native.device_proc(&d, "vkAllocateMemory", vk.ProcAllocateMemory)(
			device,
			&mem_info,
			nil,
			&memory,
		) ==
		.SUCCESS,
	)
	assert(
		native.device_proc(&d, "vkBindBufferMemory", vk.ProcBindBufferMemory)(
			device,
			buffer,
			memory,
			0,
		) ==
		.SUCCESS,
	)
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	assert(
		native.device_proc(&d, "vkBeginCommandBuffer", vk.ProcBeginCommandBuffer)(
			cmd,
			&begin_info,
		) ==
		.SUCCESS,
	)
	source, target := &pool.targets[a.index], &pool.targets[b.index]
	range := vk.ImageSubresourceRange {
		aspectMask = {.COLOR},
		levelCount = 1,
		layerCount = 1,
	}
	barrier := vk.ImageMemoryBarrier {
		sType               = .IMAGE_MEMORY_BARRIER,
		dstAccessMask       = {.TRANSFER_WRITE},
		oldLayout           = .UNDEFINED,
		newLayout           = .TRANSFER_DST_OPTIMAL,
		srcQueueFamilyIndex = max(u32),
		dstQueueFamilyIndex = max(u32),
		image               = source.image,
		subresourceRange    = range,
	}
	native.device_proc(&d, "vkCmdPipelineBarrier", vk.ProcCmdPipelineBarrier)(
		cmd,
		{.TOP_OF_PIPE},
		{.TRANSFER},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&barrier,
	)
	color := vk.ClearColorValue {
		float32 = {1, 0, 0, 1},
	}
	native.device_proc(&d, "vkCmdClearColorImage", vk.ProcCmdClearColorImage)(
		cmd,
		source.image,
		.TRANSFER_DST_OPTIMAL,
		&color,
		1,
		&range,
	)
	assert(native.advance_offscreen(&pool.scheduler, a, .Rendering, .Ready))
	assert(native.advance_offscreen(&pool.scheduler, a, .Ready, .Copying))
	assert(
		native.record_offscreen_copy(
			&d,
			cmd,
			source,
			target,
			.TRANSFER_DST_OPTIMAL,
			.UNDEFINED,
			.TRANSFER_SRC_OPTIMAL,
		),
	)
	region := vk.BufferImageCopy {
		imageSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		imageExtent = {16, 16, 1},
	}
	native.device_proc(&d, "vkCmdCopyImageToBuffer", vk.ProcCmdCopyImageToBuffer)(
		cmd,
		target.image,
		.TRANSFER_SRC_OPTIMAL,
		buffer,
		1,
		&region,
	)
	assert(native.device_proc(&d, "vkEndCommandBuffer", vk.ProcEndCommandBuffer)(cmd) == .SUCCESS)
	fence: vk.Fence
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
	}
	assert(
		native.device_proc(&d, "vkCreateFence", vk.ProcCreateFence)(
			device,
			&fence_info,
			nil,
			&fence,
		) ==
		.SUCCESS,
	)
	defer native.device_proc(&d, "vkDestroyFence", vk.ProcDestroyFence)(device, fence, nil)
	assert(
		native.submit_callback(&d, info.graphicsQueue, cast(rawptr)cmd, 0, 0, u64(fence)) ==
		i32(vk.Result.SUCCESS),
	)
	assert(
		native.device_proc(&d, "vkWaitForFences", vk.ProcWaitForFences)(
			device,
			1,
			&fence,
			true,
			max(u64),
		) ==
		.SUCCESS,
	)
	pixels: rawptr
	assert(
		native.device_proc(&d, "vkMapMemory", vk.ProcMapMemory)(
			device,
			memory,
			0,
			16 * 16 * 4,
			{},
			&pixels,
		) ==
		.SUCCESS,
	)
	for i in 0 ..< 16 * 16 {assert((cast([^]u32)pixels)[i] == 0xff0000ff)}
	native.device_proc(&d, "vkUnmapMemory", vk.ProcUnmapMemory)(device, memory)
	assert(native.advance_offscreen(&pool.scheduler, a, .Copying, .Free))
	assert(native.advance_offscreen(&pool.scheduler, b, .Rendering, .Free))
	fmt.println("ODIN_OFFSCREEN_PIXEL_COPY_PASSED")
}
