package main

import classes "../src/engine/classes"
import native_api "../src/engine/native_api"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import odin_runtime "base:runtime"
import "core:fmt"

export_info: classes.Class_Info

create_probe :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	_ = renderer
	_ = data_model
	object := new(classes.Object)
	object^ = classes.Object_Init(&export_info, "NativeExportProbe")
	return object
}

destroy_probe :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	_ = renderer
	classes.Object_Destroy(object)
	free(object)
}

multiply_export :: proc "contextless" (call: ^classes.Class_Export_Context) -> i32 {
	context = odin_runtime.default_context()
	value := vm.ArgNumber(call.L, 2)
	vm.PushNumber(call.L, value * 3)
	return 1
}

main :: proc() {
	state := vm.New()
	environment: runtime.Environment
	runtime.Environment_Init(&environment, &state)
	export_info = classes.Class_Info {
		name   = "NativeExportProbe",
		parent = classes.Find_Class(&environment.classes, "Instance").info,
	}
	classes.Register_Class(
		&environment.classes,
		&export_info,
		create_probe,
		destroy_probe,
		exports = []classes.Class_Export{{name = "Multiply", handler = multiply_export}},
	)
	ctx := &environment.extensions.native_context
	handle := native_api.Kinemium_HandleCreateInstance(ctx, "NativeExportProbe")
	assert(handle != 0)
	assert(native_api.Kinemium_HandleGetExportCount(ctx, handle) == 1)
	assert(native_api.Kinemium_HandleHasExport(ctx, handle, "Multiply"))

	input := native_api.SDK_Value {
		kind   = .Number,
		number = 7,
	}
	output: native_api.SDK_Value
	assert(native_api.Kinemium_InvokeExport(ctx, handle, "Multiply", &input, 1, &output, nil, 0))
	assert(output.kind == .Number && output.number == 21)
	assert(native_api.Kinemium_Invoke(ctx, handle, "Multiply", &input, 1, &output, nil, 0))
	assert(output.kind == .Number && output.number == 21)
	assert(!native_api.Kinemium_InvokeExport(ctx, handle, "NotThere", nil, 0, &output, nil, 0))

	runtime.Environment_Destroy(&environment)
	vm.Close(&state)
	delete(export_info.ancestors)
	fmt.println("PASS native SDK direct export handlers and generic invocation")
}
