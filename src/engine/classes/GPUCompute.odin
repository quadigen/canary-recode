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
	using object: Object,
	device:       gpu.Device,
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

gpu_compute_dimension :: proc(L: ^vm.State, index: int) -> u32 {
	value := vm.ArgNumber(L, index)
	if !(value >= 1 && value <= gpu.MAX_ELEMENTS) || math.floor(value) != value {
		_ = vm.RaiseError(
			L,
			"matrix dimensions must be positive integers within GPUCompute limits",
		)
		return 0
	}
	return u32(value)
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
		if rows > 65535 * 8 || columns > 65535 * 8 {
			return "GPUCompute matrix exceeds the dispatch dimensions"
		}
	} else {
		if !unary && len(a) != len(b) {
			return "GPUCompute element-wise inputs must have equal lengths"
		}
		params.rows = u32(len(a) / size_of(f32))
		params.columns = 1
	}
	return gpu.dispatch(device, params, a, b)
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
	switch method {
	case "IsSupported", "Dispatch":
		err :=
			gpu.open(&compute.device) if method == "IsSupported" else gpu_compute_dispatch(L, &compute.device)
		vm.PushBoolean(L, err == "")
		if err != "" {
			vm.PushString(L, err)
			return 2, true
		}
		return 1, true
	case "Poll":
		data, err := gpu.poll(&compute.device)
		if data != nil {
			vm.PushBuffer(L, data)
			gpu.clear_result(&compute.device)
			return 1, true
		}
		vm.PushNil(L)
		if err != "" {
			vm.PushString(L, err)
			return 2, true
		}
		return 1, true
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
		methods = []string{"IsSupported", "Dispatch", "Poll"},
	)
}
