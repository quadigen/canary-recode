package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:math"

Humanoid_Class := Class_Info {
	name   = "Humanoid",
	parent = &Instance_Class,
}

Humanoid :: struct {
	using object:   Object,
	health:         f32,
	max_health:     f32,
	health_changed: ^signals.Signal,
	walk_to_target: datatypes.Vector3,
	walk_to_active: bool,
	stuck_steps:    u32,
	walk_last_x:    f32,
	walk_last_z:    f32,
}

humanoid_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	h := new(Humanoid)
	h.object = Object_Init(&Humanoid_Class, "Humanoid")
	h.health = 100
	h.max_health = 100
	return &h.object
}

humanoid_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	h := cast(^Humanoid)object
	if h.health_changed != nil &&
	   h.object.signal_registry != nil &&
	   h.object.signal_registry.signal_registry != nil {
		signals.Destroy(h.health_changed)
		h.health_changed = nil
	}
	Object_Destroy(object)
	free(h)
}

Humanoid_Take_Damage :: proc(h: ^Humanoid, L: ^vm.State, amount: f32) {
	if h == nil {return}
	old := h.health
	h.health = clamp(h.health - amount, 0, h.max_health)
	if L != nil && h.health_changed != nil && h.health != old {
		vm.PushNumber(L, f64(h.health))
		signals.Fire(L, h.health_changed, 1)
		vm.Pop(L)
	}
}

humanoid_controller :: proc(h: ^Humanoid) -> ^CharacterController {
	if h == nil || h.destroyed || h.object.parent == nil {return nil}
	for child in h.object.parent.children {
		if child != nil && !child.destroyed && Is_A(child, "CharacterController") {
			return cast(^CharacterController)child
		}
	}
	return nil
}

Humanoid_StateMachine :: proc(h: ^Humanoid, cc: ^CharacterController) -> ^StateMachine {
	if h == nil ||
	   h.destroyed ||
	   h.object.parent == nil ||
	   !Is_A(h.object.parent, "CharacterModel") {
		return nil
	}
	return cast(^StateMachine)CharacterController_Find(cc, "StateMachine")
}

// Drives walk-to behavior and death; called from the controller tick.
Humanoid_Sync :: proc(h: ^Humanoid, cc: ^CharacterController, L: ^vm.State, dt: f32) {
	if h == nil || cc == nil {return}
	sm := Humanoid_StateMachine(h, cc)
	if sm != nil && sm.state == "Dead" {return}
	root := CharacterController_Root(cc)
	movement := cast(^MovementController)CharacterController_Find(cc, "MovementController")
	if h.walk_to_active && root != nil && movement != nil {
		dx := h.walk_to_target.x - root.cframe.x
		dz := h.walk_to_target.z - root.cframe.z
		dist := math.sqrt(dx * dx + dz * dz)
		if dist < 1.5 {
			h.walk_to_active = false
			h.stuck_steps = 0
			movement.input_direction = datatypes.Vector3{}
		} else {
			moved :=
				math.abs(root.cframe.x - h.walk_last_x) + math.abs(root.cframe.z - h.walk_last_z)
			if moved > 0.1 {
				h.stuck_steps = 0
			} else {
				h.stuck_steps += 1
			}
			h.walk_last_x = root.cframe.x
			h.walk_last_z = root.cframe.z
			if h.stuck_steps >= 120 {
				h.walk_to_active = false
				h.stuck_steps = 0
				movement.input_direction = datatypes.Vector3{}
			} else {
				if dist > 0.02 {
					movement.input_direction = datatypes.Vector3{dx / dist, 0, dz / dist}
				}
			}
		}
	}
	if h.health <= 0 && sm != nil {
		StateMachine_Set_State(sm, L, "Dead")
	}
}

humanoid_get :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	key: string,
) -> bool {
	h := cast(^Humanoid)object
	switch key {
	case "Health":
		vm.PushNumber(L, f64(h.health))
	case "MaxHealth":
		vm.PushNumber(L, f64(h.max_health))
	case "HealthChanged":
		if h.health_changed == nil &&
		   h.object.signal_registry != nil &&
		   h.object.signal_registry.signal_registry != nil {
			h.health_changed = signals.Create(h.object.signal_registry.signal_registry)
		}
		if h.health_changed == nil {return false}
		signals.Push(L, h.health_changed)
	case "HumanoidStateType":
		cc := humanoid_controller(h)
		sm := Humanoid_StateMachine(h, cc)
		if sm == nil {
			vm.PushNil(L)
		} else {
			vm.PushString(L, sm.state)
		}
	case "StateChanged":
		cc := humanoid_controller(h)
		sm := Humanoid_StateMachine(h, cc)
		if sm == nil {return false}
		if sm.state_changed == nil &&
		   sm.object.signal_registry != nil &&
		   sm.object.signal_registry.signal_registry != nil {
			sm.state_changed = signals.Create(sm.object.signal_registry.signal_registry)
		}
		if sm.state_changed == nil {return false}
		signals.Push(L, sm.state_changed)
	case "WalkSpeed":
		cc := humanoid_controller(h)
		if cc == nil {
			vm.PushNil(L)
		} else {
			vm.PushNumber(L, f64(cc.walk_speed))
		}
	case "JumpHeight":
		cc := humanoid_controller(h)
		if cc == nil {
			vm.PushNil(L)
		} else {
			vm.PushNumber(L, f64(cc.jump_height))
		}
	case "AutoRotate":
		cc := humanoid_controller(h)
		if cc == nil {
			vm.PushNil(L)
		} else {
			vm.PushBoolean(L, cc.auto_rotate)
		}
	case:
		return false
	}
	return true
}

humanoid_set :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	h := cast(^Humanoid)object
	switch key {
	case "Health":
		h.health = clamp(f32(vm.ArgNumber(L, value_index)), 0, h.max_health)
	case "MaxHealth":
		h.max_health = max(f32(vm.ArgNumber(L, value_index)), 0)
	case "WalkSpeed":
		cc := humanoid_controller(h)
		if cc != nil {cc.walk_speed = max(f32(vm.ArgNumber(L, value_index)), 0)}
	case "JumpHeight":
		cc := humanoid_controller(h)
		if cc != nil {cc.jump_height = max(f32(vm.ArgNumber(L, value_index)), 0)}
	case "AutoRotate":
		cc := humanoid_controller(h)
		if cc != nil {cc.auto_rotate = vm.ArgBoolean(L, value_index)}
	case:
		return false
	}
	return true
}

humanoid_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	h := cast(^Humanoid)object
	switch method {
	case "TakeDamage":
		Humanoid_Take_Damage(h, L, f32(vm.ArgNumber(L, 2)))
		return 0, true
	case "Move":
		movement := cast(^MovementController)CharacterController_Find(
			humanoid_controller(h),
			"MovementController",
		)
		if movement != nil {movement.input_direction = datatypes.Arg_Vector3(L, 2)}
		vm.PushBoolean(L, true)
		return 1, true
	case "Jump":
		movement := cast(^MovementController)CharacterController_Find(
			humanoid_controller(h),
			"MovementController",
		)
		MovementController_Queue_Jump(movement)
		vm.PushBoolean(L, true)
		return 1, true
	case "WalkTo", "MoveTo":
		h.walk_to_target = datatypes.Arg_Vector3(L, 2)
		h.walk_to_active = true
		h.stuck_steps = 0
		h.walk_last_x = 0
		h.walk_last_z = 0
		vm.PushBoolean(L, true)
		return 1, true
	case "GetState":
		sm := Humanoid_StateMachine(h, humanoid_controller(h))
		if sm == nil {
			vm.PushNil(L)
		} else {
			vm.PushString(L, sm.state)
		}
		return 1, true
	}
	return 0, false
}

Register_Humanoid :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Humanoid_Class,
		humanoid_construct,
		humanoid_destroy,
		get = humanoid_get,
		set = humanoid_set,
		namecall = humanoid_namecall,
		properties = []string{"Health", "MaxHealth"},
	)
}
