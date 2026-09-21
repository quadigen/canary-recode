package main

import "core:fmt"
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"

main :: proc() {
	source_vm := vm.New()
	source: engine_runtime.Environment
	engine_runtime.Environment_Init(&source, &source_vm)
	model, model_ok := classes.Push_New(&source.classes, &source_vm, "Model")
	assert(model_ok && model != nil)
	classes.Set_Name(model, "KineMapSmoke")
	vm.Pop(source_vm.L)
	part, part_ok := classes.Push_New(&source.classes, &source_vm, "Part")
	assert(part_ok && part != nil)
	classes.Set_Name(part, "MapMarker")
	(cast(^classes.Part)part).cframe.x = 17
	classes.Set_Parent(part, model)
	vm.Pop(source_vm.L)
	workspace_source := services.Ensure_Service(&source.services, "Workspace")
	classes.Set_Parent(model, workspace_source)
	replicated_storage_source := services.Ensure_Service(&source.services, "ReplicatedStorage")
	value, value_ok := classes.Push_New(&source.classes, &source_vm, "NumberValue")
	assert(value_ok && value != nil)
	classes.Set_Name(value, "SharedScore")
	(cast(^classes.NumberValue)value).value = 42
	classes.Set_Parent(value, replicated_storage_source)
	vm.Pop(source_vm.L)
	replicated_first_source := services.Ensure_Service(&source.services, "ReplicatedFirst")
	first_folder, first_ok := classes.Push_New(&source.classes, &source_vm, "Folder")
	assert(first_ok && first_folder != nil)
	classes.Set_Name(first_folder, "Bootstrap")
	classes.Set_Parent(first_folder, replicated_first_source)
	vm.Pop(source_vm.L)
	server_storage_source := services.Ensure_Service(&source.services, "ServerStorage")
	secret_folder, secret_ok := classes.Push_New(&source.classes, &source_vm, "Folder")
	assert(secret_ok && secret_folder != nil)
	classes.Set_Name(secret_folder, "ServerSecret")
	classes.Set_Parent(secret_folder, server_storage_source)
	vm.Pop(source_vm.L)
	assert(serializer.Serialize_To_File(&source.classes, source_vm.L, &source.services.data_model.object, "build/kine-map-smoke.kine"))

	client_vm := vm.New()
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&client, &client_vm)
	assert(engine_runtime.Load_Map(&client, &client_vm, "build/kine-map-smoke.kine"))
	workspace := services.Ensure_Service(&client.services, "Workspace")
	loaded_model := classes.Find_First_Child(workspace, "KineMapSmoke")
	assert(loaded_model != nil)
	loaded_part := classes.Find_First_Child(loaded_model, "MapMarker")
	assert(loaded_part != nil && (cast(^classes.Part)loaded_part).cframe.x == 17)
	replicated_storage := services.Ensure_Service(&client.services, "ReplicatedStorage")
	shared_score := classes.Find_First_Child(replicated_storage, "SharedScore")
	assert(shared_score != nil && (cast(^classes.NumberValue)shared_score).value == 42)
	replicated_first := services.Ensure_Service(&client.services, "ReplicatedFirst")
	assert(classes.Find_First_Child(replicated_first, "Bootstrap") != nil)
	server_storage := services.Ensure_Service(&client.services, "ServerStorage")
	assert(classes.Find_First_Child(server_storage, "ServerSecret") != nil)
	fmt.println("KINE_MAP_SMOKE_PASSED")
}
