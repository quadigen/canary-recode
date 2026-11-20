package extensions

import classes "../classes"
import services "../services"
import target "../target"
import tracy "../util/odin-tracy"
import "core:fmt"
import "core:strings"

GAME_ABI_MAJOR :: u32(2)
GAME_ABI_MINOR :: u32(0)

Game_Role :: enum u32 {Singleplayer, Client, Server}
Game_Value_Kind :: enum u32 {Nil, Boolean, Number, Integer, String, Instance, Vector3, Color3}

Game_Value :: struct {
	kind: Game_Value_Kind,
	reserved: u32,
	data: struct #raw_union {
		boolean: i32,
		number: f64,
		integer: i64,
		string: KNE_String,
		instance: KNE_Instance,
		vector3: KNE_Vector3,
		color3: KNE_Color3,
	},
}

Game_Api :: struct {
	size, abi_major, abi_minor: u32,
	role: Game_Role,
	game: rawptr,
	log: proc "c" (rawptr, KNE_String),
	get_service: proc "c" (rawptr, KNE_String) -> KNE_Instance,
	create: proc "c" (rawptr, KNE_String) -> KNE_Instance,
	find_child: proc "c" (rawptr, KNE_Instance, KNE_String) -> KNE_Instance,
	get: proc "c" (rawptr, KNE_Instance, KNE_String, ^Game_Value) -> i32,
	set: proc "c" (rawptr, KNE_Instance, KNE_String, ^Game_Value) -> i32,
	call: proc "c" (rawptr, KNE_Instance, KNE_String, ^Game_Value, i32, ^Game_Value, i32) -> i32,
	last_error: proc "c" (rawptr) -> KNE_String,
	request_exit: proc "c" (rawptr),
}

Game_Desc :: struct {
	size, abi_major, abi_minor, reserved: u32,
	start: proc "c" (^Game_Api) -> i32,
	update: proc "c" (f64),
	stop: proc "c" (),
}

Game_Library :: struct {
	// Reuse the engine's protected instance calls and callback-scoped value storage.
	bridge: Extension_Record,
	library: Platform_Library,
	desc: ^Game_Desc,
	api: Game_Api,
	exit_requested: bool,
}

Game_Load :: proc(ctx: ^Context, path: string, mode: target.Mode) -> string {
	if ctx.game != nil {return strings.clone("a game library is already loaded")}
	role: Game_Role
	switch mode {
	case .Singleplayer, .Standalone: role = .Singleplayer
	case .Client: role = .Client
	case .Server: role = .Server
	case .Editor: return strings.clone("game libraries require a game runtime")
	}
	library, err := platform_load(path)
	if err != "" {return err}
	symbol, found := platform_symbol(library, "kine_game_entry")
	if !found {
		_ = platform_unload(&library)
		delete(library.path)
		return strings.clone("the library does not export kine_game_entry")
	}
	entry := cast(proc "c" () -> ^Game_Desc)symbol
	desc := entry()
	if desc == nil || desc.size < u32(size_of(Game_Desc)) ||
	   desc.abi_major != GAME_ABI_MAJOR || desc.abi_minor > GAME_ABI_MINOR || desc.start == nil {
		_ = platform_unload(&library)
		delete(library.path)
		return strings.clone("invalid or unsupported game ABI descriptor")
	}
	game := new(Game_Library)
	game.bridge.ctx = ctx
	game.library = library
	game.desc = desc
	game.api = {
		size = u32(size_of(Game_Api)), abi_major = GAME_ABI_MAJOR, abi_minor = GAME_ABI_MINOR,
		role = role, game = game, log = game_log, get_service = game_service,
		create = game_create, find_child = game_find_child, get = game_get, set = game_set,
		call = game_call, last_error = game_last_error, request_exit = game_request_exit,
	}
	ctx.game = game
	started := desc.start(&game.api) != 0
	release_result_roots(&game.bridge, 0)
	if started {return ""}

	detail := "game start returned 0"
	if game.bridge.last_error != "" {detail = game.bridge.last_error}
	err = strings.clone(detail)
	Game_Unload(ctx)
	return err
}

Game_Unload :: proc(ctx: ^Context) {
	game := ctx.game
	if game == nil {return}
	ctx.game = nil
	if game.desc.stop != nil {game.desc.stop()}
	release_result_roots(&game.bridge, 0)
	delete(game.bridge.result_roots)
	delete(game.bridge.last_error)
	if err := platform_unload(&game.library); err != "" {
		fmt.eprintln("Could not unload game library: ", err)
		delete(err)
	}
	delete(game.library.path)
	free(game)
}

Game_Update :: proc(ctx: ^Context, dt: f64) {
	game := ctx.game
	if game != nil && !game.exit_requested && game.desc.update != nil {
		game.desc.update(dt)
		release_result_roots(&game.bridge, 0)
	}
}

Game_Exit_Requested :: proc(ctx: ^Context) -> bool {
	return ctx.game != nil && ctx.game.exit_requested
}

game_fail :: proc(game: ^Game_Library, message: string) -> i32 {
	delete(game.bridge.last_error)
	game.bridge.last_error = strings.clone(message)
	return 0
}

game_log :: proc "c" (raw: rawptr, message: KNE_String) {
	context = tracy.DefaultContext()
	game := cast(^Game_Library)raw
	services.Log_Game_Message(game.bridge.ctx.service_registry, KNE_String_To(message))
}

game_service :: proc "c" (raw: rawptr, name: KNE_String) -> KNE_Instance {
	context = tracy.DefaultContext()
	game := cast(^Game_Library)raw
	ctx := game.bridge.ctx
	L := ctx.vm_state.L
	object, allowed := services.Get_Service_For_Thread(ctx.service_registry, L, KNE_String_To(name))
	if !allowed || !classes.Object_Is_Accessible(L, object) {
		_ = game_fail(game, "service is unavailable to the game")
		return nil
	}
	return rawptr(object)
}

game_create :: proc "c" (raw: rawptr, name: KNE_String) -> KNE_Instance {
	context = tracy.DefaultContext()
	game := cast(^Game_Library)raw
	return kne_instances_create(&game.bridge, name)
}

game_find_child :: proc "c" (raw: rawptr, instance: KNE_Instance, name: KNE_String) -> KNE_Instance {
	context = tracy.DefaultContext()
	game := cast(^Game_Library)raw
	value: Game_Value
	key := KNE_String_From("FindFirstChild")
	input := Game_Value{kind = .String}
	input.data.string = name
	if game_call(rawptr(game), instance, key, &input, 1, &value, 1) == 1 && value.kind == .Instance {
		return value.data.instance
	}
	return nil
}

game_get :: proc "c" (raw: rawptr, instance: KNE_Instance, key: KNE_String, out: ^Game_Value) -> i32 {
	context = tracy.DefaultContext()
	game := cast(^Game_Library)raw
	if instance == nil || out == nil {return game_fail(game, "get requires an instance and output")}
	value := KNE_Value{kind = .Instance}
	value.data.instance = instance
	result: KNE_Value
	count := kne_operation(&game.bridge, "local object, key = ...; return object[key]", &value, key, nil, 0, &result, 1)
	if count != 1 {return 0}
	if !game_decode(result, out) {return game_fail(game, "property type is unsupported by the game ABI")}
	return 1
}

game_set :: proc "c" (raw: rawptr, instance: KNE_Instance, key: KNE_String, input: ^Game_Value) -> i32 {
	context = tracy.DefaultContext()
	game := cast(^Game_Library)raw
	if instance == nil || input == nil {return game_fail(game, "set requires an instance and value")}
	value := KNE_Value{kind = .Instance}
	value.data.instance = instance
	arg: KNE_Value
	if !game_encode(input^, &arg) {return game_fail(game, "unsupported game value")}
	count := kne_operation(&game.bridge, "local object, key, value = ...; object[key] = value", &value, key, &arg, 1, nil, 0)
	return 1 if count == 0 else 0
}

game_call :: proc "c" (raw: rawptr, instance: KNE_Instance, key: KNE_String, input: ^Game_Value, count: i32, output: ^Game_Value, capacity: i32) -> i32 {
	context = tracy.DefaultContext()
	game := cast(^Game_Library)raw
	if instance == nil || count < 0 || count > 64 || capacity < 0 || capacity > 64 ||
	   (count > 0 && input == nil) || (capacity > 0 && output == nil) {
		_ = game_fail(game, "call requires an instance and up to 64 inputs and outputs")
		return -1
	}
	args, results: [64]KNE_Value
	in_values := cast([^]Game_Value)input
	out_values := cast([^]Game_Value)output
	for i in 0..<int(count) {
		if !game_encode(in_values[i], &args[i]) {
			_ = game_fail(game, "unsupported game argument")
			return -1
		}
	}
	written := kne_instance_invoke(&game.bridge, instance, key, &args[0], count, &results[0], capacity)
	if written < 0 {return -1}
	for i in 0..<int(written) {
		if !game_decode(results[i], &out_values[i]) {
			_ = game_fail(game, "result type is unsupported by the game ABI")
			return -1
		}
	}
	return written
}

game_last_error :: proc "c" (raw: rawptr) -> KNE_String {
	context = tracy.DefaultContext()
	return KNE_String_From((cast(^Game_Library)raw).bridge.last_error)
}

game_request_exit :: proc "c" (raw: rawptr) {
	(cast(^Game_Library)raw).exit_requested = true
}

game_encode :: proc(value: Game_Value, out: ^KNE_Value) -> bool {
	out^ = {}
	switch value.kind {
	case .Nil: out.kind = .Nil
	case .Boolean: out.kind = .Boolean; out.data.boolean = value.data.boolean
	case .Number: out.kind = .Number; out.data.number = value.data.number
	case .Integer: out.kind = .Integer; out.data.integer = value.data.integer
	case .String: out.kind = .String; out.data.string = value.data.string
	case .Instance: out.kind = .Instance; out.data.instance = value.data.instance
	case .Vector3: out.kind = .Vector3; out.data.vector3 = value.data.vector3
	case .Color3: out.kind = .Color3; out.data.color3 = value.data.color3
	case: return false
	}
	return true
}

game_decode :: proc(value: KNE_Value, out: ^Game_Value) -> bool {
	out^ = {}
	#partial switch value.kind {
	case .Nil: out.kind = .Nil
	case .Boolean: out.kind = .Boolean; out.data.boolean = value.data.boolean
	case .Number: out.kind = .Number; out.data.number = value.data.number
	case .Integer: out.kind = .Integer; out.data.integer = value.data.integer
	case .String: out.kind = .String; out.data.string = value.data.string
	case .Instance: out.kind = .Instance; out.data.instance = value.data.instance
	case .Vector3: out.kind = .Vector3; out.data.vector3 = value.data.vector3
	case .Color3: out.kind = .Color3; out.data.color3 = value.data.color3
	case: return false
	}
	return true
}
