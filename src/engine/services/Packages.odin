#+build !js
// wire:service
package services


import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import fsutil "../fsutil"
import serializer "../serializer"
import vm "../vm"


PACKAGES_DOWNLOADS_DIR :: "downloaded-packages"
PACKAGES_METADATA_DIR :: ".kinemium-package"
PACKAGES_METADATA_FILE :: "metadata.json"
PACKAGES_ARCHIVE_FILE :: "package.zip"

Packages :: struct {
	using service:      Service,
	marketplace_server: string,
	plugin_roots:       [dynamic]^classes.Object,
	loaded_plugins:     map[string]bool,
}

Packages_Class := classes.Class_Info {
	name   = "Packages",
	parent = &Service_Class,
}

Packages_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Packages)
	service.service = Service_Init(&Packages_Class, "Packages", data_model)
	service.loaded_plugins = make(map[string]bool)


	if root, ok := packages_downloads_root(); ok {
		delete(root)
	}
	return &service.object
}


packages_marketplace_server :: proc(service: ^Packages) -> string {
	if service.marketplace_server != "" {
		return service.marketplace_server
	}

	registry := service.service.data_model.registry
	if descriptor := Find_Service(registry, "KinemiumService");
	   descriptor != nil && descriptor.object != nil {
		api := cast(^KinemiumService)descriptor.object
		if api.api_auth.token != "" && api.api_auth.homeserver != "" {
			return api.api_auth.homeserver
		}
	}
	if descriptor := Find_Service(registry, "MatrixService");
	   descriptor != nil && descriptor.object != nil {
		matrix_service := cast(^MatrixService)descriptor.object
		if matrix_service.session != nil && matrix_service.session.homeserver != "" {
			return matrix_service.session.homeserver
		}
	}
	return MATRIX_DEFAULT_HOMESERVER
}

packages_normalize_marketplace_server :: proc(input: string) -> string {
	trimmed := strings.trim_space(input)
	if trimmed == "" {
		return ""
	}

	normalized := matrix_normalize_homeserver(trimmed)
	defer delete(normalized)

	cleaned := strings.trim_right(normalized, "/")
	if cleaned == "" {
		return ""
	}
	return strings.clone(cleaned)
}


packages_marketplace_public_call :: proc(
	L: ^vm.State,
	service: ^Packages,
	method, path: string,
	options: Kinemium_Call_Options,
) -> i32 {
	defer kinemium_options_destroy(options)

	server := packages_marketplace_server(service)
	if server == "" {
		vm.PushBoolean(L, false)
		vm.PushString(L, "No marketplace server configured.")
		kinemium_push_meta(L, Kinemium_Meta{})
		return 3
	}

	call_options := options
	call_options.omit_auth = true
	success, data, body, meta := kinemium_call(server, "", method, path, call_options)
	defer kinemium_call_destroy(data, body, meta)
	kinemium_push_result(L, success, data, body, options.raw || !success, meta)
	return 3
}

packages_marketplace_path :: proc(namespace, name: string, suffix: string) -> string {
	return strings.concatenate(
		{"/marketplace/", kinemium_url_encode(namespace), "/", kinemium_url_encode(name), suffix},
		context.temp_allocator,
	)
}

packages_join_path :: proc(parts: []string) -> (string, bool) {
	path, err := filepath.join(parts, context.allocator)
	if err != nil {
		return "", false
	}
	return path, true
}


packages_downloads_root :: proc() -> (string, bool) {
	data_dir, data_err := os.user_data_dir(context.allocator)
	if data_err != nil {
		return "", false
	}
	defer delete(data_dir)

	root, join_err := filepath.join(
		[]string{data_dir, "Kinemium", PACKAGES_DOWNLOADS_DIR},
		context.allocator,
	)
	if join_err != nil {
		return "", false
	}

	if !os.is_directory(root) {
		if err := fsutil.Make_Directory_All(root); err != nil && !os.is_directory(root) {
			fmt.eprintf("[Packages] failed creating downloads directory %s: %v\n", root, err)
			delete(root)
			return "", false
		}
	}

	return root, true
}


packages_safe_component :: proc(value: string) -> (string, bool) {
	if value == "" || value == "." || value == ".." || len(value) > 128 {
		return "", false
	}

	for character in value {
		switch {
		case 'a' <= character &&
		     character <= 'z',
		     'A' <= character &&
		     character <= 'Z',
		     '0' <= character &&
		     character <= '9',
		     character ==
		     '.',
		     character ==
		     '_',
		     character ==
		     '-',
		     character ==
		     '+':
		case:
			return "", false
		}
	}

	return strings.clone(value), true
}

packages_json_string :: proc(value: json.Value) -> string {
	#partial switch v in value {
	case json.String:
		return string(v)
	}
	return ""
}

packages_json_number :: proc(value: json.Value) -> f64 {
	#partial switch v in value {
	case json.Integer:
		return f64(i64(v))
	case json.Float:
		return f64(v)
	}
	return 0
}

Package_Plugin_Metadata :: struct {
	is_plugin:     bool,
	namespace:     string,
	name:          string,
	version:       string,
	entrypoint:    string,
	downloaded_at: i64,
}

package_plugin_metadata_destroy :: proc(info: ^Package_Plugin_Metadata) {
	if info == nil {
		return
	}
	if info.namespace != "" {delete(info.namespace)}
	if info.name != "" {delete(info.name)}
	if info.version != "" {delete(info.version)}
	if info.entrypoint != "" {delete(info.entrypoint)}
	info^ = {}
}

packages_json_array_has_plugin_tag :: proc(value: json.Value) -> bool {
	array, ok := value.(json.Array)
	if !ok {
		return false
	}
	for item in array {
		tag, is_string := item.(json.String)
		if is_string && strings.equal_fold(string(tag), "plugin") {
			return true
		}
	}
	return false
}

packages_json_is_plugin_type :: proc(value: json.Value) -> bool {
	return strings.equal_fold(packages_json_string(value), "plugin")
}

packages_metadata_plugin_info :: proc(value: json.Value) -> (Package_Plugin_Metadata, bool) {
	metadata, is_object := value.(json.Object)
	if !is_object {
		return {}, false
	}

	namespace := packages_json_string(metadata["namespace"])
	name := packages_json_string(metadata["name"])
	version := packages_json_string(metadata["version"])
	if namespace == "" || name == "" || version == "" {
		return {}, false
	}

	package_data, has_package_data := metadata["packageData"].(json.Object)
	if !has_package_data {
		return {}, false
	}

	is_plugin := false
	if package_value, ok := package_data["package"].(json.Object); ok {
		if tags, has_tags := package_value["tags"]; has_tags {
			is_plugin = packages_json_array_has_plugin_tag(tags)
		}
		if packages_json_is_plugin_type(package_value["itemType"]) {
			is_plugin = true
		}
	}

	entrypoint := ""
	if version_value, ok := package_data["version"].(json.Object); ok {
		entrypoint = packages_json_string(version_value["entrypoint"])
		if manifest, has_manifest := version_value["manifest"].(json.Object); has_manifest {
			if !is_plugin {
				if tags, has_tags := manifest["tags"]; has_tags {
					is_plugin = packages_json_array_has_plugin_tag(tags)
				}
			}
			if packages_json_is_plugin_type(manifest["type"]) {
				is_plugin = true
			}
			if entrypoint == "" {
				entrypoint = packages_json_string(manifest["entrypoint"])
			}
		}
	}

	if entrypoint == "" {
		entrypoint = strings.concatenate({name, ".kine"}, context.allocator)
	} else {
		entrypoint = strings.clone(entrypoint)
	}

	info := Package_Plugin_Metadata {
		is_plugin     = is_plugin,
		namespace     = strings.clone(namespace),
		name          = strings.clone(name),
		version       = strings.clone(version),
		entrypoint    = entrypoint,
		downloaded_at = i64(packages_json_number(metadata["downloadedAt"])),
	}
	return info, true
}

packages_safe_entrypoint :: proc(value: string) -> (string, bool) {
	if value == "" ||
	   strings.has_prefix(value, "/") ||
	   strings.has_prefix(value, "\\") ||
	   strings.contains(value, "\\") ||
	   strings.contains(value, "..") ||
	   strings.contains(value, ":") {
		return "", false
	}
	return strings.clone(value), true
}

packages_find_plugin_script :: proc(object: ^classes.Object) -> ^classes.Object {
	if object == nil || object.destroyed {
		return nil
	}

	if common := classes.Script_Common_Of(object); common != nil {
		kind, ok := classes.Script_Kind_Of(object)
		if ok && kind != .ModuleScript && common.enabled && len(common.source) > 0 {
			return object
		}
	}

	for child in classes.Get_Children(object) {
		if found := packages_find_plugin_script(child); found != nil {
			return found
		}
	}
	return nil
}

packages_run_plugin_dir :: proc(service: ^Packages, version_dir: string) -> bool {
	if service == nil || version_dir == "" {
		return false
	}

	metadata_path, metadata_ok := packages_join_path(
		[]string{version_dir, PACKAGES_METADATA_DIR, PACKAGES_METADATA_FILE},
	)
	if !metadata_ok {
		return false
	}
	defer delete(metadata_path)

	metadata_bytes, read_err := os.read_entire_file(metadata_path, context.allocator)
	if read_err != nil {
		return false
	}
	defer delete(metadata_bytes)

	value, parse_err := json.parse_string(
		string(metadata_bytes),
		parse_integers = true,
		allocator = context.allocator,
	)
	if parse_err != nil {
		return false
	}
	defer json.destroy_value(value)

	info, info_ok := packages_metadata_plugin_info(value)
	if !info_ok {
		return false
	}
	defer package_plugin_metadata_destroy(&info)
	if !info.is_plugin {
		return false
	}

	key := strings.concatenate(
		{info.namespace, "/", info.name, "@", info.version},
		context.allocator,
	)
	defer delete(key)
	if service.loaded_plugins[key] {
		return true
	}

	entrypoint, entrypoint_ok := packages_safe_entrypoint(info.entrypoint)
	if !entrypoint_ok {
		return false
	}
	defer delete(entrypoint)

	entrypoint_path, path_ok := packages_join_path([]string{version_dir, entrypoint})
	if !path_ok {
		return false
	}
	defer delete(entrypoint_path)

	data, entrypoint_err := os.read_entire_file(entrypoint_path, context.allocator)
	if entrypoint_err != nil {
		fmt.eprintf("[Packages] plugin %s is missing entry point %s\n", key, entrypoint)
		return false
	}
	defer delete(data)

	registry := service.service.data_model.registry.classes
	if registry == nil || registry.vm_state == nil || registry.vm_state.L == nil {
		return false
	}

	root, deserialize_err := serializer.Deserialize_From_Data(
		registry,
		registry.vm_state.L,
		nil,
		data,
	)
	if !serializer.Error_Is_None(deserialize_err) {
		detail := serializer.Error_String(deserialize_err)
		fmt.eprintf("[Packages] could not load plugin %s: %s\n", key, detail)
		delete(detail)
		serializer.Error_Delete(&deserialize_err)
		return false
	}

	script := packages_find_plugin_script(root)
	common := classes.Script_Common_Of(script)
	if script == nil || common == nil {
		classes.Destroy_Hierarchy(root)
		return false
	}

	common.run_as_plugin = true
	append(&service.plugin_roots, root)
	service.loaded_plugins[strings.clone(key)] = true
	fmt.printf("[Packages] running plugin %s\n", key)
	return true
}

packages_run_downloaded_plugins_in_root :: proc(service: ^Packages, root: string) {
	if service == nil || root == "" {
		return
	}

	Package_Plugin_Candidate :: struct {
		path:          string,
		version:       string,
		downloaded_at: i64,
	}

	candidates := make(map[string]Package_Plugin_Candidate)
	defer {
		for key, candidate in candidates {
			delete(key)
			delete(candidate.path)
			delete(candidate.version)
		}
		delete(candidates)
	}

	namespaces, namespaces_err := os.read_directory_by_path(root, -1, context.allocator)
	if namespaces_err != nil {
		return
	}
	defer os.file_info_slice_delete(namespaces, context.allocator)

	for namespace_entry in namespaces {
		if namespace_entry.type != .Directory {
			continue
		}

		names, names_err := os.read_directory_by_path(
			namespace_entry.fullpath,
			-1,
			context.allocator,
		)
		if names_err != nil {
			continue
		}
		defer os.file_info_slice_delete(names, context.allocator)

		for name_entry in names {
			if name_entry.type != .Directory {
				continue
			}

			versions, versions_err := os.read_directory_by_path(
				name_entry.fullpath,
				-1,
				context.allocator,
			)
			if versions_err != nil {
				continue
			}
			defer os.file_info_slice_delete(versions, context.allocator)

			for version_entry in versions {
				if version_entry.type != .Directory {
					continue
				}

				metadata_path, metadata_ok := packages_join_path(
					[]string {
						version_entry.fullpath,
						PACKAGES_METADATA_DIR,
						PACKAGES_METADATA_FILE,
					},
				)
				if !metadata_ok {
					continue
				}

				metadata_bytes, read_err := os.read_entire_file(metadata_path, context.allocator)
				delete(metadata_path)
				if read_err != nil {
					continue
				}

				value, parse_err := json.parse_string(
					string(metadata_bytes),
					parse_integers = true,
					allocator = context.allocator,
				)
				delete(metadata_bytes)
				if parse_err != nil {
					continue
				}

				info, info_ok := packages_metadata_plugin_info(value)
				json.destroy_value(value)
				if !info_ok {
					continue
				}

				if !info.is_plugin {
					package_plugin_metadata_destroy(&info)
					continue
				}

				key := strings.concatenate({info.namespace, "/", info.name}, context.allocator)
				candidate := Package_Plugin_Candidate {
					path          = strings.clone(version_entry.fullpath),
					version       = info.version,
					downloaded_at = info.downloaded_at,
				}
				info.version = ""

				if existing, exists := candidates[key]; exists {
					is_newer :=
						candidate.downloaded_at > existing.downloaded_at ||
						(candidate.downloaded_at == existing.downloaded_at &&
								strings.compare(candidate.version, existing.version) > 0)
					if !is_newer {
						delete(key)
						delete(candidate.path)
						delete(candidate.version)
						package_plugin_metadata_destroy(&info)
						continue
					}
					delete(existing.path)
					delete(existing.version)
				}

				candidates[key] = candidate
				package_plugin_metadata_destroy(&info)
			}
		}
	}

	for _, candidate in candidates {
		_ = packages_run_plugin_dir(service, candidate.path)
	}
}

packages_run_downloaded_plugins :: proc(service: ^Packages) {
	if service == nil {
		return
	}

	root, root_ok := packages_downloads_root()
	if !root_ok {
		return
	}
	defer delete(root)

	packages_run_downloaded_plugins_in_root(service, root)
}

Packages_Run_Downloaded_Plugins :: proc(service: ^Packages) {
	packages_run_downloaded_plugins(service)
}


Packages_Run_Downloaded_Plugins_In :: proc(service: ^Packages, root: string) {
	packages_run_downloaded_plugins_in_root(service, root)
}

Packages_Run_Plugin_Directory :: proc(service: ^Packages, version_dir: string) -> bool {
	return packages_run_plugin_dir(service, version_dir)
}

packages_run_plugin_version :: proc(service: ^Packages, namespace, name, version: string) {
	root, root_ok := packages_downloads_root()
	if !root_ok {
		return
	}
	defer delete(root)

	version_dir, version_dir_ok := packages_join_path([]string{root, namespace, name, version})
	if !version_dir_ok {
		return
	}
	defer delete(version_dir)

	_ = packages_run_plugin_dir(service, version_dir)
}


packages_store_downloaded :: proc(base, token, namespace, name, version, archive: string) -> bool {
	namespace_component, namespace_ok := packages_safe_component(namespace)
	if !namespace_ok {
		return false
	}
	defer delete(namespace_component)

	name_component, name_ok := packages_safe_component(name)
	if !name_ok {
		return false
	}
	defer delete(name_component)

	version_component, version_ok := packages_safe_component(version)
	if !version_ok {
		return false
	}
	defer delete(version_component)

	root, root_ok := packages_downloads_root()
	if !root_ok {
		return false
	}
	defer delete(root)

	version_dir, version_dir_ok := packages_join_path(
		[]string{root, namespace_component, name_component, version_component},
	)
	if !version_dir_ok {
		return false
	}
	defer delete(version_dir)

	temp_dir, temp_err := os.make_directory_temp(root, "download-*", context.allocator)
	if temp_err != nil {
		return false
	}
	keep_temp := false
	defer {
		if !keep_temp {
			_ = os.remove_all(temp_dir)
		}
		delete(temp_dir)
	}


	download_archive, download_archive_ok := packages_join_path(
		[]string{temp_dir, ".download.zip"},
	)
	if !download_archive_ok {
		return false
	}
	defer delete(download_archive)

	if os.write_entire_file_from_string(download_archive, archive) != nil {
		fmt.eprintln("[Packages] failed writing downloaded package archive")
		return false
	}

	handle, opened := kineffi.Zip_Open(download_archive)
	if opened {
		if !kineffi.Zip_Extract_All(handle, temp_dir, false) {
			fmt.eprintf(
				"[Packages] failed extracting %s/%s@%s; keeping the archive only\n",
				namespace,
				name,
				version,
			)
		}
		_ = kineffi.Zip_Close(handle)
	} else {
		fmt.eprintf(
			"[Packages] downloaded %s/%s@%s is not a ZIP; keeping the archive only\n",
			namespace,
			name,
			version,
		)
	}
	_ = os.remove(download_archive)

	metadata_dir, metadata_dir_ok := packages_join_path([]string{temp_dir, PACKAGES_METADATA_DIR})
	if !metadata_dir_ok {
		return false
	}
	defer delete(metadata_dir)

	if err := fsutil.Make_Directory_All(metadata_dir);
	   err != nil && !os.is_directory(metadata_dir) {
		fmt.eprintf("[Packages] failed creating package metadata directory: %v\n", err)
		return false
	}

	archive_path, archive_path_ok := packages_join_path(
		[]string{metadata_dir, PACKAGES_ARCHIVE_FILE},
	)
	if !archive_path_ok {
		return false
	}
	defer delete(archive_path)

	if os.write_entire_file_from_string(archive_path, archive) != nil {
		fmt.eprintln("[Packages] failed writing the persisted package archive")
		return false
	}


	package_data: json.Value
	lookup_data: json.Value
	lookup_body: string
	lookup_meta: Kinemium_Meta
	defer kinemium_call_destroy(lookup_data, lookup_body, lookup_meta)
	if base != "" {
		version_url := strings.concatenate(
			{
				"/packages/",
				kinemium_url_encode(namespace),
				"/",
				kinemium_url_encode(name),
				"/versions/",
				kinemium_url_encode(version),
			},
			context.temp_allocator,
		)
		options := kinemium_options_empty()
		defer kinemium_options_destroy(options)
		ok, data, body, meta := kinemium_call(base, token, "GET", version_url, options)
		lookup_data = data
		lookup_body = body
		lookup_meta = meta
		if ok && data != nil {
			package_data = data
		}
	}

	fallback_data := make(json.Object, 3)
	defer delete(fallback_data)
	if package_data == nil {
		fallback_data["namespace"] = json.String(namespace)
		fallback_data["name"] = json.String(name)
		fallback_data["version"] = json.String(version)
		package_data = json.Value(fallback_data)
	}

	metadata := make(json.Object, 8)
	defer delete(metadata)
	metadata["namespace"] = json.String(namespace)
	metadata["name"] = json.String(name)
	metadata["version"] = json.String(version)
	metadata["size"] = json.Integer(len(archive))
	metadata["downloadedAt"] = json.Integer(i64(time.to_unix_seconds(time.now())))
	metadata["packageData"] = package_data

	metadata_bytes, marshal_err := json.marshal(metadata, {spec = .JSON}, context.temp_allocator)
	if marshal_err != nil {
		fmt.eprintf("[Packages] failed encoding package metadata: %v\n", marshal_err)
		return false
	}

	metadata_path, metadata_path_ok := packages_join_path(
		[]string{metadata_dir, PACKAGES_METADATA_FILE},
	)
	if !metadata_path_ok {
		return false
	}
	defer delete(metadata_path)

	if os.write_entire_file(metadata_path, metadata_bytes) != nil {
		fmt.eprintln("[Packages] failed writing package metadata")
		return false
	}

	parent_dir, parent_ok := packages_join_path(
		[]string{root, namespace_component, name_component},
	)
	if !parent_ok {
		return false
	}
	defer delete(parent_dir)

	if err := fsutil.Make_Directory_All(parent_dir); err != nil && !os.is_directory(parent_dir) {
		fmt.eprintf("[Packages] failed creating package directory: %v\n", err)
		return false
	}

	if os.exists(version_dir) {
		_ = os.remove_all(version_dir)
	}
	if os.rename(temp_dir, version_dir) != nil {
		fmt.eprintf("[Packages] failed moving downloaded package into %s\n", version_dir)
		return false
	}
	keep_temp = true
	return true
}

packages_download_package :: proc(L: ^vm.State, service: ^Packages) -> i32 {
	namespace := vm.ArgString(L, 2)
	name := vm.ArgString(L, 3)
	version := vm.ArgString(L, 4)
	path := strings.concatenate(
		{
			"/packages/",
			kinemium_url_encode(namespace),
			"/",
			kinemium_url_encode(name),
			"/versions/",
			kinemium_url_encode(version),
			"/download",
		},
		context.temp_allocator,
	)

	base, token, authenticated := kinemium_resolve_auth(service.service.data_model.registry, L, 0)
	if !authenticated {
		vm.PushBoolean(L, false)
		vm.PushString(L, "Not logged in.")
		kinemium_push_meta(L, Kinemium_Meta{})
		return 3
	}

	options := kinemium_options_raw()
	defer kinemium_options_destroy(options)
	success, data, body, meta := kinemium_call(base, token, "GET", path, options)
	defer kinemium_call_destroy(data, body, meta)

	if success && len(body) > 0 {
		if !packages_store_downloaded(base, token, namespace, name, version, body) {
			fmt.eprintf(
				"[Packages] downloaded %s/%s@%s but could not store it\n",
				namespace,
				name,
				version,
			)
		} else {
			packages_run_plugin_version(service, namespace, name, version)
		}
	}

	kinemium_push_result(L, success, data, body, true, meta)
	return 3
}

packages_push_downloaded_entry :: proc(L: ^vm.State, version_dir, metadata_path: string) -> bool {
	metadata_bytes, read_err := os.read_entire_file(metadata_path, context.allocator)
	if read_err != nil {
		return false
	}
	defer delete(metadata_bytes)

	value, parse_err := json.parse_string(
		string(metadata_bytes),
		parse_integers = true,
		allocator = context.allocator,
	)
	if parse_err != nil {
		return false
	}
	defer json.destroy_value(value)

	metadata, is_object := value.(json.Object)
	if !is_object {
		return false
	}

	archive_path, archive_path_ok := packages_join_path(
		[]string{version_dir, PACKAGES_METADATA_DIR, PACKAGES_ARCHIVE_FILE},
	)
	if archive_path_ok {
		defer delete(archive_path)
	}
	archive_value := ""
	if archive_path_ok && os.is_file(archive_path) {
		archive_value = archive_path
	}

	vm.NewTable(L, 0, 9)
	vm.PushString(L, version_dir)
	vm.SetField(L, -2, "path")
	vm.PushString(L, packages_json_string(metadata["name"]))
	vm.SetField(L, -2, "name")
	vm.PushString(L, packages_json_string(metadata["namespace"]))
	vm.SetField(L, -2, "namespace")
	vm.PushString(L, packages_json_string(metadata["version"]))
	vm.SetField(L, -2, "version")
	vm.PushNumber(L, packages_json_number(metadata["size"]))
	vm.SetField(L, -2, "size")
	vm.PushNumber(L, packages_json_number(metadata["downloadedAt"]))
	vm.SetField(L, -2, "downloadedAt")
	vm.PushString(L, archive_value)
	vm.SetField(L, -2, "archivePath")

	if package_data, has_data := metadata["packageData"]; has_data {
		http_push_json_value(L, package_data)
	} else {
		vm.NewTable(L, 0, 0)
	}
	vm.SetField(L, -2, "packageData")
	return true
}

packages_list_downloaded :: proc(L: ^vm.State, service: ^Packages) -> i32 {
	vm.NewTable(L, 0, 0)

	root, root_ok := packages_downloads_root()
	if !root_ok {
		return 1
	}
	defer delete(root)

	count := 0
	namespaces, namespaces_err := os.read_directory_by_path(root, -1, context.allocator)
	if namespaces_err != nil {
		return 1
	}
	defer os.file_info_slice_delete(namespaces, context.allocator)

	for namespace_entry in namespaces {
		if namespace_entry.type != .Directory {
			continue
		}

		names, names_err := os.read_directory_by_path(
			namespace_entry.fullpath,
			-1,
			context.allocator,
		)
		if names_err != nil {
			continue
		}
		defer os.file_info_slice_delete(names, context.allocator)

		for name_entry in names {
			if name_entry.type != .Directory {
				continue
			}

			versions, versions_err := os.read_directory_by_path(
				name_entry.fullpath,
				-1,
				context.allocator,
			)
			if versions_err != nil {
				continue
			}
			defer os.file_info_slice_delete(versions, context.allocator)

			for version_entry in versions {
				if version_entry.type != .Directory {
					continue
				}

				metadata_path, metadata_ok := packages_join_path(
					[]string {
						version_entry.fullpath,
						PACKAGES_METADATA_DIR,
						PACKAGES_METADATA_FILE,
					},
				)
				if !metadata_ok {
					continue
				}

				added := false
				if os.is_file(metadata_path) {
					added = packages_push_downloaded_entry(
						L,
						version_entry.fullpath,
						metadata_path,
					)
				}
				delete(metadata_path)

				if added {
					count += 1
					vm.SetArrayValue(L, -2, count)
				}
			}
		}
	}

	return 1
}

Packages_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^Packages)object
	switch key {
	case "MarketplaceServer":
		vm.PushString(L, packages_marketplace_server(service))
		return true
	case "DownloadedPackagesPath":
		root, ok := packages_downloads_root()
		if ok {
			vm.PushString(L, root)
			delete(root)
		} else {
			vm.PushString(L, "")
		}
		return true
	case "SearchPackages",
	     "PublishPackage",
	     "PublishInstance",
	     "ResolvePackages",
	     "GetPackage",
	     "UpdatePackage",
	     "GetPackageVersion",
	     "YankPackageVersion",
	     "DownloadPackage",
	     "BrowseMarketplace",
	     "GetMarketplacePackage",
	     "AcquirePackage",
	     "ListAcquisitions",
	     "ListReviews",
	     "SubmitReview",
	     "GetService",
	     "ListDownloadedPackages",
	     "GetDownloadedPackages":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

Packages_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^Packages)object
	switch key {
	case "MarketplaceServer":
		if service.marketplace_server != "" {
			delete(service.marketplace_server)
		}
		service.marketplace_server = packages_normalize_marketplace_server(
			vm.ArgString(L, value_index),
		)
		return true
	}
	return false
}

packages_push_error :: proc(L: ^vm.State, message: string) -> i32 {
	vm.PushBoolean(L, false)
	vm.PushString(L, message)
	kinemium_push_meta(L, Kinemium_Meta{})
	return 3
}


packages_publish_archive :: proc(
	L: ^vm.State,
	service: ^Packages,
	manifest_index, options_index: int,
	archive, archive_name: string,
) -> i32 {
	manifest_json := kinemium_encode_json(L, manifest_index)
	if manifest_json == "" {
		return packages_push_error(L, "The package details could not be encoded.")
	}
	defer delete(manifest_json)

	manifest_field := "manifest"
	file_field := "archive"
	filename := archive_name
	content_type := ""
	if vm.IsTable(L, options_index) {
		vm.GetField(L, options_index, "manifestField")
		if vm.IsString(L, -1) && vm.ArgString(L, -1) != "" {manifest_field = vm.ArgString(L, -1)}
		vm.Pop(L)
		vm.GetField(L, options_index, "fileField")
		if vm.IsString(L, -1) && vm.ArgString(L, -1) != "" {file_field = vm.ArgString(L, -1)}
		vm.Pop(L)
		vm.GetField(L, options_index, "filename")
		if vm.IsString(L, -1) && vm.ArgString(L, -1) != "" {filename = vm.ArgString(L, -1)}
		vm.Pop(L)
		vm.GetField(L, options_index, "contentType")
		if vm.IsString(L, -1) && vm.ArgString(L, -1) != "" {content_type = vm.ArgString(L, -1)}
		vm.Pop(L)
	}

	if filename == "" {
		name := ""
		version := ""
		if vm.IsTable(L, manifest_index) {
			vm.GetField(L, manifest_index, "name")
			name = vm.ArgOptionalString(L, -1, "")
			vm.Pop(L)
			vm.GetField(L, manifest_index, "version")
			version = vm.ArgOptionalString(L, -1, "")
			vm.Pop(L)
		}
		filename = strings.concatenate({name, "-", version, ".zip"}, context.temp_allocator)
	}
	if content_type == "" {content_type = "application/octet-stream"}

	parts := [2]Kinemium_Multipart_Part {
		{name = manifest_field, content_type = "application/json", value = manifest_json},
		{name = file_field, filename = filename, content_type = content_type, value = archive},
	}
	options := kinemium_options_empty()
	options.raw_body, options.content_type = kinemium_multipart(parts[:])
	return kinemium_domain_call(L, &service.service, 2, "POST", "/packages", options)
}

Packages_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^Packages)object
	switch method {
	case "SearchPackages":
		return kinemium_domain_call(
				L,
				&service.service,
				2,
				"GET",
				"/packages",
				kinemium_options_query(L, 3),
			),
			true

	case "PublishPackage":
		return packages_publish_archive(L, service, 3, 5, vm.ArgString(L, 4), ""), true

	case "PublishInstance":
		{
			target := export_object_from_argument(L, 2)
			if target == nil {
				return packages_push_error(
						L,
						"Packages:PublishInstance expects an Instance to publish.",
					),
					true
			}

			model := service.service.data_model
			if model == nil || model.registry == nil || model.registry.classes == nil {
				return packages_push_error(L, "No active DataModel is available for packaging."),
					true
			}

			data, serialize_err := serializer.Serialize(model.registry.classes, L, target)
			if !serializer.Error_Is_None(serialize_err) {
				detail := serializer.Error_String(serialize_err)
				defer delete(detail)
				serializer.Error_Delete(&serialize_err)
				return packages_push_error(
						L,
						fmt.tprintf("Could not serialize the selected instance: %s", detail),
					),
					true
			}
			defer delete(data)

			entrypoint := ""
			if vm.IsTable(L, 3) {
				vm.GetField(L, 3, "entrypoint")
				entrypoint = vm.ArgOptionalString(L, -1, "")
				vm.Pop(L)
			}
			if entrypoint == "" {
				entrypoint = strings.concatenate({target.name, ".kine"}, context.temp_allocator)
			}
			if strings.has_prefix(entrypoint, "/") ||
			   strings.has_prefix(entrypoint, "\\") ||
			   strings.contains(entrypoint, "..") {
				return packages_push_error(
						L,
						"The package entry point must be a relative path without '..'.",
					),
					true
			}

			temp_dir, temp_err := os.make_directory_temp(
				"",
				"kinemium-package-*",
				context.allocator,
			)
			if temp_err != nil {
				return packages_push_error(L, "Could not create a temporary package directory."),
					true
			}
			defer {
				_ = os.remove_all(temp_dir)
				delete(temp_dir)
			}

			zip_path, join_err := os.join_path({temp_dir, "package.zip"}, context.allocator)
			if join_err != nil {
				return packages_push_error(L, "Could not prepare the package archive path."), true
			}
			defer delete(zip_path)

			handle, created := kineffi.Zip_Create(zip_path)
			if !created {
				return packages_push_error(L, "Could not create the package archive."), true
			}
			if !kineffi.Zip_Add_Data(handle, entrypoint, data) {
				_ = kineffi.Zip_Close(handle)
				return packages_push_error(
						L,
						"Could not add the selected instance to the package archive.",
					),
					true
			}
			if !kineffi.Zip_Close(handle) {
				return packages_push_error(L, "Could not finalize the package archive."), true
			}

			archive_bytes, read_err := os.read_entire_file(zip_path, context.allocator)
			if read_err != nil {
				return packages_push_error(L, "Could not read the generated package archive."),
					true
			}
			defer delete(archive_bytes)

			return packages_publish_archive(L, service, 3, 4, string(archive_bytes), ""), true
		}

	case "ResolvePackages":
		{
			body := make(json.Object, 1)
			defer delete(body)
			value, err := http_lua_to_json(L, 3, 0)
			if err != "" {
				delete(err)
			} else {
				defer json.destroy_value(value)
				body["requirements"] = value
			}
			options := kinemium_options_empty()
			options.json = kinemium_marshal(body)
			return kinemium_domain_call(
					L,
					&service.service,
					2,
					"POST",
					"/packages/resolve",
					options,
				),
				true
		}

	case "GetPackage":
		{
			path := strings.concatenate(
				{
					"/packages/",
					kinemium_url_encode(vm.ArgString(L, 3)),
					"/",
					kinemium_url_encode(vm.ArgString(L, 4)),
				},
				context.temp_allocator,
			)
			return kinemium_domain_call(
					L,
					&service.service,
					2,
					"GET",
					path,
					kinemium_options_empty(),
				),
				true
		}

	case "UpdatePackage":
		{
			path := strings.concatenate(
				{
					"/packages/",
					kinemium_url_encode(vm.ArgString(L, 3)),
					"/",
					kinemium_url_encode(vm.ArgString(L, 4)),
				},
				context.temp_allocator,
			)
			return kinemium_domain_call(
					L,
					&service.service,
					2,
					"PATCH",
					path,
					kinemium_options_json(L, 5),
				),
				true
		}

	case "GetPackageVersion":
		{
			path := strings.concatenate(
				{
					"/packages/",
					kinemium_url_encode(vm.ArgString(L, 3)),
					"/",
					kinemium_url_encode(vm.ArgString(L, 4)),
					"/versions/",
					kinemium_url_encode(vm.ArgString(L, 5)),
				},
				context.temp_allocator,
			)
			return kinemium_domain_call(
					L,
					&service.service,
					2,
					"GET",
					path,
					kinemium_options_empty(),
				),
				true
		}

	case "YankPackageVersion":
		{
			path := strings.concatenate(
				{
					"/packages/",
					kinemium_url_encode(vm.ArgString(L, 3)),
					"/",
					kinemium_url_encode(vm.ArgString(L, 4)),
					"/versions/",
					kinemium_url_encode(vm.ArgString(L, 5)),
					"/yank",
				},
				context.temp_allocator,
			)
			options := kinemium_options_empty()
			options.json = strings.clone("{}")
			return kinemium_domain_call(L, &service.service, 2, "POST", path, options), true
		}

	case "DownloadPackage":
		return packages_download_package(L, service), true

	case "ListDownloadedPackages", "GetDownloadedPackages":
		return packages_list_downloaded(L, service), true

	case "BrowseMarketplace":
		return packages_marketplace_public_call(
				L,
				service,
				"GET",
				"/marketplace",
				kinemium_options_query(L, 2),
			),
			true

	case "GetMarketplacePackage":
		return packages_marketplace_public_call(
				L,
				service,
				"GET",
				packages_marketplace_path(vm.ArgString(L, 2), vm.ArgString(L, 3), ""),
				kinemium_options_empty(),
			),
			true

	case "ListReviews":
		return packages_marketplace_public_call(
				L,
				service,
				"GET",
				packages_marketplace_path(vm.ArgString(L, 2), vm.ArgString(L, 3), "/reviews"),
				kinemium_options_query(L, 4),
			),
			true

	case "AcquirePackage":
		{
			options := kinemium_options_empty()
			options.json = strings.clone("{}")
			return kinemium_domain_call(
					L,
					&service.service,
					0,
					"POST",
					packages_marketplace_path(vm.ArgString(L, 2), vm.ArgString(L, 3), "/acquire"),
					options,
				),
				true
		}

	case "ListAcquisitions":
		return kinemium_domain_call(
				L,
				&service.service,
				0,
				"GET",
				"/marketplace/acquisitions",
				kinemium_options_query(L, 2),
			),
			true

	case "SubmitReview":
		return kinemium_domain_call(
				L,
				&service.service,
				0,
				"POST",
				packages_marketplace_path(vm.ArgString(L, 2), vm.ArgString(L, 3), "/reviews"),
				kinemium_options_json(L, 4),
			),
			true

	case "GetService":
		classes.Push_Object(L, Service_Get_Service(&service.service, vm.ArgString(L, 2)))
		return 1, true
	}
	return 0, false
}

Packages_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^Packages)object
	if service.marketplace_server != "" {
		delete(service.marketplace_server)
	}
	// lua_close finalizes the plugin roots itself and may already have freed them.
	if !vm.Is_Closing() {
		for root in service.plugin_roots {
			if root != nil && !root.destroyed {
				classes.Destroy_Hierarchy(root)
			}
		}
	}
	delete(service.plugin_roots)
	for key, _ in service.loaded_plugins {
		delete(key)
	}
	delete(service.loaded_plugins)
	classes.Object_Destroy(object)
	free(service)
}

Register_Packages_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Packages_Class,
		Packages_construct,
		Packages_destroy,
		creatable = false,
		get = Packages_get,
		set = Packages_set,
		namecall = Packages_namecall,
	)
}
