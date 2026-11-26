package compositor

import "base:runtime"
import vk "vendor:vulkan"

Offscreen_Target :: struct {
	image:  vk.Image,
	memory: vk.DeviceMemory,
	extent: vk.Extent2D,
	format: vk.Format,
}

Offscreen_Pool :: struct {
	targets:   [3]Offscreen_Target,
	scheduler: Offscreen_Scheduler,
}

memory_type :: proc(
	properties: ^vk.PhysicalDeviceMemoryProperties,
	mask: u32,
	required: vk.MemoryPropertyFlags,
) -> (
	u32,
	bool,
) {
	if properties == nil {return 0, false}
	for i in 0 ..< min(properties.memoryTypeCount, u32(len(properties.memoryTypes))) {
		if mask & (u32(1) << i) != 0 &&
		   (properties.memoryTypes[i].propertyFlags & required) == required {return i, true}
	}
	return 0, false
}

destroy_offscreen_target :: proc(d: ^Frame_Dispatch, target: ^Offscreen_Target) {
	if d == nil || target == nil {return}
	device := cast(vk.Device)d.device
	destroy := device_proc(d, "vkDestroyImage", vk.ProcDestroyImage)
	free := device_proc(d, "vkFreeMemory", vk.ProcFreeMemory)
	if destroy != nil && target.image != 0 {destroy(device, target.image, nil)}
	if free != nil && target.memory != 0 {free(device, target.memory, nil)}
	target^ = {}
}

allocate_offscreen_target :: proc(
	d: ^Frame_Dispatch,
	properties: ^vk.PhysicalDeviceMemoryProperties,
	extent: vk.Extent2D,
	format: vk.Format,
	target: ^Offscreen_Target,
	usage := vk.ImageUsageFlags{.COLOR_ATTACHMENT, .TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
) -> vk.Result {
	if d == nil ||
	   properties == nil ||
	   target == nil ||
	   target.image != 0 ||
	   extent.width == 0 ||
	   extent.height == 0 {return .ERROR_INITIALIZATION_FAILED}
	device := cast(vk.Device)d.device
	create := device_proc(d, "vkCreateImage", vk.ProcCreateImage)
	requirements := device_proc(
		d,
		"vkGetImageMemoryRequirements",
		vk.ProcGetImageMemoryRequirements,
	)
	allocate := device_proc(d, "vkAllocateMemory", vk.ProcAllocateMemory)
	bind := device_proc(d, "vkBindImageMemory", vk.ProcBindImageMemory)
	if create == nil ||
	   requirements == nil ||
	   allocate == nil ||
	   bind == nil ||
	   device_proc(d, "vkDestroyImage", vk.ProcDestroyImage) == nil ||
	   device_proc(d, "vkFreeMemory", vk.ProcFreeMemory) ==
		   nil {return .ERROR_INITIALIZATION_FAILED}
	info := vk.ImageCreateInfo {
		sType         = .IMAGE_CREATE_INFO,
		imageType     = .D2,
		format        = format,
		extent        = {extent.width, extent.height, 1},
		mipLevels     = 1,
		arrayLayers   = 1,
		samples       = {._1},
		tiling        = .OPTIMAL,
		usage         = usage,
		sharingMode   = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}
	if result := create(device, &info, nil, &target.image); result != .SUCCESS {return result}
	success := false
	defer if !success {destroy_offscreen_target(d, target)}
	req: vk.MemoryRequirements
	requirements(device, target.image, &req)
	index, ok := memory_type(properties, req.memoryTypeBits, {.DEVICE_LOCAL})
	if !ok {return .ERROR_FEATURE_NOT_PRESENT}
	mem := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = req.size,
		memoryTypeIndex = index,
	}
	if result := allocate(device, &mem, nil, &target.memory); result != .SUCCESS {return result}
	if result := bind(device, target.image, target.memory, 0); result != .SUCCESS {return result}
	target.extent = extent
	target.format = format
	success = true
	return .SUCCESS
}

create_offscreen_pool :: proc(
	d: ^Frame_Dispatch,
	properties: ^vk.PhysicalDeviceMemoryProperties,
	extent: vk.Extent2D,
	format: vk.Format,
	pool: ^Offscreen_Pool,
) -> vk.Result {
	if pool == nil {return .ERROR_INITIALIZATION_FAILED}
	for target in pool.targets {if target.image != 0 {return .ERROR_INITIALIZATION_FAILED}}
	for &target in pool.targets {
		if result := allocate_offscreen_target(d, properties, extent, format, &target);
		   result != .SUCCESS {
			for &previous in pool.targets {destroy_offscreen_target(d, &previous)}
			return result
		}
	}
	pool.scheduler = {}
	return .SUCCESS
}

destroy_offscreen_pool :: proc(d: ^Frame_Dispatch, pool: ^Offscreen_Pool) -> bool {
	if pool == nil {return false}
	for slot in pool.scheduler.slots {if slot.phase != .Free {return false}}
	for &target in pool.targets {destroy_offscreen_target(d, &target)}
	pool^ = {}
	return true
}

record_offscreen_copy :: proc(
	d: ^Frame_Dispatch,
	command: vk.CommandBuffer,
	source, destination: ^Offscreen_Target,
	source_layout, destination_layout, final_layout: vk.ImageLayout,
) -> bool {
	if d == nil ||
	   command == nil ||
	   source == nil ||
	   destination == nil ||
	   source.image == 0 ||
	   destination.image == 0 ||
	   source.image == destination.image ||
	   source.extent != destination.extent ||
	   source.format != destination.format {return false}
	if source_layout != .COLOR_ATTACHMENT_OPTIMAL &&
	   source_layout != .TRANSFER_DST_OPTIMAL {return false}
	if destination_layout != .UNDEFINED && destination_layout != .PRESENT_SRC_KHR {return false}
	if final_layout != .PRESENT_SRC_KHR && final_layout != .TRANSFER_SRC_OPTIMAL {return false}
	barrier := device_proc(d, "vkCmdPipelineBarrier", vk.ProcCmdPipelineBarrier)
	copy := device_proc(d, "vkCmdCopyImage", vk.ProcCmdCopyImage)
	if barrier == nil || copy == nil {return false}
	range := vk.ImageSubresourceRange {
		aspectMask = {.COLOR},
		levelCount = 1,
		layerCount = 1,
	}
	src_access: vk.AccessFlags =
		{.COLOR_ATTACHMENT_WRITE, .TRANSFER_READ} if source_layout == .COLOR_ATTACHMENT_OPTIMAL else {.TRANSFER_WRITE}
	src_stage: vk.PipelineStageFlags =
		{.COLOR_ATTACHMENT_OUTPUT, .TRANSFER} if source_layout == .COLOR_ATTACHMENT_OPTIMAL else {.TRANSFER}
	before := [2]vk.ImageMemoryBarrier {
		{
			sType = .IMAGE_MEMORY_BARRIER,
			srcAccessMask = src_access,
			dstAccessMask = {.TRANSFER_READ},
			oldLayout = source_layout,
			newLayout = .TRANSFER_SRC_OPTIMAL,
			srcQueueFamilyIndex = max(u32),
			dstQueueFamilyIndex = max(u32),
			image = source.image,
			subresourceRange = range,
		},
		{
			sType = .IMAGE_MEMORY_BARRIER,
			dstAccessMask = {.TRANSFER_WRITE},
			oldLayout = destination_layout,
			newLayout = .TRANSFER_DST_OPTIMAL,
			srcQueueFamilyIndex = max(u32),
			dstQueueFamilyIndex = max(u32),
			image = destination.image,
			subresourceRange = range,
		},
	}
	barrier(
		command,
		src_stage | {.TOP_OF_PIPE, .BOTTOM_OF_PIPE},
		{.TRANSFER},
		{},
		0,
		nil,
		0,
		nil,
		2,
		&before[0],
	)
	layers := vk.ImageSubresourceLayers {
		aspectMask = {.COLOR},
		layerCount = 1,
	}
	region := vk.ImageCopy {
		srcSubresource = layers,
		dstSubresource = layers,
		extent         = {source.extent.width, source.extent.height, 1},
	}
	copy(
		command,
		source.image,
		.TRANSFER_SRC_OPTIMAL,
		destination.image,
		.TRANSFER_DST_OPTIMAL,
		1,
		&region,
	)
	return_access: vk.AccessFlags =
		{.COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE} if source_layout == .COLOR_ATTACHMENT_OPTIMAL else {.TRANSFER_WRITE}
	final_access: vk.AccessFlags =
		{.TRANSFER_READ} if final_layout == .TRANSFER_SRC_OPTIMAL else {}
	after := [2]vk.ImageMemoryBarrier {
		{
			sType = .IMAGE_MEMORY_BARRIER,
			srcAccessMask = {.TRANSFER_READ},
			dstAccessMask = return_access,
			oldLayout = .TRANSFER_SRC_OPTIMAL,
			newLayout = source_layout,
			srcQueueFamilyIndex = max(u32),
			dstQueueFamilyIndex = max(u32),
			image = source.image,
			subresourceRange = range,
		},
		{
			sType = .IMAGE_MEMORY_BARRIER,
			srcAccessMask = {.TRANSFER_WRITE},
			dstAccessMask = final_access,
			oldLayout = .TRANSFER_DST_OPTIMAL,
			newLayout = final_layout,
			srcQueueFamilyIndex = max(u32),
			dstQueueFamilyIndex = max(u32),
			image = destination.image,
			subresourceRange = range,
		},
	}
	barrier(
		command,
		{.TRANSFER},
		src_stage | {.TRANSFER, .BOTTOM_OF_PIPE},
		{},
		0,
		nil,
		0,
		nil,
		2,
		&after[0],
	)
	return true
}

create_color_callback :: proc "c" (
	d: ^Frame_Dispatch,
	instance, physical, get_instance_proc: rawptr,
	width, height, format: u32,
	image_out, memory_out: ^u64,
) -> i32 {
	context = runtime.default_context()
	if d == nil ||
	   instance == nil ||
	   physical == nil ||
	   get_instance_proc == nil ||
	   image_out == nil ||
	   memory_out == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	image_out^ = 0
	memory_out^ = 0
	get := cast(vk.ProcGetInstanceProcAddr)get_instance_proc
	get_memory := cast(vk.ProcGetPhysicalDeviceMemoryProperties)get(
		cast(vk.Instance)instance,
		"vkGetPhysicalDeviceMemoryProperties",
	)
	if get_memory == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	properties: vk.PhysicalDeviceMemoryProperties
	get_memory(cast(vk.PhysicalDevice)physical, &properties)
	target: Offscreen_Target
	result := allocate_offscreen_target(
		d,
		&properties,
		{width, height},
		vk.Format(format),
		&target,
	)
	if result == .SUCCESS {
		image_out^ = u64(target.image)
		memory_out^ = u64(target.memory)
	}
	return i32(result)
}

destroy_color_callback :: proc "c" (d: ^Frame_Dispatch, image, memory: u64) {
	context = runtime.default_context()
	target := Offscreen_Target {
		image  = vk.Image(image),
		memory = vk.DeviceMemory(memory),
	}
	destroy_offscreen_target(d, &target)
}

copy_color_callback :: proc "c" (
	d: ^Frame_Dispatch,
	command: rawptr,
	source, destination: u64,
	width, height, format, destination_layout: u32,
	query: u64,
) -> i32 {
	context = runtime.default_context()
	if d == nil || command == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	reset := device_proc(d, "vkResetCommandBuffer", vk.ProcResetCommandBuffer)
	begin := device_proc(d, "vkBeginCommandBuffer", vk.ProcBeginCommandBuffer)
	end := device_proc(d, "vkEndCommandBuffer", vk.ProcEndCommandBuffer)
	stamp := device_proc(d, "vkCmdWriteTimestamp", vk.ProcCmdWriteTimestamp)
	if reset == nil ||
	   begin == nil ||
	   end == nil ||
	   (query != 0 && stamp == nil) {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	cmd := cast(vk.CommandBuffer)command
	if status := reset(cmd, {}); status != .SUCCESS {return i32(status)}
	info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if status := begin(cmd, &info); status != .SUCCESS {return i32(status)}
	src := Offscreen_Target {
		image  = vk.Image(source),
		extent = {width, height},
		format = vk.Format(format),
	}
	dst := Offscreen_Target {
		image  = vk.Image(destination),
		extent = {width, height},
		format = vk.Format(format),
	}
	if !record_offscreen_copy(
		d,
		cmd,
		&src,
		&dst,
		.COLOR_ATTACHMENT_OPTIMAL,
		vk.ImageLayout(destination_layout),
		.PRESENT_SRC_KHR,
	) {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	if query != 0 {stamp(cmd, {.BOTTOM_OF_PIPE}, vk.QueryPool(query), 1)}
	return i32(end(cmd))
}

submit_copy_callback :: proc "c" (
	d: ^Frame_Dispatch,
	graphics, copy_queue, marker, command: rawptr,
	ready, acquired, present, returned, fence: u64,
) -> i32 {
	context = runtime.default_context()
	if d == nil ||
	   graphics == nil ||
	   copy_queue == nil ||
	   graphics == copy_queue ||
	   command == nil ||
	   ready == 0 ||
	   acquired == 0 ||
	   present == 0 ||
	   returned == 0 ||
	   fence == 0 {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	submit := device_proc(d, "vkQueueSubmit", vk.ProcQueueSubmit)
	if submit == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	status := submit_callback(d, graphics, marker, 0, ready, 0)
	if status != i32(vk.Result.SUCCESS) {return status}
	waits := [2]vk.Semaphore{vk.Semaphore(ready), vk.Semaphore(acquired)}
	signals := [2]vk.Semaphore{vk.Semaphore(present), vk.Semaphore(returned)}
	stages := [2]vk.PipelineStageFlags{{.ALL_COMMANDS}, {.ALL_COMMANDS}}
	cmd := cast(vk.CommandBuffer)command
	info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 2,
		pWaitSemaphores      = &waits[0],
		pWaitDstStageMask    = &stages[0],
		commandBufferCount   = 1,
		pCommandBuffers      = &cmd,
		signalSemaphoreCount = 2,
		pSignalSemaphores    = &signals[0],
	}
	return i32(submit(cast(vk.Queue)copy_queue, 1, &info, vk.Fence(fence)))
}
