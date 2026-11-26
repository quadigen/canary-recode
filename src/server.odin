#+build !js
package main

import sandbox "./sandboxed"
import "core:fmt"
import "core:time"
import classes "engine/classes"
import extensions "engine/extensions"
import engine_runtime "engine/runtime"
import services "engine/services"
import target "engine/target"
import tracy "engine/util/odin-tracy"
import vm "engine/vm"

run_headless :: proc(options: Startup_Options) -> bool {
	tracy.SetThreadName("Main/Headless")
	services.Log_Pause_On_Playtest_Error(options.playtest && options.pause_on_error)
	script_vm := vm.New()
	environment: engine_runtime.Environment
	target.set_playtest(options.playtest)
	vm.AddGlobal_Boolean(&script_vm, "IsPlaytest", options.playtest)
	vm.AddGlobal_String(&script_vm, "ProjectPath", options.project)
	sandbox.init_runtime(
		cast(^vm.VM)uintptr(&script_vm),
		cast(^engine_runtime.Environment)uintptr(&environment),
		nil,
	)
	defer sandbox.shutdown()
	defer vm.Close(&script_vm)
	defer extensions.Game_Unload(&environment.extensions)
	if options.singleplayer {
		vm.AddGlobal_Boolean(&script_vm, "IsServer", true)
		vm.AddGlobal_Boolean(&script_vm, "IsClient", true)
	}
	_ = services.Playtest_Debugger_Bootstrap(&script_vm, options.playtest_tree_dir)
	if !load_game_map(&environment, &script_vm, options) {return false}
	if options.singleplayer {
		players := cast(^services.Players)services.Ensure_Service(&environment.services, "Players")
		if players != nil && players.local_player == nil {
			players.local_player = services.Players_Add(players, script_vm.L, 1, options.username)
		}
	}

	if !load_game_library(&environment, options) {return false}

	if target.is_server() || options.singleplayer {
		server_scripts := services.Ensure_Service(&environment.services, "ServerScriptService")
		script_context := services.ScriptContext_From_Registry(&environment.services)
		if server_scripts != nil && services.ScriptContext_Runs_Server_Scripts(script_context) {
			services.ServerScriptService_RunScripts(
				environment.renderer,
				environment.services.data_model,
				server_scripts,
			)
		}
	}

	if options.singleplayer {
		services.CharacterService_Load_Local_Player(&environment.services)
	}

	if !options.singleplayer {
		mode := target.is_server() ? services.Replication_Mode.Server : .Client
		object := services.Ensure_Service(&environment.services, "ReplicatorService")
		if object == nil ||
		   !services.replication_start(
				   cast(^services.ReplicatorService)object,
				   options.address,
				   options.port,
				   mode,
				   options.username,
			   ) {
			fmt.eprintf(
				"Could not start the headless session on %s:%d\n",
				options.address,
				options.port,
			)
			return false
		}
	}
	previous := time.now()
	for !extensions.Game_Exit_Requested(&environment.extensions) {
		now := time.now()
		delta_time := f32(time.diff(previous, now)) / f32(time.Second)
		previous = now
		services.Playtest_Tree_Pump(options.playtest_tree_dir, &environment.services, script_vm.L)
		if !services.Log_Is_Playtest_Paused() {
			engine_runtime.Environment_Update_Step(&environment, &script_vm, min(delta_time, 0.1))
		}
		tracy.FrameMark()
		time.sleep(16 * time.Millisecond)
	}
	return true
}
