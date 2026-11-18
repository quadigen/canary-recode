package classes

import datatypes "../datatypes"
import enums "../enum"
import gpu "../gpucompute"
import vm "../vm"
import "core:math"

GPUCompute_Class := Class_Info {
	name = "GPUCompute",
	parent = &Instance_Class,
}

GPUCompute :: struct {
	using object: Object,
	device: gpu.Device,
}

GPUCompute_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	compute := new(GPUCompute)
	compute.object = Object_Init(&GPUCompute_Class, "GPUCompute")
	return &compute.object
}

GPUCompute_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	compute := cast(^GPUCompute)object
	gpu.close(&compute.device)
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
	return len(data) > 0 && len(data) <= gpu.MAX_ELEMENTS * size_of(f32) && len(data) % size_of(f32) == 0
}

gpu_compute_dispatch :: proc(L: ^vm.State, device: ^gpu.Device) -> string {
	params: gpu.Parameters
	switch vm.ArgString(L, 2) {
	case "Add": params.operation = .Add
	case "Subtract": params.operation = .Subtract
	case "Multiply": params.operation = .Multiply
	case "MatrixMultiply": params.operation = .MatrixMultiply
	case "Divide": params.operation = .Divide
	case "Min": params.operation = .Min
	case "Max": params.operation = .Max
	case "Abs": params.operation = .Abs
	case "Negate": params.operation = .Negate
	case "Sqrt": params.operation = .Sqrt
	case: return "unknown GPUCompute operation"
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
		if rows * inner != u64(len(a) / size_of(f32)) || inner * columns != u64(len(b) / size_of(f32)) {
			return "GPUCompute matrix dimensions do not match the input buffers"
		}
		if rows * columns > gpu.MAX_ELEMENTS || rows * inner * columns > gpu.MAX_MATRIX_PRODUCTS {
			return "GPUCompute matrix exceeds the output size or multiplication limit"
		}
		if rows > 65535 * 8 || columns > 65535 * 8 {return "GPUCompute matrix exceeds the dispatch dimensions"}
	} else {
		if !unary && len(a) != len(b) {return "GPUCompute element-wise inputs must have equal lengths"}
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
) -> (i32, bool) {
	compute := cast(^GPUCompute)object
	device := &compute.device
	switch method {
	case "IsSupported": return gpu_compute_result(L, gpu.open(device))
	case "Dispatch": return gpu_compute_result(L, gpu_compute_dispatch(L, device))
	case "Poll":
		data, err := gpu.poll(device)
		if data != nil {
			vm.PushBuffer(L, data)
			gpu.clear_result(device)
			return 1, true
		}
		return gpu_compute_nil_error(L, err)
	case "CompileShader":
		source := vm.ArgString(L, 2)
		count := gpu_compute_integer(L, 3, 1, gpu.MAX_CUSTOM_BINDINGS)
		return gpu_compute_result(L, gpu.compile_shader(device, source, count))
	case "CreateBuffer":
		size := gpu_compute_integer(L, 2, 4, gpu.MAX_CUSTOM_BUFFER_BYTES)
		id, err := gpu.create_buffer(device, int(size))
		if err != "" {return gpu_compute_nil_error(L, err)}
		vm.PushNumber(L, f64(id))
		return 1, true
	case "WriteBuffer":
		id := gpu_compute_buffer_id(L, 2)
		data := vm.ArgBuffer(L, 3)
		offset := 0
		if !vm.IsNoneOrNil(L, 4) {offset = int(gpu_compute_integer(L, 4, 0, gpu.MAX_CUSTOM_BUFFER_BYTES))}
		return gpu_compute_result(L, gpu.write_buffer(device, id, data, offset))
	case "ReadBuffer":
		id := gpu_compute_buffer_id(L, 2)
		offset := 0
		size := -1
		if !vm.IsNoneOrNil(L, 3) {offset = int(gpu_compute_integer(L, 3, 0, gpu.MAX_CUSTOM_BUFFER_BYTES))}
		if !vm.IsNoneOrNil(L, 4) {size = int(gpu_compute_integer(L, 4, 1, gpu.MAX_CUSTOM_BUFFER_BYTES))}
		data, err := gpu.read_buffer(device, id, offset, size)
		if err != "" {return gpu_compute_nil_error(L, err)}
		vm.PushBuffer(L, data)
		return 1, true
	case "BindBuffer":
		binding := gpu_compute_integer(L, 2, 0, gpu.MAX_CUSTOM_BINDINGS - 1)
		id := gpu_compute_buffer_id(L, 3)
		return gpu_compute_result(L, gpu.bind_buffer(device, binding, id))
	case "SetPushConstants": return gpu_compute_result(L, gpu.set_push_constants(device, vm.ArgBuffer(L, 2)))
	case "DispatchShader":
		x := gpu_compute_integer(L, 2, 1, f64(max(u32)))
		y, z: u32 = 1, 1
		if !vm.IsNoneOrNil(L, 3) {y = gpu_compute_integer(L, 3, 1, f64(max(u32)))}
		if !vm.IsNoneOrNil(L, 4) {z = gpu_compute_integer(L, 4, 1, f64(max(u32)))}
		return gpu_compute_result(L, gpu.dispatch_shader(device, x, y, z))
	case "PollShader":
		done, err := gpu.poll_shader(device)
		vm.PushBoolean(L, done)
		if err != "" {vm.PushString(L, err); return 2, true}
		return 1, true
	case "DestroyBuffer": return gpu_compute_result(L, gpu.destroy_buffer(device, gpu_compute_buffer_id(L, 2)))
	}
	return 0, false
}

Register_GPUCompute :: proc(registry: ^Registry) {
	Register_Class(
		registry, &GPUCompute_Class, GPUCompute_construct, GPUCompute_destroy,
		namecall = GPUCompute_namecall,
		methods = []string{
			"IsSupported", "Dispatch", "Poll", "CompileShader", "CreateBuffer", "WriteBuffer",
			"ReadBuffer", "BindBuffer", "SetPushConstants", "DispatchShader", "PollShader", "DestroyBuffer",
		},
	)
}
