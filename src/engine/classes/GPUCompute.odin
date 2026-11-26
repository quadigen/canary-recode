package classes

import datatypes "../datatypes"
import enums "../enum"
import gpu "../gpucompute"
import vm "../vm"
import "core:math"

GPUCompute_Class := Class_Info {
	name   = "GPUCompute",
	parent = &Instance_Class,
}

GPUCompute :: struct {
	using object:   Object,
	device:         gpu.Device,
	native_buffers: [gpu.MAX_CUSTOM_BUFFERS]GPUCompute_Luau_Buffer,
	warmup:         [16]GPUCompute_Warmup,
	warmup_next:    u32,
	warmup_bytes:   int,
}

GPUCompute_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	compute := new(GPUCompute)
	compute.object = Object_Init(&GPUCompute_Class, "GPUCompute")
	return &compute.object
}

GPUCompute_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	compute := cast(^GPUCompute)object
	for &job in compute.warmup {delete(job.source)}
	gpu.close(&compute.device)
	if compute.signal_registry != nil && compute.signal_registry.vm_state != nil {
		if L := compute.signal_registry.vm_state.L; L != nil {gpu_compute_release_refs(L, compute)}
	}
	Object_Destroy(object)
	free(compute)
}

gpu_compute_integer :: proc(L: ^vm.State, index: int, minimum, maximum: f64) -> u32 {
	value := vm.ArgNumber(L, index)
	if !(value >= minimum && value <= maximum) || math.floor(value) != value {
		_ = vm.RaiseError(L, "GPUCompute expects an integer argument within limits")
		return 0
	}
	return u32(value)
}

gpu_compute_dimension :: proc(L: ^vm.State, index: int) -> u32 {
	return gpu_compute_integer(L, index, 1, gpu.MAX_ELEMENTS)
}

gpu_compute_valid_buffer :: proc(data: []u8) -> bool {
	return(
		len(data) > 0 &&
		len(data) <= gpu.MAX_ELEMENTS * size_of(f32) &&
		len(data) % size_of(f32) == 0 \
	)
}

gpu_compute_dispatch :: proc(L: ^vm.State, device: ^gpu.Device) -> string {
	params: gpu.Parameters
	switch vm.ArgString(L, 2) {
	case "Add":
		params.operation = .Add
	case "Subtract":
		params.operation = .Subtract
	case "Multiply":
		params.operation = .Multiply
	case "MatrixMultiply":
		params.operation = .MatrixMultiply
	case "Divide":
		params.operation = .Divide
	case "Min":
		params.operation = .Min
	case "Max":
		params.operation = .Max
	case "Abs":
		params.operation = .Abs
	case "Negate":
		params.operation = .Negate
	case "Sqrt":
		params.operation = .Sqrt
	case:
		return "unknown GPUCompute operation"
	}
	a := vm.ArgBuffer(L, 3)
	b: []u8
	unary := params.operation == .Abs || params.operation == .Negate || params.operation == .Sqrt
	if unary {
		if !vm.IsNoneOrNil(L, 4) {return "this GPUCompute operation takes one input buffer"}
	} else {
		b = vm.ArgBuffer(L, 4)
	}
	if !gpu_compute_valid_buffer(a) || (!unary && !gpu_compute_valid_buffer(b)) {
		return "GPUCompute expects nonempty float32 buffers of at most 4000000 elements"
	}
	if params.operation == .MatrixMultiply {
		params.rows = gpu_compute_dimension(L, 5)
		params.inner = gpu_compute_dimension(L, 6)
		params.columns = gpu_compute_dimension(L, 7)
		rows, inner, columns := u64(params.rows), u64(params.inner), u64(params.columns)
		if rows * inner != u64(len(a) / size_of(f32)) ||
		   inner * columns != u64(len(b) / size_of(f32)) {
			return "GPUCompute matrix dimensions do not match the input buffers"
		}
		if rows * columns > gpu.MAX_ELEMENTS || rows * inner * columns > gpu.MAX_MATRIX_PRODUCTS {
			return "GPUCompute matrix exceeds the output size or multiplication limit"
		}
		if rows > 65535 * 8 ||
		   columns > 65535 * 8 {return "GPUCompute matrix exceeds the dispatch dimensions"}
	} else {
		if !unary &&
		   len(a) != len(b) {return "GPUCompute element-wise inputs must have equal lengths"}
		params.rows = u32(len(a) / size_of(f32))
		params.columns = 1
	}
	return gpu.dispatch(device, params, a, b)
}

gpu_compute_result :: proc(L: ^vm.State, err: string) -> (i32, bool) {
	vm.PushBoolean(L, err == "")
	if err != "" {vm.PushString(L, err); return 2, true}
	return 1, true
}

gpu_compute_nil_error :: proc(L: ^vm.State, err: string) -> (i32, bool) {
	vm.PushNil(L)
	if err != "" {vm.PushString(L, err); return 2, true}
	return 1, true
}

gpu_compute_buffer_id :: proc(L: ^vm.State, index: int) -> u32 {
	return gpu_compute_integer(L, index, 1, f64(max(u32)))
}

GPUCompute_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	compute := cast(^GPUCompute)object
	device := &compute.device
	if count, handled := GPUCompute_Render_Namecall(L, compute, method);
	   handled {return count, true}
	switch method {
	case "IsSupported":
		return gpu_compute_result(L, gpu.open(device))
	case "Dispatch":
		return gpu_compute_result(L, gpu_compute_dispatch(L, device))
	case "Poll":
		data, err := gpu.poll(device)
		if data != nil {
			vm.PushBuffer(L, data)
			gpu.clear_result(device)
			return 1, true
		}
		if err != "" {gpu_compute_release_refs(L, compute)}
		return gpu_compute_nil_error(L, err)
	case "CompileShader", "CreatePipeline":
		source := vm.ArgString(L, 2)
		count, kinds, err := gpu_compute_layout(L, 3)
		if method == "CreatePipeline" {
			if err != "" {return gpu_compute_nil_error(L, err)}
			id, reason := gpu.create_shader_pipeline(device, source, count, kinds)
			return gpu_compute_push_id(L, id, reason)
		}
		if err != "" {return gpu_compute_result(L, err)}
		return gpu_compute_result(L, gpu.compile_shader(device, source, count, kinds))
	case "CreateBuffer", "AllocateDeviceBuffer":
		size := gpu_compute_integer(L, 2, 4, gpu.MAX_CUSTOM_BUFFER_BYTES)
		id, err := gpu.create_buffer(device, int(size))
		if err != "" {return gpu_compute_nil_error(L, err)}
		vm.PushNumber(L, f64(id))
		return 1, true
	case "WriteBuffer":
		id := gpu_compute_buffer_id(L, 2)
		data := vm.ArgBuffer(L, 3)
		offset := 0
		if !vm.IsNoneOrNil(
			L,
			4,
		) {offset = int(gpu_compute_integer(L, 4, 0, gpu.MAX_CUSTOM_BUFFER_BYTES))}
		return gpu_compute_result(L, gpu.write_buffer(device, id, data, offset))
	case "ReadBuffer":
		id := gpu_compute_buffer_id(L, 2)
		offset := 0
		size := -1
		if !vm.IsNoneOrNil(
			L,
			3,
		) {offset = int(gpu_compute_integer(L, 3, 0, gpu.MAX_CUSTOM_BUFFER_BYTES))}
		if !vm.IsNoneOrNil(
			L,
			4,
		) {size = int(gpu_compute_integer(L, 4, 1, gpu.MAX_CUSTOM_BUFFER_BYTES))}
		data, err := gpu.read_buffer(device, id, offset, size)
		if err != "" {return gpu_compute_nil_error(L, err)}
		vm.PushBuffer(L, data)
		return 1, true
	case "BindBuffer":
		binding := gpu_compute_integer(L, 2, 0, gpu.MAX_CUSTOM_BINDINGS - 1)
		if vm.IsBuffer(
			L,
			3,
		) {return gpu_compute_result(L, gpu_compute_bind_luau(L, compute, binding, 3))}
		id := gpu_compute_buffer_id(L, 3)
		return gpu_compute_result(L, gpu.bind_buffer(device, binding, id))
	case "UnbindBuffer":
		return gpu_compute_result(
			L,
			gpu.unbind(device, gpu_compute_integer(L, 2, 0, gpu.MAX_CUSTOM_BINDINGS - 1)),
		)
	case "UploadBuffer", "DownloadBuffer", "ReleaseBuffer":
		return gpu_compute_result(L, gpu_compute_sync_luau(L, compute, method))
	case "CreateTexture",
	     "LoadTexture",
	     "GetTextureInfo",
	     "GetMaterialTextures",
	     "BindTexture",
	     "DestroyTexture",
	     "LoadMesh",
	     "GetMeshFromInstance",
	     "BuildBVH",
	     "GetCapabilities":
		return gpu_compute_resource_namecall(L, compute, datatype_registry, enum_registry, method)
	case "UsePipeline":
		return gpu_compute_result(
			L,
			gpu.use_shader_pipeline(device, gpu_compute_integer(L, 2, 0, f64(max(u32)))),
		)
	case "DestroyPipeline":
		return gpu_compute_result(
			L,
			gpu.destroy_shader_pipeline(device, gpu_compute_buffer_id(L, 2)),
		)
	case "BeginCommands":
		return gpu_compute_result(L, gpu.begin_commands(device))
	case "SubmitCommands":
		return gpu_compute_result(L, gpu.submit_commands(device))
	case "CancelCommands":
		return gpu_compute_result(L, gpu.cancel_commands(device))
	case "MemoryBarrier":
		return gpu_compute_result(L, gpu.command_barrier(device))
	case "CopyGPUBuffer":
		source := gpu_compute_buffer_argument(L, compute, 2)
		destination := gpu_compute_buffer_argument(L, compute, 3)
		size := gpu_compute_optional_size(L, 4, -1)
		source_offset := gpu_compute_optional_size(L, 5, 0)
		dest_offset := gpu_compute_optional_size(L, 6, 0)
		return gpu_compute_result(
			L,
			gpu.copy_gpu_buffer(device, source, destination, size, source_offset, dest_offset),
		)
	case "FillGPUBuffer":
		id := gpu_compute_buffer_argument(L, compute, 2)
		value := gpu_compute_integer(L, 3, 0, f64(max(u32)))
		size := gpu_compute_optional_size(L, 4, -1)
		offset := gpu_compute_optional_size(L, 5, 0)
		return gpu_compute_result(L, gpu.fill_gpu_buffer(device, id, value, size, offset))
	case "SetPushConstants":
		return gpu_compute_result(L, gpu.set_push_constants(device, vm.ArgBuffer(L, 2)))
	case "DispatchShader", "SubmitTask":
		x := gpu_compute_integer(L, 2, 1, f64(max(u32)))
		y, z: u32 = 1, 1
		if !vm.IsNoneOrNil(L, 3) {y = gpu_compute_integer(L, 3, 1, f64(max(u32)))}
		if !vm.IsNoneOrNil(L, 4) {z = gpu_compute_integer(L, 4, 1, f64(max(u32)))}
		if method == "SubmitTask" {
			id, err := gpu.submit_task(device, x, y, z)
			if err == gpu.TASK_DEVICE_LOST {gpu_compute_release_refs(L, compute)}
			return gpu_compute_push_id(L, id, err)
		}
		return gpu_compute_result(L, gpu.dispatch_shader(device, x, y, z))
	case "BeginTask":
		return gpu_compute_result(L, gpu.begin_task(device))
	case "SubmitTaskBatch":
		id, err := gpu.submit_task_batch(device)
		if err == gpu.TASK_DEVICE_LOST {gpu_compute_release_refs(L, compute)}
		return gpu_compute_push_id(L, id, err)
	case "PollTask":
		done, err := gpu.poll_task(device, gpu_compute_buffer_id(L, 2))
		if err == gpu.TASK_DEVICE_LOST {gpu_compute_release_refs(L, compute)}
		vm.PushBoolean(L, done)
		if err != "" {vm.PushString(L, err); return 2, true}
		return 1, true
	case "GetTaskInfo":
		info, err := gpu.get_task_info(device, gpu_compute_buffer_id(L, 2))
		if err != "" {return gpu_compute_nil_error(L, err)}
		vm.NewTable(L, 0, 3)
		gpu_compute_set_number(L, "Queue", info.queue)
		gpu_compute_set_number(L, "DispatchCount", info.dispatch_count)
		vm.PushBoolean(L, info.complete); vm.SetField(L, -2, "Complete")
		return 1, true
	case "GetPendingTaskCount":
		vm.PushNumber(L, f64(gpu.pending_task_count(device)))
		return 1, true
	case "PollShader":
		done, err := gpu.poll_shader(device)
		vm.PushBoolean(L, done)
		if err != "" {gpu_compute_release_refs(L, compute); vm.PushString(L, err); return 2, true}
		return 1, true
	case "DestroyBuffer":
		id := gpu_compute_buffer_id(L, 2)
		for entry in compute.native_buffers {
			if entry.id == id {return gpu_compute_result(L, "use ReleaseBuffer for a Luau buffer")}
		}
		return gpu_compute_result(L, gpu.destroy_buffer(device, id))
	}
	return 0, false
}

Register_GPUCompute :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&GPUCompute_Class,
		GPUCompute_construct,
		GPUCompute_destroy,
		namecall = GPUCompute_namecall,
		methods = []string {
			"DispatchTexture",
			"GetCacheStats",
			"QueuePipeline",
			"WarmupPipelines",
			"GetWarmupPendingCount",
			"IsSupported",
			"Dispatch",
			"Poll",
			"CompileShader",
			"CreateBuffer",
			"WriteBuffer",
			"ReadBuffer",
			"BindBuffer",
			"SetPushConstants",
			"DispatchShader",
			"PollShader",
			"DestroyBuffer",
			"SubmitTask",
			"BeginTask",
			"SubmitTaskBatch",
			"PollTask",
			"GetTaskInfo",
			"GetPendingTaskCount",
			"CreatePipeline",
			"UsePipeline",
			"DestroyPipeline",
			"BeginCommands",
			"SubmitCommands",
			"CancelCommands",
			"MemoryBarrier",
			"CopyGPUBuffer",
			"FillGPUBuffer",
			"AllocateDeviceBuffer",
			"UnbindBuffer",
			"UploadBuffer",
			"DownloadBuffer",
			"ReleaseBuffer",
			"CreateTexture",
			"LoadTexture",
			"GetTextureInfo",
			"BindTexture",
			"DestroyTexture",
			"GetMaterialTextures",
			"LoadMesh",
			"GetMeshFromInstance",
			"BuildBVH",
			"GetCapabilities",
		},
	)
}
