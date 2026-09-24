package classes

import "core:strings"
import enums "../enum"
import signals "../signals"
import datatypes "../datatypes"
import vm "../vm"

StateMachine_Class := Class_Info {
	name   = "StateMachine",
	parent = &Instance_Class,
}

StateMachine :: struct {
	using object: Object,

	state:         string,
	state_alloc:   bool,
	state_changed: ^signals.Signal,
}

state_machine_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	sm := new(StateMachine)
	sm.object = Object_Init(&StateMachine_Class, "StateMachine")
	sm.state = strings.clone("Idle")
	sm.state_alloc = true
	return &sm.object
}

state_machine_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	sm := cast(^StateMachine)object
	if sm.state_changed != nil {
		signals.Destroy(sm.state_changed)
		sm.state_changed = nil
	}
	if sm.state_alloc { delete(sm.state) }
	Object_Destroy(object)
	free(sm)
}

// StateMachine_Set_State transitions to `next`, firing StateChanged(old, new)
// when the state actually changes. Returns whether the state changed.
StateMachine_Set_State :: proc(sm: ^StateMachine, L: ^vm.State, next: string) -> bool {
	if sm == nil || sm.destroyed || sm.state == next { return false }
	old := sm.state
	sm.state = strings.clone(next)
	sm.state_alloc = true
	if L != nil && sm.state_changed != nil {
		vm.PushString(L, old)
		vm.PushString(L, sm.state)
		signals.Fire(L, sm.state_changed, 2)
		vm.Pop(L, 2)
	}
	delete(old)
	return true
}

state_machine_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	sm := cast(^StateMachine)object
	switch key {
	case "StateChanged":
		if sm.state_changed == nil &&
		   sm.object.signal_registry != nil &&
		   sm.object.signal_registry.signal_registry != nil {
			sm.state_changed = signals.Create(sm.object.signal_registry.signal_registry)
		}
		if sm.state_changed == nil { return false }
		signals.Push(L, sm.state_changed)
	case:
		return false
	}
	return true
}

state_machine_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	sm := cast(^StateMachine)object
	switch method {
	case "GetState":
		vm.PushString(L, sm.state)
		return 1, true
	case "SetState":
		next := vm.ArgString(L, 2)
		changed := StateMachine_Set_State(sm, L, next)
		vm.PushBoolean(L, changed)
		return 1, true
	}
	return 0, false
}

Register_StateMachine :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&StateMachine_Class,
		state_machine_construct,
		state_machine_destroy,
		get = state_machine_get,
		namecall = state_machine_namecall,
	)
}
