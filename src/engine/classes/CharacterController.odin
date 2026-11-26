package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

CHARACTER_GRAVITY :: 196.2
CHARACTER_COYOTE_TIME :: 0.1
CHARACTER_NOMINAL_MASS :: 10.0
CHARACTER_KNOCKBACK_DAMPING :: 6.0

CharacterController_Class := Class_Info {
	name   = "CharacterController",
	parent = &Instance_Class,
}

CharacterController :: struct {
	using object:      Object,
	walk_speed:        f32,
	jump_height:       f32,
	auto_rotate:       bool,
	max_slope_angle:   f32,
	gravity:           f32,
	coyote_duration:   f32,
	knockback_mass:    f32,
	knockback_damping: f32,
	max_fall_speed:    f32,
	jump_enabled:      bool,
	vertical_speed:    f32,
	coyote_time:       f32,
	step_count:        u32,
	knockback:         datatypes.Vector3,
	ragdoll:           bool,
}

character_controller_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	cc := new(CharacterController)
	cc.object = Object_Init(&CharacterController_Class, "CharacterController")
	cc.walk_speed = 16
	cc.jump_height = 7.2
	cc.auto_rotate = true
	cc.max_slope_angle = 89
	cc.gravity = 196.2
	cc.coyote_duration = 0.1
	cc.knockback_mass = 10
	cc.knockback_damping = 6
	cc.max_fall_speed = 0
	cc.jump_enabled = true
	return &cc.object
}

character_controller_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^CharacterController)object)
}

character_controller_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^CharacterController)source
	dst := cast(^CharacterController)destination
	dst.walk_speed = src.walk_speed
	dst.jump_height = src.jump_height
	dst.auto_rotate = src.auto_rotate
	dst.max_slope_angle = src.max_slope_angle
	dst.gravity = src.gravity
	dst.coyote_duration = src.coyote_duration
	dst.knockback_mass = src.knockback_mass
	dst.knockback_damping = src.knockback_damping
	dst.max_fall_speed = src.max_fall_speed
	dst.jump_enabled = src.jump_enabled
	dst.vertical_speed = 0
	dst.coyote_time = 0
	dst.step_count = 0
	dst.knockback = datatypes.Vector3{}
	dst.ragdoll = false
}

CharacterController_Root :: proc(cc: ^CharacterController) -> ^Part {
	if cc == nil || cc.destroyed || cc.object.parent == nil {return nil}
	if !Is_A(cc.object.parent, "CharacterModel") {return nil}
	return CharacterModel_Root(cast(^CharacterModel)cc.object.parent)
}

CharacterController_Find :: proc(cc: ^CharacterController, class_name: string) -> ^Object {
	if cc == nil {return nil}
	for child in cc.children {
		if child != nil && !child.destroyed && Is_A(child, class_name) {return child}
	}
	return nil
}

CharacterController_From_Model :: proc(model: ^CharacterModel) -> ^CharacterController {
	if model == nil {return nil}
	for child in model.children {
		if child != nil &&
		   !child.destroyed &&
		   Is_A(child, "CharacterController") {return cast(^CharacterController)child}
	}
	return nil
}

CharacterController_Apply_Impulse :: proc(
	cc: ^CharacterController,
	impulse: datatypes.Vector3,
) -> bool {
	if cc == nil || cc.destroyed || cc.ragdoll {return false}
	cc.knockback.x += impulse.x / f64(cc.knockback_mass)
	cc.knockback.z += impulse.z / f64(cc.knockback_mass)
	cc.vertical_speed += f32(impulse.y / f64(cc.knockback_mass))
	return true
}

Find_Child :: proc(obj: ^Object, class_name: string) -> ^Object {
	if obj == nil {return nil}
	for child in obj.children {
		if child != nil && !child.destroyed && Is_A(child, class_name) {return child}
	}
	return nil
}

NewCharacterController :: proc(registry: ^Registry, L: ^vm.State, class_name: string) -> ^Object {
	if registry == nil || L == nil {return nil}
	object, ok := Push_New(registry, registry.vm_state, class_name, false)
	if !ok || object == nil {return nil}
	vm.Pop(L)
	return object
}

Add_Child :: proc(
	registry: ^Registry,
	L: ^vm.State,
	parent: ^Object,
	class_name: string,
) -> ^Object {
	child := NewCharacterController(registry, L, class_name)
	if child == nil {return nil}
	Set_Parent(child, parent)
	return child
}

character_controller_ensure_child :: proc(
	registry: ^Registry,
	L: ^vm.State,
	parent: ^Object,
	class_name: string,
) -> ^Object {
	if existing := Find_Child(parent, class_name); existing != nil {return existing}
	return Add_Child(registry, L, parent, class_name)
}

CharacterController_Build :: proc(registry: ^Registry, L: ^vm.State, model: ^CharacterModel) {
	if registry == nil || L == nil || model == nil || model.destroyed {return}
	controller := CharacterController_From_Model(model)
	if controller == nil {
		controller = cast(^CharacterController)Add_Child(
			registry,
			L,
			&model.object,
			"CharacterController",
		)
	}
	if controller == nil {return}
	_ = character_controller_ensure_child(registry, L, &controller.object, "MovementController")
	_ = character_controller_ensure_child(registry, L, &controller.object, "GroundDetector")
	_ = character_controller_ensure_child(registry, L, &controller.object, "RotationController")
	_ = character_controller_ensure_child(registry, L, &controller.object, "StateMachine")
	_ = character_controller_ensure_child(registry, L, &controller.object, "CollisionController")

	_ = character_controller_ensure_child(
		registry,
		L,
		&controller.object,
		"CharacterPhysicsSolver",
	)
	if Find_Child(&model.object, "Humanoid") == nil {
		_ = Add_Child(registry, L, &model.object, "Humanoid")
	}
	if Find_Child(&model.object, "CharacterMotor") == nil {
		_ = Add_Child(registry, L, &model.object, "CharacterMotor")
	}
}

character_controller_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	cc := cast(^CharacterController)object
	switch key {
	case "WalkSpeed":
		vm.PushNumber(L, f64(cc.walk_speed))
	case "JumpHeight":
		vm.PushNumber(L, f64(cc.jump_height))
	case "AutoRotate":
		vm.PushBoolean(L, cc.auto_rotate)
	case "MaxSlopeAngle":
		vm.PushNumber(L, f64(cc.max_slope_angle))
	case "Gravity":
		vm.PushNumber(L, f64(cc.gravity))
	case "CoyoteTime":
		vm.PushNumber(L, f64(cc.coyote_duration))
	case "KnockbackMass":
		vm.PushNumber(L, f64(cc.knockback_mass))
	case "KnockbackDamping":
		vm.PushNumber(L, f64(cc.knockback_damping))
	case "MaxFallSpeed":
		vm.PushNumber(L, f64(cc.max_fall_speed))
	case "VerticalSpeed":
		vm.PushNumber(L, f64(cc.vertical_speed))
	case "JumpEnabled":
		vm.PushBoolean(L, cc.jump_enabled)
	case:
		return false
	}
	return true
}

character_controller_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	cc := cast(^CharacterController)object
	switch key {
	case "WalkSpeed":
		cc.walk_speed = f32(character_tuning_number(L, value_index, 0, 10000, f64(cc.walk_speed)))
	case "JumpHeight":
		cc.jump_height = f32(
			character_tuning_number(L, value_index, 0, 10000, f64(cc.jump_height)),
		)
	case "AutoRotate":
		cc.auto_rotate = vm.ArgBoolean(L, value_index)
	case "MaxSlopeAngle":
		cc.max_slope_angle = f32(
			character_tuning_number(L, value_index, 0, 89.9, f64(cc.max_slope_angle)),
		)
	case "Gravity":
		cc.gravity = f32(character_tuning_number(L, value_index, 0, 10000, f64(cc.gravity)))
	case "CoyoteTime":
		cc.coyote_duration = f32(
			character_tuning_number(L, value_index, 0, 5, f64(cc.coyote_duration)),
		)
	case "KnockbackMass":
		cc.knockback_mass = f32(
			character_tuning_number(L, value_index, 0.01, 100000, f64(cc.knockback_mass)),
		)
	case "KnockbackDamping":
		cc.knockback_damping = f32(
			character_tuning_number(L, value_index, 0, 1000, f64(cc.knockback_damping)),
		)
	case "MaxFallSpeed":
		cc.max_fall_speed = f32(
			character_tuning_number(L, value_index, 0, 10000, f64(cc.max_fall_speed)),
		)
	case "JumpEnabled":
		cc.jump_enabled = vm.ArgBoolean(L, value_index)
	case:
		return false
	}
	return true
}

character_controller_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	cc := cast(^CharacterController)object
	switch method {
	case "Move":
		movement := cast(^MovementController)CharacterController_Find(cc, "MovementController")
		if movement != nil {movement.input_direction = datatypes.Arg_Vector3(L, 2)}
		vm.PushBoolean(L, true)
		return 1, true
	case "Jump":
		movement := cast(^MovementController)CharacterController_Find(cc, "MovementController")
		MovementController_Queue_Jump(movement)
		vm.PushBoolean(L, true)
		return 1, true
	case "ApplyImpulse":
		impulse := datatypes.Arg_Vector3(L, 2)
		for value in ([3]f64{impulse.x, impulse.y, impulse.z}) {
			if math.is_nan(value) || math.is_inf(value) || math.abs(value) > 100000 {
				return vm.RaiseError(L, "character impulse components must be finite and bounded"),
					true
			}
		}
		vm.PushBoolean(L, CharacterController_Apply_Impulse(cc, impulse))
		return 1, true
	}
	return 0, false
}

Register_CharacterController :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&CharacterController_Class,
		character_controller_construct,
		character_controller_destroy,
		clone = character_controller_clone,
		get = character_controller_get,
		set = character_controller_set,
		namecall = character_controller_namecall,
		properties = []string {
			"WalkSpeed",
			"JumpHeight",
			"AutoRotate",
			"MaxSlopeAngle",
			"Gravity",
			"CoyoteTime",
			"KnockbackMass",
			"KnockbackDamping",
			"MaxFallSpeed",
			"VerticalSpeed",
			"JumpEnabled",
		},
		methods = []string{"Move", "Jump", "ApplyImpulse"},
	)
}

character_tuning_number :: proc(L: ^vm.State, index: int, lo, hi, previous: f64) -> f64 {
	value := vm.ArgNumber(L, index)
	if math.is_nan(value) || math.is_inf(value) {
		_ = vm.RaiseError(L, "character controller property must be finite")
		return previous
	}
	return clamp(value, lo, hi)
}
