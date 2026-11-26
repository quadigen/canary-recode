package main

import classes "../src/engine/classes"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

calls: int
mutate: bool
active_descriptor: ^classes.Class_Descriptor
late_object: ^classes.Object
skip_object: ^classes.Object
nested_registry: ^classes.Registry
nested_calls: int
reenter: bool

step_callback :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	calls += 1
	if reenter {
		reenter = false
		classes.Step(nested_registry, ctx.L, ctx.delta_time, phase = .Update)
	}
	if mutate {
		mutate = false
		skip_object.destroyed = true
		append(&active_descriptor.instances, late_object)
	}
}

nested_callback :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	nested_calls += 1
}

main :: proc() {
	v := vm.New()
	defer vm.Close(&v)
	registry := classes.Registry_Init()
	defer classes.Registry_Destroy(&registry)
	descriptor := new(classes.Class_Descriptor)
	descriptor._step = step_callback
	descriptor._step_phase = .Render_3D
	append(&registry.classes, descriptor)
	objects := make([]classes.Object, 4096)
	defer delete(objects)
	for &object in objects {append(&descriptor.instances, &object)}
	active_descriptor = descriptor
	skip_object = &objects[1]
	late: classes.Object
	late_object = &late
	mutate = true
	classes.Step(&registry, v.L, 0.01, phase = .Render_3D)
	assert(calls == 4095)
	calls = 0
	classes.Step(&registry, v.L, 0.01, phase = .Render_3D)
	assert(calls == 4096)
	classes.Step(&registry, v.L, 0.01, phase = .Update)
	assert(calls == 4096)
	for i in 0 ..< 5 {
		calls = 0
		start := time.tick_now()
		for _ in 0 ..< 3000 {classes.Step(&registry, v.L, 0.01, phase = .Render_3D)}
		ms := time.duration_milliseconds(time.tick_since(start))
		assert(calls == 4096 * 3000)
		fmt.printfln("CLASS_STEP_BENCH_MS %d %.3f", i, ms)
	}
	nested := new(classes.Class_Descriptor)
	nested._step = nested_callback
	nested._step_phase = .Update
	append(&registry.classes, nested)
	append(&nested.instances, late_object)
	nested_registry = &registry
	calls = 0
	reenter = true
	classes.Step(&registry, v.L, 0.01, phase = .Render_3D)
	assert(calls == 4096 && nested_calls == 1)
	classes.Step(&registry, v.L, 0.01, phase = .Update)
	assert(nested_calls == 2)
	fmt.println("CLASS_STEP_DISPATCH_SMOKE_PASSED")
}
