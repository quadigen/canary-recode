#+build js

package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:encoding/json"
import "core:strings"

foreign import "kinemium_storage"

@(default_calling_convention = "c")
foreign kinemium_storage {
	host_storage_get :: proc(key: cstring, out: [^]u8, cap: i32) -> i32 ---
	host_storage_set :: proc(key: cstring, value: [^]u8, len: i32) -> i32 ---
	host_storage_remove :: proc(key: cstring) -> i32 ---
}

web_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(object)
}


WEB_PROJECTS_KEY :: "kinemium.web.projects"
WEB_PROJECTS_PREFIX :: "kinemium://projects"
WEB_PROJECT_ENGINE_VERSION :: "1.19.0-dev"

Web_Project :: struct {
	name:           string,
	engine_version: string,
	icon:           string,
	path:           string,
	description:    string,
}

Web_File_Record :: struct {
	path:    string,
	type:    string,
	content: string,
}

Web_Project_Class := classes.Class_Info {
	name   = "Project",
	parent = &Service_Class,
}

Web_Project_Service :: struct {
	using service: Service,
	active:        string,
	projects:      [dynamic]Web_Project,
	files:         [dynamic]Web_File_Record,
}

Web_Project_Store :: struct {
	active:   string,
	projects: [dynamic]Web_Project,
	files:    [dynamic]Web_File_Record,
}

web_path_normalize :: proc(path: string) -> string {
	slashed, _ := strings.replace_all(path, "\\", "/", context.temp_allocator)

	end := len(slashed)
	for end > 0 && slashed[end - 1] == '/' {
		end -= 1
	}

	return slashed[:end]
}

web_path_name :: proc(path: string) -> string {
	if index := strings.last_index(path, "/"); index >= 0 {
		return path[index + 1:]
	}
	return path
}

web_path_parent :: proc(path: string) -> string {
	if index := strings.last_index(path, "/"); index > 0 {
		return path[:index]
	}
	return ""
}

web_path_is_child_of :: proc(path, dir: string) -> bool {
	if len(dir) == 0 || len(path) <= len(dir) {
		return false
	}
	if !strings.has_prefix(path, dir) {
		return false
	}
	return path[len(dir)] == '/'
}

web_path_is_direct_child_of :: proc(path, dir: string) -> bool {
	if !web_path_is_child_of(path, dir) {
		return false
	}
	return strings.index(path[len(dir) + 1:], "/") < 0
}

web_project_find :: proc(service: ^Web_Project_Service, path: string) -> (int, bool) {
	normalized := web_path_normalize(path)

	for &project, index in service.projects {
		if project.path == normalized {
			return index, true
		}
	}

	name := web_path_name(normalized)
	for &project, index in service.projects {
		if web_path_name(project.path) == name {
			return index, true
		}
	}

	return -1, false
}

web_project_add_dir :: proc(service: ^Web_Project_Service, path: string) {
	for &file in service.files {
		if file.path == path {
			return
		}
	}

	append(
		&service.files,
		Web_File_Record{path = strings.clone(path), type = "Directory", content = ""},
	)
}

web_project_set_file :: proc(service: ^Web_Project_Service, path, content: string) {
	for &file in service.files {
		if file.path == path {
			delete(file.content)
			file.type = "File"
			file.content = strings.clone(content)
			return
		}
	}

	append(
		&service.files,
		Web_File_Record {
			path = strings.clone(path),
			type = "File",
			content = strings.clone(content),
		},
	)
}

web_project_read_file :: proc(service: ^Web_Project_Service, path: string) -> (string, bool) {
	normalized := web_path_normalize(path)

	for &file in service.files {
		if file.path == normalized && file.type == "File" {
			return file.content, true
		}
	}

	return "", false
}

web_project_save :: proc(service: ^Web_Project_Service) {
	store := Web_Project_Store {
		active   = service.active,
		projects = service.projects,
		files    = service.files,
	}

	data, err := json.marshal(store)
	if err != nil {
		return
	}
	defer delete(data)

	key := strings.clone_to_cstring(WEB_PROJECTS_KEY)
	defer delete(key)

	_ = host_storage_set(key, raw_data(data), i32(len(data)))
}

web_project_load :: proc(service: ^Web_Project_Service) {
	key := strings.clone_to_cstring(WEB_PROJECTS_KEY)
	defer delete(key)

	size := host_storage_get(key, nil, 0)
	if size <= 0 {
		return
	}

	data := make([]u8, int(size), context.temp_allocator)
	got := host_storage_get(key, raw_data(data), i32(size))
	if got < 0 {
		return
	}

	store: Web_Project_Store
	if json.unmarshal_string(string(data[:got]), &store) != nil {
		return
	}

	service.active = store.active
	service.projects = store.projects
	service.files = store.files
}

web_project_create :: proc(
	service: ^Web_Project_Service,
	name, folder_path, description, icon: string,
) -> bool {
	if len(name) == 0 {
		return false
	}

	project_path := strings.concatenate({WEB_PROJECTS_PREFIX, "/", name})

	if _, exists := web_project_find(service, project_path); exists {
		delete(project_path)
		return false
	}

	append(
		&service.projects,
		Web_Project {
			name = strings.clone(name),
			engine_version = WEB_PROJECT_ENGINE_VERSION,
			icon = strings.clone(icon),
			path = project_path,
			description = strings.clone(description),
		},
	)

	web_project_add_dir(service, project_path)
	web_project_add_dir(service, strings.concatenate({project_path, "/assets"}))
	web_project_add_dir(service, strings.concatenate({project_path, "/assets/client"}))
	web_project_add_dir(service, strings.concatenate({project_path, "/assets/server"}))
	web_project_add_dir(service, strings.concatenate({project_path, "/assets/replicated"}))
	web_project_add_dir(service, strings.concatenate({project_path, "/scripts"}))
	web_project_add_dir(service, strings.concatenate({project_path, "/scripts/client"}))
	web_project_add_dir(service, strings.concatenate({project_path, "/scripts/server"}))

	if len(service.active) > 0 {
		delete(service.active)
	}
	service.active = strings.clone(project_path)

	web_project_save(service)

	return true
}

web_project_write_file :: proc(service: ^Web_Project_Service, path, content: string) -> bool {
	normalized := web_path_normalize(path)
	if len(normalized) == 0 {
		return false
	}

	for &project in service.projects {
		if !web_path_is_child_of(normalized, project.path) {
			continue
		}

		parent := web_path_parent(normalized)
		for len(parent) > len(project.path) && web_path_is_child_of(parent, project.path) {
			web_project_add_dir(service, parent)
			parent = web_path_parent(parent)
		}
		break
	}

	web_project_set_file(service, normalized, content)
	web_project_save(service)

	return true
}

web_project_push_project :: proc(L: ^vm.State, project: ^Web_Project) {
	vm.NewTable(L, 0, 5)

	vm.PushString(L, project.name)
	vm.SetField(L, -2, "Name")

	vm.PushString(L, project.engine_version)
	vm.SetField(L, -2, "EngineVersion")

	vm.PushString(L, project.icon)
	vm.SetField(L, -2, "Icon")

	vm.PushString(L, project.path)
	vm.SetField(L, -2, "Path")

	vm.PushString(L, project.description)
	vm.SetField(L, -2, "Description")
}

web_project_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Web_Project_Service)
	service.service = Service_Init(&Web_Project_Class, "Project", data_model)
	web_project_load(service)
	return &service.object
}

web_project_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^Web_Project_Service)object

	for &project in service.projects {
		delete(project.name)
		delete(project.engine_version)
		delete(project.icon)
		delete(project.path)
		delete(project.description)
	}
	delete(service.projects)

	for &file in service.files {
		delete(file.path)
		delete(file.type)
		delete(file.content)
	}
	delete(service.files)

	if len(service.active) > 0 {
		delete(service.active)
	}

	classes.Object_Destroy(object)
	free(service)
}

web_project_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "GetProjects",
	     "GetActiveProject",
	     "SetActiveProject",
	     "CreateProject",
	     "GetProjectEntries",
	     "PathExists",
	     "IsDirectory",
	     "ReadFile",
	     "WriteFile",
	     "CopyPathWindow":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

web_project_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^Web_Project_Service)object

	switch method {
	case "GetProjects":
		vm.NewTable(L, len(service.projects))

		for &project, index in service.projects {
			web_project_push_project(L, &project)
			vm.SetArrayValue(L, -2, index + 1)
		}

		return 1, true

	case "GetActiveProject":
		if index, ok := web_project_find(service, service.active); ok {
			web_project_push_project(L, &service.projects[index])
		} else {
			vm.PushNil(L)
		}

		return 1, true

	case "SetActiveProject":
		path := vm.ArgString(L, 2)

		index, ok := web_project_find(service, path)
		if !ok {
			vm.PushBoolean(L, false)
			return 1, true
		}

		if len(service.active) > 0 {
			delete(service.active)
		}
		service.active = strings.clone(service.projects[index].path)

		web_project_save(service)

		vm.PushBoolean(L, true)
		return 1, true

	case "CreateProject":
		name := vm.ArgString(L, 2)
		folder_path := vm.ArgString(L, 3)
		description := vm.ArgOptionalString(L, 4, "")
		icon := vm.ArgOptionalString(L, 5, "")

		vm.PushBoolean(L, web_project_create(service, name, folder_path, description, icon))
		return 1, true

	case "GetProjectEntries":
		directory := web_path_normalize(vm.ArgString(L, 2))

		vm.NewTable(L, 0)

		count := 0

		for &file in service.files {
			if !web_path_is_direct_child_of(file.path, directory) {
				continue
			}

			vm.NewTable(L, 0, 3)

			vm.PushString(L, web_path_name(file.path))
			vm.SetField(L, -2, "Name")

			vm.PushString(L, file.path)
			vm.SetField(L, -2, "Path")

			vm.PushString(L, file.type)
			vm.SetField(L, -2, "Type")

			vm.SetArrayValue(L, -2, count + 1)
			count += 1
		}

		return 1, true

	case "PathExists":
		path := web_path_normalize(vm.ArgString(L, 2))

		exists := false

		if _, ok := web_project_read_file(service, path); ok {
			exists = true
		} else {
			for &file in service.files {
				if web_path_is_child_of(file.path, path) {
					exists = true
					break
				}
			}

			if !exists {
				if _, ok := web_project_find(service, path); ok {
					exists = true
				}
			}
		}

		vm.PushBoolean(L, exists)
		return 1, true

	case "IsDirectory":
		path := web_path_normalize(vm.ArgString(L, 2))

		is_directory := false

		for &file in service.files {
			if file.path == path && file.type == "Directory" {
				is_directory = true
				break
			}
			if web_path_is_child_of(file.path, path) {
				is_directory = true
				break
			}
		}

		if !is_directory {
			if _, ok := web_project_find(service, path); ok {
				is_directory = true
			}
		}

		vm.PushBoolean(L, is_directory)
		return 1, true

	case "ReadFile":
		path := vm.ArgString(L, 2)

		if content, ok := web_project_read_file(service, path); ok {
			vm.PushString(L, content)
		} else {
			vm.PushNil(L)
		}

		return 1, true

	case "WriteFile":
		path := vm.ArgString(L, 2)
		content := vm.ArgString(L, 3)

		vm.PushBoolean(L, web_project_write_file(service, path, content))
		return 1, true

	case "CopyPathWindow":
		return 0, true
	}

	return 0, false
}

Web_PluginMarketplace_Class := classes.Class_Info {
	name   = "PluginMarketplace",
	parent = &Service_Class,
}

Web_PluginMarketplace :: struct {
	using service: Service,
}

web_plugin_marketplace_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Web_PluginMarketplace)
	service.service = Service_Init(&Web_PluginMarketplace_Class, "PluginMarketplace", data_model)
	return &service.object
}

web_plugin_marketplace_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "GetPlugins":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

web_plugin_marketplace_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "GetPlugins":
		vm.NewTable(L, 0)
		return 1, true
	}
	return 0, false
}

// ---- DialogService ----

Web_DialogService_Class := classes.Class_Info {
	name   = "DialogService",
	parent = &Service_Class,
}

Web_DialogService :: struct {
	using service: Service,
}

web_dialog_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Web_DialogService)
	service.service = Service_Init(&Web_DialogService_Class, "DialogService", data_model)
	return &service.object
}

web_dialog_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "PickFile", "PickFiles", "PickFolder", "PickSaveFile":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

web_dialog_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "PickFile", "PickFiles", "PickFolder", "PickSaveFile":
		vm.PushNil(L)
		return 1, true
	}
	return 0, false
}

// ---- Filesystem ----

Web_Filesystem_Class := classes.Class_Info {
	name   = "Filesystem",
	parent = &Service_Class,
}

Web_Filesystem :: struct {
	using service: Service,
}

web_filesystem_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Web_Filesystem)
	service.service = Service_Init(&Web_Filesystem_Class, "Filesystem", data_model)
	return &service.object
}

web_filesystem_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "MovePath",
	     "DeletePath",
	     "CopyPath",
	     "RenamePath",
	     "CreateFolder",
	     "CreateFile",
	     "PathExists",
	     "IsDirectory",
	     "ReadFile",
	     "WriteFile":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

web_filesystem_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "MovePath",
	     "DeletePath",
	     "CopyPath",
	     "RenamePath",
	     "CreateFolder",
	     "CreateFile",
	     "PathExists",
	     "IsDirectory",
	     "WriteFile":
		vm.PushBoolean(L, false)
		return 1, true
	case "ReadFile":
		vm.PushNil(L)
		return 1, true
	}
	return 0, false
}

// ---- PlaytestService ----

Web_PlaytestService_Class := classes.Class_Info {
	name   = "PlaytestService",
	parent = &Service_Class,
}

Web_PlaytestService :: struct {
	using service: Service,
}

web_playtest_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Web_PlaytestService)
	service.service = Service_Init(&Web_PlaytestService_Class, "PlaytestService", data_model)
	return &service.object
}

web_playtest_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "Start", "Stop", "StartSinglePlayer":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

web_playtest_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "Start", "Stop", "StartSinglePlayer":
		return 0, true
	}
	return 0, false
}

// ---- HttpService ----

Web_HttpService_Class := classes.Class_Info {
	name   = "HttpService",
	parent = &Service_Class,
}

Web_HttpService :: struct {
	using service: Service,
}

web_http_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Web_HttpService)
	service.service = Service_Init(&Web_HttpService_Class, "HttpService", data_model)
	return &service.object
}

web_http_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "JSONDecode", "JSONEncode", "RequestAsync", "GetAsync", "GetImageBytes", "UrlEncode":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

web_http_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "UrlEncode":
		vm.PushString(L, vm.ArgString(L, 2))
		return 1, true
	case "JSONDecode", "JSONEncode", "RequestAsync", "GetAsync", "GetImageBytes":
		vm.PushNil(L)
		return 1, true
	}
	return 0, false
}

// ---- ExportService ----

Web_ExportService_Class := classes.Class_Info {
	name   = "ExportService",
	parent = &Service_Class,
}

Web_ExportService :: struct {
	using service: Service,
}

web_export_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Web_ExportService)
	service.service = Service_Init(&Web_ExportService_Class, "ExportService", data_model)
	return &service.object
}

// ---- ExporterService ----
//
// The export panel (internal/exporter.luau) fetches this at load time. Baking a
// native executable needs the desktop host toolchain, so the browser build only
// provides the object so startup succeeds; ExportExecutable reports that the
// target is unavailable.

Web_ExporterService_Class := classes.Class_Info {
	name   = "ExporterService",
	parent = &Service_Class,
}

Web_ExporterService :: struct {
	using service: Service,
}

web_exporter_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Web_ExporterService)
	service.service = Service_Init(&Web_ExporterService_Class, "ExporterService", data_model)
	return &service.object
}

web_exporter_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "ExportExecutable":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

web_exporter_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "ExportExecutable":
		return vm.RaiseError(
				L,
				"ExporterService:ExportExecutable() is not available in the browser build",
			),
			true
	}
	return 0, false
}

// ---- TemplateService ----
//
// Only fetched (never called) by the export panel at load time; a bare object is
// enough to satisfy game:GetService("TemplateService").

Web_TemplateService_Class := classes.Class_Info {
	name   = "TemplateService",
	parent = &Service_Class,
}

Web_TemplateService :: struct {
	using service: Service,
}

web_template_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Web_TemplateService)
	service.service = Service_Init(&Web_TemplateService_Class, "TemplateService", data_model)
	return &service.object
}

// ---- UpdateService ----
//
// The browser build does not self-update; IsUpdateAvailable always reports no
// update so the editor's update_detector module starts and stays idle.

Web_UpdateService_Class := classes.Class_Info {
	name   = "UpdateService",
	parent = &Service_Class,
}

Web_UpdateService :: struct {
	using service: Service,
}

web_update_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Web_UpdateService)
	service.service = Service_Init(&Web_UpdateService_Class, "UpdateService", data_model)
	return &service.object
}

web_update_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "IsUpdateAvailable", "ApplyUpdate", "GetUpdateProgress", "FinishUpdateRestart":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

web_update_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "IsUpdateAvailable", "GetUpdateProgress":
		vm.PushNil(L)
		return 1, true
	case "ApplyUpdate", "FinishUpdateRestart":
		vm.PushBoolean(L, false)
		return 1, true
	}
	return 0, false
}

// ---- ContentProvider / EditorService ----
//
// The desktop build registers these two services for every target, so a native
// peer's replicated class surface always contains them. The browser build has no
// use for either (assets stream from the page and there is no native editor
// archive to manage), but the classes must still exist or the handshake's schema
// fingerprint will not match a native server: both classes inherit the replicable
// `Instance` properties, so their absence shifts the hash even though nothing
// about them is ever sent.
//
// They are registered as classes only. No service is created, so
// `game:GetService("ContentProvider")` and `game:GetService("EditorService")`
// keep behaving exactly as they did before this was added.

Web_ContentProvider_Class := classes.Class_Info {
	name   = "ContentProvider",
	parent = &Service_Class,
}

Web_ContentProvider :: struct {
	using service: Service,
}

web_content_provider_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Web_ContentProvider)
	service.service = Service_Init(&Web_ContentProvider_Class, "ContentProvider", data_model)
	return &service.object
}

Web_EditorService_Class := classes.Class_Info {
	name   = "EditorService",
	parent = &Service_Class,
}

Web_EditorService :: struct {
	using service: Service,
}

web_editor_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Web_EditorService)
	service.service = Service_Init(&Web_EditorService_Class, "EditorService", data_model)
	return &service.object
}

// ---- registration ----

Register_Web_Service_Classes :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Web_ContentProvider_Class,
		web_content_provider_construct,
		web_service_destroy,
		creatable = false,
	)
	classes.Register_Class(
		registry,
		&Web_EditorService_Class,
		web_editor_service_construct,
		web_service_destroy,
		creatable = false,
	)
	classes.Register_Class(
		registry,
		&Web_Project_Class,
		web_project_construct,
		web_project_destroy,
		creatable = false,
		get = web_project_get,
		namecall = web_project_namecall,
	)
	classes.Register_Class(
		registry,
		&Web_PluginMarketplace_Class,
		web_plugin_marketplace_construct,
		web_service_destroy,
		creatable = false,
		get = web_plugin_marketplace_get,
		namecall = web_plugin_marketplace_namecall,
	)
	classes.Register_Class(
		registry,
		&Web_DialogService_Class,
		web_dialog_construct,
		web_service_destroy,
		creatable = false,
		get = web_dialog_get,
		namecall = web_dialog_namecall,
	)
	classes.Register_Class(
		registry,
		&Web_Filesystem_Class,
		web_filesystem_construct,
		web_service_destroy,
		creatable = false,
		get = web_filesystem_get,
		namecall = web_filesystem_namecall,
	)
	classes.Register_Class(
		registry,
		&Web_PlaytestService_Class,
		web_playtest_construct,
		web_service_destroy,
		creatable = false,
		get = web_playtest_get,
		namecall = web_playtest_namecall,
	)
	classes.Register_Class(
		registry,
		&Web_HttpService_Class,
		web_http_construct,
		web_service_destroy,
		creatable = false,
		get = web_http_get,
		namecall = web_http_namecall,
	)
	classes.Register_Class(
		registry,
		&Web_ExportService_Class,
		web_export_construct,
		web_service_destroy,
		creatable = false,
	)
	classes.Register_Class(
		registry,
		&Web_UpdateService_Class,
		web_update_construct,
		web_service_destroy,
		creatable = false,
		get = web_update_get,
		namecall = web_update_namecall,
	)
	classes.Register_Class(
		registry,
		&Web_ExporterService_Class,
		web_exporter_construct,
		web_service_destroy,
		creatable = false,
		get = web_exporter_get,
		namecall = web_exporter_namecall,
	)
	classes.Register_Class(
		registry,
		&Web_TemplateService_Class,
		web_template_construct,
		web_service_destroy,
		creatable = false,
	)
}

Register_Web_Services :: proc(registry: ^Registry) {
	Register_Service(registry, "DialogService", "DialogService", "DialogService")
	Register_Service(registry, "ExportService", "ExportService", "ExportService")
	Register_Service(registry, "Filesystem", "Filesystem", "Filesystem")
	Register_Service(registry, "HttpService", "HttpService", "httpService")
	Register_Service(registry, "PlaytestService", "PlaytestService", "PlaytestService")
	Register_Service(registry, "PluginMarketplace", "PluginMarketplace", "PluginMarketplace")
	Register_Service(registry, "Project", "Project", "Project")
	Register_Service(registry, "UpdateService", "UpdateService", "UpdateService")
	Register_Service(registry, "ExporterService", "ExporterService", "ExporterService")
	Register_Service(registry, "TemplateService", "TemplateService", "TemplateService")
}
