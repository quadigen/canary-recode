#+build !js
package services

// wire:service global="Project"

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:os"
import "core:path/filepath"
import "core:strings"

Project_Class := classes.Class_Info {
	name   = "Project",
	parent = &Service_Class,
}

ProjectService :: struct {
	using service:       Service,
	call_count:          i64,
	projects:            [dynamic]KinemiumProject,
	registry_path:       string,
	active_project_path: string,
}

KinemiumProject :: struct {
	name:           string,
	engine_version: string,
	icon:           string,
	path:           string,
	description:    string,
}

KinemiumProjectList :: struct {
	projects: []KinemiumProject,
}

PROJECT_INTERNALS_CAPABILITY :: i64(2)
PROJECT_ENGINE_VERSION :: "1.19.0-dev"

Project_Name_Is_Valid :: proc(name: string) -> bool {
	if len(name) == 0 || name == "." || name == ".." {
		return false
	}

	has_non_whitespace := false

	for c in name {
		switch c {
		case '/', '\\', ':', '*', '?', '"', '<', '>', '|':
			return false
		}

		if c != ' ' && c != '\t' {
			has_non_whitespace = true
		}
	}

	if !has_non_whitespace {
		return false
	}

	last := name[len(name) - 1]

	if last == ' ' || last == '.' {
		return false
	}

	return true
}

Project_Create :: proc(
	service: ^ProjectService,
	name: string,
	folder_path: string,
	description: string = "",
	icon: string = "",
) -> bool {
	if !Project_Name_Is_Valid(name) {
		return false
	}

	base_path, ok := Project_Normalize_Path(folder_path)
	if !ok {
		return false
	}
	defer delete(base_path)

	if err := os.make_directory_all(base_path); err != nil {
		return false
	}

	project_path, join_err := os.join_path({base_path, name}, context.allocator)
	if join_err != nil {
		return false
	}
	defer delete(project_path)

	if os.exists(project_path) {
		return false
	}

	if err := os.make_directory_all(project_path); err != nil {
		return false
	}

	project := KinemiumProject {
		name           = name,
		engine_version = PROJECT_ENGINE_VERSION,
		icon           = icon,
		path           = project_path,
		description    = description,
	}

	if !Project_Add(service, project) {
		return false
	}

	return Project_Set_Active(service, project_path)
}

Project_push_project :: proc(L: ^vm.State, project: ^KinemiumProject) {
	if project == nil {
		vm.PushNil(L)
		return
	}

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

Project_push_projects :: proc(L: ^vm.State, service: ^ProjectService) {
	vm.NewTable(L, len(service.projects))

	for &project, index in service.projects {
		Project_push_project(L, &project)
		vm.SetArrayValue(L, -2, index + 1)
	}
}

Project_Get_Active :: proc(service: ^ProjectService) -> ^KinemiumProject {
	if len(service.active_project_path) == 0 {
		return nil
	}

	for &project in service.projects {
		if os.are_paths_identical(project.path, service.active_project_path) {
			return &project
		}
	}

	return nil
}

Project_Set_Active :: proc(service: ^ProjectService, path: string) -> bool {
	index, found := Project_Find_By_Path(service, path)
	if !found {
		return false
	}

	if len(service.active_project_path) > 0 {
		delete(service.active_project_path)
	}

	service.active_project_path = strings.clone(service.projects[index].path)

	return true
}

Project_Normalize_Path :: proc(path: string) -> (string, bool) {
	absolute, err := filepath.abs(path)
	if err != nil {
		return "", false
	}

	return absolute, true
}

Project_Find_By_Path :: proc(service: ^ProjectService, path: string) -> (int, bool) {
	normalized, ok := Project_Normalize_Path(path)
	if !ok {
		return -1, false
	}
	defer delete(normalized)

	for project, index in service.projects {
		if os.are_paths_identical(project.path, normalized) {
			return index, true
		}
	}

	return -1, false
}

Project_Registry_Path :: proc() -> (string, bool) {
	data_dir, err := os.user_data_dir(context.allocator)
	if err != nil {
		return "", false
	}
	defer delete(data_dir)

	kinemium_dir, alloc_err := os.join_path({data_dir, "Kinemium"}, context.allocator)
	if alloc_err != nil {
		return "", false
	}
	defer delete(kinemium_dir)

	if !os.exists(kinemium_dir) {
		if err := os.make_directory_all(kinemium_dir); err != nil {
			return "", false
		}
	}

	path, alloc_err2 := os.join_path({kinemium_dir, "projects.yaml"}, context.allocator)
	if alloc_err2 != nil {
		return "", false
	}

	return path, true
}

Project_Yaml_Node_String :: proc(node: ^kineffi.yaml_node_t) -> string {
	if node == nil || node.type != .SCALAR_NODE {
		return ""
	}

	return strings.string_from_ptr(node.data.scalar.value, int(node.data.scalar.length))
}

Project_Yaml_Get :: proc(
	document: ^kineffi.yaml_document_t,
	mapping: ^kineffi.yaml_node_t,
	key: string,
) -> ^kineffi.yaml_node_t {
	if mapping == nil || mapping.type != .MAPPING_NODE {
		return nil
	}

	start := mapping.data.mapping.pairs.start
	top := mapping.data.mapping.pairs.top

	if start == nil || top == nil {
		return nil
	}

	count := int((uintptr(top) - uintptr(start)) / size_of(kineffi.yaml_node_pair_t))

	pairs := ([^]kineffi.yaml_node_pair_t)(start)[:count]

	for pair in pairs {
		key_node := kineffi.yaml_document_get_node(document, pair.key)

		if key_node == nil || key_node.type != .SCALAR_NODE {
			continue
		}

		key_value := Project_Yaml_Node_String(key_node)

		if key_value == key {
			return kineffi.yaml_document_get_node(document, pair.value)
		}
	}

	return nil
}

Project_Load :: proc(service: ^ProjectService) -> bool {
	if !os.is_file(service.registry_path) {
		return Project_Save(service)
	}

	data, err := os.read_entire_file(service.registry_path, context.allocator)
	if err != nil {
		return false
	}
	defer delete(data)

	parser: kineffi.yaml_parser_t

	if kineffi.yaml_parser_initialize(&parser) == 0 {
		return false
	}
	defer kineffi.yaml_parser_delete(&parser)

	input: ^u8 = nil

	if len(data) > 0 {
		input = raw_data(data)
	}

	kineffi.yaml_parser_set_input_string(&parser, input, len(data))

	document: kineffi.yaml_document_t

	if kineffi.yaml_parser_load(&parser, &document) == 0 {
		return false
	}
	defer kineffi.yaml_document_delete(&document)

	root := kineffi.yaml_document_get_root_node(&document)
	if root == nil {
		return true
	}

	projects_node := Project_Yaml_Get(&document, root, "projects")

	if projects_node == nil || projects_node.type != .SEQUENCE_NODE {
		return true
	}

	start := projects_node.data.sequence.items.start
	top := projects_node.data.sequence.items.top

	if start == nil || top == nil {
		return true
	}

	count := int((uintptr(top) - uintptr(start)) / size_of(kineffi.yaml_node_item_t))

	items := ([^]kineffi.yaml_node_item_t)(start)[:count]

	for node_id in items {
		node := kineffi.yaml_document_get_node(&document, node_id)

		if node == nil || node.type != .MAPPING_NODE {
			continue
		}

		name := Project_Yaml_Get(&document, node, "name")
		version := Project_Yaml_Get(&document, node, "engine_version")
		icon := Project_Yaml_Get(&document, node, "icon")
		path := Project_Yaml_Get(&document, node, "path")
		description := Project_Yaml_Get(&document, node, "description")

		project := KinemiumProject {
			name           = strings.clone(Project_Yaml_Node_String(name)),
			engine_version = strings.clone(Project_Yaml_Node_String(version)),
			icon           = strings.clone(Project_Yaml_Node_String(icon)),
			path           = strings.clone(Project_Yaml_Node_String(path)),
			description    = strings.clone(Project_Yaml_Node_String(description)),
		}

		append(&service.projects, project)
	}

	return true
}

Project_Write_Field :: proc(
	builder: ^strings.Builder,
	name: string,
	value: string,
	indent: string,
) {
	strings.write_string(builder, indent)
	strings.write_string(builder, name)
	strings.write_string(builder, ": ")
	strings.write_quoted_string(builder, value)
	strings.write_byte(builder, '\n')
}

Project_Save :: proc(service: ^ProjectService) -> bool {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, "projects:\n")

	for project in service.projects {
		strings.write_string(&builder, "  - ")

		strings.write_string(&builder, "name: ")
		strings.write_quoted_string(&builder, project.name)
		strings.write_byte(&builder, '\n')

		Project_Write_Field(&builder, "engine_version", project.engine_version, "    ")

		Project_Write_Field(&builder, "icon", project.icon, "    ")

		Project_Write_Field(&builder, "path", project.path, "    ")

		Project_Write_Field(&builder, "description", project.description, "    ")
	}

	data := strings.to_string(builder)

	return os.write_entire_file(service.registry_path, data) == nil
}

Project_Add :: proc(service: ^ProjectService, project: KinemiumProject) -> bool {
	normalized_path, ok := Project_Normalize_Path(project.path)
	if !ok {
		return false
	}

	if _, exists := Project_Find_By_Path(service, normalized_path); exists {
		delete(normalized_path)
		return false
	}

	append(
		&service.projects,
		KinemiumProject {
			name = strings.clone(project.name),
			engine_version = strings.clone(project.engine_version),
			icon = strings.clone(project.icon),
			path = normalized_path,
			description = strings.clone(project.description),
		},
	)

	if !Project_Save(service) {
		index := len(service.projects) - 1
		added := &service.projects[index]

		delete(added.name)
		delete(added.engine_version)
		delete(added.icon)
		delete(added.path)
		delete(added.description)

		resize(&service.projects, index)
		return false
	}

	return true
}

Project_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^ProjectService)object

	Project_Clear(service)

	classes.Object_Destroy(object)
	free(service)
}

Project_Clear :: proc(service: ^ProjectService) {
	for &project in service.projects {
		delete(project.name)
		delete(project.engine_version)
		delete(project.icon)
		delete(project.path)
		delete(project.description)
	}

	delete(service.projects)

	if len(service.active_project_path) > 0 {
		delete(service.active_project_path)
		service.active_project_path = ""
	}
}

Project_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ProjectService)

	service.service = Service_Init(&Project_Class, "Project", data_model)

	service.projects = make([dynamic]KinemiumProject)

	registry_path, ok := Project_Registry_Path()
	if ok {
		service.registry_path = registry_path
		Project_Load(service)
	}

	return &service.object
}

Project_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^ProjectService)object
	switch key {
	case "GetProjects", "GetActiveProject", "SetActiveProject", "CreateProject":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return false
		}

		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

Project_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^ProjectService)object
	switch method {
	case "GetProjects":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Project:GetProjects() requires Internals capability"), true
		}

		Project_push_projects(L, service)
		return 1, true

	case "GetActiveProject":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Project:GetActiveProject() requires Internals capability"),
				true
		}

		project := Project_Get_Active(service)

		if project == nil {
			vm.PushNil(L)
		} else {
			Project_push_project(L, project)
		}

		return 1, true
	case "CreateProject":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Project:CreateProject() requires Internals capability"), true
		}

		name := vm.ArgString(L, 2)
		folder_path := vm.ArgString(L, 3)
		description := vm.ArgOptionalString(L, 4, "")
		icon := vm.ArgOptionalString(L, 5, "")

		if !Project_Create(service, name, folder_path, description, icon) {
			vm.PushBoolean(L, false)
			return 1, true
		}

		vm.PushBoolean(L, true)
		return 1, true
	case "SetActiveProject":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Project:SetActiveProject() requires Internals capability"),
				true
		}

		path := vm.ArgString(L, 2)

		if !Project_Set_Active(service, path) {
			vm.PushBoolean(L, false)
			return 1, true
		}

		vm.PushBoolean(L, true)
		return 1, true
	}
	return 0, false
}

Register_Project_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Project_Class,
		Project_construct,
		Project_destroy,
		creatable = false,
		get = Project_get,
		namecall = Project_namecall,
	)
}
