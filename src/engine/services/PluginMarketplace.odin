package services

// wire:service global="PluginMarketplace"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:encoding/json"
import "core:fmt"

PLUGIN_MARKETPLACE_BASE_URL :: "https://quadigen.github.io/Kinemium-Engine-Plugins/"

PLUGIN_MARKETPLACE_REGISTRY_URL :: "https://quadigen.github.io/Kinemium-Engine-Plugins/plugins.json"
PLUGIN_MARKETPLACE_INTERNALS_CAPABILITY :: i64(2)

PluginMarketplace_Class := classes.Class_Info {
	name   = "PluginMarketplace",
	parent = &Service_Class,
}

PluginMarketplace :: struct {
	using service: Service,
	call_count:    i64,
}

PluginMarketplace_Load_Image :: proc(
	http_service: ^HttpService,
	slug: string,
	kind: string,
	relative_url: string,
) -> string {
	if len(relative_url) == 0 {
		return ""
	}

	url := fmt.aprintf(
		"%s%s",
		PLUGIN_MARKETPLACE_BASE_URL,
		relative_url,
		allocator = context.allocator,
	)
	defer delete(url)

	fmt.println("[Marketplace] fetching ", kind, ": ", url)

	data, ok := HttpService_GetAsync(
		http_service,
		url,
		context.allocator,
	)

	fmt.println(
		"[Marketplace] fetch returned: ok=",
		ok,
		" bytes=",
		len(data),
	)

	if !ok || len(data) == 0 {
		return ""
	}
	defer delete(data)

	content_id := fmt.aprintf(
		"memory://marketplace/%s/%s",
		slug,
		kind,
		allocator = context.allocator,
	)
	defer delete(content_id)

	fmt.println("[Marketplace] registering ", content_id)

	result := classes.ImageLabel_Register_Runtime_Image(
		content_id,
		data,
	)

	fmt.println("[Marketplace] registered ", result)

	return result
}

PluginMarketplace_push_string_array :: proc(L: ^vm.State, values: []string) {
	vm.NewTable(L, len(values))

	for value, index in values {
		vm.PushString(L, value)
		vm.SetArrayValue(L, -2, index + 1)
	}
}

PluginMarketplace_push_dependencies :: proc(L: ^vm.State, dependencies: map[string]string) {
	vm.NewTable(L, 0, len(dependencies))

	for key, value in dependencies {
		vm.PushString(L, value)
		vm.SetField(L, -2, key)
	}
}

PluginMarketplace_push_plugin :: proc(
	L: ^vm.State,
	plugin: ^KinemiumPlugin,
	http_service: ^HttpService,
) {
	icon_source := PluginMarketplace_Load_Image(
		http_service,
		plugin.slug,
		"icon",
		plugin.assets.icon_url,
	)

	thumbnail_source := PluginMarketplace_Load_Image(
		http_service,
		plugin.slug,
		"thumbnail",
		plugin.assets.thumbnail_url,
	)

	vm.NewTable(L, 0, 8)

	vm.PushString(L, plugin.slug)
	vm.SetField(L, -2, "Slug")

	vm.PushString(L, plugin.generated_at)
	vm.SetField(L, -2, "GeneratedAt")

	vm.PushString(L, plugin.updated_at)
	vm.SetField(L, -2, "UpdatedAt")

	// Manifest
	vm.NewTable(L, 0, 15)

	vm.PushString(L, plugin.manifest.name)
	vm.SetField(L, -2, "Name")

	vm.PushString(L, plugin.manifest.id)
	vm.SetField(L, -2, "Id")

	vm.PushString(L, plugin.manifest.version)
	vm.SetField(L, -2, "Version")

	vm.PushString(L, plugin.manifest.description)
	vm.SetField(L, -2, "Description")

	vm.PushString(L, plugin.manifest.icon)
	vm.SetField(L, -2, "Icon")

	vm.PushString(L, plugin.manifest.thumbnail)
	vm.SetField(L, -2, "Thumbnail")

	vm.PushString(L, plugin.manifest.homepage)
	vm.SetField(L, -2, "Homepage")

	vm.PushString(L, plugin.manifest.repository)
	vm.SetField(L, -2, "Repository")

	vm.PushString(L, plugin.manifest.author)
	vm.SetField(L, -2, "Author")

	vm.PushString(L, plugin.manifest.license)
	vm.SetField(L, -2, "License")

	vm.PushString(L, plugin.manifest.main)
	vm.SetField(L, -2, "Main")

	PluginMarketplace_push_string_array(L, plugin.manifest.keywords)
	vm.SetField(L, -2, "Keywords")

	PluginMarketplace_push_string_array(L, plugin.manifest.intents)
	vm.SetField(L, -2, "Intents")

	PluginMarketplace_push_dependencies(L, plugin.manifest.dependencies)
	vm.SetField(L, -2, "Dependencies")

	vm.NewTable(L, 0, 1)
	vm.PushString(L, plugin.manifest.engine.min_version)
	vm.SetField(L, -2, "MinVersion")
	vm.SetField(L, -2, "Engine")

	vm.SetField(L, -2, "Manifest")

	// Assets
	vm.NewTable(L, 0, 2)

	vm.PushString(L, icon_source)
	vm.SetField(L, -2, "IconUrl")

	vm.PushString(L, thumbnail_source)
	vm.SetField(L, -2, "ThumbnailUrl")

	vm.SetField(L, -2, "Assets")

	// Download
	vm.NewTable(L, 0, 4)

	vm.PushString(L, plugin.download.name)
	vm.SetField(L, -2, "Name")

	vm.PushString(L, plugin.download.url)
	vm.SetField(L, -2, "Url")

	vm.PushNumber(L, f64(plugin.download.size))
	vm.SetField(L, -2, "Size")

	vm.PushString(L, plugin.download.sha256)
	vm.SetField(L, -2, "Sha256")

	vm.SetField(L, -2, "Download")

	vm.PushString(L, plugin.details_url)
	vm.SetField(L, -2, "DetailsUrl")

	vm.PushNumber(L, f64(plugin.file_count))
	vm.SetField(L, -2, "FileCount")
}

PluginMarketplace_push_plugins :: proc(
	L: ^vm.State,
	plugins: []KinemiumPlugin,
	http_service: ^HttpService,
) {
	vm.NewTable(L, len(plugins))

	for &plugin, index in plugins {
		PluginMarketplace_push_plugin(L, &plugin, http_service)

		vm.SetArrayValue(L, -2, index + 1)
	}
}

plugin_marketplace_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(PluginMarketplace)
	service.service = Service_Init(&PluginMarketplace_Class, "PluginMarketplace", data_model)

	return &service.object
}

plugin_marketplace_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^PluginMarketplace)object
	switch key {
	case "GetPlugins":
		if !vm.ThreadHasSecurityCapability(L, PLUGIN_MARKETPLACE_INTERNALS_CAPABILITY) {
			return false
		}

		vm.PushUserdataMethod(L, key)

	case:
		return false
	}
	return true
}

plugin_marketplace_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^PluginMarketplace)object
	switch method {
	case "GetPlugins":
		if !vm.ThreadHasSecurityCapability(L, PLUGIN_MARKETPLACE_INTERNALS_CAPABILITY) {
			return vm.RaiseError(
					L,
					"PluginMarketplace:GetPlugins() requires Internals capability",
				),
				true
		}

		http_service_obj := Service_Get_Service(&service.service, "HttpService")
		if http_service_obj == nil {
			return vm.RaiseError(L, "PluginMarketplace:GetPlugins(): HttpService is unavailable"),
				true
		}

		http_service := cast(^HttpService)(http_service_obj)

		link := PLUGIN_MARKETPLACE_REGISTRY_URL

		fmt.println("Fetching plugin registry: ", link)

		body, ok := HttpService_GetAsync(http_service, link, context.allocator)

		if !ok {
			fmt.println("Plugin registry HTTP request failed")

			return vm.RaiseError(L, "PluginMarketplace:GetPlugins(): HTTP request failed"), true
		}

		defer delete(body)

		fmt.println("Plugin registry response bytes: ", len(body))

		list: Plugin_List

		err := json.unmarshal_string(body, &list)
		if err != nil {
			fmt.println("Plugin registry JSON decode failed: ", err)

			return vm.RaiseError(L, "PluginMarketplace:GetPlugins(): invalid registry JSON"), true
		}

		fmt.println("Loaded plugins: ", len(list.plugins))

		PluginMarketplace_push_plugins(L, list.plugins, http_service)

		return 1, true
	}
	return 0, false
}

plugin_marketplace_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^PluginMarketplace)object)
}

Register_PluginMarketplace_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&PluginMarketplace_Class,
		plugin_marketplace_construct,
		plugin_marketplace_destroy,
		creatable = false,
		get = plugin_marketplace_get,
		namecall = plugin_marketplace_namecall,
	)
}
