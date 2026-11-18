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
	compile_shader :: proc(device: ^Device, source: string, count: u32) -> string {return CUSTOM_UNAVAILABLE}
	create_buffer :: proc(device: ^Device, size: int) -> (u32, string) {return 0, CUSTOM_UNAVAILABLE}
	write_buffer :: proc(device: ^Device, id: u32, data: []u8, offset: int) -> string {return CUSTOM_UNAVAILABLE}
	read_buffer :: proc(device: ^Device, id: u32, offset, size: int) -> ([]u8, string) {return nil, CUSTOM_UNAVAILABLE}
	bind_buffer :: proc(device: ^Device, binding, id: u32) -> string {return CUSTOM_UNAVAILABLE}
	set_push_constants :: proc(device: ^Device, data: []u8) -> string {return CUSTOM_UNAVAILABLE}
	dispatch_shader :: proc(device: ^Device, x, y, z: u32) -> string {return CUSTOM_UNAVAILABLE}
	poll_shader :: proc(device: ^Device) -> (bool, string) {return false, CUSTOM_UNAVAILABLE}
	destroy_buffer :: proc(device: ^Device, id: u32) -> string {return CUSTOM_UNAVAILABLE}
}
