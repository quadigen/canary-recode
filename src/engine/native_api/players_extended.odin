package native_api

import classes "../classes"
import services "../services"
import vm "../vm"
import odin_runtime "base:runtime"

sdk_players :: proc(ctx: ^Context) -> ^services.Players {
	if ctx == nil || !ctx.active || ctx.services == nil {return nil}
	object := services.DataModel_Get_Service(ctx.services.data_model, "Players")
	if object == nil || object.destroyed {return nil}
	return cast(^services.Players)object
}

sdk_player :: proc(ctx: ^Context, handle: u64) -> ^services.Player {
	object := resolve_handle(ctx, handle)
	if object == nil || !classes.Is_A(object, "Player") {return nil}
	players := sdk_players(ctx)
	if players == nil || !classes.Is_Descendant_Of(object, &players.object) {return nil}
	return cast(^services.Player)object
}

sdk_player_at :: proc(players: ^services.Players, index: u64) -> ^services.Player {
	if players == nil {return nil}
	i: u64
	for child in players.children {
		if child == nil || child.destroyed || !classes.Is_A(child, "Player") {continue}
		if i == index {return cast(^services.Player)child}
		i += 1
	}
	return nil
}

@(export)
Kinemium_PlayersGetCount :: proc "c" (ctx: ^Context) -> u64 {
	context = odin_runtime.default_context()
	players := sdk_players(ctx)
	if players == nil {return 0}
	count: u64
	for child in players.children {
		if child != nil && !child.destroyed && classes.Is_A(child, "Player") {count += 1}
	}
	return count
}

@(export)
Kinemium_PlayersGetAt :: proc "c" (ctx: ^Context, index: u64) -> u64 {
	context = odin_runtime.default_context()
	player := sdk_player_at(sdk_players(ctx), index)
	if player == nil {return 0}
	return register_handle(ctx, &player.object)
}

@(export)
Kinemium_PlayersGetLocalPlayer :: proc "c" (ctx: ^Context) -> u64 {
	context = odin_runtime.default_context()
	players := sdk_players(ctx)
	if players == nil || players.local_player == nil || players.local_player.destroyed {return 0}
	return register_handle(ctx, &players.local_player.object)
}

@(export)
Kinemium_PlayersFindByUserId :: proc "c" (ctx: ^Context, user_id: u32) -> u64 {
	context = odin_runtime.default_context()
	player := services.Players_Find_By_User_Id(sdk_players(ctx), user_id)
	if player == nil {return 0}
	return register_handle(ctx, &player.object)
}

@(export)
Kinemium_PlayersFindByCharacter :: proc "c" (ctx: ^Context, character_handle: u64) -> u64 {
	context = odin_runtime.default_context()
	character := resolve_handle(ctx, character_handle)
	if character == nil || !classes.Is_A(character, "CharacterModel") {return 0}
	players := sdk_players(ctx)
	if players == nil {return 0}
	for child in players.children {
		if child == nil || child.destroyed || !classes.Is_A(child, "Player") {continue}
		player := cast(^services.Player)child
		if player.character != nil &&
		   !player.character.destroyed &&
		   &player.character.object == character {
			return register_handle(ctx, child)
		}
	}
	return 0
}

@(export)
Kinemium_PlayerGetUserId :: proc "c" (ctx: ^Context, player_handle: u64, output: ^u32) -> bool {
	context = odin_runtime.default_context()
	player := sdk_player(ctx, player_handle)
	if player == nil || output == nil {return false}
	output^ = player.user_id
	return true
}

@(export)
Kinemium_PlayerGetCharacter :: proc "c" (ctx: ^Context, player_handle: u64) -> u64 {
	context = odin_runtime.default_context()
	player := sdk_player(ctx, player_handle)
	if player == nil || player.character == nil || player.character.destroyed {return 0}
	return register_handle(ctx, &player.character.object)
}

@(export)
Kinemium_PlayerGetPing :: proc "c" (ctx: ^Context, player_handle: u64, output: ^f64) -> bool {
	context = odin_runtime.default_context()
	player := sdk_player(ctx, player_handle)
	if player == nil || output == nil {return false}
	output^ = player.network_ping
	return true
}

@(export)
Kinemium_PlayerGetWalkSpeed :: proc "c" (ctx: ^Context, player_handle: u64, output: ^f64) -> bool {
	context = odin_runtime.default_context()
	player := sdk_player(ctx, player_handle)
	if player == nil || output == nil {return false}
	output^ = f64(player.walk_speed)
	return true
}

@(export)
Kinemium_PlayerSetWalkSpeed :: proc "c" (ctx: ^Context, player_handle: u64, speed: f64) -> bool {
	context = odin_runtime.default_context()
	player := sdk_player(ctx, player_handle)
	if player == nil {return false}
	return sdk_property_set(ctx, &player.object, "WalkSpeed", .Number, number = speed)
}

@(export)
Kinemium_PlayerGetJumpPower :: proc "c" (ctx: ^Context, player_handle: u64, output: ^f64) -> bool {
	context = odin_runtime.default_context()
	player := sdk_player(ctx, player_handle)
	if player == nil || output == nil {return false}
	output^ = f64(player.jump_power)
	return true
}

@(export)
Kinemium_PlayerSetJumpPower :: proc "c" (ctx: ^Context, player_handle: u64, power: f64) -> bool {
	context = odin_runtime.default_context()
	player := sdk_player(ctx, player_handle)
	if player == nil {return false}
	return sdk_property_set(ctx, &player.object, "JumpPower", .Number, number = power)
}

@(export)
Kinemium_PlayerLoadCharacter :: proc "c" (ctx: ^Context, player_handle: u64) -> u64 {
	context = odin_runtime.default_context()
	player := sdk_player(ctx, player_handle)
	if player == nil || ctx.script_vm == nil || ctx.script_vm.L == nil {return 0}
	if player.character != nil && !player.character.destroyed {
		return register_handle(ctx, &player.character.object)
	}
	if !vm.CheckStack(ctx.script_vm.L, 24) {
		sdk_error(ctx, "insufficient Luau stack space to create character")
		return 0
	}
	object := services.DataModel_Get_Service(ctx.services.data_model, "CharacterService")
	if object == nil {
		sdk_error(ctx, "CharacterService unavailable")
		return 0
	}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	character := services.CharacterService_Load(cast(^services.CharacterService)object, player)
	if character == nil || character.destroyed {
		sdk_error(ctx, "character loading is unavailable in this network mode")
		return 0
	}
	sdk_clear_error(ctx)
	return register_handle(ctx, &character.object)
}
