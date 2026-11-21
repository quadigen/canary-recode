#+build linux, windows
package gpucompute

import vk "vendor:vulkan"

Custom_Buffer :: struct {
	id:      u32,
	storage: Storage,
	history: Task_Access_History,
}
Custom_Pipeline :: struct {
	set_layout:         vk.DescriptorSetLayout,
	layout:             vk.PipelineLayout,
	pipeline:           vk.Pipeline,
	count:              u32,
	kinds:              Binding_Layout,
	image_requirements: Image_Requirements,
	readonly:           [MAX_CUSTOM_BINDINGS]bool,
}
Custom_Pipeline_Entry :: struct {
	id:        u32,
	shader:    Custom_Pipeline,
	bindings:  [MAX_CUSTOM_BINDINGS]u32,
	constants: [MAX_PUSH_CONSTANT_BYTES]u8,
}
Custom_State :: struct {
	shader:             Custom_Pipeline,
	legacy:             Custom_Pipeline_Entry,
	pipelines:          [MAX_CUSTOM_PIPELINES]Custom_Pipeline_Entry,
	active_pipeline:    u32,
	recording:          bool,
	parallel_recording: bool,
	task_resources:     Task_Resources,
	batch_pools:        [MAX_BATCH_DISPATCHES]vk.DescriptorPool,
	batch_count:        u32,
	buffers:            [MAX_CUSTOM_BUFFERS]Custom_Buffer,
	textures:           [MAX_CUSTOM_TEXTURES]Custom_Texture,
	bindings:           [MAX_CUSTOM_BINDINGS]u32,
	next_id:            u32,
	total_bytes:        int,
	constants:          [MAX_PUSH_CONSTANT_BYTES]u8,
	command:            vk.CommandBuffer,
	descriptors:        vk.DescriptorPool,
	fence:              vk.Fence,
	submitted:          bool,
	diagnostic:         [4096]u8,
}

custom_bind_idle :: proc(device: ^Device) -> string {
	if device.custom.submitted {return "GPUCompute shader is pending; call PollShader first"}
	if device.job.submitted {return "GPUCompute math job is pending; call Poll first"}
	return ""
}

custom_idle :: proc(device: ^Device) -> string {
	if device.custom.recording {return "GPUCompute commands are recording; submit or cancel first"}
	if device.parallel.count !=
	   0 {return "parallel GPUCompute tasks are pending; poll their task IDs first"}
	return custom_bind_idle(device)
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


custom_clear_job :: proc(device: ^Device) {
	c := &device.custom
	d := &device.procs
	if c.fence != 0 {d.DestroyFence(device.handle, c.fence, nil)}
	if c.command != nil {d.FreeCommandBuffers(device.handle, device.commands, 1, &c.command)}
	if c.descriptors != 0 {d.DestroyDescriptorPool(device.handle, c.descriptors, nil)}
	c.fence = 0
	c.command = nil
	c.descriptors = 0
	for pool in c.batch_pools[:c.batch_count] {if pool != 0 {d.DestroyDescriptorPool(device.handle, pool, nil)}}
	c.batch_pools = {}
	c.batch_count = 0
	c.recording = false
	c.parallel_recording = false
	c.task_resources = {}
	c.submitted = false
}

custom_close :: proc(device: ^Device) {
	c := &device.custom
	if c.submitted {
		_ = device.procs.WaitForFences(device.handle, 1, &c.fence, true, max(u64))
	}
	custom_clear_job(device)
	custom_free_pipeline(device, &c.legacy.shader)
	for &entry in c.pipelines {custom_free_pipeline(device, &entry.shader)}
	for &entry in c.buffers {custom_free_storage(device, &entry.storage)}
	for &entry in c.textures {texture_free(device, &entry)}
	c^ = {}
}

custom_install_shader :: proc(
	device: ^Device,
	code: []u8,
	count: u32,
	kinds: Binding_Layout,
	output: ^Custom_Pipeline = nil,
	image_requirements: Image_Requirements = {},
	readonly: [MAX_CUSTOM_BINDINGS]bool = {},
) -> (
	err: string,
) {
	if len(code) < 20 || len(code) % 4 != 0 {return "invalid SPIR-V bytecode length"}
	if code[0] != 3 ||
	   code[1] != 2 ||
	   code[2] != 35 ||
	   code[3] != 7 {return "invalid SPIR-V magic"}
	if count == 0 || count > MAX_CUSTOM_BINDINGS {return "invalid GPUCompute binding count"}
	counts: [4]u32
	for i in 0 ..< int(count) {counts[int(kinds[i])] += 1}
	l := device.limits
	if counts[0] > min(l.maxPerStageDescriptorStorageBuffers, l.maxDescriptorSetStorageBuffers) ||
	   counts[1] > min(l.maxPerStageDescriptorUniformBuffers, l.maxDescriptorSetUniformBuffers) ||
	   counts[2] >
		   min(
			   l.maxPerStageDescriptorSampledImages,
			   l.maxDescriptorSetSampledImages,
			   l.maxPerStageDescriptorSamplers,
			   l.maxDescriptorSetSamplers,
		   ) ||
	   counts[3] > min(l.maxPerStageDescriptorStorageImages, l.maxDescriptorSetStorageImages) ||
	   count > l.maxPerStageResources {return "GPUCompute descriptor layout exceeds device limits"}
	d := &device.procs
	h := device.handle
	candidate := Custom_Pipeline {
		count              = count,
		kinds              = kinds,
		image_requirements = image_requirements,
		readonly           = readonly,
	}
	defer {if err != "" {custom_free_pipeline(device, &candidate)}}
	bindings: [MAX_CUSTOM_BINDINGS]vk.DescriptorSetLayoutBinding
	for i in 0 ..< int(count) {
		bindings[i] = {
			binding         = u32(i),
			descriptorType  = binding_type(kinds[i]),
			descriptorCount = 1,
			stageFlags      = {.COMPUTE},
		}
	}
	set_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = count,
		pBindings    = &bindings[0],
	}
	if d.CreateDescriptorSetLayout(h, &set_info, nil, &candidate.set_layout) != .SUCCESS {
		return "could not create custom compute descriptor layout"
	}
	constants := vk.PushConstantRange {
		stageFlags = {.COMPUTE},
		size       = MAX_PUSH_CONSTANT_BYTES,
	}
	layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &candidate.set_layout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &constants,
	}
	if d.CreatePipelineLayout(h, &layout_info, nil, &candidate.layout) != .SUCCESS {
		return "could not create custom compute pipeline layout"
	}
	words := make([]u32, len(code) / 4)
	defer delete(words)
	copy((cast([^]u8)raw_data(words))[:len(code)], code)
	shader_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = &words[0],
	}
	module: vk.ShaderModule
	if d.CreateShaderModule(h, &shader_info, nil, &module) !=
	   .SUCCESS {return "could not load custom compute shader"}
	defer d.DestroyShaderModule(h, module, nil)
	info := vk.ComputePipelineCreateInfo {
		sType = .COMPUTE_PIPELINE_CREATE_INFO,
		layout = candidate.layout,
		basePipelineIndex = -1,
		stage = {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.COMPUTE},
			module = module,
			pName = "main",
		},
	}
	if d.CreateComputePipelines(h, 0, 1, &info, nil, &candidate.pipeline) != .SUCCESS {
		return "could not create custom compute pipeline; check shader features and layout"
	}
	if output != nil {
		output^ = candidate
		return ""
	}
	c := &device.custom
	pipeline_save_state(c)
	custom_free_pipeline(device, &c.legacy.shader)
	c.legacy = {
		shader = candidate,
	}
	c.active_pipeline = 0
	c.shader = candidate
	c.bindings = {}
	c.constants = {}
	return ""
}

custom_get_buffer :: proc(device: ^Device, id: u32) -> ^Custom_Buffer {
	if id == 0 {return nil}
	for &entry in device.custom.buffers {if entry.id == id {return &entry}}
	return nil
}

create_buffer :: proc(device: ^Device, size: int) -> (u32, string) {
	if reason := parallel_cpu_idle(device); reason != "" {return 0, reason}
	if size < 4 ||
	   size > MAX_CUSTOM_BUFFER_BYTES ||
	   size % 4 != 0 {return 0, "buffer size must be a positive multiple of four within limits"}
	if reason := open(device); reason != "" {return 0, reason}
	c := &device.custom
	if u64(size) >
	   u64(device.limits.maxStorageBufferRange) {return 0, "buffer exceeds Vulkan storage range"}
	if c.total_bytes >
	   MAX_CUSTOM_TOTAL_BYTES - size {return 0, "GPUCompute persistent buffer budget exceeded"}
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
	if reason := parallel_cpu_idle(device); reason != "" {return reason}
	entry := custom_get_buffer(device, id)
	if task_resource_busy(device, id) {return "GPUCompute resource is in use by a task"}
	if entry == nil {return "unknown GPUCompute buffer"}
	if offset < 0 ||
	   offset > len(entry.storage.data) ||
	   len(data) > len(entry.storage.data) - offset {
		return "GPUCompute buffer write is out of bounds"
	}
	copy(entry.storage.data[offset:], data)
	return ""
}


read_buffer :: proc(device: ^Device, id: u32, offset, requested_size: int) -> ([]u8, string) {
	if reason := parallel_cpu_idle(device); reason != "" {return nil, reason}
	entry := custom_get_buffer(device, id)
	if task_resource_busy(device, id) {return nil, "GPUCompute resource is in use by a task"}
	if entry == nil {return nil, "unknown GPUCompute buffer"}
	if offset < 0 ||
	   offset > len(entry.storage.data) {return nil, "GPUCompute buffer offset is out of bounds"}
	size := requested_size
	if size == -1 {size = len(entry.storage.data) - offset}
	if size <= 0 ||
	   size >
		   len(entry.storage.data) -
			   offset {return nil, "GPUCompute buffer read is out of bounds or empty"}
	return entry.storage.data[offset:offset + size], ""
}

bind_buffer :: proc(device: ^Device, binding, id: u32) -> string {
	if reason := custom_bind_idle(device); reason != "" {return reason}
	if binding >=
	   device.custom.shader.count {return "GPUCompute binding index is outside the compiled layout"}
	kind := device.custom.shader.kinds[binding]
	if kind != .StorageBuffer &&
	   kind != .UniformBuffer {return "GPUCompute binding requires a texture"}
	entry := custom_get_buffer(device, id)
	if entry == nil {return "unknown GPUCompute buffer"}
	if kind == .UniformBuffer &&
	   len(entry.storage.data) >
		   int(device.limits.maxUniformBufferRange) {return "GPUCompute uniform range exceeded"}
	device.custom.bindings[binding] = id
	return ""
}

set_push_constants :: proc(device: ^Device, data: []u8) -> string {
	if reason := custom_bind_idle(device); reason != "" {return reason}
	if device.custom.shader.pipeline == 0 {return "compile a GPUCompute shader first"}
	if len(data) > MAX_PUSH_CONSTANT_BYTES ||
	   len(data) % 4 != 0 {return "push constants must be at most 128 bytes and four-byte aligned"}
	device.custom.constants = {}
	copy(device.custom.constants[:], data)
	return ""
}

destroy_buffer :: proc(device: ^Device, id: u32) -> string {
	if reason := parallel_cpu_idle(device); reason != "" {return reason}
	entry := custom_get_buffer(device, id)
	if task_resource_busy(device, id) {return "GPUCompute resource is in use by a task"}
	if entry == nil {return "unknown GPUCompute buffer"}
	for &binding, i in device.custom.bindings {if binding == id && (device.custom.shader.kinds[i] == .StorageBuffer || device.custom.shader.kinds[i] == .UniformBuffer) {binding = 0}}
	for &pipeline in device.custom.pipelines {pipeline_clear_binding(&pipeline, id, false)}
	pipeline_clear_binding(&device.custom.legacy, id, false)
	device.custom.total_bytes -= len(entry.storage.data)
	custom_free_storage(device, &entry.storage)
	entry^ = {}
	return ""
}

dispatch_shader :: proc(device: ^Device, x, y, z: u32) -> (err: string) {
	if reason := custom_bind_idle(device); reason != "" {return reason}
	c := &device.custom
	if device.parallel.count != 0 &&
	   !c.parallel_recording {return "use SubmitTask while parallel jobs are pending"}
	if c.shader.pipeline == 0 {return "compile a GPUCompute shader first"}
	groups := [3]u32{x, y, z}
	for value, i in groups {
		if value == 0 ||
		   value >
			   device.limits.maxComputeWorkGroupCount[i] {return "GPUCompute workgroup count exceeds device limits"}
	}
	if c.recording &&
	   c.batch_count >= MAX_BATCH_DISPATCHES {return "GPUCompute command batch limit exceeded"}
	count := c.shader.count
	infos: [MAX_CUSTOM_BINDINGS]vk.DescriptorBufferInfo
	images: [MAX_CUSTOM_BINDINGS]vk.DescriptorImageInfo
	writes: [MAX_CUSTOM_BINDINGS]vk.WriteDescriptorSet
	counts: [4]u32
	for i in 0 ..< int(count) {
		kind := c.shader.kinds[i]
		counts[int(kind)] += 1
		if kind == .StorageBuffer || kind == .UniformBuffer {
			entry := custom_get_buffer(device, c.bindings[i])
			if entry == nil {return "all GPUCompute buffer bindings must be bound"}
			infos[i] = {
				buffer = entry.storage.buffer,
				range  = vk.DeviceSize(len(entry.storage.data)),
			}
		} else {
			entry := texture_find(device, c.bindings[i])
			if entry == nil {return "all GPUCompute texture bindings must be bound"}
			images[i] = {
				imageView   = entry.view,
				imageLayout = entry.layout,
			}
			if kind == .SampledTexture {images[i].sampler = entry.sampler}
		}
	}
	d := &device.procs
	h := device.handle
	pool_handle: vk.DescriptorPool
	defer {if pool_handle != 0 {d.DestroyDescriptorPool(h, pool_handle, nil)}}
	defer {if err != "" && !c.recording {custom_clear_job(device)}}
	pool_sizes: [4]vk.DescriptorPoolSize
	n: u32
	for amount, i in counts {
		if amount == 0 {continue}
		pool_sizes[n] = {
			type            = binding_type(Binding_Kind(i)),
			descriptorCount = amount,
		}
		n += 1
	}
	pool := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = 1,
		poolSizeCount = n,
		pPoolSizes    = &pool_sizes[0],
	}
	if d.CreateDescriptorPool(h, &pool, nil, &pool_handle) !=
	   .SUCCESS {return "could not create custom compute descriptor pool"}
	set_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = pool_handle,
		descriptorSetCount = 1,
		pSetLayouts        = &c.shader.set_layout,
	}
	set: vk.DescriptorSet
	if d.AllocateDescriptorSets(h, &set_info, &set) !=
	   .SUCCESS {return "could not allocate custom compute descriptors"}
	for i in 0 ..< int(count) {
		writes[i] = {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = set,
			dstBinding      = u32(i),
			descriptorCount = 1,
			descriptorType  = binding_type(c.shader.kinds[i]),
		}
		if c.shader.kinds[i] == .StorageBuffer ||
		   c.shader.kinds[i] ==
			   .UniformBuffer {writes[i].pBufferInfo = &infos[i]} else {writes[i].pImageInfo = &images[i]}
	}
	d.UpdateDescriptorSets(h, count, &writes[0], 0, nil)
	if !c.recording {
		if reason := command_begin(device); reason != "" {return reason}
	}
	if c.recording {
		c.batch_pools[c.batch_count] = pool_handle
		c.batch_count += 1
	} else {
		c.descriptors = pool_handle
	}
	pool_handle = 0
	if c.parallel_recording {
		for i in 0 ..< int(count) {
			kind := c.shader.kinds[i]
			task_add_resource(
				&c.task_resources,
				c.bindings[i],
				(kind == .StorageBuffer || kind == .StorageTexture) && !c.shader.readonly[i],
			)
		}
	}

	before := vk.MemoryBarrier {
		sType         = .MEMORY_BARRIER,
		srcAccessMask = {.SHADER_WRITE},
		dstAccessMask = {.SHADER_READ, .SHADER_WRITE},
	}
	d.CmdPipelineBarrier(
		c.command,
		{.COMPUTE_SHADER},
		{.COMPUTE_SHADER},
		{},
		1,
		&before,
		0,
		nil,
		0,
		nil,
	)

	d.CmdBindPipeline(c.command, .COMPUTE, c.shader.pipeline)
	d.CmdBindDescriptorSets(c.command, .COMPUTE, c.shader.layout, 0, 1, &set, 0, nil)
	d.CmdPushConstants(
		c.command,
		c.shader.layout,
		{.COMPUTE},
		0,
		MAX_PUSH_CONSTANT_BYTES,
		&c.constants[0],
	)
	d.CmdDispatch(c.command, x, y, z)
	if c.recording {return ""}
	return command_submit(device)
}

poll_shader :: proc(device: ^Device) -> (bool, string) {
	c := &device.custom
	if !c.submitted {return false, ""}
	#partial switch device.procs.GetFenceStatus(device.handle, c.fence) {
	case .NOT_READY:
		return false, ""
	case .SUCCESS:
		custom_clear_job(device)
		return true, ""
	case:
		close(device)
		return false, "Vulkan custom compute job failed; device and buffers were reset"
	}
}


binding_type :: proc(kind: Binding_Kind) -> vk.DescriptorType {
	switch kind {
	case .StorageBuffer:
		return .STORAGE_BUFFER
	case .UniformBuffer:
		return .UNIFORM_BUFFER
	case .SampledTexture:
		return .COMBINED_IMAGE_SAMPLER
	case .StorageTexture:
		return .STORAGE_IMAGE
	}
	return .STORAGE_BUFFER
}

unbind :: proc(device: ^Device, binding: u32) -> string {
	if reason := custom_bind_idle(device); reason != "" {return reason}
	if binding >=
	   device.custom.shader.count {return "GPUCompute binding index is outside the compiled layout"}
	device.custom.bindings[binding] = 0
	return ""
}


pipeline_find :: proc(c: ^Custom_State, id: u32) -> ^Custom_Pipeline_Entry {
	if id == 0 {return &c.legacy}
	for &p in c.pipelines {if p.id == id {return &p}}
	return nil
}

pipeline_save_state :: proc(c: ^Custom_State) {
	if p := pipeline_find(c, c.active_pipeline); p != nil {
		p.bindings = c.bindings
		p.constants = c.constants
	}
}

pipeline_clear_binding :: proc(p: ^Custom_Pipeline_Entry, id: u32, texture: bool) {
	for &binding, i in p.bindings {
		kind := p.shader.kinds[i]
		if binding == id &&
		   texture == (kind == .SampledTexture || kind == .StorageTexture) {binding = 0}
	}
}

use_shader_pipeline :: proc(device: ^Device, id: u32) -> string {
	if reason := custom_bind_idle(device); reason != "" {return reason}
	c := &device.custom
	p := pipeline_find(c, id)
	if p == nil || p.shader.pipeline == 0 {return "unknown GPUCompute pipeline"}
	if c.active_pipeline == id {return ""}
	pipeline_save_state(c)
	c.active_pipeline, c.shader, c.bindings, c.constants = id, p.shader, p.bindings, p.constants
	return ""
}

destroy_shader_pipeline :: proc(device: ^Device, id: u32) -> string {
	if reason := custom_idle(device); reason != "" {return reason}
	if id == 0 {return "the legacy shader is replaced by CompileShader"}
	c := &device.custom
	p := pipeline_find(c, id)
	if p == nil {return "unknown GPUCompute pipeline"}
	if c.active_pipeline == id {
		c.active_pipeline, c.shader, c.bindings, c.constants =
			0, c.legacy.shader, c.legacy.bindings, c.legacy.constants
	}
	custom_free_pipeline(device, &p.shader)
	p^ = {}
	return ""
}

command_begin :: proc(device: ^Device) -> string {
	c := &device.custom
	d := &device.procs
	ci := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = device.commands,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	if d.AllocateCommandBuffers(device.handle, &ci, &c.command) !=
	   .SUCCESS {return "could not allocate compute commands"}
	begin := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if d.BeginCommandBuffer(c.command, &begin) !=
	   .SUCCESS {return "could not begin compute commands"}
	return ""
}

command_submit :: proc(device: ^Device) -> string {
	c := &device.custom
	d := &device.procs
	h := device.handle
	after := vk.MemoryBarrier {
		sType         = .MEMORY_BARRIER,
		srcAccessMask = {.SHADER_WRITE},
		dstAccessMask = {.HOST_READ},
	}
	d.CmdPipelineBarrier(c.command, {.COMPUTE_SHADER}, {.HOST}, {}, 1, &after, 0, nil, 0, nil)
	if d.EndCommandBuffer(c.command) != .SUCCESS {return "could not end compute commands"}
	fi := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
	}
	if d.CreateFence(h, &fi, nil, &c.fence) != .SUCCESS {return "could not create compute fence"}
	submit := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &c.command,
	}
	if d.QueueSubmit(device.queue, 1, &submit, c.fence) !=
	   .SUCCESS {return "could not submit compute commands"}
	c.recording = false
	c.submitted = true
	return ""
}

begin_commands :: proc(device: ^Device) -> string {
	if reason := custom_idle(device); reason != "" {return reason}
	if reason := open(device); reason != "" {return reason}
	if reason := command_begin(device); reason != "" {custom_clear_job(device); return reason}
	device.custom.recording = true
	return ""
}

submit_commands :: proc(device: ^Device) -> string {
	if !device.custom.recording ||
	   device.custom.parallel_recording {return "no legacy GPUCompute command batch; use SubmitTaskBatch for tasks"}
	if device.custom.batch_count == 0 {return "empty GPUCompute command batch"}
	if reason := command_submit(device); reason != "" {custom_clear_job(device); return reason}
	return ""
}

cancel_commands :: proc(device: ^Device) -> string {
	if !device.custom.recording {return "no GPUCompute command batch"}
	custom_clear_job(device)
	return ""
}

command_barrier :: proc(device: ^Device) -> string {
	if !device.custom.recording {return "no GPUCompute command batch"}
	barrier := vk.MemoryBarrier {
		sType         = .MEMORY_BARRIER,
		srcAccessMask = {.SHADER_WRITE},
		dstAccessMask = {.SHADER_READ, .SHADER_WRITE},
	}
	device.procs.CmdPipelineBarrier(
		device.custom.command,
		{.COMPUTE_SHADER},
		{.COMPUTE_SHADER},
		{},
		1,
		&barrier,
		0,
		nil,
		0,
		nil,
	)
	return ""
}


buffer_transfer :: proc(
	device: ^Device,
	source, destination: u32,
	requested_size, source_offset, destination_offset: int,
	fill: bool,
	value: u32,
) -> string {
	if reason := custom_idle(device); reason != "" {return reason}
	dst := custom_get_buffer(device, destination)
	if dst == nil {return "unknown destination GPUCompute buffer"}
	size := requested_size
	if size == -1 {size = len(dst.storage.data) - destination_offset}
	if size <= 0 ||
	   size % 4 != 0 ||
	   destination_offset < 0 ||
	   destination_offset % 4 != 0 ||
	   destination_offset > len(dst.storage.data) ||
	   size >
		   len(dst.storage.data) -
			   destination_offset {return "invalid GPU buffer transfer destination range"}
	src: ^Custom_Buffer
	if !fill {
		src = custom_get_buffer(device, source)
		if src == nil {return "unknown source GPUCompute buffer"}
		if source_offset < 0 ||
		   source_offset % 4 != 0 ||
		   source_offset > len(src.storage.data) ||
		   size >
			   len(src.storage.data) -
				   source_offset {return "invalid GPU buffer transfer source range"}
		if source == destination &&
		   source_offset < destination_offset + size &&
		   destination_offset < source_offset + size {return "GPU buffer copy ranges overlap"}
	}
	c := &device.custom
	d := &device.procs
	defer custom_clear_job(device)
	if reason := command_begin(device); reason != "" {return reason}
	before := vk.MemoryBarrier {
		sType         = .MEMORY_BARRIER,
		srcAccessMask = {.SHADER_WRITE, .TRANSFER_WRITE},
		dstAccessMask = {.TRANSFER_READ, .TRANSFER_WRITE},
	}
	d.CmdPipelineBarrier(
		c.command,
		{.COMPUTE_SHADER, .TRANSFER},
		{.TRANSFER},
		{},
		1,
		&before,
		0,
		nil,
		0,
		nil,
	)
	if fill {
		d.CmdFillBuffer(
			c.command,
			dst.storage.buffer,
			vk.DeviceSize(destination_offset),
			vk.DeviceSize(size),
			value,
		)
	} else {
		region := vk.BufferCopy {
			srcOffset = vk.DeviceSize(source_offset),
			dstOffset = vk.DeviceSize(destination_offset),
			size      = vk.DeviceSize(size),
		}
		d.CmdCopyBuffer(c.command, src.storage.buffer, dst.storage.buffer, 1, &region)
	}
	after := vk.MemoryBarrier {
		sType         = .MEMORY_BARRIER,
		srcAccessMask = {.TRANSFER_WRITE},
		dstAccessMask = {.SHADER_READ, .SHADER_WRITE, .HOST_READ},
	}
	d.CmdPipelineBarrier(
		c.command,
		{.TRANSFER},
		{.COMPUTE_SHADER, .HOST},
		{},
		1,
		&after,
		0,
		nil,
		0,
		nil,
	)
	if reason := command_submit(device); reason != "" {return reason}
	if d.WaitForFences(device.handle, 1, &c.fence, true, max(u64)) !=
	   .SUCCESS {return "GPUCompute transfer failed"}
	return ""
}

copy_gpu_buffer :: proc(
	device: ^Device,
	source, destination: u32,
	size, source_offset, destination_offset: int,
) -> string {
	return buffer_transfer(
		device,
		source,
		destination,
		size,
		source_offset,
		destination_offset,
		false,
		0,
	)
}

fill_gpu_buffer :: proc(device: ^Device, id, value: u32, size, offset: int) -> string {
	return buffer_transfer(device, 0, id, size, 0, offset, true, value)
}
