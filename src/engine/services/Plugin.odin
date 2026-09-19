package services

// wire:service global="Plugin"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Plugin_Class := classes.Class_Info {
	name   = "Plugin",
	parent = &Service_Class,
}

Plugin :: struct {
	using service: Service,
	call_count:    i64,
}

Plugin_Engine :: struct {
	min_version: string `json:"minVersion"`,
}

Plugin_Assets :: struct {
	icon_url:      string `json:"iconUrl"`,
	thumbnail_url: string `json:"thumbnailUrl"`,
}

Plugin_Download :: struct {
	name:   string `json:"name"`,
	url:    string `json:"url"`,
	size:   i64    `json:"size"`,
	sha256: string `json:"sha256"`,
}

Plugin_Manifest :: struct {
	name:         string            `json:"name"`,
	id:           string            `json:"id"`,
	version:      string            `json:"version"`,
	description:  string            `json:"description"`,
	icon:         string            `json:"icon"`,
	thumbnail:    string            `json:"thumbnail"`,
	homepage:     string            `json:"homepage"`,
	repository:   string            `json:"repository"`,
	keywords:     []string          `json:"keywords"`,
	author:       string            `json:"author"`,
	license:      string            `json:"license"`,
	main:         string            `json:"main"`,
	engine:       Plugin_Engine     `json:"engine"`,
	dependencies: map[string]string `json:"dependencies"`,
	intents:      []string          `json:"intents"`,
}

KinemiumPlugin :: struct {
	slug:         string          `json:"slug"`,
	generated_at: string          `json:"generatedAt"`,
	updated_at:   string          `json:"updatedAt"`,
	manifest:     Plugin_Manifest `json:"manifest"`,
	assets:       Plugin_Assets   `json:"assets"`,
	download:     Plugin_Download `json:"download"`,
	details_url:  string          `json:"detailsUrl"`,
	file_count:   int             `json:"fileCount"`,
}

Plugin_List :: struct {
	version:      int      `json:"version"`,
	generated_at: string   `json:"generatedAt"`,
	plugin_count: int      `json:"pluginCount"`,
	plugins:      []KinemiumPlugin `json:"plugins"`,
}

plugins: Plugin_List

Plugin_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Plugin)
	service.service = Service_Init(&Plugin_Class, "Plugin", data_model)

	return &service.object
}

Plugin_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^Plugin)object
	switch key {
	case "CallCount":
		vm.PushNumber(L, f64(service.call_count))
	case "Add", "Echo", "MakeColor", "GetService":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

Plugin_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^Plugin)object
	switch method {
	case "Add":
		service.call_count += 1
		vm.PushNumber(L, vm.ArgNumber(L, 2) + vm.ArgNumber(L, 3))
		return 1, true
	case "Echo":
		service.call_count += 1
		vm.PushValue(L, 2)
		return 1, true
	case "MakeColor":
		service.call_count += 1
		if datatype_registry == nil {return 0, false}
		datatypes.Push_Color3(
			L,
			datatype_registry,
			datatypes.Color3 {
				f32(vm.ArgNumber(L, 2)),
				f32(vm.ArgNumber(L, 3)),
				f32(vm.ArgNumber(L, 4)),
			},
		)
		return 1, true
	case "GetService":
		classes.Push_Object(L, Service_Get_Service(&service.service, vm.ArgString(L, 2)))
		return 1, true
	}
	return 0, false
}

Plugin_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Plugin)object)
}

Register_Plugin_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Plugin_Class,
		Plugin_construct,
		Plugin_destroy,
		creatable = false,
		get = Plugin_get,
		namecall = Plugin_namecall,
	)
}
