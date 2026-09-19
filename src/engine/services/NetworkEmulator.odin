package services

import "core:time"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

NetworkEmulator_Class := classes.Class_Info{name = "NetworkEmulator", parent = &classes.Instance_Class}

Network_Queued_Value :: struct {
	due: f64,
	reference: i32,
}

NetworkEmulator :: struct {
	using object: classes.Object,
	latency: f64,
	jitter: f64,
	loss: f64,
	reorder: f64,
	seed: u64,
	queue: [dynamic]Network_Queued_Value,
}

network_emulator_now :: proc() -> f64 {
	return f64(time.to_unix_nanoseconds(time.now())) / 1e9
}

network_emulator_random :: proc(emulator: ^NetworkEmulator) -> f64 {
	emulator.seed ~= emulator.seed << 13
	emulator.seed ~= emulator.seed >> 7
	emulator.seed ~= emulator.seed << 17
	return f64(emulator.seed & 0xFFFFFF) / f64(0x1000000)
}

network_emulator_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	emulator := new(NetworkEmulator)
	emulator.object = classes.Object_Init(&NetworkEmulator_Class, "NetworkEmulator")
	emulator.seed = u64(time.to_unix_nanoseconds(time.now())) | 1
	return &emulator.object
}

network_emulator_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	emulator := cast(^NetworkEmulator)object
	if emulator.signal_registry != nil && emulator.signal_registry.vm_state != nil && emulator.signal_registry.vm_state.L != nil {
		for queued in emulator.queue { vm.ReleaseValue(emulator.signal_registry.vm_state.L, queued.reference) }
	}
	delete(emulator.queue)
	classes.Object_Destroy(object)
	free(emulator)
}

network_emulator_get :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool {
	emulator := cast(^NetworkEmulator)object
	switch key {
	case "Latency": vm.PushNumber(L, emulator.latency)
	case "Jitter": vm.PushNumber(L, emulator.jitter)
	case "Loss": vm.PushNumber(L, emulator.loss)
	case "Reorder": vm.PushNumber(L, emulator.reorder)
	case "Send", "Drain": vm.PushUserdataMethod(L, key)
	case: return false
	}
	return true
}

network_emulator_namecall :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, method: string) -> (i32, bool) {
	emulator := cast(^NetworkEmulator)object
	switch method {
	case "Send":
		reliable := vm.ArgOptionalBoolean(L, 3, true)
		if !reliable && network_emulator_random(emulator) < emulator.loss { vm.PushBoolean(L, false); return 1, true }
		now := vm.ArgOptionalNumber(L, 4, network_emulator_now())
		jitter := (network_emulator_random(emulator) * 2 - 1) * emulator.jitter
		due := now + max(0, emulator.latency + jitter)
		if !reliable && network_emulator_random(emulator) < emulator.reorder {
			due += emulator.jitter * network_emulator_random(emulator)
		}
		vm.PushValue(L, 2)
		reference := vm.RetainValue(L)
		vm.Pop(L)
		append(&emulator.queue, Network_Queued_Value{due = due, reference = reference})
		vm.PushBoolean(L, true)
		return 1, true
	case "Drain":
		now := vm.ArgOptionalNumber(L, 2, network_emulator_now())
		vm.NewTable(L)
		index := 1
		for cursor := len(emulator.queue) - 1; cursor >= 0; cursor -= 1 {
			queued := emulator.queue[cursor]
			if queued.due > now { continue }
			vm.PushRegistryReference(L, queued.reference)
			vm.SetArrayValue(L, -2, index)
			index += 1
			vm.ReleaseValue(L, queued.reference)
			ordered_remove(&emulator.queue, cursor)
		}
		return 1, true
	}
	return 0, false
}

Register_NetworkEmulator_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(registry, &NetworkEmulator_Class, network_emulator_construct, network_emulator_destroy, creatable = false, get = network_emulator_get, namecall = network_emulator_namecall)
}
