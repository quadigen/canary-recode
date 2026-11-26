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
	using object:          Object,
	health:                f32,
	max_health:            f32,
	health_changed:        ^signals.Signal,
	died:                  ^signals.Signal,
	move_to_finished:      ^signals.Signal,
	state_enabled_changed: ^signals.Signal,
	walk_to_target:        datatypes.Vector3,
	walk_to_active:        bool,
	walk_elapsed:          f32,
	dead_notified:         bool,
	disabled_states:       [19]bool,
	animation_played:      ^signals.Signal,
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
	if h.health_changed != nil {signals.Destroy(h.health_changed)}
	if h.died != nil {signals.Destroy(h.died)}
	if h.move_to_finished != nil {signals.Destroy(h.move_to_finished)}
	if h.state_enabled_changed != nil {signals.Destroy(h.state_enabled_changed)}
	Object_Destroy(object)
	free(h)
}

humanoid_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Humanoid)source
	dst := cast(^Humanoid)destination
	dst.health = src.health
	dst.max_health = src.max_health
	dst.walk_to_target = src.walk_to_target
	dst.walk_to_active = false
	dst.walk_elapsed = 0
	dst.dead_notified = src.health <= 0
	dst.disabled_states = src.disabled_states
	dst.health_changed = nil
	dst.died = nil
	dst.move_to_finished = nil
	dst.state_enabled_changed = nil
}


humanoid_state_index :: proc(name: string) -> int {
	switch name {
	case "FallingDown":
		return 0
	case "Ragdoll":
		return 1
	case "GettingUp":
		return 2
	case "Jumping":
		return 3
	case "Swimming":
		return 4
	case "Falling", "Freefall":
		return 5
	case "Flying":
		return 6
	case "Landed":
		return 7
	case "Idle", "Running":
		return 8
	case "RunningNoPhysics":
		return 10
	case "StrafingNoPhysics":
		return 11
	case "Climbing":
		return 12
	case "Seated":
		return 13
	case "PlatformStanding":
		return 14
	case "Dead":
		return 15
	case "Physics":
		return 16
	case "None":
		return 18
	}
	return -1
}

Humanoid_State_Enabled_Name :: proc(h: ^Humanoid, state: string) -> bool {
	if h == nil || state == "Idle" {return true}
	index := humanoid_state_index(state)
	return index < 0 || !h.disabled_states[index]
}

humanoid_arg_state :: proc(L: ^vm.State, index: int, registry: ^enums.Registry) -> string {


	if vm.IsString(L, index) {return vm.ArgString(L, index)}
	if registry == nil {
		_ = vm.RaiseError(L, "Humanoid state requires Enum.HumanoidStateType")
		return ""
	}
	item := enums.Arg_Item(L, index, registry, "HumanoidStateType")
	return enums.Item_Name(item)
}

humanoid_signal :: proc(h: ^Humanoid, slot: ^^signals.Signal) -> ^signals.Signal {
	if slot^ == nil &&
	   h.object.signal_registry != nil &&
	   h.object.signal_registry.signal_registry != nil {
		slot^ = signals.Create(h.object.signal_registry.signal_registry)
	}
	return slot^
}

humanoid_finish_walk :: proc(h: ^Humanoid, L: ^vm.State, reached: bool) {
	if h == nil || !h.walk_to_active {return}
	h.walk_to_active = false
	h.walk_elapsed = 0
	if L != nil && h.move_to_finished != nil {
		vm.PushBoolean(L, reached)
		signals.Fire(L, h.move_to_finished, 1)
		vm.Pop(L)
	}
}

humanoid_set_health :: proc(h: ^Humanoid, L: ^vm.State, value: f32) {
	if h == nil {return}
	old := h.health
	h.health = clamp(value, 0, h.max_health)
	if h.health != old && L != nil && h.health_changed != nil {
		vm.PushNumber(L, f64(h.health))
		signals.Fire(L, h.health_changed, 1)
		vm.Pop(L)
	}
	if h.health > 0 {
		h.dead_notified = false
		return
	}
	if old > 0 {
		humanoid_finish_walk(h, L, false)
		cc := humanoid_controller(h)
		if sm := Humanoid_StateMachine(h, cc); sm != nil {
			StateMachine_Set_State(sm, L, "Dead")
		}
	}
	if !h.dead_notified {
		h.dead_notified = true
		if L != nil && h.died != nil {
			signals.Fire(L, h.died, 0)
		}
	}
}

Humanoid_Take_Damage :: proc(h: ^Humanoid, L: ^vm.State, amount: f32) {
	if h == nil {return}
	humanoid_set_health(h, L, h.health - amount)
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


Humanoid_Sync :: proc(h: ^Humanoid, cc: ^CharacterController, L: ^vm.State, dt: f32) {
	if h == nil || cc == nil {return}
	sm := Humanoid_StateMachine(h, cc)
	if h.health <= 0 {
		humanoid_set_health(h, L, h.health)
		if sm != nil {StateMachine_Set_State(sm, L, "Dead")}
	}
	if sm != nil && sm.state == "Dead" {
		humanoid_finish_walk(h, L, false)
		return
	}
	if !h.walk_to_active {return}
	root := CharacterController_Root(cc)
	movement := cast(^MovementController)CharacterController_Find(cc, "MovementController")
	h.walk_elapsed += max(dt, 0)
	if root != nil && movement != nil {
		dx := h.walk_to_target.x - root.cframe.x
		dz := h.walk_to_target.z - root.cframe.z
		dist := math.sqrt(dx * dx + dz * dz)
		if dist < 1.5 {
			movement.input_direction = datatypes.Vector3{}
			humanoid_finish_walk(h, L, true)
			return
		}
		if h.walk_elapsed < 8 {
			movement.input_direction = datatypes.Vector3{dx / dist, 0, dz / dist}
		}
	}
	if h.walk_elapsed >= 8 {
		if movement != nil {movement.input_direction = datatypes.Vector3{}}
		humanoid_finish_walk(h, L, false)
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
		if humanoid_signal(h, &h.health_changed) == nil {return false}
		signals.Push(L, h.health_changed)
	case "Died":
		if humanoid_signal(h, &h.died) == nil {return false}
		signals.Push(L, h.died)
	case "MoveToFinished":
		if humanoid_signal(h, &h.move_to_finished) == nil {return false}
		signals.Push(L, h.move_to_finished)
	case "StateEnabledChanged":
		if humanoid_signal(h, &h.state_enabled_changed) == nil {return false}
		signals.Push(L, h.state_enabled_changed)
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
		humanoid_set_health(h, L, f32(vm.ArgNumber(L, value_index)))
	case "MaxHealth":
		h.max_health = max(f32(vm.ArgNumber(L, value_index)), 0)
		if h.health > h.max_health {humanoid_set_health(h, L, h.max_health)}
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
	enum_registry: ^enums.Registry,
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
		h.walk_to_active = false
		h.walk_elapsed = 0
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
		h.walk_elapsed = 0
		vm.PushBoolean(L, true)
		return 1, true
	case "ChangeState":
		state := humanoid_arg_state(L, 2, enum_registry)
		if humanoid_state_index(state) < 0 {
			return vm.RaiseError(L, "unknown Humanoid state"), true
		}
		if !Humanoid_State_Enabled_Name(h, state) {return 0, true}
		sm := Humanoid_StateMachine(h, humanoid_controller(h))
		if sm != nil {StateMachine_Set_State(sm, L, state)}
		return 0, true
	case "GetStateEnabled":
		state := humanoid_arg_state(L, 2, enum_registry)
		if humanoid_state_index(state) < 0 {
			return vm.RaiseError(L, "unknown Humanoid state"), true
		}
		vm.PushBoolean(L, Humanoid_State_Enabled_Name(h, state))
		return 1, true
	case "SetStateEnabled":
		state := humanoid_arg_state(L, 2, enum_registry)
		index := humanoid_state_index(state)
		if index < 0 {return vm.RaiseError(L, "unknown Humanoid state"), true}
		enabled := vm.ArgBoolean(L, 3)
		if h.disabled_states[index] == !enabled {return 0, true}
		h.disabled_states[index] = !enabled
		if index == 3 {
			if cc := humanoid_controller(h); cc != nil {cc.jump_enabled = enabled}
		}
		if L != nil && h.state_enabled_changed != nil {
			if enum_registry != nil {
				_ = enums.Push_Item_By_Value(L, enum_registry, "HumanoidStateType", i64(index))
			} else {
				vm.PushString(L, state)
			}
			vm.PushBoolean(L, enabled)
			signals.Fire(L, h.state_enabled_changed, 2)
			vm.Pop(L, 2)
		}
		return 0, true
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
		clone = humanoid_clone,
		get = humanoid_get,
		set = humanoid_set,
		namecall = humanoid_namecall,
		properties = []string{"Health", "MaxHealth"},
		methods = []string {
			"TakeDamage",
			"Move",
			"Jump",
			"WalkTo",
			"MoveTo",
			"GetState",
			"ChangeState",
			"GetStateEnabled",
			"SetStateEnabled",
		},
		events = []string {
			"HealthChanged",
			"StateChanged",
			"Died",
			"MoveToFinished",
			"StateEnabledChanged",
		},
	)
}
