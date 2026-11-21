package gpucompute

Operation :: enum u32 {
	Add,
	Subtract,
	Multiply,
	MatrixMultiply,
	Divide,
	Min,
	Max,
	Abs,
	Negate,
	Sqrt,
}

MAX_ELEMENTS :: 4_000_000
MAX_MATRIX_PRODUCTS :: 256_000_000
MAX_CUSTOM_BINDINGS :: 16
MAX_CUSTOM_BUFFERS :: 64
MAX_CUSTOM_BUFFER_BYTES :: 64 * 1024 * 1024
MAX_CUSTOM_TOTAL_BYTES :: 256 * 1024 * 1024
MAX_PUSH_CONSTANT_BYTES :: 128
MAX_SHADER_SOURCE_BYTES :: 1024 * 1024

Binding_Kind :: enum {
	StorageBuffer,
	UniformBuffer,
	SampledTexture,
	StorageTexture,
}
Binding_Layout :: [MAX_CUSTOM_BINDINGS]Binding_Kind
MAX_CUSTOM_TEXTURES :: 64
MAX_CUSTOM_PIPELINES :: 32
MAX_BATCH_DISPATCHES :: 64
MAX_PARALLEL_TASKS :: 32
MAX_COMPUTE_QUEUES :: 4
Task_Info :: struct {
	queue, dispatch_count: u32,
	complete:              bool,
}
TASK_DEVICE_LOST :: "Vulkan task failed; GPUCompute device and resources were reset"

Texture_Format :: enum {
	RGBA8,
	RGBA8_SRGB,
	R8,
	RG8,
	R32F,
	RG32F,
	RGBA16F,
	RGBA32F,
	R32UI,
}
Texture_Dimension :: enum {
	D1,
	D2,
	D3,
	D2Array,
}
Texture_Desc :: struct {
	width, height, depth, layers:      u32,
	format:                            Texture_Format,
	dimension:                         Texture_Dimension,
	writable, nearest, clamp, mipmaps: bool,
}
Texture_Info :: struct {
	desc:       Texture_Desc,
	mip_levels: u32,
}
Image_Requirement :: struct {
	declared:  bool,
	dimension: Texture_Dimension,
	unsigned:  bool,
	format:    Texture_Format,
}
Image_Requirements :: [MAX_CUSTOM_BINDINGS]Image_Requirement

texture_pixel_bytes :: proc(format: Texture_Format) -> u64 {
	switch format {
	case .R8:
		return 1
	case .RG8:
		return 2
	case .RGBA8, .RGBA8_SRGB, .R32F, .R32UI:
		return 4
	case .RG32F, .RGBA16F:
		return 8
	case .RGBA32F:
		return 16
	}
	return 0
}
Capabilities :: struct {
	name:                                                                          [256]u8,
	buffer_size, uniform_size, texture_1d, texture_2d, texture_3d, texture_layers: u32,
	shared_memory, workgroup_invocations:                                          u32,
	workgroup_size, workgroup_count:                                               [3]u32,
	float64, int64, int16, storage_extended:                                       bool,
	compute_queues:                                                                u32,
	timeline_semaphores:                                                           bool,
}

Parameters :: struct {
	operation: Operation,
	rows:      u32,
	inner:     u32,
	columns:   u32,
}

when ODIN_OS != .Linux && ODIN_OS != .Windows {
	Device :: struct {}
	open :: proc(device: ^Device) -> string {return "GPUCompute is unavailable on this platform"}
	close :: proc(device: ^Device) {}
	dispatch :: proc(device: ^Device, params: Parameters, a, b: []u8) -> string {
		return "GPUCompute is unavailable on this platform"
	}
	poll :: proc(device: ^Device) -> (data: []u8, err: string) {
		return nil, "GPUCompute is unavailable on this platform"
	}
	clear_result :: proc(device: ^Device) {}
	CUSTOM_UNAVAILABLE :: "GPUCompute is unavailable on this platform"
	compile_shader :: proc(
		device: ^Device,
		source: string,
		count: u32,
		kinds: Binding_Layout = {},
	) -> string {return CUSTOM_UNAVAILABLE}
	get_capabilities :: proc(device: ^Device) -> (Capabilities, string) {return {},
			CUSTOM_UNAVAILABLE}
	create_texture_desc :: proc(
		device: ^Device,
		desc: Texture_Desc,
		pixels: []u8,
	) -> (
		u32,
		string,
	) {return 0, CUSTOM_UNAVAILABLE}
	get_texture_info :: proc(device: ^Device, id: u32) -> (Texture_Info, string) {return {},
			CUSTOM_UNAVAILABLE}
	create_texture :: proc(
		device: ^Device,
		width, height: u32,
		pixels: []u8,
		srgb: bool,
		writable: bool = false,
	) -> (
		u32,
		string,
	) {return 0, CUSTOM_UNAVAILABLE}
	bind_texture :: proc(device: ^Device, binding, id: u32) -> string {return CUSTOM_UNAVAILABLE}
	destroy_texture :: proc(device: ^Device, id: u32) -> string {return CUSTOM_UNAVAILABLE}
	copy_gpu_buffer :: proc(
		device: ^Device,
		source, destination: u32,
		size, source_offset, destination_offset: int,
	) -> string {return CUSTOM_UNAVAILABLE}
	fill_gpu_buffer :: proc(device: ^Device, id, value: u32, size, offset: int) -> string {return(
			CUSTOM_UNAVAILABLE \
		)}
	begin_task :: proc(device: ^Device) -> string {return CUSTOM_UNAVAILABLE}
	submit_task :: proc(device: ^Device, x, y, z: u32) -> (u32, string) {return 0,
			CUSTOM_UNAVAILABLE}
	submit_task_batch :: proc(device: ^Device) -> (u32, string) {return 0, CUSTOM_UNAVAILABLE}
	poll_task :: proc(device: ^Device, id: u32) -> (bool, string) {return false,
			CUSTOM_UNAVAILABLE}
	get_task_info :: proc(device: ^Device, id: u32) -> (Task_Info, string) {return {},
			CUSTOM_UNAVAILABLE}
	pending_task_count :: proc(device: ^Device) -> u32 {return 0}
	create_shader_pipeline :: proc(
		device: ^Device,
		source: string,
		count: u32,
		kinds: Binding_Layout,
	) -> (
		u32,
		string,
	) {return 0, CUSTOM_UNAVAILABLE}
	use_shader_pipeline :: proc(device: ^Device, id: u32) -> string {return CUSTOM_UNAVAILABLE}
	destroy_shader_pipeline :: proc(device: ^Device, id: u32) -> string {return CUSTOM_UNAVAILABLE}
	begin_commands :: proc(device: ^Device) -> string {return CUSTOM_UNAVAILABLE}
	submit_commands :: proc(device: ^Device) -> string {return CUSTOM_UNAVAILABLE}
	cancel_commands :: proc(device: ^Device) -> string {return CUSTOM_UNAVAILABLE}
	command_barrier :: proc(device: ^Device) -> string {return CUSTOM_UNAVAILABLE}
	unbind :: proc(device: ^Device, binding: u32) -> string {return CUSTOM_UNAVAILABLE}
	create_buffer :: proc(device: ^Device, size: int) -> (u32, string) {return 0,
			CUSTOM_UNAVAILABLE}
	write_buffer :: proc(device: ^Device, id: u32, data: []u8, offset: int) -> string {return(
			CUSTOM_UNAVAILABLE \
		)}
	read_buffer :: proc(
		device: ^Device,
		id: u32,
		offset, size: int,
	) -> (
		[]u8,
		string,
	) {return nil, CUSTOM_UNAVAILABLE}
	bind_buffer :: proc(device: ^Device, binding, id: u32) -> string {return CUSTOM_UNAVAILABLE}
	set_push_constants :: proc(device: ^Device, data: []u8) -> string {return CUSTOM_UNAVAILABLE}
	dispatch_shader :: proc(device: ^Device, x, y, z: u32) -> string {return CUSTOM_UNAVAILABLE}
	poll_shader :: proc(device: ^Device) -> (bool, string) {return false, CUSTOM_UNAVAILABLE}
	destroy_buffer :: proc(device: ^Device, id: u32) -> string {return CUSTOM_UNAVAILABLE}
}
