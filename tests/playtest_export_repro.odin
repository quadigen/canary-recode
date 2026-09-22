package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import classes "../src/engine/classes"
import datatypes "../src/engine/datatypes"
import services "../src/engine/services"
import vm "../src/engine/vm"

instantiate_all_services :: proc(environment: ^engine_runtime.Environment) {
	all := [?]string{
		"CharacterService", "CollectionService", "ContentProvider", "DialogService",
		"EditorService", "ExportService", "ExampleService", "HttpService", "Lighting",
		"LocalizationService", "LogService", "LuauService", "Physics", "Players",
		"PlaytestService", "Plugin", "PluginMarketplace", "ProfilerService", "Project",
		"ReplicatedFirst", "ReplicatedStorage", "ReplicatorService", "RunService",
		"ScriptContext", "Selection", "ServerScriptService", "ServerStorage",
		"SoundService", "StarterGui", "StarterPack", "StarterPlayer",
		"StudioThemeService", "TaskScheduler", "Terrain", "TextService", "TweenService",
		"UpdateService", "UserInputService", "Workspace",
	}
	for name in all {
		object := services.Ensure_Service(&environment.services, name)
		if object == nil {
			fmt.eprintf("could not instantiate service %s\n", name)
		}
	}
}

find_child_by_name :: proc(parent: ^classes.Object, target: string) -> ^classes.Object {
	if parent == nil {
		return nil
	}
	found := find_child_by_name_recursive(parent, target)
	return found
}

find_child_by_name_recursive :: proc(parent: ^classes.Object, target: string) -> ^classes.Object {
	for child in parent.children {
		if child != nil && child.name == target {
			return child
		}
		rescursive := find_child_by_name_recursive(child, target)
		if rescursive != nil {
			return rescursive
		}
	}
	return nil
}

main :: proc() {
	source_vm := vm.New()
	source: engine_runtime.Environment
	engine_runtime.Environment_Init(&source, &source_vm)
	instantiate_all_services(&source)

	// User content: a part in Workspace.
	part, part_ok := classes.Push_New(&source.classes, &source_vm, "Part")
	assert(part_ok && part != nil)
	classes.Set_Name(part, "MapMarker")
	(cast(^classes.Part)part).cframe.x = 17
	workspace := services.Ensure_Service(&source.services, "Workspace")
	classes.Set_Parent(part, workspace)
	vm.Pop(source_vm.L)

	// Runtime scaffolding that must NOT leak into a map file: the editor mounts
	// its Studio UI into CoreGui (a StarterGui-class service). Its read-only
	// properties used to abort the whole playtest deserialize.
	core_gui := services.Ensure_Service(&source.services, "CoreGui")
	assert(core_gui != nil)
	screen_gui, screen_gui_ok := classes.Push_New(&source.classes, &source_vm, "ScreenGui")
	assert(screen_gui_ok && screen_gui != nil)
	classes.Set_Name(screen_gui, "StudioUI")
	classes.Set_Parent(screen_gui, core_gui)
	vm.Pop(source_vm.L)

	text_button, text_button_ok := classes.Push_New(&source.classes, &source_vm, "TextButton")
	assert(text_button_ok && text_button != nil)
	classes.Set_Name(text_button, "EditorBackground")
	classes.Set_Parent(text_button, screen_gui)
	vm.Pop(source_vm.L)

	fmt.println("exporting DataModel through ExportService...")
	export_service := cast(^services.ExportService)services.Ensure_Service(&source.services, "ExportService")
	assert(export_service != nil)
	ok := services.export_datamodel_to_file(export_service, source_vm.L, "build/playtest-export-repro.kine")
	fmt.println("export_ok:", ok)
	assert(ok)

	fmt.println("loading exported map...")
	client_vm := vm.New()
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&client, &client_vm)
	load_ok := engine_runtime.Load_Map(&client, &client_vm, "build/playtest-export-repro.kine")
	fmt.println("load_ok:", load_ok)
	assert(load_ok)

	loaded_workspace := services.Ensure_Service(&client.services, "Workspace")
	loaded_marker := find_child_by_name(loaded_workspace, "MapMarker")
	fmt.println("map marker present:", loaded_marker != nil, "marker x:", (cast(^classes.Part)loaded_marker).cframe.x)
	assert(loaded_marker != nil)

	loaded_starter_gui := services.Ensure_Service(&client.services, "StarterGui")
	loaded_editor_ui := find_child_by_name(loaded_starter_gui, "EditorBackground")
	fmt.println("editor UI leaked into StarterGui:", loaded_editor_ui != nil)
	assert(loaded_editor_ui == nil)

	loaded_core_gui := services.Ensure_Service(&client.services, "CoreGui")
	leaked_studio_ui := find_child_by_name(loaded_core_gui, "StudioUI")
	fmt.println("editor UI leaked into CoreGui:", leaked_studio_ui != nil)
	assert(leaked_studio_ui == nil)

	fmt.println("PLAYTEST_EXPORT_REPRO_PASSED")

	fmt.println("teardown: destroying client...")
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&client)
	fmt.println("teardown: destroying source...")
	vm.Close(&source_vm)
	engine_runtime.Environment_Destroy(&source)
	fmt.println("ALL_TEARDOWN_DONE")
}