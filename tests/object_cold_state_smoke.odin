package main

import classes "../src/engine/classes"
import runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

Probe_Class_A := classes.Class_Info {
	name   = "OptimizationProbe",
	parent = &classes.Instance_Class,
}
Probe_Class_B := classes.Class_Info {
	name   = "OptimizationProbe",
	parent = &classes.Instance_Class,
}

probe_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	obj := new(classes.Object)
	obj^ = classes.Object_Init(&Probe_Class_A, "OptimizationProbe")
	return obj
}

probe_destroy :: proc(obj: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(obj)
	free(obj)
}

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(v, source, "object_cold_state_smoke")
	if !ok {fmt.eprintln(err); delete(err); panic("cold state smoke")}
}

global_object :: proc(v: ^vm.VM, name: string) -> ^classes.Object {
	vm.GetGlobal(v.L, name)
	obj := classes.Object_From_Argument(v.L, -1)
	vm.Pop(v.L)
	assert(obj != nil)
	return obj
}

main :: proc() {
	v := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &v)
	defer {vm.Close(&v); runtime.Environment_Destroy(&env)}
	reg := &env.classes
	classes.Register_Class(reg, &Probe_Class_A, probe_construct, probe_destroy)
	first := classes.Find_Class(reg, "OptimizationProbe")
	assert(first != nil && first.info == &Probe_Class_A)
	classes.Register_Class(reg, &Probe_Class_B, probe_construct, probe_destroy)
	assert(classes.Find_Class(reg, "OptimizationProbe") == first)
	classes.Unregister_Class(reg, first)
	second := classes.Find_Class(reg, "OptimizationProbe")
	assert(second != nil && second.info == &Probe_Class_B)
	classes.Unregister_Class(reg, second)
	assert(classes.Find_Class(reg, "OptimizationProbe") == nil)

	run(
		&v,
		`
source = Instance.new("Folder")
receiver = Instance.new("Folder")
receiver:SetAttribute("LocalOnly", "yes")
receiver:AddTag("LocalTag")
probe = Instance.new("Model")
`,
	)
	source := global_object(&v, "source")
	receiver := global_object(&v, "receiver")
	probe := global_object(&v, "probe")
	assert(source.server_metadata == nil && receiver.server_metadata == nil)
	assert(probe.imported_values == nil)
	empty: [8]u8
	assert(services.replication_apply_metadata(v.L, reg, receiver, empty[:]))
	assert(receiver.server_metadata == nil)
	run(
		&v,
		`
source:SetAttribute("Remote", 42)
source:AddTag("RemoteTag")
oldInput = probe.ModelStreamingMode
probe.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
clone = probe:Clone()
assert(clone.ModelStreamingMode == Enum.ModelStreamingMode.Atomic)
`,
	)
	assert(probe.imported_values != nil)
	encoded, ok := services.replication_encode_metadata(v.L, reg, source)
	assert(ok)
	assert(services.replication_apply_metadata(v.L, reg, receiver, encoded[:]))
	delete(encoded)
	assert(receiver.server_metadata != nil)
	run(
		&v,
		`
assert(receiver:GetAttribute("Remote") == 42 and receiver:HasTag("RemoteTag"))
probe.ModelStreamingMode = oldInput
assert(probe.ModelStreamingMode == oldInput)
`,
	)
	assert(probe.imported_values == nil)
	assert(services.replication_apply_metadata(v.L, reg, receiver, empty[:]))
	run(
		&v,
		`
assert(receiver:GetAttribute("Remote") == nil and not receiver:HasTag("RemoteTag"))
assert(receiver:GetAttribute("LocalOnly") == "yes" and receiver:HasTag("LocalTag"))
source:Destroy()
receiver:Destroy()
probe:Destroy()
clone:Destroy()
`,
	)
	fmt.println("OBJECT_COLD_STATE_SMOKE_PASSED")
}
