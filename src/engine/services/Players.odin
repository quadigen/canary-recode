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
	return &player.object
}

player_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Player)object)
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
	case:
		return false
	}
	return true
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

Players_Remove :: proc(service: ^Players, L: ^vm.State, player: ^Player) {
	if service == nil || player == nil || player.destroyed {return}
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
