#+build !js
// wire:service
package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import rpc "../util/discord_rpc"
import vm "../vm"
import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

DEFAULT_APP_ID :: "1495125520445210877"
MIN_UPDATE_INTERVAL :: 4 * time.Second
RECONNECT_INTERVAL :: 5 * time.Second

DiscordRPC_Class := classes.Class_Info {
	name   = "DiscordRPC",
	parent = &Service_Class,
}

Presence :: struct {
	details:     string,
	state:       string,
	large_image: string,
	large_text:  string,
	small_image: string,
	small_text:  string,
	start_time:  i64,
	end_time:    i64,
}


Shared :: struct {
	mu:           sync.Mutex,
	quit:         bool,
	generation:   u64,
	app_id:       string,
	has_presence: bool,
	desired:      Presence,
}

DiscordRPC :: struct {
	using service: Service,
	shared:        ^Shared,
	worker:        ^thread.Thread,
}


@(private = "file")
free_str :: proc(s: string) {
	if len(s) > 0 {
		delete(s, runtime.heap_allocator())
	}
}

@(private = "file")
presence_destroy :: proc(p: ^Presence) {
	free_str(p.details)
	free_str(p.state)
	free_str(p.large_image)
	free_str(p.large_text)
	free_str(p.small_image)
	free_str(p.small_text)
	p^ = {}
}

@(private = "file")
presence_clone :: proc(p: Presence) -> Presence {
	a := runtime.heap_allocator()
	return Presence {
		details = strings.clone(p.details, a),
		state = strings.clone(p.state, a),
		large_image = strings.clone(p.large_image, a),
		large_text = strings.clone(p.large_text, a),
		small_image = strings.clone(p.small_image, a),
		small_text = strings.clone(p.small_text, a),
		start_time = p.start_time,
		end_time = p.end_time,
	}
}

Snapshot :: struct {
	gen:          u64,
	app_id:       string,
	has_presence: bool,
	presence:     Presence,
}

@(private = "file")
snapshot_destroy :: proc(s: ^Snapshot) {
	free_str(s.app_id)
	presence_destroy(&s.presence)
	s^ = {}
}

@(private = "file")
take_snapshot :: proc(sh: ^Shared) -> Snapshot {
	sync.mutex_lock(&sh.mu)
	defer sync.mutex_unlock(&sh.mu)
	s := Snapshot {
		gen          = sh.generation,
		app_id       = strings.clone(sh.app_id, runtime.heap_allocator()),
		has_presence = sh.has_presence,
	}
	if sh.has_presence {
		s.presence = presence_clone(sh.desired)
	}
	return s
}

@(private = "file")
peek :: proc(sh: ^Shared) -> (gen: u64, quit: bool) {
	sync.mutex_lock(&sh.mu)
	defer sync.mutex_unlock(&sh.mu)
	return sh.generation, sh.quit
}


@(private = "file")
apply_snapshot :: proc(client: ^rpc.Client, s: ^Snapshot) {
	if !s.has_presence {
		rpc.clear_activity(client)
		return
	}
	p := &s.presence
	err := rpc.set_activity(
		client,
		rpc.Activity {
			details = p.details,
			state = p.state,
			timestamps = {start = p.start_time, end = p.end_time},
			assets = {
				large_image = p.large_image,
				large_text = p.large_text,
				small_image = p.small_image,
				small_text = p.small_text,
			},
		},
	)
	if err != .None {
		fmt.eprintfln("[DiscordRPC] set_activity failed: %v", err)
	}
}

@(private = "file")
worker_proc :: proc(data: rawptr) {
	sh := cast(^Shared)data

	client: rpc.Client
	defer rpc.disconnect(&client)

	connected_id: string
	defer free_str(connected_id)

	applied_gen: u64
	last_send: time.Tick
	have_sent := false
	last_attempt: time.Tick
	attempted := false

	for {
		gen, quit := peek(sh)
		if quit {
			break
		}
		if gen == 0 {
			time.sleep(100 * time.Millisecond)
			continue
		}


		if !client.connected {
			if attempted && time.tick_since(last_attempt) < RECONNECT_INTERVAL {
				time.sleep(100 * time.Millisecond)
				continue
			}
			attempted = true
			last_attempt = time.tick_now()

			snap := take_snapshot(sh)
			if rpc.connect(&client, snap.app_id) == .None {
				free_str(connected_id)
				connected_id = snap.app_id
				snap.app_id = ""
				applied_gen = 0
				fmt.printfln("[DiscordRPC] connected as %s", client.user.username)
			}
			snapshot_destroy(&snap)
			continue
		}


		if gen != applied_gen {
			if have_sent && time.tick_since(last_send) < MIN_UPDATE_INTERVAL {
				rpc.update(&client, 100)
				continue
			}
			snap := take_snapshot(sh)
			if snap.app_id != connected_id {

				rpc.disconnect(&client)
				attempted = false
				snapshot_destroy(&snap)
				continue
			}
			apply_snapshot(&client, &snap)
			applied_gen = snap.gen
			last_send = time.tick_now()
			have_sent = true
			snapshot_destroy(&snap)
		}


		rpc.update(&client, 250)
		if client.last_error.code != 0 {
			fmt.eprintfln(
				"[DiscordRPC] Discord error %d: %s",
				client.last_error.code,
				client.last_error.message,
			)
			client.last_error.code = 0
		}
	}

	if client.connected {
		rpc.clear_activity(&client)
		rpc.update(&client, 100)
	}
}


@(private = "file")
table_string :: proc(L: ^vm.State, idx: int, key: string) -> string {
	vm.GetField(L, idx, key)
	defer vm.Pop(L)
	if s, ok := vm.ToString(L, -1); ok {
		return strings.clone(s, runtime.heap_allocator())
	}
	return ""
}

@(private = "file")
table_number :: proc(L: ^vm.State, idx: int, key: string) -> f64 {
	vm.GetField(L, idx, key)
	defer vm.Pop(L)
	if n, ok := vm.ToNumber(L, -1); ok {
		return n
	}
	return 0
}

@(private = "file")
set_presence :: proc(service: ^DiscordRPC, L: ^vm.State, idx: int) {
	p := Presence {
		details     = table_string(L, idx, "Details"),
		state       = table_string(L, idx, "State"),
		large_image = table_string(L, idx, "LargeImage"),
		large_text  = table_string(L, idx, "LargeText"),
		small_image = table_string(L, idx, "SmallImage"),
		small_text  = table_string(L, idx, "SmallText"),
		start_time  = i64(table_number(L, idx, "StartTimestamp")),
		end_time    = i64(table_number(L, idx, "EndTimestamp")),
	}

	app_id := table_string(L, idx, "AppId")
	if len(app_id) == 0 {
		app_id = strings.clone(DEFAULT_APP_ID, runtime.heap_allocator())
	}

	sh := service.shared
	sync.mutex_lock(&sh.mu)
	defer sync.mutex_unlock(&sh.mu)
	presence_destroy(&sh.desired)
	free_str(sh.app_id)
	sh.desired = p
	sh.app_id = app_id
	sh.has_presence = true
	sh.generation += 1
}

@(private = "file")
clear_presence :: proc(service: ^DiscordRPC) {
	sh := service.shared
	sync.mutex_lock(&sh.mu)
	defer sync.mutex_unlock(&sh.mu)
	presence_destroy(&sh.desired)
	sh.has_presence = false
	sh.generation += 1
}


DiscordRPC_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(DiscordRPC)
	service.service = Service_Init(&DiscordRPC_Class, "DiscordRPC", data_model)

	service.shared = new(Shared, runtime.heap_allocator())
	service.shared.app_id = strings.clone(DEFAULT_APP_ID, runtime.heap_allocator())


	service.worker = thread.create_and_start_with_data(service.shared, worker_proc)

	return &service.object
}

DiscordRPC_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "SetPresence", "ClearPresence", "GetService":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

DiscordRPC_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^DiscordRPC)object
	switch method {
	case "SetPresence":
		if !vm.IsTable(L, 2) {
			return vm.RaiseError(L, "SetPresence expects a table"), true
		}

		app_id_type := vm.GetField(L, 2, "AppId")
		vm.Pop(L)
		if app_id_type == .Number {
			return vm.RaiseError(
					L,
					"AppId must be a string (Discord IDs are too large for a Luau number)",
				),
				true
		}
		set_presence(service, L, 2)
		return 0, true
	case "ClearPresence":
		clear_presence(service)
		return 0, true
	case "GetService":
		classes.Push_Object(L, Service_Get_Service(&service.service, vm.ArgString(L, 2)))
		return 1, true
	}
	return 0, false
}

DiscordRPC_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^DiscordRPC)object

	sync.mutex_lock(&service.shared.mu)
	service.shared.quit = true
	sync.mutex_unlock(&service.shared.mu)
	thread.join(service.worker)
	thread.destroy(service.worker)

	presence_destroy(&service.shared.desired)
	free_str(service.shared.app_id)
	free(service.shared, runtime.heap_allocator())

	classes.Object_Destroy(object)
	free(service)
}

Register_DiscordRPC_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&DiscordRPC_Class,
		DiscordRPC_construct,
		DiscordRPC_destroy,
		creatable = false,
		get = DiscordRPC_get,
		namecall = DiscordRPC_namecall,
		methods = []string{"SetPresence", "ClearPresence"},
	)
}
