#+build !js
// wire:service
package services

import "vendor:sdl3"


import assetstore "../assetstore"
import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import fsutil "../fsutil"
import serializer "../serializer"
import git "../util/git"
import tracy "../util/odin-tracy"
import vm "../vm"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:thread"

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
	autosave_elapsed:    f32,
	autosave_worker:     ^thread.Thread,
}

KinemiumProject :: struct {
	name:           string,
	engine_version: string,
	icon:           string,
	path:           string,
	description:    string,
	dimension:      string,
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

Project_CreateFolders :: proc(project: KinemiumProject) {
	path := project.path

	fsutil.Make_Directory(strings.concatenate({path, "/assets"}))
	fsutil.Make_Directory(strings.concatenate({path, "/scripts"}))
	fsutil.Make_Directory(strings.concatenate({path, "/scripts/client"}))
	fsutil.Make_Directory(strings.concatenate({path, "/scripts/server"}))
	fsutil.Make_Directory(strings.concatenate({path, "/assets/replicated"}))
	fsutil.Make_Directory(strings.concatenate({path, "/assets/server"}))
	fsutil.Make_Directory(strings.concatenate({path, "/assets/client"}))
}

Project_Create :: proc(
	service: ^ProjectService,
	L: ^vm.State,
	name: string,
	folder_path: string,
	description: string = "",
	icon: string = "",
	enable_git: bool,
	dimension: f64,
) -> bool {
	fmt.eprintf(
		"[Project] CreateProject name=%q folder=%q desc=%q\n",
		name,
		folder_path,
		description,
	)
	if !Project_Name_Is_Valid(name) {
		fmt.eprintf("[Project] create failed: invalid name\n")
		return false
	}

	base_path: string
	base_ok := false
	if len(folder_path) > 0 {
		base_path, base_ok = Project_Normalize_Path(folder_path)
	}
	if !base_ok {
		base_path, base_ok = Project_Default_Projects_Dir(context.allocator)
		fmt.eprintf("[Project] create: using default projects dir %q\n", base_path)
		if !base_ok {
			fmt.eprintf("[Project] create failed: no default projects dir\n")
			return false
		}
	}
	defer delete(base_path)

	if err := fsutil.Make_Directory_All(base_path); err != nil {
		fmt.eprintf("[Project] create failed: mkdir base %q err=%v\n", base_path, err)
		return false
	}

	project_path, join_err := os.join_path({base_path, name}, context.allocator)
	if join_err != nil {
		fmt.eprintf("[Project] create failed: join path err=%v\n", join_err)
		return false
	}
	defer delete(project_path)

	if os.exists(project_path) {
		fmt.eprintf("[Project] create failed: project path exists %q\n", project_path)
		return false
	}

	if err := fsutil.Make_Directory_All(project_path); err != nil {
		fmt.eprintf("[Project] create failed: mkdir project %q err=%v\n", project_path, err)
		return false
	}

	resolved_dimension := "1"

	if dimension != 1 {
		resolved_dimension = "2"
		// this is so stupid
	}

	project := KinemiumProject {
		name           = name,
		engine_version = PROJECT_ENGINE_VERSION,
		icon           = icon,
		path           = project_path,
		description    = description,
		dimension      = resolved_dimension,
	}

	if enable_git {
		git.init(project_path, initial_branch = "main")
	}

	Project_CreateFolders(project)

	if !Project_Add(service, project) {
		fmt.eprintf("[Project] create failed: Project_Add (registry %q)\n", service.registry_path)
		return false
	}

	if Project_Get_Active(service) != nil {Project_Clear_Map(service, L)}
	Project_Activate(service, len(service.projects) - 1)
	fmt.eprintf("[Project] created project at %q\n", project_path)
	return true
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

	Project_Activate(service, index)
	return true
}

Project_Activate :: proc(service: ^ProjectService, index: int) {
	if len(service.active_project_path) > 0 {
		delete(service.active_project_path)
	}

	service.active_project_path = strings.clone(service.projects[index].path)
	assetstore.Set_Project_Root(service.active_project_path)
	service.autosave_elapsed = 0
}

Project_Normalize_Path :: proc(path: string) -> (string, bool) {
	if len(path) == 0 {
		return "", false
	}

	absolute, err := filepath.abs(path)
	if err == nil && absolute != "" {
		return absolute, true
	}
	delete(absolute)

	// On Linux filepath.abs opens the target. A project base may not exist yet.
	when ODIN_OS == .Linux {
		if err == nil || err == .Not_Exist {
			if filepath.is_abs(path) {
				cleaned, clean_err := filepath.clean(path)
				return cleaned, clean_err == nil
			}
			cwd, cwd_err := os.get_working_directory(context.allocator)
			if cwd_err == nil {
				defer delete(cwd)
				joined, join_err := os.join_path({cwd, path}, context.allocator)
				return joined, join_err == nil
			}
		}
	}
	return "", false
}

Project_Default_Projects_Dir :: proc(allocator := context.allocator) -> (string, bool) {
	data_dir, err := os.user_data_dir(allocator)
	if err != nil {
		return "", false
	}
	defer delete(data_dir, allocator)

	base, err2 := os.join_path({data_dir, "Kinemium", "projects"}, allocator)
	if err2 != nil {
		return "", false
	}

	return base, true
}

Project_Find_By_Path :: proc(service: ^ProjectService, path: string) -> (int, bool) {
	normalized, ok := Project_Normalize_Path(path)
	if !ok {
		return -1, false
	}
	defer delete(normalized)

	for project, index in service.projects {
		if os.are_paths_identical(project.path, path) ||
		   os.are_paths_identical(project.path, normalized) {
			return index, true
		}
		// Older registries can contain a symlink spelling of the project path.
		if stored, valid := Project_Normalize_Path(project.path); valid {
			defer delete(stored)
			if os.are_paths_identical(stored, normalized) {
				return index, true
			}
		}
	}

	return -1, false
}

Project_Separator_Index :: proc(path: string) -> int {
	index := strings.last_index(path, "/")

	if backslash := strings.last_index(path, "\\"); backslash > index {
		index = backslash
	}

	return index
}

Project_Entry_Name :: proc(path: string) -> string {
	if index := Project_Separator_Index(path); index >= 0 {
		return path[index + 1:]
	}

	return path
}

Project_Entry_Parent :: proc(path: string) -> (string, bool) {
	index := Project_Separator_Index(path)

	if index <= 0 {
		return "", false
	}

	return path[:index], true
}

Project_Join_Path :: proc(parent, name: string) -> (string, bool) {
	if len(parent) == 0 || len(name) == 0 {
		return "", false
	}

	path, err := os.join_path({parent, name}, context.allocator)
	if err != nil {
		return "", false
	}

	return path, true
}

Project_Is_Same_Or_Descendant :: proc(path, ancestor: string) -> bool {
	if len(path) == 0 || len(ancestor) == 0 {
		return false
	}

	if path == ancestor {
		return true
	}

	for separator in ([]string{"/", "\\"}) {
		probe := strings.concatenate({ancestor, separator})
		defer delete(probe)

		if strings.has_prefix(path, probe) {
			return true
		}
	}

	return false
}

Project_Unique_Child_Path :: proc(parent, name: string) -> (string, bool) {
	if len(parent) == 0 || len(name) == 0 {
		return "", false
	}

	extension := filepath.ext(name)
	stem := name[:len(name) - len(extension)]

	candidate := strings.clone(name)
	defer delete(candidate)

	for index := 2;; index += 1 {
		path, ok := Project_Join_Path(parent, candidate)
		if !ok {
			return "", false
		}
		defer delete(path)

		if !os.exists(path) {
			return strings.clone(path), true
		}


		delete(candidate)
		candidate = fmt.aprintf("%s (%d)%s", stem, index, extension)
	}

	return "", false
}

Project_Copy_File_Bytes :: proc(from, to: string) -> bool {
	data, err := os.read_entire_file(from, context.allocator)
	if err != nil {
		return false
	}
	defer delete(data, context.allocator)

	return fsutil.Write_File(to, data) == nil
}

Project_Copy_Entry :: proc(from, to: string) -> bool {
	if os.is_directory(from) {
		if err := fsutil.Make_Directory_All(to); err != nil {
			return false
		}

		dir, open_err := os.open(from)
		if open_err != nil {
			return false
		}
		defer os.close(dir)

		entries, read_err := os.read_dir(dir, -1, context.allocator)
		if read_err != nil {
			return false
		}
		defer os.file_info_slice_delete(entries, context.allocator)

		for entry in entries {
			child_to, ok := Project_Join_Path(to, entry.name)
			if !ok {
				return false
			}
			defer delete(child_to)

			if !Project_Copy_Entry(entry.fullpath, child_to) {
				return false
			}
		}

		return true
	}

	return Project_Copy_File_Bytes(from, to)
}

Project_Is_Case_Only_Rename :: proc(path, destination: string) -> bool {
	return os.exists(destination) && strings.equal_fold(destination, path)
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
		if err := fsutil.Make_Directory_All(kinemium_dir); err != nil {
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

Project_Delete :: proc(service: ^ProjectService, path: string) -> bool {
	normalized, valid := Project_Normalize_Path(path)
	if !valid {
		return false
	}
	defer delete(normalized)

	index, found := Project_Find_By_Path(service, normalized)
	if !found {
		return false
	}

	project_to_delete := service.projects[index]

	if len(service.active_project_path) > 0 &&
	   os.are_paths_identical(project_to_delete.path, service.active_project_path) {
		delete(service.active_project_path)
		service.active_project_path = ""
		assetstore.Set_Project_Root("")
	}

	if err := os.remove_all(project_to_delete.path); err != nil {
		fmt.eprintf(
			"[Project] delete failed: could not remove directory %q: %v\n",
			project_to_delete.path,
			err,
		)
	}

	delete(project_to_delete.name)
	delete(project_to_delete.engine_version)
	delete(project_to_delete.icon)
	delete(project_to_delete.path)
	delete(project_to_delete.description)

	ordered_remove(&service.projects, index)

	if !Project_Save(service) {
		fmt.eprintf("[Project] delete warning: failed to update registry after removing project\n")
		return false
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

	return project_write_atomic(service.registry_path, data)
}

project_write_atomic :: proc(path, data: string) -> bool {
	directory, ok := Project_Entry_Parent(path)
	if !ok {return false}
	staging, staging_err := os.make_directory_temp(directory, ".project-save-*", context.allocator)
	if staging_err != nil {
		fmt.eprintf("[Project] could not stage a write to %q: %v\n", path, staging_err)
		return false
	}
	defer delete(staging)
	defer os.remove(staging)
	pending := fmt.tprintf("%s/pending", staging)
	defer os.remove(pending)
	if write_err := os.write_entire_file(pending, data); write_err != nil {
		fmt.eprintf("[Project] could not write %q: %v\n", pending, write_err)
		return false
	}
	if rename_err := os.rename(pending, path); rename_err != nil {
		fmt.eprintf("[Project] could not replace %q: %v\n", path, rename_err)
		return false
	}
	return true
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
	_ = project_finish_autosave(service, true)

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
		assetstore.Set_Project_Root("")
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
	case "GetProjects",
	     "GetActiveProject",
	     "SetActiveProject",
	     "CreateProject",
	     "UpdateProject",
	     "OpenProject",
	     "RegisterProject",
	     "DeleteProject",
	     "SaveProject",
	     "GetProjectBackups",
	     "RestoreProjectBackup",
	     "ExitEditor",
	     "KeepEditorSceneHelper",
	     "GetProjectEntries",
	     "PathExists",
	     "IsDirectory":
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
	case "UpdateProject",
	     "OpenProject",
	     "RegisterProject",
	     "SaveProject",
	     "GetProjectBackups",
	     "RestoreProjectBackup",
	     "DeleteProject",
	     "ExitEditor",
	     "KeepEditorSceneHelper":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Project editing requires Internals capability"), true
		}
		ok: bool
		switch method {
		case "UpdateProject":
			ok = Project_Update(
				service,
				vm.ArgString(L, 2),
				vm.ArgString(L, 3),
				vm.ArgOptionalString(L, 4, ""),
				vm.ArgOptionalString(L, 5, ""),
			)
		case "OpenProject":
			ok = Project_Open(service, L, vm.ArgString(L, 2))
		case "RegisterProject":
			path := vm.ArgString(L, 2)
			name := vm.ArgString(L, 3)
			ok =
				Project_Name_Is_Valid(name) &&
				os.is_file(fmt.tprintf("%s/default.project.json", path)) &&
				Project_Add(
					service,
					KinemiumProject {
						name = name,
						engine_version = PROJECT_ENGINE_VERSION,
						path = path,
					},
				)
		case "SaveProject":
			ok = Project_Save_To_File(service, L)
		case "GetProjectBackups":
			project_push_backups(service, L)
			return 1, true
		case "DeleteProject":
			path := vm.ArgString(L, 2)
			ok = Project_Delete(service, path)
			return 1, true
		case "RestoreProjectBackup":
			ok = project_restore_backup(service, L, vm.ArgString(L, 2))
		case "KeepEditorSceneHelper":
			if service.data_model.registry.mode != .Editor {return 0, true}
			helper := classes.Object_From_Argument(L, 2)
			if helper != nil && !helper.destroyed && !classes.Is_A(helper, "Service") {
				helper.editor_scene_helper = true
				helper.archivable = false
				classes.Set_Can_Replicate(helper, false)
				ok = true
			}
		case "ExitEditor":
			if service.data_model.registry.mode != .Editor {return 0, true}
			event: sdl3.Event
			event.type = .QUIT
			ok = sdl3.PushEvent(&event)
		}
		vm.PushBoolean(L, ok)
		return 1, true

	case "GetProjects":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Project:GetProjects() requires Internals capability"), true
		}

		Project_push_projects(L, service)
		return 1, true

	case "GetActiveProject":
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
		enable_git := vm.ArgOptionalBoolean(L, 6, true)
		dimension := vm.ArgNumber(L, 7)

		if dimension > 2 {
			// only 2 dimensions
			// 1 = 3D, 2 = 2D
			// on default, is 1
			fmt.println(
				"Project:CreateProject only accepts 0-2 range dimensions (1 is 3D, 2 is 2D)",
			)
			return 1, true
		}

		if !Project_Create(
			service,
			L,
			name,
			folder_path,
			description,
			icon,
			enable_git,
			dimension,
		) {
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
	case "GetProjectEntries":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Project:GetProjectEntries() requires Internals capability"),
				true
		}

		path := vm.ArgString(L, 2)

		dir, open_err := os.open(path)
		if open_err != nil {
			return vm.RaiseError(L, "Project:GetProjectEntries() failed to open directory"), true
		}
		defer os.close(dir)

		entries, read_err := os.read_dir(dir, -1, context.allocator)
		if read_err != nil {
			return vm.RaiseError(L, "Project:GetProjectEntries() failed to read directory"), true
		}
		defer os.file_info_slice_delete(entries, context.allocator)

		vm.NewTable(L, len(entries), 0)

		for entry, i in entries {
			vm.NewTable(L, 0, 4)

			vm.PushString(L, entry.name)
			vm.SetField(L, -2, "Name")

			vm.PushString(L, entry.fullpath)
			vm.SetField(L, -2, "Path")

			type_name: string
			#partial switch entry.type {
			case .Directory:
				type_name = "Directory"
			case .Regular:
				type_name = "File"
			case .Symlink:
				type_name = "Symlink"
			case:
				type_name = "Other"
			}
			vm.PushString(L, type_name)
			vm.SetField(L, -2, "Type")

			vm.SetArrayValue(L, -2, i + 1)
		}

		return 1, true
	case "CopyPathWindow":
		path := vm.ArgString(L, 2)

		text := strings.clone_to_cstring(path)
		sdl3.SetClipboardText(text)
		delete(text)
	}
	return 0, false
}

Project_Update :: proc(service: ^ProjectService, path, name, description, icon: string) -> bool {
	if !Project_Name_Is_Valid(name) {return false}
	normalized, valid := Project_Normalize_Path(path)
	if !valid {return false}
	defer delete(normalized)
	index, found := Project_Find_By_Path(service, normalized)
	if !found {return false}

	project := &service.projects[index]
	previous := project^
	project.name = strings.clone(name)
	project.description = strings.clone(description)
	project.icon = strings.clone(icon)
	if !Project_Save(service) {
		delete(project.name)
		delete(project.description)
		delete(project.icon)
		project^ = previous
		return false
	}
	delete(previous.name)
	delete(previous.description)
	delete(previous.icon)
	return true
}

Project_Clear_Map :: proc(service: ^ProjectService, L: ^vm.State) {
	clear_editor_selection(service.data_model.registry, L)
	for name in MAP_CONTENT_SERVICES {
		target := Service_Get_Service(&service.service, name)
		if target == nil {continue}
		for i := len(target.children) - 1; i >= 0; i -= 1 {
			child := target.children[i]
			if map_keep_child(target, child) {continue}
			if name == "StarterPlayer" &&
			   (child.name == "StarterPlayerScripts" || child.name == "StarterCharacterScripts") {
				for len(child.children) > 0 {
					classes.Destroy_Hierarchy(child.children[len(child.children) - 1])
				}
				continue
			}
			classes.Destroy_Hierarchy(child)
		}
	}
	if object := Service_Get_Service(&service.service, "Terrain"); object != nil {
		terrain := cast(^Terrain)object
		empty: serializer.Kine_Terrain
		Terrain_Read_Kine_Table(terrain, terrain.renderer, &empty)
	}
}

Project_Open :: proc(service: ^ProjectService, L: ^vm.State, path: string) -> bool {
	normalized, valid := Project_Normalize_Path(path)
	if !valid {
		fmt.eprintf("[Project] open failed: could not resolve %q\n", path)
		return false
	}
	defer delete(normalized)
	index, found := Project_Find_By_Path(service, path)
	if !found {
		fmt.eprintf("[Project] open failed: %q is not registered\n", normalized)
		return false
	}
	info, stat_err := os.stat(normalized, context.allocator)
	if stat_err != nil {
		fmt.eprintf("[Project] open failed: checking %q: %v\n", normalized, stat_err)
		return false
	}
	defer os.file_info_delete(info, context.allocator)
	if info.type != .Directory {
		fmt.eprintf("[Project] open failed: %q is not a directory\n", normalized)
		return false
	}
	if service.active_project_path == service.projects[index].path {return true}
	if worker := service.autosave_worker; worker != nil {
		job := cast(^Project_Autosave_Job)worker.data
		if os.are_paths_identical(job.path, service.projects[index].path) {
			_ = project_finish_autosave(service, true)
		}
	}

	snapshot := fmt.tprintf("%s/autosave.kine", normalized)
	if os.exists(snapshot) {
		data, read_err := os.read_entire_file(snapshot, context.allocator)
		if read_err != nil {
			fmt.eprintf("[Project] open failed: reading %q: %v\n", snapshot, read_err)
			return false
		}
		defer delete(data)
		assetstore.Set_Project_Root(normalized)
		if !Restore_Map(service.data_model.registry, L, data, snapshot, clear_assets = false) {
			assetstore.Set_Project_Root(service.active_project_path)
			return false
		}
	} else {
		Project_Clear_Map(service, L)
	}
	Project_Activate(service, index)
	return true
}

Project_Save_To_File :: proc(service: ^ProjectService, L: ^vm.State) -> bool {
	tracy.ZoneNC("Project Save", 0xD19A66)
	current := Project_Get_Active(service)
	if current == nil {return false}
	_ = project_finish_autosave(service, true)
	data, ok := project_snapshot(service, L)
	if !ok {return false}
	defer delete(data)
	if !project_write_snapshot(current.path, data) {return false}
	service.autosave_elapsed = 0
	return true
}

project_snapshot :: proc(service: ^ProjectService, L: ^vm.State) -> ([]u8, bool) {
	exporter := cast(^ExportService)Service_Get_Service(&service.service, "ExportService")
	data, err := export_datamodel_snapshot(exporter, L)
	defer serializer.Error_Delete(&err)
	if !serializer.Error_Is_None(err) {
		serializer.Error_Print(err, "Could not save project: ")
		return nil, false
	}
	return data, true
}

project_write_snapshot :: proc(path: string, data: []u8) -> bool {
	tracy.ZoneNC("Project Snapshot Write", 0xD19A66)
	staging, staging_err := os.make_directory_temp(path, ".project-save-*", context.allocator)
	if staging_err != nil {
		fmt.eprintf("[Project] save failed: staging in %q: %v\n", path, staging_err)
		return false
	}
	defer delete(staging)
	defer os.remove(staging)
	pending := fmt.tprintf("%s/autosave.kine", staging)
	defer os.remove(pending)

	err := serializer.Write_File_Data(pending, data)
	defer serializer.Error_Delete(&err)
	if !serializer.Error_Is_None(err) {
		serializer.Error_Print(err, "Could not save project: ")
		return false
	}
	snapshot := fmt.tprintf("%s/autosave.kine", path)
	backed_up, unchanged := project_backup_previous(path, snapshot, pending)
	if !backed_up {
		fmt.eprintf("[Project] save failed: could not back up %q\n", snapshot)
		return false
	}
	if !unchanged {
		if rename_err := os.rename(pending, snapshot); rename_err != nil {
			fmt.eprintf("[Project] save failed: replacing %q: %v\n", snapshot, rename_err)
			return false
		}
	}
	return true
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
