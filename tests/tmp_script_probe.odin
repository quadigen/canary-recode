package main

import "core:fmt"
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

STEP_DT :: f32(1.0 / 60.0)

run :: proc(v: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(v, source, name)
	if !ok {
		fmt.eprintln("setup failed:", name, err)
		delete(err)
		panic("probe setup failed")
	}
}

dump_children :: proc(root: ^classes.Object, label: string) {
	if root == nil {
		fmt.println(label, ": <nil>")
		return
	}
	fmt.printf("%s (%s) children:\n", label, classes.Get_Full_Name(root))
	for child in root.children {
		if child == nil {continue}
		state := ""
		if common := classes.Script_Common_Of(child); common != nil {
			state = fmt.aprintf(" state=%v src=%d", common.execution_state, len(common.source))
		}
		fmt.printf("  - %s [%s]%s\n", child.name, classes.Get_Class_Name(child), state)
	}
}

main :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()

	server: engine_runtime.Environment
	client: engine_runtime.Environment

	engine_runtime.Environment_Init(&server, &server_vm, nil, .Server)
	engine_runtime.Environment_Init(&client, &client_vm, nil, .Client)

	// Local player on the client (mirrors the smoke test harness).
	players := cast(^services.Players)services.Ensure_Service(&client.services, "Players")
	player := services.Players_Add(players, client_vm.L, 1, "Player1")
	players.local_player = player

	run(&server_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39477))
local template = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local bootstrap = Instance.new("LocalScript", template)
bootstrap.Name = "NetBootstrap"
bootstrap.Source = "_G.net_bootstrap_ran = true"
`, "server_setup")

	run(&client_vm, `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39477))`, "client_connect")

	for frame in 0..<60 {
		engine_runtime.Environment_Update_Step(&server, &server_vm, STEP_DT)
		engine_runtime.Environment_Update_Step(&client, &client_vm, STEP_DT)
		engine_runtime.Environment_Render_Step(&server, &server_vm, STEP_DT)
		engine_runtime.Environment_Render_Step(&client, &client_vm, STEP_DT)
		if frame == 0 {
			fmt.println("player_scripts before prepare:", player.player_scripts != nil)
			ctx := services.Ensure_Service(&client.services, "ScriptContext")
			fmt.println("ScriptContext on client:", ctx != nil)
			data_model := cast(^services.DataModel)ctx.parent
			fmt.println("data_model:", data_model != nil, "registry:", data_model != nil && data_model.registry != nil)
			starter := services.Ensure_Service(&client.services, "StarterPlayer")
			fmt.println("starter player:", starter != nil)
			copied := services.ClientScripts_Prepare_Local_Player(
				data_model,
				player,
			)
			fmt.println("direct Prepare copied:", copied)
			fmt.println("player_scripts after prepare:", player.player_scripts != nil)
			dump_children(&player.object, "client Player1 after direct Prepare")
		}
	}

	run(&client_vm, `print("RESULT net_bootstrap_ran =", _G.net_bootstrap_ran)`, "probe_result")

	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
}
