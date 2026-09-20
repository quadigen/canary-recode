#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

CharacterService_Class := classes.Class_Info {
	name   = "CharacterService",
	parent = &Service_Class,
}

CharacterService :: struct {
	using service:          Service,
	move_direction:         datatypes.Vector3,
	jump_queued:            bool,
	local_jump_pending:     bool,
	input_sequence:         u32,
	last_ack:               u32,
	authoritative_received: bool,
	predictions:            [dynamic]Character_Prediction,
}

Character_Prediction :: struct {
	sequence: u32,
	position: datatypes.Vector3,
}

character_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(CharacterService)
	service.service = Service_Init(&CharacterService_Class, "CharacterService", data_model)
	return &service.object
}

character_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	delete((cast(^CharacterService)object).predictions)
	classes.Object_Destroy(object)
	free(cast(^CharacterService)object)
}

character_service_part :: proc(
	service: ^CharacterService,
	model: ^classes.CharacterModel,
	name: string,
	size, offset: datatypes.Vector3,
	color: datatypes.Color3,
	visible: bool,
) -> ^classes.Part {
	object, ok := classes.Push_New(
		service.data_model.registry.classes,
		service.data_model.registry.vm_state,
		"Part",
		false,
	)
	if !ok || object == nil {return nil}
	part := cast(^classes.Part)object
	classes.Set_Name(object, name)
	part.size = size
	part.color = color
	part.anchored = true
	part.can_collide = false
	part.transparency = visible ? 0 : 1
	part.cframe.x = offset.x
	part.cframe.y = offset.y
	part.cframe.z = offset.z
	part.position = offset
	classes.Set_Parent(object, &model.object)
	vm.Pop(service.data_model.registry.vm_state.L)
	return part
}

CharacterService_Load :: proc(
	service: ^CharacterService,
	player: ^Player,
) -> ^classes.CharacterModel {
	if service == nil ||
	   player == nil ||
	   player.destroyed ||
	   service.data_model == nil ||
	   service.data_model.registry == nil {return nil}
	if player.character != nil && !player.character.destroyed {return player.character}
	replicator := cast(^ReplicatorService)DataModel_Get_Service(
		service.data_model,
		"ReplicatorService",
	)
	if replicator == nil || replicator.mode != .Server {return nil}
	workspace := DataModel_Get_Service(service.data_model, "Workspace")
	if workspace == nil {return nil}
	object, ok := classes.Push_New(
		service.data_model.registry.classes,
		service.data_model.registry.vm_state,
		"CharacterModel",
		false,
	)
	if !ok || object == nil {return nil}
	model := cast(^classes.CharacterModel)object
	model.owner_user_id = player.user_id
	classes.Set_Name(object, player.name)
	spawn := datatypes.Vector3{0, 5, 0}
	for child in workspace.children {
		if child != nil &&
		   !child.destroyed &&
		   child.name == "Spawn" &&
		   classes.Is_A(child, "Part") {
			part := cast(^classes.Part)child
			spawn = datatypes.Vector3{part.cframe.x, part.cframe.y + 4, part.cframe.z}
			break
		}
	}
	yellow := datatypes.Color3 {
		R = 0.96,
		G = 0.8,
		B = 0.08,
	}
	blue := datatypes.Color3 {
		R = 0.08,
		G = 0.3,
		B = 0.85,
	}
	gray := datatypes.Color3 {
		R = 0.16,
		G = 0.16,
		B = 0.18,
	}
	_ = character_service_part(
		service,
		model,
		"HumanoidRootPart",
		datatypes.Vector3{2, 2, 1},
		spawn,
		gray,
		false,
	)
	_ = character_service_part(
		service,
		model,
		"Torso",
		datatypes.Vector3{2, 2, 1},
		datatypes.Vector3{spawn.x, spawn.y, spawn.z},
		blue,
		true,
	)
	_ = character_service_part(
		service,
		model,
		"Head",
		datatypes.Vector3{1.2, 1.2, 1.2},
		datatypes.Vector3{spawn.x, spawn.y + 1.7, spawn.z},
		yellow,
		true,
	)
	_ = character_service_part(
		service,
		model,
		"LeftArm",
		datatypes.Vector3{0.7, 2, 0.8},
		datatypes.Vector3{spawn.x - 1.4, spawn.y, spawn.z},
		yellow,
		true,
	)
	_ = character_service_part(
		service,
		model,
		"RightArm",
		datatypes.Vector3{0.7, 2, 0.8},
		datatypes.Vector3{spawn.x + 1.4, spawn.y, spawn.z},
		yellow,
		true,
	)
	_ = character_service_part(
		service,
		model,
		"LeftLeg",
		datatypes.Vector3{0.8, 2, 0.8},
		datatypes.Vector3{spawn.x - 0.55, spawn.y - 2, spawn.z},
		gray,
		true,
	)
	_ = character_service_part(
		service,
		model,
		"RightLeg",
		datatypes.Vector3{0.8, 2, 0.8},
		datatypes.Vector3{spawn.x + 0.55, spawn.y - 2, spawn.z},
		gray,
		true,
	)
	classes.Set_Parent(object, workspace)
	vm.Pop(service.data_model.registry.vm_state.L)
	Player_Set_Character(player, service.data_model.registry.vm_state.L, model)
	player.ground_y = spawn.y
	player.vertical_speed = 0
	_ = replication_register(replicator, object)
	root := classes.CharacterModel_Root(model)
	if root != nil {
		id := replication_register(replicator, &root.object)
		entity := replication_entity_by_id(replicator, id)
		if entity != nil {entity.owner_id = player.user_id}
	}
	return model
}

CharacterService_Unload :: proc(service: ^CharacterService, player: ^Player) -> bool {
	if service == nil || player == nil || player.character == nil {return false}
	model := player.character
	Player_Set_Character(player, service.data_model.registry.vm_state.L, nil)
	if !model.destroyed {classes.Destroy_Hierarchy(&model.object)}
	return true
}

CharacterService_Bind :: proc(
	data_model: ^DataModel,
	model: ^classes.CharacterModel,
	L: ^vm.State,
) {
	if data_model == nil || model == nil || model.owner_user_id == 0 {return}
	players := cast(^Players)DataModel_Get_Service(data_model, "Players")
	if players == nil {return}
	player: ^Player
	for child in players.children {
		if child != nil &&
		   !child.destroyed &&
		   classes.Is_A(child, "Player") &&
		   (cast(^Player)child).user_id == model.owner_user_id {
			player = cast(^Player)child
			break
		}
	}
	if player == nil {player = Players_Add(players, L, model.owner_user_id, model.name)}
	if player != nil {
		Player_Set_Character(player, L, model)
		root := classes.CharacterModel_Root(model)
		if root != nil {player.ground_y = root.cframe.y}
		if player == players.local_player {
			workspace := cast(^Workspace)DataModel_Get_Service(data_model, "Workspace")
			if workspace != nil && workspace.current_camera != nil {
				workspace.current_camera.CameraSubject = &model.object
			}
			service := cast(^CharacterService)Ensure_Service(
				data_model.registry,
				"CharacterService",
			)
			if service != nil {
				clear(&service.predictions)
				service.last_ack = 0
				service.authoritative_received = false
			}
		}
	}
}

CharacterService_Unbind :: proc(
	data_model: ^DataModel,
	model: ^classes.CharacterModel,
	L: ^vm.State,
) {
	if data_model == nil || model == nil {return}
	players := cast(^Players)DataModel_Get_Service(data_model, "Players")
	if players == nil {return}
	for child in players.children {
		if child == nil || child.destroyed || !classes.Is_A(child, "Player") {continue}
		player := cast(^Player)child
		if player.character != model {continue}
		if player == players.local_player {
			workspace := cast(^Workspace)DataModel_Get_Service(data_model, "Workspace")
			if workspace != nil &&
			   workspace.current_camera != nil &&
			   workspace.current_camera.CameraSubject == &model.object {
				workspace.current_camera.CameraSubject = nil
			}
		}
		Player_Set_Character(player, L, nil)
		if player != players.local_player {Players_Remove(players, L, player)}
		break
	}
}

character_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "LoadPlayer",
	     "LoadCharacter",
	     "UnloadPlayer",
	     "UnloadCharacter",
	     "GetCharacter",
	     "SetMoveDirection",
	     "Jump":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

character_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^CharacterService)object
	switch method {
	case "LoadPlayer", "LoadCharacter", "UnloadPlayer", "UnloadCharacter", "GetCharacter":
		player_object := collection_object_from_argument(L, 2)
		if player_object == nil ||
		   !classes.Is_A(
				   player_object,
				   "Player",
			   ) {return vm.RaiseError(L, "expected Player"), true}
		player := cast(^Player)player_object
		switch method {
		case "LoadPlayer", "LoadCharacter":
			model := CharacterService_Load(service, player)
			if model == nil {vm.PushNil(L)} else {classes.Push_Object(L, &model.object)}
		case "UnloadPlayer", "UnloadCharacter":
			vm.PushBoolean(L, CharacterService_Unload(service, player))
		case "GetCharacter":
			if player.character == nil ||
			   player.character.destroyed {vm.PushNil(L)} else {classes.Push_Object(L, &player.character.object)}
		}
		return 1, true
	case "SetMoveDirection":
		service.move_direction = datatypes.Arg_Vector3(L, 2)
		vm.PushBoolean(L, true)
		return 1, true
	case "Jump":
		service.jump_queued = true
		service.local_jump_pending = true
		vm.PushBoolean(L, true)
		return 1, true
	}
	return 0, false
}

Register_CharacterService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&CharacterService_Class,
		character_service_construct,
		character_service_destroy,
		creatable = false,
		get = character_service_get,
		namecall = character_service_namecall,
	)
}
