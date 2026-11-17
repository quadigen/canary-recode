package services

// wire:service

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:strings"

ScriptEditorService_Class := classes.Class_Info {
	name = "ScriptEditorService",
	parent = &Service_Class,
}

script_editor_service_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(Service)
	service^ = Service_Init(&ScriptEditorService_Class, "ScriptEditorService", data_model)
	return &service.object
}

script_editor_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Service)object)
}

script_editor_service_get :: proc(L: ^vm.State, object: ^classes.Object, dt: ^datatypes.Registry, en: ^enums.Registry, key: string) -> bool {
	if key != "GetEditorSource" && key != "UpdateSourceAsync" {return false}
	vm.PushUserdataMethod(L, key)
	return true
}

script_editor_service_namecall :: proc(L: ^vm.State, object: ^classes.Object, dt: ^datatypes.Registry, en: ^enums.Registry, method: string) -> (i32, bool) {
	if method != "GetEditorSource" && method != "UpdateSourceAsync" {return 0, false}
	if object.signal_registry.mode != .Editor {return vm.RaiseError(L, "ScriptEditorService is available in the editor"), true}
	script := classes.Object_From_Argument(L, 2)
	common := classes.Script_Common_Of(script)
	if common == nil || script.destroyed {return vm.RaiseError(L, "expected a LuaSourceContainer"), true}
	if method == "GetEditorSource" {
		vm.PushString(L, common.source)
		return 1, true
	}
	if !vm.IsFunction(L, 3) {return vm.RaiseError(L, "expected a source update callback"), true}
	vm.PushValue(L, 3)
	vm.PushString(L, common.source)
	ok, err := vm.ProtectedCall(L, 1, 1)
	if !ok {
		message := strings.clone(err, context.temp_allocator)
		delete(err)
		return vm.RaiseError(L, message), true
	}
	if vm.IsNil(L, -1) {return 0, true}
	if !vm.IsString(L, -1) {return vm.RaiseError(L, "source callback must return a string or nil"), true}
	// The callback can delete or replace the original instance.
	script = classes.Object_From_Argument(L, 2)
	if script == nil || script.destroyed {return vm.RaiseError(L, "the source instance was destroyed"), true}
	descriptor := classes.Find_Class(object.signal_registry, script.class.name)
	_ = classes.descriptor_set(L, script, descriptor, "Source", vm.StackTop(L))
	return 0, true
}

Register_ScriptEditorService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry, &ScriptEditorService_Class, script_editor_service_construct, script_editor_service_destroy,
		creatable = false,
		get = script_editor_service_get,
		namecall = script_editor_service_namecall,
		methods = []string{"GetEditorSource", "UpdateSourceAsync"},
	)
}
