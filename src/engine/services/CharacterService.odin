package services
// wire:service

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import target "../target"
import vm "../vm"
import "core:math"

CharacterService_Class := classes.Class_Info {
	name   = "CharacterService",
	parent = &Service_Class,
}

CharacterService :: struct {
	using service:          Service,
	move_direction:         datatypes.Vector3,
	jump_queued:            bool,
	local_jump_pending:     bool,
	scripted_move:          bool,
	input_sequence:         u32,
	last_ack:               u32,
	authoritative_received: bool,
	scene_frozen:           bool,
	respawn_time:           f32,
	predictions:            [dynamic]Character_Prediction,
	pending_binds:          [dynamic]^classes.CharacterModel,
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
	service.respawn_time = 5
	return &service.object
}

character_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^CharacterService)object
	delete(service.predictions)
	delete(service.pending_binds)
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
	shape: enums.PartType,
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
	part.shape = shape
	classes.Set_Parent(object, &model.object)
	vm.Pop(service.data_model.registry.vm_state.L)
	return part
}

character_service_singleplayer :: proc(data_model: ^DataModel) -> bool {
	return(
		data_model != nil &&
		data_model.registry != nil &&
		data_model.registry.mode == .Singleplayer \
	)
}

character_service_is_spawn_candidate :: proc(object: ^classes.Object) -> bool {
	if object == nil || object.destroyed {return false}
	if classes.Is_A(object, "SpawnLocation") {return true}
	return object.name == "Spawn" && classes.Is_A(object, "Part")
}

CharacterService_Spawn_Position :: proc(
	data_model: ^DataModel,
	origin: ^datatypes.Vector3 = nil,
) -> datatypes.Vector3 {
	position := datatypes.Vector3{0, 30, 0}
	if data_model == nil {return position}
	workspace := DataModel_Get_Service(data_model, "Workspace")
	if workspace == nil {return position}

	best_dist := f32(math.F32_MAX)
	found := false
	for child in workspace.children {
		if !character_service_is_spawn_candidate(child) {continue}
		part := cast(^classes.Part)child
		candidate := datatypes.Vector3{part.cframe.x, part.cframe.y + 4, part.cframe.z}
		if origin == nil {
			return candidate
		}
		dx := candidate.x - origin.x
		dy := candidate.y - origin.y
		dz := candidate.z - origin.z
		dist := dx * dx + dy * dy + dz * dz
		if !found || dist < best_dist {
			found = true
			best_dist = dist
			position = candidate
		}
	}
	return position
}

CharacterService_Begin_Ragdoll :: proc(data_model: ^DataModel, model: ^classes.CharacterModel) {
	if data_model == nil || model == nil || model.destroyed {return}
	controller := classes.CharacterController_From_Model(model)
	if controller == nil {return}
	controller.ragdoll = true
	controller.knockback = datatypes.Vector3{}
	controller.vertical_speed = 0
	collision := cast(^classes.CollisionController)classes.CharacterController_Find(
		controller,
		"CollisionController",
	)
	root := classes.CharacterModel_Root(model)
	if collision != nil && root != nil {
		physics := cast(^Physics)DataModel_Get_Service(data_model, "Physics")
		Physics_Start_Character_Ragdoll(physics, collision, root)
	}
	replicator := cast(^ReplicatorService)DataModel_Get_Service(data_model, "ReplicatorService")
	if replicator != nil && replicator.mode == .Server {
		if root := classes.CharacterModel_Root(model); root != nil {
			if entity := replication_entity_by_id(
				replicator,
				replication_register(replicator, &root.object),
			); entity != nil {
				entity.owner_id = 0
			}
		}
	}
}

CharacterService_Update_Ragdoll :: proc(
	service: ^CharacterService,
	model: ^classes.CharacterModel,
) {
	if service == nil || model == nil || model.destroyed {return}
	root := classes.CharacterModel_Root(model)
	controller := classes.CharacterController_From_Model(model)
	if root == nil || controller == nil {return}
	collision := cast(^classes.CollisionController)classes.CharacterController_Find(
		controller,
		"CollisionController",
	)
	if collision == nil {return}
	physics := cast(^Physics)DataModel_Get_Service(service.data_model, "Physics")
	cf, ok := Physics_Get_Character_Capsule_CFrame(physics, collision)
	if !ok {return}
	character_set_root_frame(root, cf)
}

CharacterService_Update_Death :: proc(
	service: ^CharacterService,
	player: ^Player,
	delta_time: f32,
) {
	if service == nil ||
	   player == nil ||
	   player.character == nil ||
	   player.character.destroyed {return}
	humanoid := cast(^classes.Humanoid)classes.Find_Child(&player.character.object, "Humanoid")
	dead := humanoid != nil && !humanoid.destroyed && humanoid.health <= 0

	if !dead {
		player.ragdoll = false
		player.respawn_timer = 0
		return
	}

	if !player.ragdoll {
		player.ragdoll = true
		player.respawn_timer = 0
		CharacterService_Begin_Ragdoll(service.data_model, player.character)
		return
	}

	player.respawn_timer += delta_time
	if player.respawn_timer < service.respawn_time {return}

	respawn_origin: datatypes.Vector3
	has_origin := false
	if root := classes.CharacterModel_Root(player.character); root != nil {
		respawn_origin = datatypes.Vector3{root.cframe.x, root.cframe.y, root.cframe.z}
		has_origin = true
	}

	player.ragdoll = false
	player.respawn_timer = 0
	CharacterService_Unload(service, player)
	if has_origin {
		_ = CharacterService_Load(service, player, &respawn_origin)
	} else {
		_ = CharacterService_Load(service, player)
	}
}

character_service_is_template :: proc(object: ^classes.Object) -> bool {
	return object != nil &&
	       object.name == "StarterCharacter" &&
	       classes.Is_A(object, "Model") &&
	       object.parent != nil &&
	       classes.Is_A(object.parent, "StarterPlayer")
}

CharacterService_Load :: proc(
	service: ^CharacterService,
	player: ^Player,
	respawn_origin: ^datatypes.Vector3 = nil,
) -> ^classes.CharacterModel {
	if service == nil ||
	   player == nil ||
	   player.destroyed ||
	   service.data_model == nil ||
	   service.data_model.registry == nil {return nil}
	if player.character != nil && !player.character.destroyed {return player.character}


	singleplayer := character_service_singleplayer(service.data_model)
	replicator: ^ReplicatorService
	if !singleplayer {
		replicator = cast(^ReplicatorService)DataModel_Get_Service(
			service.data_model,
			"ReplicatorService",
		)
		if replicator == nil || replicator.mode != .Server {return nil}
	}
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
	spawn := CharacterService_Spawn_Position(service.data_model, respawn_origin)
	starter := DataModel_Get_Service(service.data_model, "StarterPlayer")
	template := classes.Find_First_Child(starter, "StarterCharacter")
	template_provides_controller := false
	if character_service_is_template(template) && template.archivable {
		root := classes.Find_First_Child(template, "HumanoidRootPart")
		if root != nil && root.archivable && classes.Is_A(root, "Part") {
			template_provides_controller =
				classes.Find_Child(template, "CharacterController") != nil
			registry := service.data_model.registry
			classes.CharacterModel_Copy_Template(registry.vm_state.L, registry.classes, model, template)
		}
	}
	classes.Set_Name(object, player.name)
	if root := classes.CharacterModel_Root(model); root != nil {
		frame := root.cframe
		frame.x, frame.y, frame.z = spawn.x, spawn.y, spawn.z
		classes.Model_Pivot_To(&model.model, frame)
	} else {
		white := datatypes.Color3 {
			R = 1,
			G = 1,
			B = 1,
		}

		_ = character_service_part(
			service,
			model,
			"HumanoidRootPart",
			datatypes.Vector3{3, 5, 3},
			spawn,
			white,
			false,
			.Block,
		)

		_ = character_service_part(
			service,
			model,
			"CharacterCollider",
			datatypes.Vector3{3, 3, 3},
			spawn,
			white,
			true,
			.Capsule,
		)
	}

	classes.Set_Parent(object, workspace)
	vm.Pop(service.data_model.registry.vm_state.L)
	Player_Set_Character(player, service.data_model.registry.vm_state.L, model)
	player.ground_y = spawn.y
	player.vertical_speed = 0


	if !singleplayer {
		_ = replication_register(replicator, object)
		root := classes.CharacterModel_Root(model)
		if root != nil {
			id := replication_register(replicator, &root.object)
			entity := replication_entity_by_id(replicator, id)
			if entity != nil {entity.owner_id = player.user_id}
		}
	} else {


		players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
		if player == players.local_player {
			workspace_service := cast(^Workspace)workspace
			if workspace_service != nil && workspace_service.current_camera != nil {
				workspace_service.current_camera.CameraSubject = &model.object
			}
		}
	}
	when !#config(FORCE_LEGACY_CHARACTERS, false) {
		classes.CharacterController_Build(
			service.data_model.registry.classes,
			service.data_model.registry.vm_state.L,
			model,
		)
		controller := classes.CharacterController_From_Model(model)
		if !template_provides_controller {
			StarterPlayer_Apply_Character(service.data_model, controller)
		}
	}
	return model
}

CharacterService_Unload :: proc(service: ^CharacterService, player: ^Player) -> bool {
	if service == nil || player == nil || player.character == nil {return false}
	model := player.character
	when !#config(FORCE_LEGACY_CHARACTERS, false) {
		controller := classes.CharacterController_From_Model(model)
		if controller != nil {
			collision_object := classes.CharacterController_Find(controller, "CollisionController")
			if collision_object != nil {
				physics := cast(^Physics)DataModel_Get_Service(service.data_model, "Physics")
				if physics != nil {
					Physics_Destroy_Character_Capsule(
						physics,
						cast(^classes.CollisionController)collision_object,
					)
				}
			}
		}
	}
	Player_Set_Character(player, service.data_model.registry.vm_state.L, nil)
	if !model.destroyed {classes.Destroy_Hierarchy(&model.object)}
	return true
}


character_service_player_for_model :: proc(
	players: ^Players,
	model: ^classes.CharacterModel,
) -> ^Player {
	if players == nil || model == nil {return nil}
	for child in players.children {
		if child != nil &&
		   !child.destroyed &&
		   classes.Is_A(child, "Player") &&
		   (cast(^Player)child).user_id == model.owner_user_id {
			return cast(^Player)child
		}
	}
	return nil
}


character_service_bind_ready :: proc(
	data_model: ^DataModel,
	model: ^classes.CharacterModel,
	L: ^vm.State,
	player: ^Player,
	players: ^Players,
) {
	Player_Set_Character(player, L, model)
	root := classes.CharacterModel_Root(model)
	if root != nil {player.ground_y = root.cframe.y}
	if player == players.local_player {
		workspace := cast(^Workspace)DataModel_Get_Service(data_model, "Workspace")
		if workspace != nil && workspace.current_camera != nil {
			workspace.current_camera.CameraSubject = &model.object
		}
		service := cast(^CharacterService)Ensure_Service(data_model.registry, "CharacterService")
		if service != nil {
			clear(&service.predictions)
			service.last_ack = 0
			service.authoritative_received = false
		}
	}
	when !#config(FORCE_LEGACY_CHARACTERS, false) {
		classes.CharacterController_Build(data_model.registry.classes, L, model)
		controller := classes.CharacterController_From_Model(model)
		StarterPlayer_Apply_Character(data_model, controller)
	}
}


CharacterService_Flush_Pending_Binds :: proc(data_model: ^DataModel) {
	if data_model == nil ||
	   data_model.registry == nil ||
	   data_model.registry.vm_state == nil {return}
	service := cast(^CharacterService)DataModel_Get_Service(data_model, "CharacterService")
	if service == nil || len(service.pending_binds) == 0 {return}
	players := cast(^Players)DataModel_Get_Service(data_model, "Players")
	if players == nil {return}
	pending := service.pending_binds
	service.pending_binds = nil
	defer delete(pending)
	L := data_model.registry.vm_state.L
	for model in pending {


		if model == nil || model.destroyed {continue}
		player := character_service_player_for_model(players, model)
		if player == nil {continue}
		character_service_bind_ready(data_model, model, L, player, players)
	}
}

CharacterService_Bind :: proc(
	data_model: ^DataModel,
	model: ^classes.CharacterModel,
	L: ^vm.State,
) {
	if data_model == nil || model == nil || model.owner_user_id == 0 {return}
	players := cast(^Players)DataModel_Get_Service(data_model, "Players")
	if players == nil {return}
	player := character_service_player_for_model(players, model)
	if player == nil {player = Players_Add(players, L, model.owner_user_id, model.name)}
	if player == nil {return}


	replicator := cast(^ReplicatorService)DataModel_Get_Service(data_model, "ReplicatorService")
	if replicator != nil && replicator.mode == .Client && !replicator.scene_ready {
		service := cast(^CharacterService)Ensure_Service(data_model.registry, "CharacterService")
		if service != nil {
			for queued in service.pending_binds {
				if queued == model {return}
			}
			append(&service.pending_binds, model)
		}
		return
	}

	character_service_bind_ready(data_model, model, L, player, players)
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
	service := cast(^CharacterService)object
	switch key {
	case "LoadPlayer",
	     "LoadCharacter",
	     "UnloadPlayer",
	     "UnloadCharacter",
	     "GetCharacter",
	     "SetMoveDirection",
	     "Jump":
		vm.PushUserdataMethod(L, key)
	case "RespawnTime":
		vm.PushNumber(L, f64(service.respawn_time))
	case:
		return false
	}
	return true
}

character_service_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^CharacterService)object
	switch key {
	case "RespawnTime":
		service.respawn_time = max(f32(vm.ArgNumber(L, value_index)), 0)
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
		service.scripted_move = true
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
		set = character_service_set,
		namecall = character_service_namecall,
		properties = []string{"RespawnTime"},
	)
}
