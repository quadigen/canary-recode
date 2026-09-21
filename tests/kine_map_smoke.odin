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
	assert(serializer.Serialize_To_File(&source.classes, source_vm.L, model, "build/kine-map-smoke.kine"))

	client_vm := vm.New()
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&client, &client_vm)
	assert(engine_runtime.Load_Map(&client, &client_vm, "build/kine-map-smoke.kine"))
	workspace := services.Ensure_Service(&client.services, "Workspace")
	loaded_model := classes.Find_First_Child(workspace, "KineMapSmoke")
	assert(loaded_model != nil)
	loaded_part := classes.Find_First_Child(loaded_model, "MapMarker")
	assert(loaded_part != nil && (cast(^classes.Part)loaded_part).cframe.x == 17)
	fmt.println("KINE_MAP_SMOKE_PASSED")
}
