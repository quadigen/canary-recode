package native_api

import gpu "../gpucompute"
import odin_runtime "base:runtime"

SDK_GPU_Capabilities :: struct {
	name:                                                               [256]u8,
	max_buffer_size, max_uniform_size:                                  u32,
	max_texture_1d, max_texture_2d, max_texture_3d, max_texture_layers: u32,
	max_shared_memory, max_workgroup_invocations:                       u32,
	max_workgroup_size, max_workgroup_count:                            [3]u32,
	float64, int64, int16, extended_storage:                            bool,
	compute_queues:                                                     u32,
	timeline_semaphores:                                                bool,
}

SDK_GPU_Task_Info :: struct {
	queue, dispatch_count: u32,
	complete:              bool,
}

sdk_gpu :: proc(ctx: ^Context) -> ^gpu.Device {
	if ctx == nil || !ctx.active {return nil}
	return ctx.gpu_device
}

gpu_compute_release :: proc(ctx: ^Context) {
	if ctx == nil || ctx.gpu_device == nil {return}
	gpu.close(ctx.gpu_device)
	free(ctx.gpu_device)
	ctx.gpu_device = nil
}

gpu_compute_check :: proc(ctx: ^Context) -> bool {
	if sdk_gpu(ctx) != nil {return true}
	sdk_error(ctx, "GPUCompute device is not open; call GPUComputeOpen first")
	return false
}

gpu_compute_status :: proc(ctx: ^Context, err: string) -> bool {
	if err != "" {sdk_error(ctx, err); return false}
	sdk_clear_error(ctx)
	return true
}

gpu_compute_id :: proc(ctx: ^Context, id: u32, err: string, output: ^u32) -> bool {
	if err != "" {sdk_error(ctx, err); return false}
	if id == 0 {sdk_error(ctx, "GPUCompute returned an invalid resource ID"); return false}
	output^ = id
	sdk_clear_error(ctx)
	return true
}

gpu_compute_slice :: proc(data: rawptr, length: u64) -> []u8 {
	if length == 0 {return nil}
	return (cast([^]u8)data)[:int(length)]
}

@(export)
Kinemium_GPUComputeOpen :: proc "c" (ctx: ^Context) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active {return false}
	if ctx.gpu_device == nil {ctx.gpu_device = new(gpu.Device)}
	if err := gpu.open(ctx.gpu_device); err != "" {
		gpu_compute_release(ctx)
		sdk_error(ctx, err)
		return false
	}
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_GPUComputeClose :: proc "c" (ctx: ^Context) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active {return false}
	gpu_compute_release(ctx)
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_GPUComputeGetCapabilities :: proc "c" (
	ctx: ^Context,
	out: ^SDK_GPU_Capabilities,
) -> bool {
	context = odin_runtime.default_context()
	if out == nil || !Kinemium_GPUComputeOpen(ctx) {return false}
	cap, err := gpu.get_capabilities(ctx.gpu_device)
	if !gpu_compute_status(ctx, err) {return false}
	out^ = {
		name                      = cap.name,
		max_buffer_size           = cap.buffer_size,
		max_uniform_size          = cap.uniform_size,
		max_texture_1d            = cap.texture_1d,
		max_texture_2d            = cap.texture_2d,
		max_texture_3d            = cap.texture_3d,
		max_texture_layers        = cap.texture_layers,
		max_shared_memory         = cap.shared_memory,
		max_workgroup_invocations = cap.workgroup_invocations,
		max_workgroup_size        = cap.workgroup_size,
		max_workgroup_count       = cap.workgroup_count,
		float64                   = cap.float64,
		int64                     = cap.int64,
		int16                     = cap.int16,
		extended_storage          = cap.storage_extended,
		compute_queues            = cap.compute_queues,
		timeline_semaphores       = cap.timeline_semaphores,
	}
	return true
}

@(export)
Kinemium_GPUComputeCreateBuffer :: proc "c" (ctx: ^Context, size: u64, out: ^u32) -> bool {
	context = odin_runtime.default_context()
	if out == nil || !gpu_compute_check(ctx) {return false}
	if size < 4 || size > gpu.MAX_CUSTOM_BUFFER_BYTES || size % 4 != 0 {
		sdk_error(
			ctx,
			"GPUCompute buffer size must be aligned, at least 4 bytes and within 64 MiB",
		)
		return false
	}
	id, err := gpu.create_buffer(ctx.gpu_device, int(size))
	return gpu_compute_id(ctx, id, err, out)
}

@(export)
Kinemium_GPUComputeDestroyBuffer :: proc "c" (ctx: ^Context, id: u32) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	return gpu_compute_status(ctx, gpu.destroy_buffer(ctx.gpu_device, id))
}

@(export)
Kinemium_GPUComputeWriteBuffer :: proc "c" (
	ctx: ^Context,
	id: u32,
	data: rawptr,
	size, offset: u64,
) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	if data == nil ||
	   size == 0 ||
	   size > gpu.MAX_CUSTOM_BUFFER_BYTES ||
	   offset > gpu.MAX_CUSTOM_BUFFER_BYTES {
		sdk_error(ctx, "invalid GPUCompute buffer write source or size")
		return false
	}
	return gpu_compute_status(
		ctx,
		gpu.write_buffer(ctx.gpu_device, id, gpu_compute_slice(data, size), int(offset)),
	)
}

@(export)
Kinemium_GPUComputeReadBuffer :: proc "c" (
	ctx: ^Context,
	id: u32,
	offset, size: u64,
	out: rawptr,
	capacity: u64,
) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	if out == nil ||
	   size == 0 ||
	   size > gpu.MAX_CUSTOM_BUFFER_BYTES ||
	   offset > gpu.MAX_CUSTOM_BUFFER_BYTES ||
	   capacity < size {
		sdk_error(ctx, "invalid GPUCompute buffer read destination or size")
		return false
	}
	bytes, err := gpu.read_buffer(ctx.gpu_device, id, int(offset), int(size))
	if !gpu_compute_status(ctx, err) {return false}
	copy(gpu_compute_slice(out, size), bytes)
	return true
}

@(export)
Kinemium_GPUComputeCopyBuffer :: proc "c" (
	ctx: ^Context,
	src, dst: u32,
	size, src_offset, dst_offset: u64,
) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	if size == 0 ||
	   size > gpu.MAX_CUSTOM_BUFFER_BYTES ||
	   src_offset > gpu.MAX_CUSTOM_BUFFER_BYTES ||
	   dst_offset > gpu.MAX_CUSTOM_BUFFER_BYTES {
		sdk_error(ctx, "invalid GPUCompute buffer copy range")
		return false
	}
	return gpu_compute_status(
		ctx,
		gpu.copy_gpu_buffer(ctx.gpu_device, src, dst, int(size), int(src_offset), int(dst_offset)),
	)
}

@(export)
Kinemium_GPUComputeFillBuffer :: proc "c" (
	ctx: ^Context,
	id, value: u32,
	size, offset: u64,
) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	if size == 0 ||
	   size > gpu.MAX_CUSTOM_BUFFER_BYTES ||
	   offset > gpu.MAX_CUSTOM_BUFFER_BYTES ||
	   size % 4 != 0 ||
	   offset % 4 != 0 {
		sdk_error(ctx, "GPUCompute fill range must be four-byte aligned and within limits")
		return false
	}
	return gpu_compute_status(
		ctx,
		gpu.fill_gpu_buffer(ctx.gpu_device, id, value, int(size), int(offset)),
	)
}

@(export)
Kinemium_GPUComputeCreatePipeline :: proc "c" (
	ctx: ^Context,
	source: cstring,
	binding_count: u32,
	kinds: [^]u32,
	out: ^u32,
) -> bool {
	context = odin_runtime.default_context()
	if out == nil || !gpu_compute_check(ctx) {return false}
	if source == nil ||
	   kinds == nil ||
	   binding_count == 0 ||
	   binding_count > gpu.MAX_CUSTOM_BINDINGS {
		sdk_error(ctx, "invalid GPUCompute shader source or binding layout")
		return false
	}
	text := string(source)
	if len(text) == 0 || len(text) > gpu.MAX_SHADER_SOURCE_BYTES {
		sdk_error(ctx, "GPUCompute shader source exceeds 1 MiB limit or is empty")
		return false
	}
	layout: gpu.Binding_Layout
	for index in 0 ..< int(binding_count) {
		if kinds[index] > 3 {
			sdk_error(ctx, "invalid GPUCompute descriptor binding kind")
			return false
		}
		layout[index] = gpu.Binding_Kind(kinds[index])
	}
	id, err := gpu.create_shader_pipeline(ctx.gpu_device, text, binding_count, layout)
	return gpu_compute_id(ctx, id, err, out)
}

@(export)
Kinemium_GPUComputeUsePipeline :: proc "c" (ctx: ^Context, id: u32) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	return gpu_compute_status(ctx, gpu.use_shader_pipeline(ctx.gpu_device, id))
}

@(export)
Kinemium_GPUComputeDestroyPipeline :: proc "c" (ctx: ^Context, id: u32) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	return gpu_compute_status(ctx, gpu.destroy_shader_pipeline(ctx.gpu_device, id))
}

@(export)
Kinemium_GPUComputeBindBuffer :: proc "c" (ctx: ^Context, binding, id: u32) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	return gpu_compute_status(ctx, gpu.bind_buffer(ctx.gpu_device, binding, id))
}

@(export)
Kinemium_GPUComputeUnbind :: proc "c" (ctx: ^Context, binding: u32) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	return gpu_compute_status(ctx, gpu.unbind(ctx.gpu_device, binding))
}

@(export)
Kinemium_GPUComputeSetPushConstants :: proc "c" (ctx: ^Context, data: rawptr, size: u64) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	if size > gpu.MAX_PUSH_CONSTANT_BYTES || size % 4 != 0 || (data == nil && size != 0) {
		sdk_error(
			ctx,
			"GPUCompute push constants must be 4-byte aligned and no more than 128 bytes",
		)
		return false
	}
	return gpu_compute_status(
		ctx,
		gpu.set_push_constants(ctx.gpu_device, gpu_compute_slice(data, size)),
	)
}

@(export)
Kinemium_GPUComputeDispatch :: proc "c" (ctx: ^Context, x, y, z: u32) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	return gpu_compute_status(ctx, gpu.dispatch_shader(ctx.gpu_device, x, y, z))
}

@(export)
Kinemium_GPUComputePoll :: proc "c" (ctx: ^Context, completed: ^bool) -> bool {
	context = odin_runtime.default_context()
	if completed == nil || !gpu_compute_check(ctx) {return false}
	done, err := gpu.poll_shader(ctx.gpu_device)
	if !gpu_compute_status(ctx, err) {return false}
	completed^ = done
	return true
}

@(export)
Kinemium_GPUComputeBeginCommands :: proc "c" (ctx: ^Context) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	return gpu_compute_status(ctx, gpu.begin_commands(ctx.gpu_device))
}

@(export)
Kinemium_GPUComputeSubmitCommands :: proc "c" (ctx: ^Context) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	return gpu_compute_status(ctx, gpu.submit_commands(ctx.gpu_device))
}

@(export)
Kinemium_GPUComputeCancelCommands :: proc "c" (ctx: ^Context) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	return gpu_compute_status(ctx, gpu.cancel_commands(ctx.gpu_device))
}

@(export)
Kinemium_GPUComputeBarrier :: proc "c" (ctx: ^Context) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	return gpu_compute_status(ctx, gpu.command_barrier(ctx.gpu_device))
}

@(export)
Kinemium_GPUComputeBeginTask :: proc "c" (ctx: ^Context) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	return gpu_compute_status(ctx, gpu.begin_task(ctx.gpu_device))
}

@(export)
Kinemium_GPUComputeSubmitTask :: proc "c" (ctx: ^Context, x, y, z: u32, out: ^u32) -> bool {
	context = odin_runtime.default_context()
	if out == nil || !gpu_compute_check(ctx) {return false}
	id, err := gpu.submit_task(ctx.gpu_device, x, y, z)
	return gpu_compute_id(ctx, id, err, out)
}

@(export)
Kinemium_GPUComputeSubmitTaskBatch :: proc "c" (ctx: ^Context, out: ^u32) -> bool {
	context = odin_runtime.default_context()
	if out == nil || !gpu_compute_check(ctx) {return false}
	id, err := gpu.submit_task_batch(ctx.gpu_device)
	return gpu_compute_id(ctx, id, err, out)
}

@(export)
Kinemium_GPUComputePollTask :: proc "c" (ctx: ^Context, id: u32, completed: ^bool) -> bool {
	context = odin_runtime.default_context()
	if completed == nil || !gpu_compute_check(ctx) {return false}
	done, err := gpu.poll_task(ctx.gpu_device, id)
	if !gpu_compute_status(ctx, err) {return false}
	completed^ = done
	return true
}

@(export)
Kinemium_GPUComputeGetTaskInfo :: proc "c" (
	ctx: ^Context,
	id: u32,
	out: ^SDK_GPU_Task_Info,
) -> bool {
	context = odin_runtime.default_context()
	if out == nil || !gpu_compute_check(ctx) {return false}
	info, err := gpu.get_task_info(ctx.gpu_device, id)
	if !gpu_compute_status(ctx, err) {return false}
	out^ = {info.queue, info.dispatch_count, info.complete}
	return true
}

@(export)
Kinemium_GPUComputePendingTaskCount :: proc "c" (ctx: ^Context) -> u32 {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return 0}
	return gpu.pending_task_count(ctx.gpu_device)
}
