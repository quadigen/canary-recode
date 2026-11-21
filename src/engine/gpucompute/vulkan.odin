#+build linux, windows
package gpucompute

import "core:dynlib"
import vk "vendor:vulkan"

ALLOW_SOFTWARE :: #config(KINE_GPU_COMPUTE_ALLOW_SOFTWARE, false)
QUEUE_LIMIT :: clamp(
	#config(KINE_GPU_COMPUTE_MAX_QUEUES, MAX_COMPUTE_QUEUES),
	1,
	MAX_COMPUTE_QUEUES,
)
KERNEL :: #load("kernels.spv")

Device :: struct {
	library:           dynlib.Library,
	instance:          vk.Instance,
	destroy:           vk.ProcDestroyInstance,
	handle:            vk.Device,
	procs:             vk.Device_VTable,
	queue:             vk.Queue,
	parallel:          Parallel_State,
	memory:            vk.PhysicalDeviceMemoryProperties,
	set_layout:        vk.DescriptorSetLayout,
	layout:            vk.PipelineLayout,
	pipeline:          vk.Pipeline,
	commands:          vk.CommandPool,
	job:               Job,
	custom:            Custom_State,
	limits:            vk.PhysicalDeviceLimits,
	robust_access:     bool,
	physical:          vk.PhysicalDevice,
	capabilities:      Capabilities,
	format_properties: vk.ProcGetPhysicalDeviceFormatProperties,
}

Storage :: struct {
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	data:   []u8,
}

Job :: struct {
	storage:     [3]Storage,
	descriptors: vk.DescriptorPool,
	command:     vk.CommandBuffer,
	fence:       vk.Fence,
	submitted:   bool,
}

open :: proc(device: ^Device) -> (err: string) {
	if device.handle != nil {return ""}
	when ODIN_OS == .Windows {
		library_name :: "vulkan-1.dll"
	} else when #config(KINE_ANDROID, false) {
		library_name :: "libvulkan.so"
	} else {
		library_name :: "libvulkan.so.1"
	}
	library, loaded := dynlib.load_library(library_name)
	if !loaded {return "Vulkan loader is unavailable"}
	device.library = library
	defer {
		if err != "" {close(device)}
	}

	resolve := cast(vk.ProcGetInstanceProcAddr)dynlib.symbol_address(
		library,
		"vkGetInstanceProcAddr",
	)
	if resolve == nil {return "Vulkan loader is missing vkGetInstanceProcAddr"}
	create_instance := cast(vk.ProcCreateInstance)resolve(nil, "vkCreateInstance")
	if create_instance == nil {return "Vulkan loader is missing vkCreateInstance"}
	api_version: u32 = vk.API_VERSION_1_0
	if enumerate_version := cast(vk.ProcEnumerateInstanceVersion)resolve(
		   nil,
		   "vkEnumerateInstanceVersion",
	   ); enumerate_version != nil {
		version: u32
		if enumerate_version(&version) == .SUCCESS {api_version = min(version, vk.API_VERSION_1_2)}
	}
	app := vk.ApplicationInfo {
		sType            = .APPLICATION_INFO,
		pApplicationName = "Kinemium GPUCompute",
		apiVersion       = api_version,
	}
	instance_info := vk.InstanceCreateInfo {
		sType            = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &app,
	}
	if create_instance(&instance_info, nil, &device.instance) != .SUCCESS {
		return "could not create a Vulkan compute instance"
	}
	device.destroy = cast(vk.ProcDestroyInstance)resolve(device.instance, "vkDestroyInstance")

	physical, family, available_queues := select_device(device.instance, resolve)
	if physical == nil {return "no compatible Vulkan compute GPU is available"}
	device.physical = physical
	device.format_properties = auto_cast resolve(
		device.instance,
		"vkGetPhysicalDeviceFormatProperties",
	)
	get_memory := cast(vk.ProcGetPhysicalDeviceMemoryProperties)resolve(
		device.instance,
		"vkGetPhysicalDeviceMemoryProperties",
	)
	get_memory(physical, &device.memory)
	get_properties := cast(vk.ProcGetPhysicalDeviceProperties)resolve(
		device.instance,
		"vkGetPhysicalDeviceProperties",
	)
	properties: vk.PhysicalDeviceProperties
	get_properties(physical, &properties)
	device.limits = properties.limits
	get_features := cast(vk.ProcGetPhysicalDeviceFeatures)resolve(
		device.instance,
		"vkGetPhysicalDeviceFeatures",
	)
	available_features: vk.PhysicalDeviceFeatures
	get_features(physical, &available_features)
	features := vk.PhysicalDeviceFeatures {
		robustBufferAccess                = available_features.robustBufferAccess,
		shaderStorageImageExtendedFormats = available_features.shaderStorageImageExtendedFormats,
		shaderFloat64                     = available_features.shaderFloat64,
		shaderInt64                       = available_features.shaderInt64,
		shaderInt16                       = available_features.shaderInt16,
	}
	l := properties.limits
	device.capabilities = {
		name                  = properties.deviceName,
		buffer_size           = min(l.maxStorageBufferRange, MAX_CUSTOM_BUFFER_BYTES),
		uniform_size          = l.maxUniformBufferRange,
		texture_1d            = min(l.maxImageDimension1D, 16384),
		texture_2d            = min(l.maxImageDimension2D, 16384),
		texture_3d            = min(l.maxImageDimension3D, 16384),
		texture_layers        = min(l.maxImageArrayLayers, 2048),
		shared_memory         = l.maxComputeSharedMemorySize,
		workgroup_invocations = l.maxComputeWorkGroupInvocations,
		workgroup_size        = l.maxComputeWorkGroupSize,
		workgroup_count       = l.maxComputeWorkGroupCount,
		float64               = bool(features.shaderFloat64),
		int64                 = bool(features.shaderInt64),
		int16                 = bool(features.shaderInt16),
		storage_extended      = bool(features.shaderStorageImageExtendedFormats),
	}
	device.robust_access = bool(features.robustBufferAccess)
	create_device := cast(vk.ProcCreateDevice)resolve(device.instance, "vkCreateDevice")
	timeline := vk.PhysicalDeviceTimelineSemaphoreFeatures {
		sType = .PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES,
	}
	if api_version >= vk.API_VERSION_1_2 && properties.apiVersion >= vk.API_VERSION_1_2 {
		query := cast(vk.ProcGetPhysicalDeviceFeatures2)resolve(
			device.instance,
			"vkGetPhysicalDeviceFeatures2",
		)
		if query != nil {
			f2 := vk.PhysicalDeviceFeatures2 {
				sType = .PHYSICAL_DEVICE_FEATURES_2,
				pNext = &timeline,
			}
			query(physical, &f2)
		}
	}
	queue_count: u32 = 1
	if timeline.timelineSemaphore {queue_count = min(available_queues, u32(QUEUE_LIMIT))}
	device.capabilities.compute_queues = queue_count
	device.capabilities.timeline_semaphores = bool(timeline.timelineSemaphore)
	priorities := [MAX_COMPUTE_QUEUES]f32{0.5, 0.5, 0.5, 0.5}
	queue_info := vk.DeviceQueueCreateInfo {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = family,
		queueCount       = queue_count,
		pQueuePriorities = &priorities[0],
	}
	info := vk.DeviceCreateInfo {
		sType                = .DEVICE_CREATE_INFO,
		queueCreateInfoCount = 1,
		pQueueCreateInfos    = &queue_info,
		pEnabledFeatures     = &features,
	}
	if timeline.timelineSemaphore {info.pNext = &timeline}
	if create_device(physical, &info, nil, &device.handle) != .SUCCESS {
		return "could not create a Vulkan compute device"
	}


	get_proc := cast(vk.ProcGetDeviceProcAddr)resolve(device.instance, "vkGetDeviceProcAddr")
	load_procs(device.handle, get_proc, &device.procs)
	d := &device.procs
	d.GetDeviceQueue(device.handle, family, 0, &device.queue)
	for i in 0 ..< queue_count {d.GetDeviceQueue(device.handle, family, i, &device.parallel.queues[i])}
	if queue_count > 1 {
		if err = parallel_init(device); err != "" {return err}
	}
	pool := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.TRANSIENT},
		queueFamilyIndex = family,
	}
	if d.CreateCommandPool(device.handle, &pool, nil, &device.commands) != .SUCCESS {
		return "could not create the Vulkan compute command pool"
	}
	return create_pipeline(device)
}

select_device :: proc(
	instance: vk.Instance,
	resolve: vk.ProcGetInstanceProcAddr,
) -> (
	vk.PhysicalDevice,
	u32,
	u32,
) {
	enumerate := cast(vk.ProcEnumeratePhysicalDevices)resolve(
		instance,
		"vkEnumeratePhysicalDevices",
	)
	get_properties := cast(vk.ProcGetPhysicalDeviceProperties)resolve(
		instance,
		"vkGetPhysicalDeviceProperties",
	)
	get_queues := cast(vk.ProcGetPhysicalDeviceQueueFamilyProperties)resolve(
		instance,
		"vkGetPhysicalDeviceQueueFamilyProperties",
	)
	count: u32
	if enumerate(instance, &count, nil) != .SUCCESS || count == 0 {return nil, 0, 0}
	devices := make([]vk.PhysicalDevice, count)
	defer delete(devices)
	if enumerate(instance, &count, raw_data(devices)) != .SUCCESS {return nil, 0, 0}

	best: vk.PhysicalDevice
	best_family, best_queue_count: u32
	best_rank := 0
	for physical in devices[:count] {
		properties: vk.PhysicalDeviceProperties
		get_properties(physical, &properties)
		rank := 1
		switch properties.deviceType {
		case .DISCRETE_GPU:
			rank = 4
		case .INTEGRATED_GPU:
			rank = 3
		case .VIRTUAL_GPU, .OTHER:
			rank = 2
		case .CPU:
			if !ALLOW_SOFTWARE {continue}
		}
		if rank <= best_rank {continue}
		queue_count: u32
		get_queues(physical, &queue_count, nil)
		if queue_count == 0 {continue}
		queues := make([]vk.QueueFamilyProperties, queue_count)
		defer delete(queues)
		get_queues(physical, &queue_count, raw_data(queues))
		family_score: u32
		for queue, index in queues[:queue_count] {
			if .COMPUTE not_in queue.queueFlags || queue.queueCount == 0 {continue}

			score := min(queue.queueCount, u32(QUEUE_LIMIT)) * 2
			if .GRAPHICS not_in queue.queueFlags {score += 1}
			if score <= family_score {continue}
			family_score = score
			best, best_family, best_rank, best_queue_count =
				physical, u32(index), rank, queue.queueCount
		}
	}
	return best, best_family, best_queue_count
}

create_pipeline :: proc(device: ^Device) -> string {
	d := &device.procs
	handle := device.handle
	bindings: [3]vk.DescriptorSetLayoutBinding
	for &binding, i in bindings {
		binding = {
			binding         = u32(i),
			descriptorType  = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags      = {.COMPUTE},
		}
	}
	set_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = len(bindings),
		pBindings    = &bindings[0],
	}
	if d.CreateDescriptorSetLayout(handle, &set_info, nil, &device.set_layout) != .SUCCESS {
		return "could not create GPUCompute's storage layout"
	}
	constants := vk.PushConstantRange {
		stageFlags = {.COMPUTE},
		size       = size_of(Parameters),
	}
	layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &device.set_layout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &constants,
	}
	if d.CreatePipelineLayout(handle, &layout_info, nil, &device.layout) != .SUCCESS {
		return "could not create GPUCompute's pipeline layout"
	}


	code := make([]u32, len(KERNEL) / size_of(u32))
	defer delete(code)
	copy((cast([^]u8)raw_data(code))[:len(KERNEL)], KERNEL)
	shader_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(KERNEL),
		pCode    = &code[0],
	}
	shader: vk.ShaderModule
	if d.CreateShaderModule(handle, &shader_info, nil, &shader) != .SUCCESS {
		return "could not load GPUCompute's kernels"
	}
	defer d.DestroyShaderModule(handle, shader, nil)
	info := vk.ComputePipelineCreateInfo {
		sType = .COMPUTE_PIPELINE_CREATE_INFO,
		layout = device.layout,
		basePipelineIndex = -1,
		stage = {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.COMPUTE},
			module = shader,
			pName = "main",
		},
	}
	if d.CreateComputePipelines(handle, 0, 1, &info, nil, &device.pipeline) != .SUCCESS {
		return "could not create GPUCompute's pipeline"
	}
	return ""
}

create_storage :: proc(device: ^Device, storage: ^Storage, bytes: int) -> bool {
	d := &device.procs
	handle := device.handle
	info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size  = vk.DeviceSize(bytes),
		usage = {.STORAGE_BUFFER, .UNIFORM_BUFFER, .TRANSFER_SRC, .TRANSFER_DST},
	}
	if d.CreateBuffer(handle, &info, nil, &storage.buffer) != .SUCCESS {return false}
	requirements: vk.MemoryRequirements
	d.GetBufferMemoryRequirements(handle, storage.buffer, &requirements)
	for i in 0 ..< device.memory.memoryTypeCount {
		flags := device.memory.memoryTypes[i].propertyFlags
		if requirements.memoryTypeBits & (u32(1) << i) == 0 ||
		   .HOST_VISIBLE not_in flags ||
		   .HOST_COHERENT not_in flags {continue}

		allocation := vk.MemoryAllocateInfo {
			sType           = .MEMORY_ALLOCATE_INFO,
			allocationSize  = requirements.size,
			memoryTypeIndex = i,
		}
		if d.AllocateMemory(handle, &allocation, nil, &storage.memory) != .SUCCESS {continue}
		if d.BindBufferMemory(handle, storage.buffer, storage.memory, 0) != .SUCCESS {return false}
		mapped: rawptr
		if d.MapMemory(handle, storage.memory, 0, vk.DeviceSize(bytes), {}, &mapped) != .SUCCESS {
			return false
		}
		storage.data = (cast([^]u8)mapped)[:bytes]
		return true
	}
	return false
}

dispatch :: proc(device: ^Device, params: Parameters, a, b: []u8) -> (err: string) {
	if device.job.submitted ||
	   device.custom.submitted ||
	   device.custom.recording ||
	   device.parallel.count != 0 {return "a GPUCompute job or batch is already pending"}
	if reason := open(device); reason != "" {return reason}
	defer {
		if err != "" {clear_result(device)}
	}
	job := &device.job
	d := &device.procs
	handle := device.handle
	output_size := int(params.rows * params.columns) * size_of(f32)
	sizes := [3]int{len(a), len(b), output_size}
	for size, i in sizes {
		if size == 0 {continue}
		if !create_storage(device, &job.storage[i], size) {
			return "could not allocate GPUCompute storage buffers"
		}
	}
	copy(job.storage[0].data, a)
	if len(b) != 0 {copy(job.storage[1].data, b)}

	pool_size := vk.DescriptorPoolSize {
		type            = .STORAGE_BUFFER,
		descriptorCount = 3,
	}
	pool := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = 1,
		poolSizeCount = 1,
		pPoolSizes    = &pool_size,
	}
	if d.CreateDescriptorPool(handle, &pool, nil, &job.descriptors) != .SUCCESS {
		return "could not create GPUCompute descriptors"
	}
	set_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = job.descriptors,
		descriptorSetCount = 1,
		pSetLayouts        = &device.set_layout,
	}
	set: vk.DescriptorSet
	if d.AllocateDescriptorSets(handle, &set_info, &set) != .SUCCESS {
		return "could not allocate GPUCompute descriptors"
	}
	buffers: [3]vk.DescriptorBufferInfo
	writes: [3]vk.WriteDescriptorSet
	for storage, i in job.storage {
		buffers[i] = {
			buffer = storage.buffer,
			range  = vk.DeviceSize(sizes[i]),
		}

		if i == 1 && len(b) == 0 {buffers[i] = buffers[0]}
		writes[i] = {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = set,
			dstBinding      = u32(i),
			descriptorCount = 1,
			descriptorType  = .STORAGE_BUFFER,
			pBufferInfo     = &buffers[i],
		}
	}
	d.UpdateDescriptorSets(handle, len(writes), &writes[0], 0, nil)

	command_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = device.commands,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	if d.AllocateCommandBuffers(handle, &command_info, &job.command) != .SUCCESS {
		return "could not allocate GPUCompute commands"
	}
	if !record_commands(device, params, set) {return "could not record GPUCompute commands"}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
	}
	if d.CreateFence(handle, &fence_info, nil, &job.fence) != .SUCCESS {
		return "could not create the GPUCompute completion fence"
	}
	submit := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &job.command,
	}
	if d.QueueSubmit(device.queue, 1, &submit, job.fence) != .SUCCESS {
		return "could not submit the GPUCompute job"
	}
	job.submitted = true
	return ""
}

record_commands :: proc(device: ^Device, params: Parameters, set: vk.DescriptorSet) -> bool {
	d := &device.procs
	command := device.job.command
	begin := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if d.BeginCommandBuffer(command, &begin) != .SUCCESS {return false}
	d.CmdBindPipeline(command, .COMPUTE, device.pipeline)
	local_set, constants := set, params
	d.CmdBindDescriptorSets(command, .COMPUTE, device.layout, 0, 1, &local_set, 0, nil)
	d.CmdPushConstants(command, device.layout, {.COMPUTE}, 0, size_of(Parameters), &constants)
	if params.operation == .MatrixMultiply {
		d.CmdDispatch(command, (params.columns + 7) / 8, (params.rows + 7) / 8, 1)
	} else {
		d.CmdDispatch(command, (params.rows + 63) / 64, 1, 1)
	}
	barrier := vk.MemoryBarrier {
		sType         = .MEMORY_BARRIER,
		srcAccessMask = {.SHADER_WRITE},
		dstAccessMask = {.HOST_READ},
	}
	d.CmdPipelineBarrier(command, {.COMPUTE_SHADER}, {.HOST}, {}, 1, &barrier, 0, nil, 0, nil)
	return d.EndCommandBuffer(command) == .SUCCESS
}

poll :: proc(device: ^Device) -> ([]u8, string) {
	job := &device.job
	if !job.submitted {return nil, ""}
	#partial switch device.procs.GetFenceStatus(device.handle, job.fence) {
	case .NOT_READY:
		return nil, ""
	case .SUCCESS:
		return job.storage[2].data, ""
	case:
		close(device)
		return nil, "the Vulkan compute job failed"
	}
}

clear_result :: proc(device: ^Device) {
	d := &device.procs
	handle := device.handle
	job := &device.job
	if job.fence != 0 {d.DestroyFence(handle, job.fence, nil)}
	if job.command != nil {d.FreeCommandBuffers(handle, device.commands, 1, &job.command)}
	if job.descriptors != 0 {d.DestroyDescriptorPool(handle, job.descriptors, nil)}
	for storage in job.storage {
		if storage.data != nil {d.UnmapMemory(handle, storage.memory)}
		if storage.buffer != 0 {d.DestroyBuffer(handle, storage.buffer, nil)}
		if storage.memory != 0 {d.FreeMemory(handle, storage.memory, nil)}
	}
	job^ = {}
}

close :: proc(device: ^Device) {
	if handle := device.handle; handle != nil {
		d := &device.procs
		if device.job.submitted {
			_ = d.WaitForFences(handle, 1, &device.job.fence, true, max(u64))
		}
		clear_result(device)
		parallel_close(device)
		custom_close(device)
		if device.pipeline != 0 {d.DestroyPipeline(handle, device.pipeline, nil)}
		if device.layout != 0 {d.DestroyPipelineLayout(handle, device.layout, nil)}
		if device.set_layout != 0 {d.DestroyDescriptorSetLayout(handle, device.set_layout, nil)}
		if device.commands != 0 {d.DestroyCommandPool(handle, device.commands, nil)}
		d.DestroyDevice(handle, nil)
	}
	if device.instance != nil {device.destroy(device.instance, nil)}
	if device.library != nil {_ = dynlib.unload_library(device.library)}
	device^ = {}
}

load_procs :: proc(device: vk.Device, get: vk.ProcGetDeviceProcAddr, table: ^vk.Device_VTable) {
	table.CreateSemaphore = auto_cast get(device, "vkCreateSemaphore")
	table.DestroySemaphore = auto_cast get(device, "vkDestroySemaphore")
	table.DeviceWaitIdle = auto_cast get(device, "vkDeviceWaitIdle")
	table.CreateImage = auto_cast get(device, "vkCreateImage")
	table.DestroyImage = auto_cast get(device, "vkDestroyImage")
	table.GetImageMemoryRequirements = auto_cast get(device, "vkGetImageMemoryRequirements")
	table.BindImageMemory = auto_cast get(device, "vkBindImageMemory")
	table.CreateImageView = auto_cast get(device, "vkCreateImageView")
	table.DestroyImageView = auto_cast get(device, "vkDestroyImageView")
	table.CreateSampler = auto_cast get(device, "vkCreateSampler")
	table.DestroySampler = auto_cast get(device, "vkDestroySampler")
	table.CmdCopyBufferToImage = auto_cast get(device, "vkCmdCopyBufferToImage")
	table.CmdCopyBuffer = auto_cast get(device, "vkCmdCopyBuffer")
	table.CmdFillBuffer = auto_cast get(device, "vkCmdFillBuffer")
	table.AllocateCommandBuffers = auto_cast get(device, "vkAllocateCommandBuffers")
	table.AllocateDescriptorSets = auto_cast get(device, "vkAllocateDescriptorSets")
	table.AllocateMemory = auto_cast get(device, "vkAllocateMemory")
	table.BeginCommandBuffer = auto_cast get(device, "vkBeginCommandBuffer")
	table.BindBufferMemory = auto_cast get(device, "vkBindBufferMemory")
	table.CmdBindDescriptorSets = auto_cast get(device, "vkCmdBindDescriptorSets")
	table.CmdBindPipeline = auto_cast get(device, "vkCmdBindPipeline")
	table.CmdDispatch = auto_cast get(device, "vkCmdDispatch")
	table.CmdPipelineBarrier = auto_cast get(device, "vkCmdPipelineBarrier")
	table.CmdPushConstants = auto_cast get(device, "vkCmdPushConstants")
	table.CreateBuffer = auto_cast get(device, "vkCreateBuffer")
	table.CreateCommandPool = auto_cast get(device, "vkCreateCommandPool")
	table.CreateComputePipelines = auto_cast get(device, "vkCreateComputePipelines")
	table.CreateDescriptorPool = auto_cast get(device, "vkCreateDescriptorPool")
	table.CreateDescriptorSetLayout = auto_cast get(device, "vkCreateDescriptorSetLayout")
	table.CreateFence = auto_cast get(device, "vkCreateFence")
	table.CreatePipelineLayout = auto_cast get(device, "vkCreatePipelineLayout")
	table.CreateShaderModule = auto_cast get(device, "vkCreateShaderModule")
	table.DestroyBuffer = auto_cast get(device, "vkDestroyBuffer")
	table.DestroyCommandPool = auto_cast get(device, "vkDestroyCommandPool")
	table.DestroyDescriptorPool = auto_cast get(device, "vkDestroyDescriptorPool")
	table.DestroyDescriptorSetLayout = auto_cast get(device, "vkDestroyDescriptorSetLayout")
	table.DestroyDevice = auto_cast get(device, "vkDestroyDevice")
	table.DestroyFence = auto_cast get(device, "vkDestroyFence")
	table.DestroyPipeline = auto_cast get(device, "vkDestroyPipeline")
	table.DestroyPipelineLayout = auto_cast get(device, "vkDestroyPipelineLayout")
	table.DestroyShaderModule = auto_cast get(device, "vkDestroyShaderModule")
	table.EndCommandBuffer = auto_cast get(device, "vkEndCommandBuffer")
	table.FreeCommandBuffers = auto_cast get(device, "vkFreeCommandBuffers")
	table.FreeMemory = auto_cast get(device, "vkFreeMemory")
	table.GetBufferMemoryRequirements = auto_cast get(device, "vkGetBufferMemoryRequirements")
	table.GetDeviceQueue = auto_cast get(device, "vkGetDeviceQueue")
	table.GetFenceStatus = auto_cast get(device, "vkGetFenceStatus")
	table.MapMemory = auto_cast get(device, "vkMapMemory")
	table.QueueSubmit = auto_cast get(device, "vkQueueSubmit")
	table.UnmapMemory = auto_cast get(device, "vkUnmapMemory")
	table.UpdateDescriptorSets = auto_cast get(device, "vkUpdateDescriptorSets")
	table.WaitForFences = auto_cast get(device, "vkWaitForFences")
}


get_capabilities :: proc(device: ^Device) -> (Capabilities, string) {
	if err := open(device); err != "" {return {}, err}
	return device.capabilities, ""
}
