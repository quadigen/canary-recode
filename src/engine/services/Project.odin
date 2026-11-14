#+build !js
// wire:service
package services
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
import "core:bytes"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:thread"
import "vendor:sdl3"

Project_Class := classes.Class_Info {
	name   = "Project",
	parent = &Service_Class,
}

Project_State_Provider :: proc(service: ^ProjectService) -> ^vm.State

Project_Entry :: struct {
	name:      string,
	path:      string,
	type_name: string,
}

ProjectService :: struct {
	using service:       Service,
	call_count:          i64,
	projects:            [dynamic]KinemiumProject,
	registry_path:       string,
	active_project_path: string,
	autosave_elapsed:    f32,
	autosave_worker:     ^thread.Thread,
	exit_approved:       bool,
	skip_exit_save:      bool,
	vm_state:            ^vm.State,
	vm_state_provider:   Project_State_Provider,
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

PROJECT_ENGINE_VERSION :: "1.19.0-dev"

// Call once from editor bootstrap with a stable, live VM state.
// Do not bind a short-lived coroutine; use Project_Set_State_Provider for that.
Project_Bind_State :: proc(service: ^ProjectService, state: ^vm.State) {
	if service != nil {service.vm_state = state}
}

Project_Set_State_Provider :: proc(service: ^ProjectService, provider: Project_State_Provider) {
	if service != nil {service.vm_state_provider = provider}
}

Project_Resolve_State :: proc(service: ^ProjectService) -> ^vm.State {
	if service == nil {return nil}
	if service.vm_state_provider != nil {
		return service.vm_state_provider(service)
	}
	return service.vm_state
}

Project_Get_Projects :: proc(service: ^ProjectService) -> []KinemiumProject {
	if service == nil {return nil}
	return service.projects[:]
}

Project_Get_By_Path :: proc(service: ^ProjectService, path: string) -> ^KinemiumProject {
	if service == nil {return nil}
	index, found := Project_Find_By_Path(service, path)
	if !found {return nil}
	return &service.projects[index]
}

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

Project_CreateFolders :: proc(project: KinemiumProject) -> bool {
	folders := []string {
		"assets",
		"scripts",
		"scripts/client",
		"scripts/server",
		"assets/replicated",
		"assets/server",
		"assets/client",
	}
	for folder in folders {
		path := fmt.tprintf("%s/%s", project.path, folder)
		if err := fsutil.Make_Directory_All(path); err != nil {
			fmt.eprintf("[Project] could not create %q: %v\n", path, err)
			return false
		}
	}
	return true
}

// Native Odin API. No Lua state needs to be passed by the caller.
// A live VM is only needed when replacing an already-loaded editor scene.
Project_Create :: proc(
	service: ^ProjectService,
	name: string,
	folder_path: string,
	description: string = "",
	icon: string = "",
	enable_git: bool = true,
	dimension: f64 = 1,
) -> bool {
	return project_create_impl(
		service,
		Project_Resolve_State(service),
		name,
		folder_path,
		description,
		icon,
		enable_git,
		dimension,
	)
}

project_create_impl :: proc(
	service: ^ProjectService,
	L: ^vm.State,
	name: string,
	folder_path: string,
	description: string,
	icon: string,
	enable_git: bool,
	dimension: f64,
) -> bool {
	if service == nil || !Project_Name_Is_Valid(name) || (dimension != 1 && dimension != 2) {
		fmt.eprintf("[Project] create failed: invalid name or dimension\n")
		return false
	}
	if Project_Get_Active(service) != nil && L == nil {
		fmt.eprintf("[Project] create failed: a live editor VM is required to clear the scene\n")
		return false
	}
	base_path: string
	base_ok := false
	if len(folder_path) > 0 {
		base_path, base_ok = Project_Normalize_Path(folder_path)
	}
	if !base_ok {
		base_path, base_ok = Project_Default_Projects_Dir(context.allocator)
		if !base_ok {return false}
	}
	defer delete(base_path)
	if err := fsutil.Make_Directory_All(base_path); err != nil {
		fmt.eprintf("[Project] create failed: mkdir %q: %v\n", base_path, err)
		return false
	}
	project_path, join_err := os.join_path({base_path, name}, context.allocator)
	if join_err != nil {return false}
	defer delete(project_path)
	if os.exists(project_path) {
		fmt.eprintf("[Project] create failed: %q already exists\n", project_path)
		return false
	}
	if err := fsutil.Make_Directory_All(project_path); err != nil {return false}
	project := KinemiumProject {
		name           = name,
		engine_version = PROJECT_ENGINE_VERSION,
		icon           = icon,
		path           = project_path,
		description    = description,
		dimension      = "1",
	}
	if dimension == 2 {project.dimension = "2"}
	if !Project_CreateFolders(project) {
		_ = os.remove_all(project_path)
		return false
	}
	if enable_git {
		git.init(project_path, initial_branch = "main")
	}
	if !Project_Add(service, project) {
		fmt.eprintf("[Project] create failed: could not register %q\n", project_path)
		_ = os.remove_all(project_path)
		return false
	}
	if Project_Get_Active(service) != nil {
		project_clear_map_impl(service, L)
	}
	return Project_Activate(service, len(service.projects) - 1)
}

Project_push_project :: proc(L: ^vm.State, project: ^KinemiumProject) {
	if project == nil {
		vm.PushNil(L)
		return
	}
	vm.NewTable(L, 0, 6)
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
	vm.PushString(L, project.dimension)
	vm.SetField(L, -2, "Dimension")
}

Project_push_projects :: proc(L: ^vm.State, service: ^ProjectService) {
	vm.NewTable(L, len(service.projects))
	for &project, index in service.projects {
		Project_push_project(L, &project)
		vm.SetArrayValue(L, -2, index + 1)
	}
}

Project_Get_Active :: proc(service: ^ProjectService) -> ^KinemiumProject {
	if service == nil {return nil}
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

// SetActive only changes the active project/root. Use Project_Open to load its scene.
Project_Set_Active :: proc(service: ^ProjectService, path: string) -> bool {
	if service == nil {return false}
	index, found := Project_Find_By_Path(service, path)
	if !found {return false}
	return Project_Activate(service, index)
}

Project_Activate :: proc(service: ^ProjectService, index: int) -> bool {
	if service == nil || index < 0 || index >= len(service.projects) {return false}
	new_path := strings.clone(service.projects[index].path)
	if len(service.active_project_path) > 0 {delete(service.active_project_path)}
	service.active_project_path = new_path
	assetstore.Set_Project_Root(service.active_project_path)
	service.autosave_elapsed = 0
	return true
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
	if service == nil {return -1, false}
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

Project_Register :: proc(service: ^ProjectService, path, name: string) -> bool {
	if service == nil || !Project_Name_Is_Valid(name) {return false}
	normalized, ok := Project_Normalize_Path(path)
	if !ok {return false}
	defer delete(normalized)
	if !os.is_directory(normalized) {return false}
	if !os.is_file(fmt.tprintf("%s/default.project.json", normalized)) {return false}
	return Project_Add(
		service,
		KinemiumProject {
			name = name,
			engine_version = PROJECT_ENGINE_VERSION,
			path = normalized,
			dimension = "1",
		},
	)
}

Project_Path_Exists :: proc(path: string) -> bool {
	return os.exists(path)
}

Project_Is_Directory :: proc(path: string) -> bool {
	return os.is_directory(path)
}

// The returned entries own their strings; call Project_Free_Entries when done.
Project_Get_Entries :: proc(path: string) -> ([]Project_Entry, bool) {
	dir, open_err := os.open(path)
	if open_err != nil {return nil, false}
	defer os.close(dir)
	entries, read_err := os.read_dir(dir, -1, context.allocator)
	if read_err != nil {return nil, false}
	defer os.file_info_slice_delete(entries, context.allocator)
	result := make([]Project_Entry, len(entries))
	for entry, i in entries {
		type_name := "Other"
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
		result[i] = Project_Entry {
			name      = strings.clone(entry.name),
			path      = strings.clone(entry.fullpath),
			type_name = type_name,
		}
	}
	return result, true
}

Project_Free_Entries :: proc(entries: []Project_Entry) {
	for entry in entries {
		delete(entry.name)
		delete(entry.path)
	}
	delete(entries)
}

Project_Copy_Path_Window :: proc(path: string) -> bool {
	text := strings.clone_to_cstring(path)
	defer delete(text)
	return sdl3.SetClipboardText(text)
}

// Requests editor shutdown. When skip_exit_save is true, the surrounding
// editor shutdown routine can skip its final autosave. This does not skip
// joining an already-running autosave worker during destruction.
Project_Exit_Editor :: proc(service: ^ProjectService, skip_exit_save: bool = false) -> bool {
	if service == nil || service.data_model.registry.mode != .Editor {return false}
	event: sdl3.Event
	event.type = .QUIT
	ok := sdl3.PushEvent(&event)
	service.exit_approved = ok
	service.skip_exit_save = ok && skip_exit_save
	return ok
}

// Explicit naming for Odin callers that initiate the editor close flow.
Project_Request_Exit :: proc(service: ^ProjectService, skip_exit_save: bool = false) -> bool {
	return Project_Exit_Editor(service, skip_exit_save)
}

// Call this if a previously accepted exit event gets cancelled elsewhere.
Project_Reset_Exit_Request :: proc(service: ^ProjectService) {
	if service == nil {return}
	service.exit_approved = false
	service.skip_exit_save = false
}

Project_Keep_Editor_Scene_Helper :: proc(
	service: ^ProjectService,
	helper: ^classes.Object,
) -> bool {
	if service == nil || service.data_model.registry.mode != .Editor {return false}
	if helper == nil || helper.destroyed || classes.Is_A(helper, "Service") {return false}
	helper.editor_scene_helper = true
	helper.archivable = false
	classes.Set_Can_Replicate(helper, false)
	return true
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
	if service == nil || len(service.registry_path) == 0 {return false}
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
		dimension := Project_Yaml_Get(&document, node, "dimension")
		dimension_value := Project_Yaml_Node_String(dimension)
		if len(dimension_value) == 0 {dimension_value = "1"}
		project := KinemiumProject {
			name           = strings.clone(Project_Yaml_Node_String(name)),
			engine_version = strings.clone(Project_Yaml_Node_String(version)),
			icon           = strings.clone(Project_Yaml_Node_String(icon)),
			path           = strings.clone(Project_Yaml_Node_String(path)),
			description    = strings.clone(Project_Yaml_Node_String(description)),
			dimension      = strings.clone(dimension_value),
		}
		append(&service.projects, project)
	}
	return true
}

// Destructive delete: removes the project directory and then its registry entry.
Project_Delete :: proc(service: ^ProjectService, path: string) -> bool {
	if service == nil {return false}
	normalized, valid := Project_Normalize_Path(path)
	if !valid {return false}
	defer delete(normalized)
	index, found := Project_Find_By_Path(service, normalized)
	if !found {return false}
	project_to_delete := service.projects[index]
	was_active :=
		len(service.active_project_path) > 0 &&
		os.are_paths_identical(project_to_delete.path, service.active_project_path)
	// Finish a pending write before deleting the directory it targets.
	if service.autosave_worker != nil {
		job := cast(^Project_Autosave_Job)service.autosave_worker.data
		if os.are_paths_identical(job.path, project_to_delete.path) {
			_ = project_finish_autosave(service, true)
		}
	}
	if err := os.remove_all(project_to_delete.path); err != nil {
		fmt.eprintf(
			"[Project] delete failed: could not remove directory %q: %v\n",
			project_to_delete.path,
			err,
		)
		return false
	}
	if was_active {
		delete(service.active_project_path)
		service.active_project_path = ""
		assetstore.Set_Project_Root("")
	}
	delete(project_to_delete.name)
	delete(project_to_delete.engine_version)
	delete(project_to_delete.icon)
	delete(project_to_delete.path)
	delete(project_to_delete.description)
	delete(project_to_delete.dimension)
	ordered_remove(&service.projects, index)
	if !Project_Save(service) {
		fmt.eprintf("[Project] delete warning: project removed but registry update failed\n")
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
	if service == nil || len(service.registry_path) == 0 {return false}
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
		Project_Write_Field(&builder, "dimension", project.dimension, "    ")
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
	if service == nil || !Project_Name_Is_Valid(project.name) {return false}
	normalized_path, ok := Project_Normalize_Path(project.path)
	if !ok {
		return false
	}
	if _, exists := Project_Find_By_Path(service, normalized_path); exists {
		delete(normalized_path)
		return false
	}
	dimension := project.dimension
	if len(dimension) == 0 {dimension = "1"}
	append(
		&service.projects,
		KinemiumProject {
			name = strings.clone(project.name),
			engine_version = strings.clone(project.engine_version),
			icon = strings.clone(project.icon),
			path = normalized_path,
			description = strings.clone(project.description),
			dimension = strings.clone(dimension),
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
		delete(added.dimension)
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
	if service == nil {return}
	for &project in service.projects {
		delete(project.name)
		delete(project.engine_version)
		delete(project.icon)
		delete(project.path)
		delete(project.description)
		delete(project.dimension)
	}
	delete(service.projects)
	if len(service.registry_path) > 0 {
		delete(service.registry_path)
		service.registry_path = ""
	}
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

project_is_method :: proc(method: string) -> bool {
	switch method {
	case "GetProjects",
	     "GetActiveProject",
	     "SetActiveProject",
	     "CreateProject",
	     "UpdateProject",
	     "OpenProject",
	     "OpenProjectWindow",
	     "GetProject",
	     "RegisterProject",
	     "DeleteProject",
	     "SaveProject",
	     "GetProjectBackups",
	     "RestoreProjectBackup",
	     "HasUnsavedChanges",
	     "ExitEditor",
	     "KeepEditorSceneHelper",
	     "GetProjectEntries",
	     "PathExists",
	     "IsDirectory",
	     "CopyPathWindow":
		return true
	}
	return false
}

Project_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	// These two methods are exposed through namecalls only.
	if !project_is_method(key) || key == "GetProject" || key == "OpenProjectWindow" ||
	   !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
		return false
	}
	vm.PushUserdataMethod(L, key)
	return true
}

Project_New_Window_With_Project :: proc(
	service: ^ProjectService,
	L: ^vm.State,
	projectPath: string,
) -> (
	i32,
	bool,
) {
	executable, executable_err := os.get_executable_path(context.temp_allocator)
	if executable_err != nil {
		vm.PushBoolean(L, false)
		return 1, true
	}
	command := []string{executable, "--project", projectPath}
	process, stderr_pipe, failure, failed := playtest_spawn(command)
	return 1, true
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
	if !project_is_method(method) {return 0, false}
	if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
		return vm.RaiseError(L, "Project APIs require Internals capability"), true
	}
	service := cast(^ProjectService)object
	switch method {
	case "UpdateProject",
	     "OpenProject",
	     "RegisterProject",
	     "SaveProject",
	     "GetProjectBackups",
	     "RestoreProjectBackup",
	     "DeleteProject",
	     "HasUnsavedChanges",
	     "GetProject",
	     "OpenProjectWindow",
	     "ExitEditor",
	     "KeepEditorSceneHelper":
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
		case "OpenProjectWindow":
			path := vm.ArgString(L, 2)
			return Project_New_Window_With_Project(service, L, path)
		case "GetProject":
			path := vm.ArgString(L, 2)
			project := Project_Get_By_Path(service, path)
			Project_push_project(L, project)
			return 1, true
		case "OpenProject":
			ok = project_open_impl(service, L, vm.ArgString(L, 2))
		case "RegisterProject":
			ok = Project_Register(service, vm.ArgString(L, 2), vm.ArgString(L, 3))
		case "SaveProject":
			ok = project_save_to_file_impl(service, L)
		case "GetProjectBackups":
			project_push_backups(service, L)
			return 1, true
		case "DeleteProject":
			ok = Project_Delete(service, vm.ArgString(L, 2))
		case "RestoreProjectBackup":
			ok = project_restore_backup(service, L, vm.ArgString(L, 2))
		case "HasUnsavedChanges":
			ok = project_has_unsaved_changes(service, L)
		case "KeepEditorSceneHelper":
			helper := classes.Object_From_Argument(L, 2)
			ok = Project_Keep_Editor_Scene_Helper(service, helper)
		case "ExitEditor":
			ok = Project_Exit_Editor(service, vm.ArgOptionalBoolean(L, 2, false))
		}
		vm.PushBoolean(L, ok)
		return 1, true
	case "GetProjects":
		Project_push_projects(L, service)
		return 1, true
	case "GetActiveProject":
		Project_push_project(L, Project_Get_Active(service))
		return 1, true
	case "CreateProject":
		name := vm.ArgString(L, 2)
		folder_path := vm.ArgString(L, 3)
		description := vm.ArgOptionalString(L, 4, "")
		icon := vm.ArgOptionalString(L, 5, "")
		enable_git := vm.ArgOptionalBoolean(L, 6, true)
		dimension := vm.ArgNumber(L, 7)
		if dimension != 1 && dimension != 2 {
			vm.PushBoolean(L, false)
			return 1, true
		}
		if !project_create_impl(
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
		path := vm.ArgString(L, 2)
		if !Project_Set_Active(service, path) {
			vm.PushBoolean(L, false)
			return 1, true
		}
		vm.PushBoolean(L, true)
		return 1, true
	case "GetProjectEntries":
		path := vm.ArgString(L, 2)
		entries, ok := Project_Get_Entries(path)
		if !ok {
			return vm.RaiseError(L, "Project:GetProjectEntries() failed to read directory"), true
		}
		defer Project_Free_Entries(entries)
		vm.NewTable(L, len(entries), 0)
		for entry, i in entries {
			vm.NewTable(L, 0, 4)
			vm.PushString(L, entry.name)
			vm.SetField(L, -2, "Name")
			vm.PushString(L, entry.path)
			vm.SetField(L, -2, "Path")
			vm.PushString(L, entry.type_name)
			vm.SetField(L, -2, "Type")
			vm.SetArrayValue(L, -2, i + 1)
		}
		return 1, true
	case "PathExists":
		vm.PushBoolean(L, Project_Path_Exists(vm.ArgString(L, 2)))
		return 1, true
	case "IsDirectory":
		vm.PushBoolean(L, Project_Is_Directory(vm.ArgString(L, 2)))
		return 1, true
	case "CopyPathWindow":
		vm.PushBoolean(L, Project_Copy_Path_Window(vm.ArgString(L, 2)))
		return 1, true
	}
	return 0, false
}

Project_Update :: proc(service: ^ProjectService, path, name, description, icon: string) -> bool {
	if service == nil {return false}
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

// Native scene API; uses the state registered with Project_Bind_State /
// Project_Set_State_Provider, or fails rather than touching a null VM.
Project_Clear_Map :: proc(service: ^ProjectService) -> bool {
	L := Project_Resolve_State(service)
	if L == nil {return false}
	project_clear_map_impl(service, L)
	return true
}

project_clear_map_impl :: proc(service: ^ProjectService, L: ^vm.State) {
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

// Opens a registered project from any Odin caller without a Lua argument.
// Must run on the editor/main thread; the snapshot deserializer uses the VM.
Project_Open :: proc(service: ^ProjectService, path: string) -> bool {
	return project_open_impl(service, Project_Resolve_State(service), path)
}

project_open_impl :: proc(service: ^ProjectService, L: ^vm.State, path: string) -> bool {
	if service == nil {return false}
	normalized, valid := Project_Normalize_Path(path)
	if !valid {
		fmt.eprintf("[Project] open failed: could not resolve %q\n", path)
		return false
	}
	defer delete(normalized)
	index, found := Project_Find_By_Path(service, normalized)
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
	target := service.projects[index].path
	if len(service.active_project_path) > 0 &&
	   os.are_paths_identical(service.active_project_path, target) {
		return true
	}
	if L == nil {
		fmt.eprintf("[Project] open failed: bind a live VM state or state provider first\n")
		return false
	}
	if worker := service.autosave_worker; worker != nil {
		job := cast(^Project_Autosave_Job)worker.data
		if os.are_paths_identical(job.path, target) {
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
		assetstore.Set_Project_Root(target)
		if !Restore_Map(service.data_model.registry, L, data, snapshot, clear_assets = false) {
			assetstore.Set_Project_Root(service.active_project_path)
			return false
		}
	} else {
		project_clear_map_impl(service, L)
	}
	return Project_Activate(service, index)
}

// Saves the active scene, not the YAML registry (Project_Save does that).
Project_Save_To_File :: proc(service: ^ProjectService) -> bool {
	return project_save_to_file_impl(service, Project_Resolve_State(service))
}

Project_Save_Active :: proc(service: ^ProjectService) -> bool {
	return Project_Save_To_File(service)
}

project_save_to_file_impl :: proc(service: ^ProjectService, L: ^vm.State) -> bool {
	tracy.ZoneNC("Project Save", 0xD19A66)
	if service == nil || L == nil {return false}
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

Project_Restore_Backup :: proc(service: ^ProjectService, path: string) -> bool {
	if service == nil {return false}
	L := Project_Resolve_State(service)
	if L == nil {return false}
	return project_restore_backup(service, L, path)
}

project_snapshot :: proc(service: ^ProjectService, L: ^vm.State) -> ([]u8, bool) {
	exporter := cast(^ExportService)Service_Get_Service(&service.service, "ExportService")
	if exporter == nil {return nil, false}
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

// Odin-native counterpart of Project:HasUnsavedChanges(). On an active project
// lacking a live VM, return true: we cannot establish that changes were saved.
Project_Has_Unsaved_Changes :: proc(service: ^ProjectService) -> bool {
	if service == nil || Project_Get_Active(service) == nil {return false}
	L := Project_Resolve_State(service)
	if L == nil {return true}
	return project_has_unsaved_changes(service, L)
}

// This signature is kept for existing native callers that supply their VM.
project_has_unsaved_changes :: proc(service: ^ProjectService, L: ^vm.State) -> bool {
	if service == nil {return false}
	current := Project_Get_Active(service)
	if current == nil {return false}
	if L == nil {return true}

	// Finish pending writes before comparing with the committed snapshot.
	_ = project_finish_autosave(service, true)
	data, snapshot_ok := project_snapshot(service, L)
	defer delete(data)
	if !snapshot_ok {return true}

	previous, read_err := os.read_entire_file(
		fmt.tprintf("%s/autosave.kine", current.path),
		context.allocator,
	)
	if read_err != nil {return true}
	defer delete(previous)
	return !bytes.equal(previous, data)
}

// Called for OS window-close requests. The optional L preserves the original
// (registry, L) calls while allowing Odin code to call it with just registry.
// If no VM is available, we ask the Studio frontend to confirm rather than
// silently treating an active project as saved.
Project_Request_Window_Close :: proc(registry: ^Registry, L: ^vm.State = nil) -> bool {
	if registry == nil || registry.mode != .Editor {return true}
	studio := cast(^Studio)DataModel_Get_Service(registry.data_model, "Studio")
	project := cast(^ProjectService)DataModel_Get_Service(registry.data_model, "Project")
	if project == nil || project.exit_approved || studio == nil {return true}
	if setting, found := studio.settings["confirmExit"];
	   found && setting.kind == .Boolean && !setting.boolean {
		return true
	}

	live_state := L
	if live_state == nil {live_state = Project_Resolve_State(project)}
	if live_state == nil {
		if Project_Get_Active(project) == nil {return true}
		Studio_Send_Through_Pipe(studio, "ConfirmExit", true)
		return false
	}

	previous := vm.GetThreadSecurityCapabilities(live_state)
	vm.SetThreadSecurityCapabilities(live_state, vm.THREAD_SECURITY_ALL)
	defer vm.SetThreadSecurityCapabilities(live_state, previous)
	if !project_has_unsaved_changes(project, live_state) {return true}
	Studio_Send_Through_Pipe(studio, "ConfirmExit", true)
	return false
}
