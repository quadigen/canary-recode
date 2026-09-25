package services

// wire:service global="StarterPlayer"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

StarterPlayer_Class := classes.Class_Info{
	name   = "StarterPlayer",
	parent = &Service_Class,
}

StarterPlayer :: struct {
	using service: Service,

	auto_jump_enabled:       bool,
	character_walk_speed:    f64,
	character_jump_power:    f64,
	character_max_slope_angle: f64,
	load_character_appearance: bool,
}

starter_player_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(StarterPlayer)
	service.service = Service_Init(
		&StarterPlayer_Class,
		"StarterPlayer",
		data_model,
	)

	service.auto_jump_enabled = true
	service.character_walk_speed = 16
	service.character_jump_power = 53.1534
	service.character_max_slope_angle = 89
	service.load_character_appearance = true

	// The starter template containers exist as soon as the service does, on
	// every runtime, so places and scripts can author into them immediately
	// (mirroring Roblox's default hierarchy) instead of silently parenting to
	// nil on runtimes that have not prepared a local player yet. The class/name
	// pairs match what ClientScripts uses when preparing player containers:
	// "StarterPlayerScripts" is an instance name; its class is PlayerScripts.
	if model := cast(^DataModel)data_model; model != nil &&
	   model.registry != nil && model.registry.vm_state != nil {
		containers := [?]struct{class_name, name: string}{
			{"PlayerScripts", "StarterPlayerScripts"},
			{"StarterCharacterScripts", "StarterCharacterScripts"},
		}
		for container in containers {
			object, ok := classes.Push_New(
				model.registry.classes,
				model.registry.vm_state,
				container.class_name,
				false,
			)
			if !ok || object == nil {continue}
			classes.Set_Name(object, container.name)
			classes.Set_Parent(object, &service.object)
			vm.Pop(model.registry.vm_state.L)
		}
	}

	return &service.object
}

starter_player_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^StarterPlayer)object

	switch key {
	case "AutoJumpEnabled":
		vm.PushBoolean(L, service.auto_jump_enabled)

	case "CharacterWalkSpeed":
		vm.PushNumber(L, service.character_walk_speed)

	case "CharacterJumpPower":
		vm.PushNumber(L, service.character_jump_power)

	case "CharacterMaxSlopeAngle":
		vm.PushNumber(L, service.character_max_slope_angle)

	case "LoadCharacterAppearance":
		vm.PushBoolean(L, service.load_character_appearance)

	case:
		return false
	}

	return true
}

starter_player_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^StarterPlayer)object

	switch key {
	case "AutoJumpEnabled":
		service.auto_jump_enabled = vm.ArgBoolean(L, value_index)

	case "CharacterWalkSpeed":
		value := vm.ArgNumber(L, value_index)
		if value < 0 {
			_ = vm.RaiseError(L, "CharacterWalkSpeed must be >= 0")
			return true
		}
		service.character_walk_speed = value

	case "CharacterJumpPower":
		value := vm.ArgNumber(L, value_index)
		if value < 0 {
			_ = vm.RaiseError(L, "CharacterJumpPower must be >= 0")
			return true
		}
		service.character_jump_power = value

	case "CharacterMaxSlopeAngle":
		value := vm.ArgNumber(L, value_index)
		if value < 0 || value > 90 {
			_ = vm.RaiseError(
				L,
				"CharacterMaxSlopeAngle must be between 0 and 90",
			)
			return true
		}
		service.character_max_slope_angle = value

	case "LoadCharacterAppearance":
		service.load_character_appearance =
			vm.ArgBoolean(L, value_index)

	case:
		return false
	}

	return true
}

starter_player_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	classes.Object_Destroy(object)
	free(cast(^StarterPlayer)object)
}

Register_StarterPlayer_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&StarterPlayer_Class,
		starter_player_construct,
		starter_player_destroy,
		creatable = false,
		get = starter_player_get,
		set = starter_player_set,
	)
}

StarterPlayer_Apply_Character :: proc(
	data_model: ^DataModel,
	controller: ^classes.CharacterController,
) {
	if data_model == nil || controller == nil || controller.destroyed {return}
	starter := cast(^StarterPlayer)DataModel_Get_Service(data_model, "StarterPlayer")
	if starter == nil {return}
	controller.walk_speed = f32(starter.character_walk_speed)
	controller.max_slope_angle = f32(starter.character_max_slope_angle)
	controller.jump_height = f32(
		starter.character_jump_power *
		starter.character_jump_power /
		(2 * classes.CHARACTER_GRAVITY),
	)
}
