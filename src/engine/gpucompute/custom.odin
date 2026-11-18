#+build linux, windows
package gpucompute

import vk "vendor:vulkan"

Custom_Buffer :: struct {
	id: u32,
	storage: Storage,
}
Custom_Pipeline :: struct {
	set_layout: vk.DescriptorSetLayout,
	layout: vk.PipelineLayout,
	pipeline: vk.Pipeline,
	count: u32,
}
Custom_State :: struct {
	shader: Custom_Pipeline,
	buffers: [MAX_CUSTOM_BUFFERS]Custom_Buffer,
	bindings: [MAX_CUSTOM_BINDINGS]u32,
	next_id: u32,
	total_bytes: int,
	constants: [MAX_PUSH_CONSTANT_BYTES]u8,
	command: vk.CommandBuffer,
	descriptors: vk.DescriptorPool,
	fence: vk.Fence,
	submitted: bool,
	diagnostic: [4096]u8,
}

custom_idle :: proc(device: ^Device) -> string {
	if device.custom.submitted {return "GPUCompute shader is pending; call PollShader first"}
	if device.job.submitted {return "GPUCompute math job is pending; call Poll first"}
	return ""
}

custom_free_storage :: proc(device: ^Device, storage: ^Storage) {
	d := &device.procs
	if storage.data != nil {d.UnmapMemory(device.handle, storage.memory)}
	if storage.buffer != 0 {d.DestroyBuffer(device.handle, storage.buffer, nil)}
	if storage.memory != 0 {d.FreeMemory(device.handle, storage.memory, nil)}
	storage^ = {}
}

custom_free_pipeline :: proc(device: ^Device, shader: ^Custom_Pipeline) {
	d := &device.procs
	if shader.pipeline != 0 {d.DestroyPipeline(device.handle, shader.pipeline, nil)}
	if shader.layout != 0 {d.DestroyPipelineLayout(device.handle, shader.layout, nil)}
	if shader.set_layout != 0 {d.DestroyDescriptorSetLayout(device.handle, shader.set_layout, nil)}
	shader^ = {}
}

// Called only after completion, an unsuccessful submit, or device loss.
custom_clear_job :: proc(device: ^Device) {
	c := &device.custom
	d := &device.procs
	if c.fence != 0 {d.DestroyFence(device.handle, c.fence, nil)}
	if c.command != nil {d.FreeCommandBuffers(device.handle, device.commands, 1, &c.command)}
	if c.descriptors != 0 {d.DestroyDescriptorPool(device.handle, c.descriptors, nil)}
	c.fence = 0
	c.command = nil
	c.descriptors = 0
	c.submitted = false
}

custom_close :: proc(device: ^Device) {
	c := &device.custom
	if c.submitted {
		_ = device.procs.WaitForFences(device.handle, 1, &c.fence, true, max(u64))
	}
	custom_clear_job(device)
	custom_free_pipeline(device, &c.shader)
	for &entry in c.buffers {custom_free_storage(device, &entry.storage)}
	c^ = {}
}

custom_install_shader :: proc(device: ^Device, code: []u8, count: u32) -> (err: string) {
	if len(code) < 20 || len(code) % 4 != 0 {return "invalid SPIR-V bytecode length"}
	if code[0] != 3 || code[1] != 2 || code[2] != 35 || code[3] != 7 {return "invalid SPIR-V magic"}
	if count == 0 || count > MAX_CUSTOM_BINDINGS ||
	   count > device.limits.maxPerStageDescriptorStorageBuffers ||
	   count > device.limits.maxDescriptorSetStorageBuffers {
		return "GPUCompute storage binding count exceeds device limits"
	}
	d := &device.procs
	h := device.handle
	candidate := Custom_Pipeline{count = count}
	defer {if err != "" {custom_free_pipeline(device, &candidate)}}
	bindings: [MAX_CUSTOM_BINDINGS]vk.DescriptorSetLayoutBinding
	for i in 0 ..< int(count) {
		bindings[i] = {binding = u32(i), descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1, stageFlags = {.COMPUTE}}
	}
	set_info := vk.DescriptorSetLayoutCreateInfo{
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO, bindingCount = count, pBindings = &bindings[0],
	}
	if d.CreateDescriptorSetLayout(h, &set_info, nil, &candidate.set_layout) != .SUCCESS {
		return "could not create custom compute descriptor layout"
	}
	constants := vk.PushConstantRange{stageFlags = {.COMPUTE}, size = MAX_PUSH_CONSTANT_BYTES}
	layout_info := vk.PipelineLayoutCreateInfo{
		sType = .PIPELINE_LAYOUT_CREATE_INFO, setLayoutCount = 1,
		pSetLayouts = &candidate.set_layout, pushConstantRangeCount = 1, pPushConstantRanges = &constants,
	}
	if d.CreatePipelineLayout(h, &layout_info, nil, &candidate.layout) != .SUCCESS {
		return "could not create custom compute pipeline layout"
	}
	words := make([]u32, len(code) / 4)
	defer delete(words)
	copy((cast([^]u8)raw_data(words))[:len(code)], code)
	shader_info := vk.ShaderModuleCreateInfo{
		sType = .SHADER_MODULE_CREATE_INFO, codeSize = len(code), pCode = &words[0],
	}
	module: vk.ShaderModule
	if d.CreateShaderModule(h, &shader_info, nil, &module) != .SUCCESS {return "could not load custom compute shader"}
	defer d.DestroyShaderModule(h, module, nil)
	info := vk.ComputePipelineCreateInfo{
		sType = .COMPUTE_PIPELINE_CREATE_INFO, layout = candidate.layout, basePipelineIndex = -1,
		stage = {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.COMPUTE}, module = module, pName = "main"},
	}
	if d.CreateComputePipelines(h, 0, 1, &info, nil, &candidate.pipeline) != .SUCCESS {
		return "could not create custom compute pipeline; check shader features and layout"
	}
	custom_free_pipeline(device, &device.custom.shader)
	device.custom.shader = candidate
	device.custom.bindings = {}
	device.custom.constants = {}
	return ""
}

custom_get_buffer :: proc(device: ^Device, id: u32) -> ^Custom_Buffer {
	if id == 0 {return nil}
	for &entry in device.custom.buffers {if entry.id == id {return &entry}}
	return nil
}

create_buffer :: proc(device: ^Device, size: int) -> (u32, string) {
	if reason := custom_idle(device); reason != "" {return 0, reason}
	if size < 4 || size > MAX_CUSTOM_BUFFER_BYTES || size % 4 != 0 {return 0, "buffer size must be a positive multiple of four within limits"}
	if reason := open(device); reason != "" {return 0, reason}
	c := &device.custom
	if u64(size) > u64(device.limits.maxStorageBufferRange) {return 0, "buffer exceeds Vulkan storage range"}
	if c.total_bytes > MAX_CUSTOM_TOTAL_BYTES - size {return 0, "GPUCompute persistent buffer budget exceeded"}
	if c.next_id == max(u32) {return 0, "GPUCompute buffer IDs exhausted"}
	for &entry in c.buffers {
		if entry.id != 0 {continue}
		if !create_storage(device, &entry.storage, size) {
			custom_free_storage(device, &entry.storage)
			return 0, "could not allocate persistent compute storage"
		}
		for &value in entry.storage.data {value = 0}
		c.next_id += 1
		entry.id = c.next_id
		c.total_bytes += size
		return entry.id, ""
	}
	return 0, "GPUCompute persistent buffer count exceeded"
}

write_buffer :: proc(device: ^Device, id: u32, data: []u8, offset: int) -> string {
	if reason := custom_idle(device); reason != "" {return reason}
	entry := custom_get_buffer(device, id)
	if entry == nil {return "unknown GPUCompute buffer"}
	if offset < 0 || offset > len(entry.storage.data) || len(data) > len(entry.storage.data) - offset {
		return "GPUCompute buffer write is out of bounds"
	}
	copy(entry.storage.data[offset:], data)
	return ""
}

// Borrowed mapped memory; caller must copy it before next mutation/dispatch.
read_buffer :: proc(device: ^Device, id: u32, offset, requested_size: int) -> ([]u8, string) {
	if reason := custom_idle(device); reason != "" {return nil, reason}
	entry := custom_get_buffer(device, id)
	if entry == nil {return nil, "unknown GPUCompute buffer"}
	if offset < 0 || offset > len(entry.storage.data) {return nil, "GPUCompute buffer offset is out of bounds"}
	size := requested_size
	if size == -1 {size = len(entry.storage.data) - offset}
	if size <= 0 || size > len(entry.storage.data) - offset {return nil, "GPUCompute buffer read is out of bounds or empty"}
	return entry.storage.data[offset:offset+size], ""
}

bind_buffer :: proc(device: ^Device, binding, id: u32) -> string {
	if reason := custom_idle(device); reason != "" {return reason}
	if binding >= device.custom.shader.count {return "GPUCompute binding index is outside the compiled layout"}
	if custom_get_buffer(device, id) == nil {return "unknown GPUCompute buffer"}
	device.custom.bindings[binding] = id
	return ""
}

set_push_constants :: proc(device: ^Device, data: []u8) -> string {
	if reason := custom_idle(device); reason != "" {return reason}
	if device.custom.shader.pipeline == 0 {return "compile a GPUCompute shader first"}
	if len(data) > MAX_PUSH_CONSTANT_BYTES || len(data) % 4 != 0 {return "push constants must be at most 128 bytes and four-byte aligned"}
	device.custom.constants = {}
	copy(device.custom.constants[:], data)
	return ""
}

destroy_buffer :: proc(device: ^Device, id: u32) -> string {
	if reason := custom_idle(device); reason != "" {return reason}
	entry := custom_get_buffer(device, id)
	if entry == nil {return "unknown GPUCompute buffer"}
	for &binding in device.custom.bindings {if binding == id {binding = 0}}
	device.custom.total_bytes -= len(entry.storage.data)
	custom_free_storage(device, &entry.storage)
	entry^ = {}
	return ""
}

dispatch_shader :: proc(device: ^Device, x, y, z: u32) -> (err: string) {
	if reason := custom_idle(device); reason != "" {return reason}
	c := &device.custom
	if c.shader.pipeline == 0 {return "compile a GPUCompute shader first"}
	groups := [3]u32{x, y, z}
	for value, i in groups {
		if value == 0 || value > device.limits.maxComputeWorkGroupCount[i] {return "GPUCompute workgroup count exceeds device limits"}
	}
	count := c.shader.count
	infos: [MAX_CUSTOM_BINDINGS]vk.DescriptorBufferInfo
	writes: [MAX_CUSTOM_BINDINGS]vk.WriteDescriptorSet
	for i in 0 ..< int(count) {
		entry := custom_get_buffer(device, c.bindings[i])
		if entry == nil {return "all GPUCompute storage bindings must have a buffer"}
		infos[i] = {buffer = entry.storage.buffer, range = vk.DeviceSize(len(entry.storage.data))}
	}
	d := &device.procs
	h := device.handle
	defer {if err != "" {custom_clear_job(device)}}
	pool_size := vk.DescriptorPoolSize{type = .STORAGE_BUFFER, descriptorCount = count}
	pool := vk.DescriptorPoolCreateInfo{
		sType = .DESCRIPTOR_POOL_CREATE_INFO, maxSets = 1, poolSizeCount = 1, pPoolSizes = &pool_size,
	}
	if d.CreateDescriptorPool(h, &pool, nil, &c.descriptors) != .SUCCESS {return "could not create custom compute descriptor pool"}
	set_info := vk.DescriptorSetAllocateInfo{
		sType = .DESCRIPTOR_SET_ALLOCATE_INFO, descriptorPool = c.descriptors,
		descriptorSetCount = 1, pSetLayouts = &c.shader.set_layout,
	}
	set: vk.DescriptorSet
	if d.AllocateDescriptorSets(h, &set_info, &set) != .SUCCESS {return "could not allocate custom compute descriptors"}
	for i in 0 ..< int(count) {
		writes[i] = {sType = .WRITE_DESCRIPTOR_SET, dstSet = set, dstBinding = u32(i),
			descriptorCount = 1, descriptorType = .STORAGE_BUFFER, pBufferInfo = &infos[i]}
	}
	d.UpdateDescriptorSets(h, count, &writes[0], 0, nil)
	command_info := vk.CommandBufferAllocateInfo{
		sType = .COMMAND_BUFFER_ALLOCATE_INFO, commandPool = device.commands, level = .PRIMARY, commandBufferCount = 1,
	}
	if d.AllocateCommandBuffers(h, &command_info, &c.command) != .SUCCESS {return "could not allocate custom compute commands"}
	begin := vk.CommandBufferBeginInfo{sType = .COMMAND_BUFFER_BEGIN_INFO, flags = {.ONE_TIME_SUBMIT}}
	if d.BeginCommandBuffer(c.command, &begin) != .SUCCESS {return "could not begin custom compute commands"}
	// Make previous shader writes visible to this dispatch (persistent accumulation).
	before := vk.MemoryBarrier{sType = .MEMORY_BARRIER, srcAccessMask = {.SHADER_WRITE}, dstAccessMask = {.SHADER_READ, .SHADER_WRITE}}
	d.CmdPipelineBarrier(c.command, {.COMPUTE_SHADER}, {.COMPUTE_SHADER}, {}, 1, &before, 0, nil, 0, nil)
	// Host-coherent writes before QueueSubmit are made available by submission.
	d.CmdBindPipeline(c.command, .COMPUTE, c.shader.pipeline)
	d.CmdBindDescriptorSets(c.command, .COMPUTE, c.shader.layout, 0, 1, &set, 0, nil)
	d.CmdPushConstants(c.command, c.shader.layout, {.COMPUTE}, 0, MAX_PUSH_CONSTANT_BYTES, &c.constants[0])
	d.CmdDispatch(c.command, x, y, z)
	after := vk.MemoryBarrier{sType = .MEMORY_BARRIER, srcAccessMask = {.SHADER_WRITE}, dstAccessMask = {.HOST_READ}}
	d.CmdPipelineBarrier(c.command, {.COMPUTE_SHADER}, {.HOST}, {}, 1, &after, 0, nil, 0, nil)
	if d.EndCommandBuffer(c.command) != .SUCCESS {return "could not end custom compute commands"}
	fence_info := vk.FenceCreateInfo{sType = .FENCE_CREATE_INFO}
	if d.CreateFence(h, &fence_info, nil, &c.fence) != .SUCCESS {return "could not create custom compute fence"}
	submit := vk.SubmitInfo{sType = .SUBMIT_INFO, commandBufferCount = 1, pCommandBuffers = &c.command}
	if d.QueueSubmit(device.queue, 1, &submit, c.fence) != .SUCCESS {return "could not submit custom compute job"}
	c.submitted = true
	return ""
}

poll_shader :: proc(device: ^Device) -> (bool, string) {
	c := &device.custom
	if !c.submitted {return false, ""}
	#partial switch device.procs.GetFenceStatus(device.handle, c.fence) {
	case .NOT_READY: return false, ""
	case .SUCCESS:
		custom_clear_job(device)
		return true, ""
	case:
		close(device)
		return false, "Vulkan custom compute job failed; device and buffers were reset"
	}
}
