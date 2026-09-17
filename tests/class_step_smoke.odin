package main

import "core:fmt"
import classes "../src/engine/classes"
import datatypes "../src/engine/datatypes"
import enums "../src/engine/enum"
import vm "../src/engine/vm"

Step_Probe_Class := classes.Class_Info{name = "StepProbe", parent = &classes.Instance_Class}
expected_renderer: ^classes.Renderer_Object
construct_saw_renderer: bool
destroy_saw_renderer: bool

Step_Probe :: struct {
	using object: classes.Object,
	step_count: i32,
	last_delta: f32,
}

step_probe_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	construct_saw_renderer = renderer == expected_renderer
	probe := new(Step_Probe)
	probe.object = classes.Object_Init(&Step_Probe_Class, "StepProbe")
	return &probe.object
}

step_probe_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	destroy_saw_renderer = renderer == expected_renderer
	classes.Object_Destroy(object)
	free(cast(^Step_Probe)object)
}

step_probe_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	probe := cast(^Step_Probe)object
	switch key {
	case "StepCount": vm.PushNumber(L, f64(probe.step_count))
	case "LastDelta": vm.PushNumber(L, f64(probe.last_delta))
	case: return false
	}
	return true
}

step_probe_step :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	probe := cast(^Step_Probe)object
	probe.step_count += 1
	probe.last_delta = ctx.delta_time
}

run_script :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "class_step_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("class step smoke failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	datatype_registry: datatypes.Registry
	datatypes.Registry_Init(&datatype_registry)
	enum_registry: enums.Registry
	enums.Registry_Init(&enum_registry)
	renderer_object: classes.Renderer_Object
	expected_renderer = &renderer_object
	signal_registry := classes.Registry_Init(&datatype_registry, &enum_registry, &renderer_object)
	classes.Register_Default_Classes(&signal_registry)
	classes.Register_Class(
		&signal_registry,
		&Step_Probe_Class,
		step_probe_construct,
		step_probe_destroy,
		get = step_probe_get,
		_step = step_probe_step,
	)
	classes.Install_Instance_Library(&signal_registry, &script_vm)

	run_script(&script_vm, `
activeProbe = Instance.new("StepProbe")
destroyedProbe = Instance.new("StepProbe")
destroyedProbe:Destroy()
`)
	classes.Step(&signal_registry, script_vm.L, 0.25)
	classes.Step(&signal_registry, script_vm.L, 0.5)
	run_script(&script_vm, `
assert(activeProbe.StepCount == 2)
assert(math.abs(activeProbe.LastDelta - 0.5) < 1e-6)
assert(destroyedProbe.StepCount == 0)
activeProbe:Destroy()
`)
	assert(construct_saw_renderer)
	classes.Step(&signal_registry, script_vm.L, 1.0)
	run_script(&script_vm, `assert(activeProbe.StepCount == 2)`)

	vm.Close(&script_vm)
	assert(destroy_saw_renderer)
	classes.Registry_Destroy(&signal_registry)
	enums.Registry_Destroy(&enum_registry)
	fmt.println("CLASS_STEP_SMOKE_PASSED")
}
