package main

// Standalone-baked-map fixture generator and runtime smoke test.
//
// It does three things in one process:
//
//  1. authors a real map (a Script under ServerScriptService and a LocalScript
//     in the StarterPlayerScripts template) and serializes it to
//     build/standalone-map.kine;
//  2. boots a standalone runtime (a client runtime flipped into .Standalone
//     mode, exactly like run_desktop does for a baked offline build) and loads
//     that map, proving both script kinds execute;
//  3. boots a normal network client against the same map as a negative control,
//     proving the Script stays inert there (client scope) instead.
//
// The generated fixture is also the artifact used to bake a real client:
//
//	just client-bake "" build/standalone-map.kine

import "core:fmt"
import "core:strings"

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import packages "../src/engine/packages"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import target "../src/engine/target"
import vm "../src/engine/vm"

STEP_DT :: f32(1.0 / 60.0)
FIXTURE_PATH :: "build/standalone-map.kine"

SERVER_SCRIPT_SOURCE :: `_G.fixture_server_ran = true`
LOCAL_SCRIPT_SOURCE  :: `_G.fixture_local_ran = true`

failures := 0

fail :: proc(message: string) {
	failures += 1
	fmt.eprintln("FAILED:", message)
}

verify :: proc(v: ^vm.VM, body: string, name: string) {
	source := strings.concatenate(
		{
			`
local __failures = {}
local function expect(condition, message)
	if not condition then
		table.insert(__failures, message)
	end
end
`,
			body,
			`
if #__failures > 0 then
	error(table.concat(__failures, "\n  "), 0)
end
`,
		},
	)
	defer delete(source)

	ok, err := vm.RunInternal(v, source, name)
	if !ok {
		fail(err)
		delete(err)
	}
}

step :: proc(environment: ^engine_runtime.Environment, v: ^vm.VM, frames: int) {
	for frame in 0..<frames {
		engine_runtime.Environment_Update_Step(environment, v, STEP_DT)
		engine_runtime.Environment_Render_Step(environment, v, STEP_DT)
	}
}

make_local_player :: proc(
	environment: ^engine_runtime.Environment,
	v: ^vm.VM,
	id: u32,
	name: string,
) {
	players := cast(^services.Players)services.Ensure_Service(&environment.services, "Players")
	if players == nil {
		panic("standalone_map_fixture: Players service missing")
	}
	player := services.Players_Add(players, v.L, id, name)
	players.local_player = player
}

author_fixture :: proc(destroy: bool) {
	source_vm := vm.New()
	source: engine_runtime.Environment
	engine_runtime.Environment_Init(&source, &source_vm, nil, .Server)

	server_scripts := services.Ensure_Service(&source.services, "ServerScriptService")
	server_script, ok := classes.Push_New(&source.classes, &source_vm, "Script")
	assert(ok && server_script != nil)
	classes.Set_Name(server_script, "FixtureServer")
	classes.Script_Set_Source(cast(^classes.Script)server_script, SERVER_SCRIPT_SOURCE)
	classes.Set_Parent(server_script, server_scripts)
	vm.Pop(source_vm.L)

	starter_player := services.Ensure_Service(&source.services, "StarterPlayer")
	template := classes.Find_First_Child(starter_player, "StarterPlayerScripts")
	assert(template != nil)
	local_script, ok2 := classes.Push_New(&source.classes, &source_vm, "LocalScript")
	assert(ok2 && local_script != nil)
	classes.Set_Name(local_script, "FixtureLocal")
	classes.LocalScript_Set_Source(cast(^classes.LocalScript)local_script, LOCAL_SCRIPT_SOURCE)
	classes.Set_Parent(local_script, template)
	vm.Pop(source_vm.L)

	assert(
		serializer.Serialize_To_File(
			&source.classes,
			source_vm.L,
			&source.services.data_model.object,
			FIXTURE_PATH,
		),
	)
	fmt.println("FIXTURE_WRITTEN", FIXTURE_PATH)

	if destroy {
		vm.Close(&source_vm)
		fmt.println("DEBUG_author_vm_closed")
		engine_runtime.Environment_Destroy(&source)
		fmt.println("DEBUG_author_destroyed")
	} else {
		vm.Close(&source_vm)
	}
}

// boot_standalone mirrors the standalone branch of run_desktop: a client
// runtime, flipped to .Standalone mode, with both script-role globals enabled,
// the baked map loaded, and a local player synthesized.
boot_standalone :: proc(load_map := true) -> (standalone: engine_runtime.Environment, v: vm.VM) {
	v = vm.New()
	engine_runtime.Environment_Init(&standalone, &v, nil, .Client)
	engine_runtime.Environment_Set_Mode(&standalone, target.Mode.Client)
	vm.AddGlobal_Boolean(&v, "IsServer", false)
	vm.AddGlobal_Boolean(&v, "IsClient", true)
	if load_map {
		assert(engine_runtime.Load_Map(&standalone, &v, FIXTURE_PATH))
	}
	make_local_player(&standalone, &v, 1, "Solo")
	return standalone, v
}

boot_classic :: proc() -> (client: engine_runtime.Environment, v: vm.VM) {
	v = vm.New()
	engine_runtime.Environment_Init(&client, &v, nil, .Client)
	assert(engine_runtime.Load_Map(&client, &v, FIXTURE_PATH))
	make_local_player(&client, &v, 7, "NetPlayer")
	return client, v
}

main :: proc() {
	author_fixture(destroy = false)
	fmt.println("DEBUG_author_done")

	standalone, standalone_vm := boot_standalone(load_map = false)
	fmt.println("DEBUG_standalone_booted")
	defer {
		vm.Close(&standalone_vm)
		engine_runtime.Environment_Destroy(&standalone)
	}
	for frame in 0..<6 {
		fmt.println("DEBUG_phase_packages_start")
		packages.Update(&standalone.packages, STEP_DT)
		fmt.println("DEBUG_phase_packages_ok")
		if svc := services.Find_Service(&standalone.services, "ReplicatorService"); svc != nil && svc.object != nil {
			services.Replication_Step(cast(^services.ReplicatorService)svc.object, standalone_vm.L, STEP_DT)
		}
		fmt.println("DEBUG_phase_replication_ok")
		if svc := services.Find_Service(&standalone.services, "CharacterService"); svc != nil && svc.object != nil {
			services.CharacterService_Step(cast(^services.CharacterService)svc.object, STEP_DT)
		}
		fmt.println("DEBUG_phase_character_ok")
		if svc := services.Find_Service(&standalone.services, "UserInputService"); svc != nil && svc.object != nil {
			services.User_Input_Begin_Frame(cast(^services.UserInputService)svc.object)
		}
		fmt.println("DEBUG_phase_userinput_ok")
		if svc := services.Find_Service(&standalone.services, "Physics"); svc != nil && svc.object != nil {
			services.Physics_Step(cast(^services.Physics)svc.object, STEP_DT)
		}
		fmt.println("DEBUG_phase_physics_ok")
		if svc := services.Find_Service(&standalone.services, "TaskScheduler"); svc != nil && svc.object != nil {
			services.Task_Scheduler_Step(cast(^services.TaskScheduler)svc.object, STEP_DT)
		}
		fmt.println("DEBUG_phase_taskscheduler_ok")
		if svc := services.Find_Service(&standalone.services, "RunService"); svc != nil && svc.object != nil {
			services.Run_Service_Heartbeat(cast(^services.RunService)svc.object, standalone_vm.L, STEP_DT)
		}
		fmt.println("DEBUG_phase_runservice_ok")
		classes.Step(&standalone.classes, standalone_vm.L, STEP_DT, phase = .Update)
		fmt.println("DEBUG_phase_classes_ok")
		services.Prepare_3D(&standalone.services, nil)
		fmt.println("DEBUG_phase_prepare3d_ok")
		fmt.printf("DEBUG_standalone_frame_%d\n", frame)
		engine_runtime.Environment_Render_Step(&standalone, &standalone_vm, STEP_DT)
		fmt.printf("DEBUG_standalone_render_%d\n", frame)
	}

	verify(
		&standalone_vm,
		`
expect(_G.fixture_server_ran == true, "Script runs in standalone mode")
expect(_G.fixture_local_ran == true, "LocalScript runs in standalone mode")
expect(game:GetService("ServerScriptService"):FindFirstChild("FixtureServer") ~= nil, "the loaded Script exists")
local copy = game:GetService("Players").LocalPlayer.PlayerScripts:FindFirstChild("FixtureLocal")
expect(copy ~= nil, "the template LocalScript was copied to PlayerScripts")
`,
		"standalone_verify",
	)

	client, client_vm := boot_classic()
	defer {
		vm.Close(&client_vm)
		engine_runtime.Environment_Destroy(&client)
	}
	step(&client, &client_vm, 6)

	verify(
		&client_vm,
		`
expect(_G.fixture_server_ran == nil, "Script must not run on a network client")
expect(_G.fixture_local_ran == true, "LocalScript still runs on a network client")
`,
		"classic_client_verify",
	)

	if failures > 0 {
		fmt.printf("standalone_map_fixture failures: %d\n", failures)
		panic("STANDALONE_MAP_FIXTURE_FAILED")
	}
	fmt.println("STANDALONE_MAP_FIXTURE_PASSED")
}