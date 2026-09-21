#+build !js

package services

// wire:service global="EditorService"

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import kineffi "../bindings"
import classes "../classes"

EDITOR_REPOSITORY_API_URL :: "https://api.github.com/repos/quadigen/kinemium-editor/commits/main"
EDITOR_ARCHIVE_BASE_URL :: "https://codeload.github.com/quadigen/kinemium-editor/zip/"
EDITOR_ARCHIVE_NAME :: "editor.zip"
EDITOR_VERSION_NAME :: "editor.version"
EDITOR_ENTRYPOINT_SUFFIX :: "/internal/editor_ui.luau"

EditorService_Class := classes.Class_Info {
	name   = "EditorService",
	parent = &Service_Class,
}

EditorService :: struct {
	using service: Service,
}

Editor_Commit :: struct {
	sha: string,
}

Editor_Fetch_Result :: struct {
	path:              string,
	downloaded:        bool,
	update_checked:    bool,
	using_stale_cache: bool,
	warning:           string,
	error_message:     string,
}

EditorService_Cache_Paths :: proc() -> (
	string,
	string,
	bool,
) {
	data_dir, err := os.user_data_dir(context.allocator)
	if err != nil {
		return "", "", false
	}
	defer delete(data_dir)

	kinemium_dir, join_err := filepath.join(
		[]string{data_dir, "Kinemium"},
		context.allocator,
	)
	if join_err != nil {
		return "", "", false
	}
	defer delete(kinemium_dir)

	if err := os.make_directory_all(kinemium_dir); err != nil {
		return "", "", false
	}

	archive_path, archive_err := filepath.join(
		[]string{kinemium_dir, EDITOR_ARCHIVE_NAME},
		context.allocator,
	)
	if archive_err != nil {
		return "", "", false
	}

	version_path, version_err := filepath.join(
		[]string{kinemium_dir, EDITOR_VERSION_NAME},
		context.allocator,
	)
	if version_err != nil {
		delete(archive_path)
		return "", "", false
	}

	return archive_path, version_path, true
}

EditorService_Commit_Is_Valid :: proc(sha: string) -> bool {
	if len(sha) != 40 {
		return false
	}

	for character in sha {
		if !((character >= '0' && character <= '9') ||
		     (character >= 'a' && character <= 'f') ||
		     (character >= 'A' && character <= 'F')) {
			return false
		}
	}

	return true
}

EditorService_Validate_Blob :: proc(path: string) -> bool {
	handle, opened := kineffi.Zip_Open(path)
	if !opened {
		return false
	}
	defer kineffi.Zip_Close(handle)

	for index := u32(0); index < kineffi.Zip_File_Count(handle); index += 1 {
		name, ok := kineffi.Zip_File_Name(handle, index)
		if !ok {
			continue
		}

		is_entrypoint := name == "internal/editor_ui.luau" ||
		                 strings.has_suffix(name, EDITOR_ENTRYPOINT_SUFFIX)
		delete(name)

		if is_entrypoint {
			return true
		}
	}

	return false
}

EditorService_Read_Cached_Version :: proc(path: string) -> string {
	if !os.is_file(path) {
		return ""
	}

	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return ""
	}
	defer delete(data)

	version := strings.trim_space(string(data))
	if !EditorService_Commit_Is_Valid(version) {
		return ""
	}

	return strings.clone(version)
}

EditorService_Remote_Version :: proc(
	service: ^EditorService,
) -> (string, bool) {
	http_object := Service_Get_Service(&service.service, "HttpService")
	if http_object == nil {
		return "", false
	}

	commit: Editor_Commit
	if !HttpService_GetJSON(
		cast(^HttpService)http_object,
		EDITOR_REPOSITORY_API_URL,
		&commit,
	) {
		return "", false
	}

	if !EditorService_Commit_Is_Valid(commit.sha) {
		if len(commit.sha) > 0 {
			delete(commit.sha)
		}
		return "", false
	}

	return commit.sha, true
}

EditorService_Replace_File :: proc(temp_path, destination: string) -> bool {
	return os.rename(temp_path, destination) == nil
}

EditorService_Write_Version :: proc(path, version: string) -> bool {
	temp_path := strings.concatenate({path, ".download"})
	defer delete(temp_path)

	if err := os.write_entire_file_from_string(temp_path, version); err != nil {
		return false
	}

	if !EditorService_Replace_File(temp_path, path) {
		_ = os.remove(temp_path)
		return false
	}

	return true
}

EditorService_Needs_Download :: proc(
	valid_cache: bool,
	cached_version: string,
	remote_version: string,
	update_checked: bool,
) -> bool {
	if !valid_cache {
		return true
	}

	return update_checked && cached_version != remote_version
}

EditorService_Download_Blob :: proc(
	service: ^EditorService,
	archive_path: string,
	reference: string,
) -> bool {
	http_object := Service_Get_Service(&service.service, "HttpService")
	if http_object == nil {
		return false
	}

	url := fmt.aprintf("%s%s", EDITOR_ARCHIVE_BASE_URL, reference)
	defer delete(url)

	data, fetched := HttpService_GetAsync(cast(^HttpService)http_object, url)
	if !fetched {
		return false
	}
	defer delete(data)

	temp_path := strings.concatenate({archive_path, ".download"})
	defer delete(temp_path)

	if err := os.write_entire_file_from_string(temp_path, data); err != nil {
		return false
	}

	if !EditorService_Validate_Blob(temp_path) {
		_ = os.remove(temp_path)
		return false
	}

	if !EditorService_Replace_File(temp_path, archive_path) {
		_ = os.remove(temp_path)
		return false
	}

	return true
}

EditorService_Get_Editor :: proc(service: ^EditorService) -> Editor_Fetch_Result {
	result := Editor_Fetch_Result{}

	archive_path, version_path, paths_ok := EditorService_Cache_Paths()
	if !paths_ok {
		result.error_message = "Failed resolving the editor cache paths"
		return result
	}
	defer delete(version_path)

	valid_cache := os.is_file(archive_path) && EditorService_Validate_Blob(archive_path)
	cached_version := EditorService_Read_Cached_Version(version_path)
	defer if len(cached_version) > 0 { delete(cached_version) }

	remote_version, update_checked := EditorService_Remote_Version(service)
	defer if len(remote_version) > 0 { delete(remote_version) }
	result.update_checked = update_checked

	needs_download := EditorService_Needs_Download(
		valid_cache,
		cached_version,
		remote_version,
		update_checked,
	)

	if !needs_download {
		result.path = archive_path
		if !update_checked {
			result.using_stale_cache = true
			result.warning = "Editor update check failed; using the cached editor"
		}
		return result
	}

	download_reference := "main"
	if update_checked {
		download_reference = remote_version
	}

	if !EditorService_Download_Blob(service, archive_path, download_reference) {
		if valid_cache {
			result.path = archive_path
			result.using_stale_cache = true
			result.warning = "Editor update download failed; using the cached editor"
			return result
		}

		delete(archive_path)
		result.error_message = "Failed downloading the editor archive"
		return result
	}

	result.path = archive_path
	result.downloaded = true
	if update_checked && !EditorService_Write_Version(version_path, remote_version) {
		result.warning = "Editor downloaded, but its version metadata could not be cached"
	}

	return result
}

editor_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(EditorService)
	service.service = Service_Init(&EditorService_Class, "EditorService", data_model)
	return &service.object
}

editor_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	classes.Object_Destroy(object)
	free(cast(^EditorService)object)
}

Register_EditorService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&EditorService_Class,
		editor_service_construct,
		editor_service_destroy,
		creatable = false,
	)
}
