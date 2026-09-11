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
	service.character_jump_power = 50
	service.character_max_slope_angle = 89
	service.load_character_appearance = true

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
