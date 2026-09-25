package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

Player_Class := classes.Class_Info {
	name   = "Player",
	parent = &classes.Instance_Class,
}
Players_Class := classes.Class_Info {
	name   = "Players",
	parent = &Service_Class,
}

Player :: struct {
	using object: classes.Object,
	user_id:      u32,
	character:    ^classes.CharacterModel,
	character_added: ^signals.Signal,
	character_removing: ^signals.Signal,
	player_scripts: ^classes.Object,
	player_gui:     ^classes.Object,
	prepared_character: ^classes.CharacterModel,
	move_direction: datatypes.Vector3,
	jump_queued: bool,
	input_sequence: u32,
	ground_y: f32,
	vertical_speed: f32,
	walk_speed: f32,
	jump_power: f32,
}

Players :: struct {
	using service:   Service,
	local_player:    ^Player,
	player_added:    ^signals.Signal,
	player_removing: ^signals.Signal,
}

player_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	player := new(Player)
	player.object = classes.Object_Init(&Player_Class, "Player")
	player.walk_speed = 16
	player.jump_power = 22
	return &player.object
}

player_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	player := cast(^Player)object
	if player.character_added != nil {signals.Destroy(player.character_added)}
	if player.character_removing != nil {signals.Destroy(player.character_removing)}
	classes.Object_Destroy(object)
	free(player)
}

Player_Set_Character :: proc(player: ^Player, L: ^vm.State, model: ^classes.CharacterModel) {
	if player == nil || player.character == model {return}
	previous := player.character
	if previous != nil && !previous.destroyed && player.character_removing != nil && L != nil {
		classes.Push_Object(L, &previous.object)
		signals.Fire(L, player.character_removing, 1)
		vm.Pop(L)
	}
	player.character = model
	if model != nil && !model.destroyed && player.character_added != nil && L != nil {
		classes.Push_Object(L, &model.object)
		signals.Fire(L, player.character_added, 1)
		vm.Pop(L)
	}
}

player_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	player := cast(^Player)object
	switch key {
	case "UserId":
		vm.PushNumber(L, f64(player.user_id))
	case "DisplayName":
		vm.PushString(L, player.name)
	case "WalkSpeed":
		vm.PushNumber(L, f64(player.walk_speed))
	case "JumpPower":
		vm.PushNumber(L, f64(player.jump_power))
	case "Character":
		if player.character == nil || player.character.destroyed {vm.PushNil(L)} else {classes.Push_Object(L, &player.character.object)}
	case "PlayerScripts":
		if player.player_scripts == nil || player.player_scripts.destroyed {
			scripts, _ := ClientScripts_Ensure_Player_Containers(
				player.signal_registry,
				L,
				player,
			)
			if scripts == nil {vm.PushNil(L); break}
		}
		classes.Push_Object(L, player.player_scripts)
	case "PlayerGui":
		if player.player_gui == nil || player.player_gui.destroyed {
			_, gui := ClientScripts_Ensure_Player_Containers(
				player.signal_registry,
				L,
				player,
			)
			if gui == nil {vm.PushNil(L); break}
		}
		classes.Push_Object(L, player.player_gui)
	case "CharacterAdded":
		if player.character_added == nil {player.character_added = signals.Create(player.signal_registry.signal_registry)}
		signals.Push(L, player.character_added)
	case "CharacterRemoving":
		if player.character_removing == nil {player.character_removing = signals.Create(player.signal_registry.signal_registry)}
		signals.Push(L, player.character_removing)
	case "LoadCharacter":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

player_set :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string, value_index: int) -> bool {
	player := cast(^Player)object
	switch key {
	case "WalkSpeed":
		value := vm.ArgNumber(L, value_index)
		if value < 0 || value > 100 {_ = vm.RaiseError(L, "WalkSpeed must be between 0 and 100"); return true}
		player.walk_speed = f32(value)
		if controller := player_controller(player); controller != nil {controller.walk_speed = f32(value)}
	case "JumpPower":
		value := vm.ArgNumber(L, value_index)
		if value < 0 || value > 100 {_ = vm.RaiseError(L, "JumpPower must be between 0 and 100"); return true}
		player.jump_power = f32(value)
		if controller := player_controller(player); controller != nil {
			controller.jump_height = f32(value * value / (2 * classes.CHARACTER_GRAVITY))
		}
	case:
		return false
	}
	return true
}

player_controller :: proc(player: ^Player) -> ^classes.CharacterController {
	if player == nil || player.character == nil || player.character.destroyed {return nil}
	return classes.CharacterController_From_Model(player.character)
}

player_namecall :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, method: string) -> (i32, bool) {
	if method != "LoadCharacter" {return 0, false}
	player := cast(^Player)object
	when ODIN_OS == .JS {
		vm.PushNil(L)
	} else {
		service := cast(^CharacterService)DataModel_Get_Service(cast(^DataModel)player.signal_registry.data_model, "CharacterService")
		model := CharacterService_Load(service, player)
		if model == nil {vm.PushNil(L)} else {classes.Push_Object(L, &model.object)}
	}
	return 1, true
}

players_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Players)
	service.service = Service_Init(&Players_Class, "Players", data_model)
	return &service.object
}

players_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^Players)object
	if service.player_added != nil {signals.Destroy(service.player_added)}
	if service.player_removing != nil {signals.Destroy(service.player_removing)}
	classes.Object_Destroy(object)
	free(service)
}

players_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^Players)object
	switch key {
	case "LocalPlayer":
		if service.local_player == nil ||
		   service.local_player.destroyed {vm.PushNil(L)} else {classes.Push_Object(L, &service.local_player.object)}
	case "PlayerAdded":
		if service.player_added ==
		   nil {service.player_added = signals.Create(service.signal_registry.signal_registry)}
		signals.Push(L, service.player_added)
	case "PlayerRemoving":
		if service.player_removing ==
		   nil {service.player_removing = signals.Create(service.signal_registry.signal_registry)}
		signals.Push(L, service.player_removing)
	case "GetPlayers":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

players_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^Players)object
	if method != "GetPlayers" {return 0, false}
	vm.NewTable(L, len(service.children))
	index := 1
	for child in service.children {
		if child == nil || child.destroyed || !classes.Is_A(child, "Player") {continue}
		classes.Push_Object(L, child)
		vm.SetArrayValue(L, -2, index)
		index += 1
	}
	return 1, true
}

Players_Add :: proc(service: ^Players, L: ^vm.State, id: u32, name: string) -> ^Player {
	if service == nil ||
	   service.data_model == nil ||
	   service.data_model.registry == nil {return nil}
	registry := service.data_model.registry.classes
	object, ok := classes.Push_New(registry, service.data_model.registry.vm_state, "Player", false)
	if !ok || object == nil {return nil}
	player := cast(^Player)object
	player.user_id = id
	classes.Set_Name(object, name)
	classes.Set_Parent(object, &service.object)
	vm.Pop(L)
	if service.player_added != nil {
		classes.Push_Object(L, object)
		signals.Fire(L, service.player_added, 1)
		vm.Pop(L)
	}
	return player
}

Players_Forget_Client_Container :: proc(object: ^classes.Object) {
	if object == nil || object.parent == nil || !classes.Is_A(object.parent, "Player") {
		return
	}
	player := cast(^Player)object.parent
	if player.player_scripts == object {
		player.player_scripts = nil
	}
	if player.player_gui == object {
		player.player_gui = nil
	}
}

Players_Remove :: proc(service: ^Players, L: ^vm.State, player: ^Player) {
	if service == nil || player == nil || player.destroyed {return}
	when ODIN_OS != .JS {
		character_service := cast(^CharacterService)DataModel_Get_Service(service.data_model, "CharacterService")
		if character_service != nil && player.character != nil {CharacterService_Unload(character_service, player)}
	}
	if service.player_removing != nil {
		classes.Push_Object(L, &player.object)
		signals.Fire(L, service.player_removing, 1)
		vm.Pop(L)
	}
	if service.local_player == player {service.local_player = nil}
	classes.Destroy_Hierarchy(&player.object)
}

Register_Players_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Player_Class,
		player_construct,
		player_destroy,
		creatable = false,
		get = player_get,
		set = player_set,
		namecall = player_namecall,
	)
	classes.Register_Class(
		registry,
		&Players_Class,
		players_construct,
		players_destroy,
		creatable = false,
		get = players_get,
		namecall = players_namecall,
	)
}
