#+build !js
package services


import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

PLUGIN_LOADER_INTERNALS :: i64(2)

PluginLoader_List_Proc :: proc(ctx: rawptr, L: ^vm.State)
PluginLoader_Action_Proc :: proc(ctx: rawptr, action, id: string) -> (bool, string)

PluginLoader_Backend :: struct {
	ctx:    rawptr,
	list:   PluginLoader_List_Proc,
	action: PluginLoader_Action_Proc,
}

plugin_loader_backend: PluginLoader_Backend

PluginLoader_Set_Backend :: proc(backend: PluginLoader_Backend) {
	plugin_loader_backend = backend
}

PluginLoader_Class := classes.Class_Info {
	name   = "PluginLoader",
	parent = &Service_Class,
}

PluginLoader :: struct {
	using service: Service,
}

plugin_loader_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	instance := new(PluginLoader)
	instance.service = Service_Init(&PluginLoader_Class, "PluginLoader", data_model)
	return &instance.object
}

plugin_loader_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^PluginLoader)object)
}

plugin_loader_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "GetNativePlugins", "LoadNativePlugin", "UnloadNativePlugin":
		if !vm.ThreadHasSecurityCapability(L, PLUGIN_LOADER_INTERNALS) {return false}
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

plugin_loader_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "GetNativePlugins", "LoadNativePlugin", "UnloadNativePlugin":
		if !vm.ThreadHasSecurityCapability(L, PLUGIN_LOADER_INTERNALS) {
			return vm.RaiseError(L, "PluginLoader requires Internals capability"), true
		}
		if plugin_loader_backend.ctx == nil ||
		   plugin_loader_backend.list == nil ||
		   plugin_loader_backend.action == nil {
			return vm.RaiseError(
					L,
					"Native plugin loader is unavailable outside the local editor",
				),
				true
		}
		if method == "GetNativePlugins" {
			plugin_loader_backend.list(plugin_loader_backend.ctx, L)
			return 1, true
		}
		if !vm.IsString(L, 2) {
			return vm.RaiseError(L, "Expected native plugin ID as a string"), true
		}
		id := vm.ArgString(L, 2)
		action := method == "LoadNativePlugin" ? "load" : "unload"
		ok, err := plugin_loader_backend.action(plugin_loader_backend.ctx, action, id)
		defer delete(err)
		vm.PushBoolean(L, ok)
		vm.PushString(L, err)
		return 2, true
	}
	return 0, false
}

Register_PluginLoader_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&PluginLoader_Class,
		plugin_loader_construct,
		plugin_loader_destroy,
		creatable = false,
		get = plugin_loader_get,
		namecall = plugin_loader_namecall,
		methods = []string{"GetNativePlugins", "LoadNativePlugin", "UnloadNativePlugin"},
	)
}
