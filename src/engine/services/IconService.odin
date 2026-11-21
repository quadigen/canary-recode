package services


import assetstore "../assetstore"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:fmt"
import "core:strings"

IconService_Class := classes.Class_Info {
	name   = "IconService",
	parent = &Service_Class,
}

IconService :: struct {
	using service: Service,
}

icon_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(IconService)
	service.service = Service_Init(&IconService_Class, "IconService", data_model)
	return &service.object
}

icon_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^IconService)object)
}

icon_service_has_method :: proc(method: string) -> bool {
	switch method {
	case "RegisterIconPack", "LoadIconPack", "SetIconPack", "ResetIconPack", "UnregisterIconPack":
		return true
	}
	return false
}

icon_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {return false}
	if key == "ActiveIconPack" {
		vm.PushString(L, classes.IconPack_Active())
	} else if icon_service_has_method(key) {
		vm.PushUserdataMethod(L, key)
	} else {
		return false
	}
	return true
}

icon_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if !icon_service_has_method(method) {return 0, false}
	if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
		return vm.RaiseError(L, "IconService requires Internals capability"), true
	}
	switch method {
	case "RegisterIconPack":
		name := vm.ArgString(L, 2)
		if !vm.IsTable(
			L,
			3,
		) {return vm.RaiseError(L, "Expected an icon name to image bytes table"), true}
		icons: map[string]string
		vm.PushNil(L)
		for vm.Next(L, 3) {
			key, key_ok := vm.ToString(L, -2)
			data, data_ok := vm.ToString(L, -1)
			canonical := classes.IconPack_Key(key)
			if !key_ok || !data_ok || canonical == "" || data == "" || canonical in icons {
				classes.IconPack_Free_Entries(icons)
				return vm.RaiseError(L, "Invalid or duplicate icon entry"), true
			}
			icons[strings.clone(canonical)] = strings.clone(data)
			vm.Pop(L)
		}
		ok := classes.IconPack_Register(name, icons)
		if !ok {classes.IconPack_Free_Entries(icons)}
		vm.PushBoolean(L, ok)
	case "LoadIconPack":
		name := vm.ArgString(L, 2)
		directory := vm.ArgString(L, 3)
		if name == "" || name == classes.DEFAULT_ICON_PACK || directory == "" {
			vm.PushBoolean(L, false)
			return 1, true
		}
		icons: map[string]string
		when ODIN_OS != .JS {
			for file in classes.IMAGE_LABEL_CLASS_ICONS {
				path := fmt.tprintf("%s/%s", directory, file.name)
				data, found := assetstore.Read_Asset_File(path)
				if !found || len(data) == 0 {delete(data); continue}
				key := classes.IconPack_Key(file.name)
				icons[strings.clone(key)] = transmute(string)data
			}
		}
		ok := classes.IconPack_Register(name, icons)
		if !ok {classes.IconPack_Free_Entries(icons)}
		vm.PushBoolean(L, ok)
	case "SetIconPack":
		vm.PushBoolean(L, classes.IconPack_Set(vm.ArgString(L, 2)))
	case "ResetIconPack":
		vm.PushBoolean(L, classes.IconPack_Set(classes.DEFAULT_ICON_PACK))
	case "UnregisterIconPack":
		vm.PushBoolean(L, classes.IconPack_Remove(vm.ArgString(L, 2)))
	case:
		return 0, false
	}
	return 1, true
}

Register_IconService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&IconService_Class,
		icon_service_construct,
		icon_service_destroy,
		creatable = false,
		get = icon_service_get,
		namecall = icon_service_namecall,
	)
}
