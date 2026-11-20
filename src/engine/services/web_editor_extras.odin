#+build js
package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:strings"

Web_Editor_Extra :: struct {
	using service:      Service,
	marketplace_server: string,
}

Web_MatrixService_Class := classes.Class_Info {
	name   = "MatrixService",
	parent = &Service_Class,
}
web_MatrixService_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	s := new(Web_Editor_Extra)
	s.service = Service_Init(&Web_MatrixService_Class, "MatrixService", data_model)
	return &s.object
}

Web_Packages_Class := classes.Class_Info {
	name   = "Packages",
	parent = &Service_Class,
}
web_Packages_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	s := new(Web_Editor_Extra)
	s.service = Service_Init(&Web_Packages_Class, "Packages", data_model)
	return &s.object
}

Web_ZipService_Class := classes.Class_Info {
	name   = "ZipService",
	parent = &Service_Class,
}
web_ZipService_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	s := new(Web_Editor_Extra)
	s.service = Service_Init(&Web_ZipService_Class, "ZipService", data_model)
	return &s.object
}

Web_Plugin_Class := classes.Class_Info {
	name   = "Plugin",
	parent = &Service_Class,
}
web_Plugin_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	s := new(Web_Editor_Extra)
	s.service = Service_Init(&Web_Plugin_Class, "Plugin", data_model)
	return &s.object
}

Web_DiscordRPC_Class := classes.Class_Info {
	name   = "DiscordRPC",
	parent = &Service_Class,
}
web_DiscordRPC_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	s := new(Web_Editor_Extra)
	s.service = Service_Init(&Web_DiscordRPC_Class, "DiscordRPC", data_model)
	return &s.object
}

Web_CollaborationService_Class := classes.Class_Info {
	name   = "CollaborationService",
	parent = &Service_Class,
}
web_CollaborationService_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	s := new(Web_Editor_Extra)
	s.service = Service_Init(&Web_CollaborationService_Class, "CollaborationService", data_model)
	return &s.object
}

web_editor_extra_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	s := cast(^Web_Editor_Extra)object
	delete(s.marketplace_server)
	classes.Object_Destroy(object)
	free(s)
}

web_editor_extra_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	s := cast(^Web_Editor_Extra)object
	switch object.class.name {
	case "MatrixService":
		switch key {
		case "Session":
			vm.PushNil(L); return true
		case "DefaultHomeserver":
			vm.PushString(L, "https://matrix.org"); return true
		case "GetSession",
		     "GetProfile",
		     "Login",
		     "Register",
		     "SetSession",
		     "ResolveHomeserver",
		     "NormalizeUsername",
		     "MxcToHttp":
			vm.PushUserdataMethod(L, key); return true
		}
	case "Packages":
		switch key {
		case "MarketplaceServer":
			vm.PushString(
				L,
				s.marketplace_server if s.marketplace_server != "" else "https://opus.quadigen.com",
			)
			return true
		case "ListDownloadedPackages",
		     "BrowseMarketplace",
		     "GetMarketplacePackage",
		     "DownloadPackage",
		     "PublishInstance":
			vm.PushUserdataMethod(L, key); return true
		}
	case "DiscordRPC":
		if key == "SetPresence" ||
		   key == "ClearPresence" {vm.PushUserdataMethod(L, key); return true}
	case "Plugin":
		if key == "__SyncPluginToolbars" ||
		   key == "__PluginActionClicked" ||
		   key == "__PluginDockWidgetClosed" {vm.PushUserdataMethod(L, key); return true}
	case "CollaborationService":
		if key == "IsConnected" {vm.PushBoolean(L, false); return true}
	}
	return false
}
web_editor_extra_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	if object.class.name == "Packages" && key == "MarketplaceServer" {
		s := cast(^Web_Editor_Extra)object
		delete(s.marketplace_server)
		s.marketplace_server = strings.clone(vm.ArgString(L, index))
		return true
	}
	return false
}
web_editor_extra_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "GetSession", "MxcToHttp":
		vm.PushNil(L); return 1, true
	case "NormalizeUsername":
		vm.PushString(L, vm.ArgString(L, 2)); return 1, true
	case "ListDownloadedPackages":
		vm.NewTable(L, 0); return 1, true
	case "SetPresence",
	     "ClearPresence",
	     "__SyncPluginToolbars",
	     "__PluginActionClicked",
	     "__PluginDockWidgetClosed":
		return 0, true
	case "GetProfile",
	     "Login",
	     "Register",
	     "SetSession",
	     "ResolveHomeserver",
	     "BrowseMarketplace",
	     "GetMarketplacePackage",
	     "DownloadPackage",
	     "PublishInstance":
		vm.PushBoolean(L, false)
		vm.PushString(L, "This desktop integration is unavailable in the web editor")
		return 2, true
	case:
		return 0, false
	}
}
Register_Web_Editor_Extras :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Web_MatrixService_Class,
		web_MatrixService_construct,
		web_editor_extra_destroy,
		creatable = false,
		get = web_editor_extra_get,
		set = web_editor_extra_set,
		namecall = web_editor_extra_namecall,
	)
	classes.Register_Class(
		registry,
		&Web_Packages_Class,
		web_Packages_construct,
		web_editor_extra_destroy,
		creatable = false,
		get = web_editor_extra_get,
		set = web_editor_extra_set,
		namecall = web_editor_extra_namecall,
	)
	classes.Register_Class(
		registry,
		&Web_ZipService_Class,
		web_ZipService_construct,
		web_editor_extra_destroy,
		creatable = false,
		get = web_editor_extra_get,
		set = web_editor_extra_set,
		namecall = web_editor_extra_namecall,
	)
	classes.Register_Class(
		registry,
		&Web_Plugin_Class,
		web_Plugin_construct,
		web_editor_extra_destroy,
		creatable = false,
		get = web_editor_extra_get,
		set = web_editor_extra_set,
		namecall = web_editor_extra_namecall,
	)
	classes.Register_Class(
		registry,
		&Web_DiscordRPC_Class,
		web_DiscordRPC_construct,
		web_editor_extra_destroy,
		creatable = false,
		get = web_editor_extra_get,
		set = web_editor_extra_set,
		namecall = web_editor_extra_namecall,
	)
	classes.Register_Class(
		registry,
		&Web_CollaborationService_Class,
		web_CollaborationService_construct,
		web_editor_extra_destroy,
		creatable = false,
		get = web_editor_extra_get,
		set = web_editor_extra_set,
		namecall = web_editor_extra_namecall,
	)
}
Register_Web_Editor_Extra_Services :: proc(registry: ^Registry) {
	Register_Service(registry, "MatrixService", "MatrixService")
	Register_Service(registry, "Packages", "Packages")
	Register_Service(registry, "ZipService", "ZipService")
	Register_Service(registry, "Plugin", "Plugin")
	Register_Service(registry, "DiscordRPC", "DiscordRPC")
	Register_Service(registry, "CollaborationService", "CollaborationService")
}
