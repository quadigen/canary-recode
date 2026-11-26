package main
import gpu "../src/engine/gpucompute"
import "core:fmt"
main :: proc() {
	device: gpu.Device
	id, err := gpu.create_buffer(&device, 0)
	assert(id == 0 && err != "")
	id, err = gpu.create_buffer(&device, 3)
	assert(id == 0 && err != "")
	id, err = gpu.create_buffer(&device, gpu.MAX_CUSTOM_BUFFER_BYTES + 4)
	assert(id == 0 && err != "")
	id, err = gpu.create_texture_desc(
		&device,
		gpu.Texture_Desc {
			width = 0,
			height = 1,
			depth = 1,
			layers = 1,
			dimension = .D2,
			format = .RGBA8,
		},
		nil,
	)
	assert(id == 0 && err != "")
	bytes, read_err := gpu.read_buffer(&device, 12345, 0, 4)
	assert(bytes == nil && read_err != "")

	err = gpu.dispatch(
		&device,
		gpu.Parameters{operation = .Add, rows = max(u32), columns = 2},
		[]u8{0, 0, 0, 0},
		[]u8{0, 0, 0, 0},
	)
	assert(err != "", "overflowing output dimensions should fail before GPU setup")
	err = gpu.dispatch(
		&device,
		gpu.Parameters{operation = .Add, rows = 4, columns = 1},
		[]u8{0, 0, 0, 0},
		[]u8{0, 0, 0, 0},
	)
	assert(err != "", "input size mismatch should fail before GPU setup")
	err = gpu.dispatch(
		&device,
		gpu.Parameters{operation = .MatrixMultiply, rows = 2, inner = 2, columns = 2},
		[]u8{0, 0, 0, 0},
		[]u8{0, 0, 0, 0},
	)
	assert(err != "", "matrix size mismatch should fail before GPU setup")
	gpu.close(&device)
	fmt.println("GPU_COMPUTE_AUDIT_PASSED")
}
