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
}
