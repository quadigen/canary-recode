package compositor

import kineffi "../../bindings"
import "base:runtime"
import vk "vendor:vulkan"

Frame_Dispatch :: kineffi.KineVulkanFrameDispatch
Frame_Resources :: kineffi.KineVulkanFrameResources
Transition :: kineffi.KineVulkanTransition

device_proc :: proc(d: ^Frame_Dispatch, name: cstring, $T: typeid) -> T {
	if d == nil || d.device == nil || d.get_device_proc == nil {return nil}
	get := cast(vk.ProcGetDeviceProcAddr)d.get_device_proc
	return cast(T)get(cast(vk.Device)d.device, name)
}

destroy_frame :: proc(d: ^Frame_Dispatch, r: ^Frame_Resources) {
	if d == nil || r == nil {return}
	device := cast(vk.Device)d.device
	free := device_proc(d, "vkFreeCommandBuffers", vk.ProcFreeCommandBuffers)
	destroy_fence := device_proc(d, "vkDestroyFence", vk.ProcDestroyFence)
	destroy_query := device_proc(d, "vkDestroyQueryPool", vk.ProcDestroyQueryPool)
	buffers: [5]vk.CommandBuffer
	count: u32
	for command in r.commands {
		if command != nil {
			buffers[count] = cast(vk.CommandBuffer)command
			count += 1
		}
	}
	if free != nil && count != 0 {free(device, vk.CommandPool(d.command_pool), count, &buffers[0])}
	if destroy_fence != nil && r.fence != 0 {destroy_fence(device, vk.Fence(r.fence), nil)}
	if destroy_query != nil && r.query != 0 {destroy_query(device, vk.QueryPool(r.query), nil)}
	r^ = {}
}

destroy_frame_callback :: proc "c" (d: ^Frame_Dispatch, r: ^Frame_Resources) {
	context = runtime.default_context()
	destroy_frame(d, r)
}

create_frame_callback :: proc "c" (d: ^Frame_Dispatch, r: ^Frame_Resources) -> i32 {
	context = runtime.default_context()
	if d == nil || r == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	r^ = {}
	device := cast(vk.Device)d.device
	allocate := device_proc(d, "vkAllocateCommandBuffers", vk.ProcAllocateCommandBuffers)
	create_fence := device_proc(d, "vkCreateFence", vk.ProcCreateFence)
	create_query := device_proc(d, "vkCreateQueryPool", vk.ProcCreateQueryPool)
	begin := device_proc(d, "vkBeginCommandBuffer", vk.ProcBeginCommandBuffer)
	end := device_proc(d, "vkEndCommandBuffer", vk.ProcEndCommandBuffer)
	barrier := device_proc(d, "vkCmdPipelineBarrier", vk.ProcCmdPipelineBarrier)
	stamp := device_proc(d, "vkCmdWriteTimestamp", vk.ProcCmdWriteTimestamp)
	if allocate == nil ||
	   create_fence == nil ||
	   begin == nil ||
	   end == nil ||
	   barrier == nil ||
	   device_proc(d, "vkFreeCommandBuffers", vk.ProcFreeCommandBuffers) == nil ||
	   device_proc(d, "vkDestroyFence", vk.ProcDestroyFence) == nil {
		return i32(vk.Result.ERROR_INITIALIZATION_FAILED)
	}
	success := false
	defer if !success {destroy_frame(d, r)}
	if d.timing != 0 &&
	   create_query != nil &&
	   stamp != nil &&
	   device_proc(d, "vkDestroyQueryPool", vk.ProcDestroyQueryPool) != nil {
		info := vk.QueryPoolCreateInfo {
			sType      = .QUERY_POOL_CREATE_INFO,
			queryType  = .TIMESTAMP,
			queryCount = 4,
		}
		query: vk.QueryPool
		status := create_query(device, &info, nil, &query)
		if status == .ERROR_DEVICE_LOST {return i32(status)}
		if status == .SUCCESS {r.query = u64(query)}
	}
	detail := r.query != 0 && d.detail != 0
	completion := r.query != 0 && d.offscreen != 0
	count: u32 = 3 + u32(detail) + u32(completion)
	info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = vk.CommandPool(d.command_pool),
		level              = .PRIMARY,
		commandBufferCount = count,
	}
	commands: [5]vk.CommandBuffer
	if status := allocate(device, &info, &commands[0]); status != .SUCCESS {return i32(status)}
	for i in 0 ..< 3 {r.commands[i] = cast(rawptr)commands[i]}
	if detail {r.commands[3] = cast(rawptr)commands[3]}
	if completion {r.commands[4] = cast(rawptr)commands[3 + u32(detail)]}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
	}
	fence: vk.Fence
	if status := create_fence(device, &fence_info, nil, &fence);
	   status != .SUCCESS {return i32(status)}
	r.fence = u64(fence)
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	if status := begin(commands[1], &begin_info); status != .SUCCESS {return i32(status)}
	memory := vk.MemoryBarrier {
		sType         = .MEMORY_BARRIER,
		srcAccessMask = {.MEMORY_READ, .MEMORY_WRITE},
		dstAccessMask = {.MEMORY_READ, .MEMORY_WRITE},
	}
	barrier(commands[1], {.ALL_COMMANDS}, {.ALL_COMMANDS}, {}, 1, &memory, 0, nil, 0, nil)
	if r.query != 0 {stamp(commands[1], {.BOTTOM_OF_PIPE}, vk.QueryPool(r.query), 2)}
	if status := end(commands[1]); status != .SUCCESS {return i32(status)}
	if detail {
		if status := begin(commands[3], &begin_info); status != .SUCCESS {return i32(status)}
		stamp(commands[3], {.BOTTOM_OF_PIPE}, vk.QueryPool(r.query), 3)
		if status := end(commands[3]); status != .SUCCESS {return i32(status)}
	}
	if completion {
		command := cast(vk.CommandBuffer)r.commands[4]
		if status := begin(command, &begin_info); status != .SUCCESS {return i32(status)}
		stamp(command, {.BOTTOM_OF_PIPE}, vk.QueryPool(r.query), 1)
		if status := end(command); status != .SUCCESS {return i32(status)}
	}
	success = true
	return i32(vk.Result.SUCCESS)
}

transition_scope :: proc(
	old_layout, new_layout: vk.ImageLayout,
) -> (
	src, dst: vk.PipelineStageFlags,
	read, write: vk.AccessFlags,
) {
	src = {.COLOR_ATTACHMENT_OUTPUT}
	dst = {.BOTTOM_OF_PIPE}
	#partial switch old_layout {
	case .UNDEFINED:
		src = {.TOP_OF_PIPE}
	case .COLOR_ATTACHMENT_OPTIMAL:
		src = {.COLOR_ATTACHMENT_OUTPUT, .TRANSFER}
		read = {.COLOR_ATTACHMENT_WRITE, .TRANSFER_READ}
	case .PRESENT_SRC_KHR:
		src = {.BOTTOM_OF_PIPE}
	case:
	}
	if new_layout == .COLOR_ATTACHMENT_OPTIMAL {
		dst = {.COLOR_ATTACHMENT_OUTPUT}
		write = {.COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE}
	}
	return
}

record_transition_callback :: proc "c" (d: ^Frame_Dispatch, t: ^Transition) -> i32 {
	context = runtime.default_context()
	if d == nil || t == nil || t.command == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	reset := device_proc(d, "vkResetCommandBuffer", vk.ProcResetCommandBuffer)
	begin := device_proc(d, "vkBeginCommandBuffer", vk.ProcBeginCommandBuffer)
	end := device_proc(d, "vkEndCommandBuffer", vk.ProcEndCommandBuffer)
	barrier := device_proc(d, "vkCmdPipelineBarrier", vk.ProcCmdPipelineBarrier)
	stamp := device_proc(d, "vkCmdWriteTimestamp", vk.ProcCmdWriteTimestamp)
	reset_query := device_proc(d, "vkCmdResetQueryPool", vk.ProcCmdResetQueryPool)
	if reset == nil ||
	   begin == nil ||
	   end == nil ||
	   barrier == nil ||
	   (t.query != 0 &&
			   (stamp == nil ||
					   reset_query == nil)) {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	command := cast(vk.CommandBuffer)t.command
	if status := reset(command, {}); status != .SUCCESS {return i32(status)}
	info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	if t.reusable == 0 {info.flags = {.ONE_TIME_SUBMIT}}
	if status := begin(command, &info); status != .SUCCESS {return i32(status)}
	old_layout, new_layout := vk.ImageLayout(t.old_layout), vk.ImageLayout(t.new_layout)
	src, dst, read, write := transition_scope(old_layout, new_layout)
	if old_layout != new_layout {
		image := vk.ImageMemoryBarrier {
			sType = .IMAGE_MEMORY_BARRIER,
			oldLayout = old_layout,
			newLayout = new_layout,
			srcAccessMask = read,
			dstAccessMask = write,
			srcQueueFamilyIndex = max(u32),
			dstQueueFamilyIndex = max(u32),
			image = vk.Image(t.image),
			subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
		}
		barrier(command, src, dst, {}, 0, nil, 0, nil, 1, &image)
	}
	if t.query != 0 {
		query := vk.QueryPool(t.query)
		if new_layout == .PRESENT_SRC_KHR {
			stamp(command, {.BOTTOM_OF_PIPE}, query, 1)
		} else {
			reset_query(command, query, 0, 4)
			stamp(command, {.BOTTOM_OF_PIPE}, query, 0)
		}
	}
	return i32(end(command))
}

submit_callback :: proc "c" (
	d: ^Frame_Dispatch,
	queue, command: rawptr,
	wait, signal, fence: u64,
) -> i32 {
	context = runtime.default_context()
	submit := device_proc(d, "vkQueueSubmit", vk.ProcQueueSubmit)
	if submit == nil || queue == nil {return i32(vk.Result.ERROR_INITIALIZATION_FAILED)}
	cmd := cast(vk.CommandBuffer)command
	wait_sem, signal_sem := vk.Semaphore(wait), vk.Semaphore(signal)
	stage := vk.PipelineStageFlags{.ALL_COMMANDS}
	info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
	}
	if command != nil {info.commandBufferCount = 1; info.pCommandBuffers = &cmd}
	if wait !=
	   0 {info.waitSemaphoreCount = 1; info.pWaitSemaphores = &wait_sem; info.pWaitDstStageMask = &stage}
	if signal != 0 {info.signalSemaphoreCount = 1; info.pSignalSemaphores = &signal_sem}
	return i32(submit(cast(vk.Queue)queue, 1, &info, vk.Fence(fence)))
}
