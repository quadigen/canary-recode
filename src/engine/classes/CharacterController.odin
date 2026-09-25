package classes

import "core:math"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

CHARACTER_GRAVITY :: 196.2
CHARACTER_COYOTE_TIME :: 0.1

CharacterController_Class := Class_Info {
	name   = "CharacterController",
	parent = &Instance_Class,
}

CharacterController :: struct {
	using object: Object,

	walk_speed:      f32,
	jump_height:     f32,
	auto_rotate:     bool,
	max_slope_angle: f32,

	vertical_speed: f32,
	coyote_time:    f32,
	step_count:     u32,
}

character_controller_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	cc := new(CharacterController)
	cc.object = Object_Init(&CharacterController_Class, "CharacterController")
	cc.walk_speed = 16
	cc.jump_height = 7.2
	cc.auto_rotate = true
	cc.max_slope_angle = 89
	return &cc.object
}

character_controller_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^CharacterController)object)
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
		if child != nil && !child.destroyed && Is_A(child, "CharacterController") {return cast(^CharacterController)child}
	}
	return nil
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

Add_Child :: proc(registry: ^Registry, L: ^vm.State, parent: ^Object, class_name: string) -> ^Object {
	child := NewCharacterController(registry, L, class_name)
	if child == nil {return nil}
	Set_Parent(child, parent)
	return child
}

CharacterController_Build :: proc(registry: ^Registry, L: ^vm.State, model: ^CharacterModel) {
	if registry == nil || L == nil || model == nil || model.destroyed {return}
	if CharacterController_From_Model(model) != nil {return}
	controller := Add_Child(registry, L, &model.object, "CharacterController")
	if controller == nil {return}
	_ = Add_Child(registry, L, controller, "MovementController")
	_ = Add_Child(registry, L, controller, "GroundDetector")
	_ = Add_Child(registry, L, controller, "RotationController")
	_ = Add_Child(registry, L, controller, "StateMachine")
	_ = Add_Child(registry, L, controller, "CollisionController")
	_ = Add_Child(registry, L, &model.object, "Humanoid")
	motor := Add_Child(registry, L, &model.object, "CharacterMotor")
	_ = motor
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
		cc.walk_speed = max(f32(vm.ArgNumber(L, value_index)), 0)
	case "JumpHeight":
		cc.jump_height = max(f32(vm.ArgNumber(L, value_index)), 0)
	case "AutoRotate":
		cc.auto_rotate = vm.ArgBoolean(L, value_index)
	case "MaxSlopeAngle":
		cc.max_slope_angle = f32(vm.ArgNumber(L, value_index))
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
) -> (i32, bool) {
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
	}
	return 0, false
}

Register_CharacterController :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&CharacterController_Class,
		character_controller_construct,
		character_controller_destroy,
		get = character_controller_get,
		set = character_controller_set,
		namecall = character_controller_namecall,
		properties = []string{"WalkSpeed", "JumpHeight", "AutoRotate", "MaxSlopeAngle"},
	)
}