package services


import assetstore "../assetstore"
import "core:encoding/json"
import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

LocalizationService_Class := classes.Class_Info {
	name   = "LocalizationService",
	parent = &Service_Class,
}

LocalizationService :: struct {
	using service:    Service,
	roblox_locale_id: string,
	system_locale_id: string,
	dictionaries:     map[string]json.Object,
}

localization_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(LocalizationService)
	service.service = Service_Init(&LocalizationService_Class, "LocalizationService", data_model)


	service.roblox_locale_id = strings.clone("en-us")
	service.system_locale_id = strings.clone("en-us")
	service.dictionaries = make(map[string]json.Object)

	return &service.object
}

localization_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^LocalizationService)object

	switch key {
	case "RobloxLocaleId":
		vm.PushString(L, service.roblox_locale_id)

	case "SystemLocaleId":
		vm.PushString(L, service.system_locale_id)

	case "SetLocale", "LoadTranslations", "LoadTranslationFile", "Translate":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}

localization_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^LocalizationService)object

	switch method {
	case "SetLocale":
		locale := vm.ArgString(L, 2)
		if len(locale) == 0 {
			return vm.RaiseError(L, "locale must not be empty"), true
		}

		delete(service.roblox_locale_id)
		service.roblox_locale_id = strings.to_lower(locale, context.allocator)

		if !vm.IsNoneOrNil(L, 3) {
			delete(service.system_locale_id)
			service.system_locale_id = strings.clone(vm.ArgString(L, 3))
		}

		localization_changed(service)
		return 0, true
	case "LoadTranslations":
		vm.PushBoolean(L, localization_load(service, vm.ArgString(L, 2), vm.ArgString(L, 3)))
		return 1, true
	case "LoadTranslationFile":
		locale, path := vm.ArgString(L, 2), vm.ArgString(L, 3)
		if data, found := assetstore.Resolve_Bytes(path); found {
			vm.PushBoolean(L, localization_load(service, locale, string(data)))
			return 1, true
		}
		if assetstore.Is_Uri(path) ||
		   !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			vm.PushBoolean(L, false)
			return 1, true
		}
		data, found := assetstore.Read_Asset_File(path)
		if !found {vm.PushBoolean(L, false); return 1, true}
		defer delete(data)
		vm.PushBoolean(L, localization_load(service, locale, string(data)))
		return 1, true
	case "Translate":
		vm.PushString(L, localization_translate(service, vm.ArgString(L, 2)))
		return 1, true
	}
	return 0, false
}

localization_load :: proc(service: ^LocalizationService, locale, source: string) -> bool {
	if locale == "" {return false}
	value, err := json.parse_string(source, allocator = context.allocator)
	if err != nil {return false}
	entries, ok := value.(json.Object)
	if !ok {json.destroy_value(value); return false}
	for _, entry in entries {
		if _, valid := entry.(json.String); !valid {json.destroy_value(value); return false}
	}
	key := strings.to_lower(locale, context.allocator)
	for old_key, old in service.dictionaries {
		if old_key == key {
			delete_key(&service.dictionaries, old_key)
			json.destroy_value(json.Value(old))
			delete(old_key)
			break
		}
	}
	service.dictionaries[key] = entries
	localization_changed(service)
	return true
}

localization_translate :: proc(
	service: ^LocalizationService,
	source: string,
	object: ^classes.Object = nil,
) -> string {
	if service == nil || source == "" {return source}
	path := ""
	path_resolved := false
	best := -1
	result := source
	for child in service.children {
		if child == nil ||
		   child.destroyed ||
		   child.class != &classes.LocalizationTable_Class {continue}
		if !path_resolved &&
		   object != nil {path = classes.Get_Full_Name(object); path_resolved = true}
		value, score, found := classes.LocalizationTable_Translate(
			cast(^classes.LocalizationTable)child,
			source,
			service.roblox_locale_id,
			path,
		)
		if found && score > best {result, best = value, score}
	}
	if best >= 0 {return result}
	if dictionary, found := service.dictionaries[service.roblox_locale_id]; found {
		if translated, ok := dictionary[source].(json.String); ok {return string(translated)}
	}
	return source
}

localization_render_text :: proc(
	data_model: rawptr,
	source: string,
	object: ^classes.Object,
) -> string {
	model := cast(^DataModel)data_model
	if model == nil || model.registry == nil {return source}
	descriptor := Find_Service(model.registry, "LocalizationService")
	if descriptor == nil || descriptor.object == nil || descriptor.object.destroyed {return source}
	return localization_translate(cast(^LocalizationService)descriptor.object, source, object)
}

localization_changed :: proc(service: ^LocalizationService) {
	if service.data_model == nil || service.data_model.registry == nil {return}
	classes.Invalidate_Localized_Text(service.data_model.registry.classes)
}

localization_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^LocalizationService)object

	delete(service.roblox_locale_id)
	delete(service.system_locale_id)
	for key, dictionary in service.dictionaries {
		json.destroy_value(json.Value(dictionary))
		delete(key)
	}
	delete(service.dictionaries)

	classes.Object_Destroy(object)
	free(service)
}

localization_service_parallel_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "RobloxLocaleId", "SystemLocaleId", "Translate":
		return localization_service_get(L, object, d, e, key)
	}
	return false
}

localization_service_parallel_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "Translate":
		return localization_service_namecall(L, object, d, e, method)
	}
	return 0, false
}

Register_LocalizationService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&LocalizationService_Class,
		localization_service_construct,
		localization_service_destroy,
		creatable = false,
		get = localization_service_get,
		parallel_get = localization_service_parallel_get,
		namecall = localization_service_namecall,
		parallel_namecall = localization_service_parallel_namecall,
	)
}
