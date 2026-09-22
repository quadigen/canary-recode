#+build !js

package services

// wire:service global="UpdateService"

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:thread"
import "core:time"
import json "core:encoding/json"

import globals "../global"
import target "../target"
import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

import http "../util/odin-http"
import http_client "../util/odin-http/client"

UPDATE_ARCHIVE_EXT         :: ".zip"
UPDATE_DIR_NAME            :: "updates"
UPDATE_PENDING_NAME        :: "pending"
UPDATE_PENDING_VERSION_NAME :: "pending.version"
UPDATE_STALE_SUFFIX        :: ".kinemium-old"
UPDATE_CHECK_TTL_SECONDS   :: 1800

UpdateService_Class := classes.Class_Info{
	name   = "UpdateService",
	parent = &Service_Class,
}

UpdateService :: struct {
	using service: Service,

	cached:            UpdateReport,
	cached_valid:      bool,
	cached_time:       i64,

	background_started: bool,
}

UpdateStatus :: enum u8 {
	Check_Failed,
	Up_To_Date,
	Update_Available,
}

UpdateReport :: struct {
	status:    UpdateStatus,
	available: bool,

	current_display:    string,
	current_prerelease: string,
	current_git:        string,
	current_major:      int,
	current_minor:      int,
	current_patch:      int,

	latest_version:   string,
	latest_tag:       string,
	latest_url:       string,
	latest_published: string,
	latest_notes:     string,

	asset_name: string,
	asset_url:  string,
	asset_size: i64,

	staged_ready:   bool,
	staged_version: string,

	error: string,
}

GitHub_Asset :: struct {
	name:                 string,
	browser_download_url: string,
	size:                 i64,
}

GitHub_Release :: struct {
	tag_name:    string,
	html_url:    string,
	published_at: string,
	body:        string,
	assets:      []GitHub_Asset,
}

update_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(UpdateService)
	service.service = Service_Init(&UpdateService_Class, "UpdateService", data_model)
	return &service.object
}

update_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	service := cast(^UpdateService)object
	update_report_destroy(&service.cached)
	classes.Object_Destroy(object)
	free(service)
}

update_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "IsUpdateAvailable", "ApplyUpdate":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

update_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	service := cast(^UpdateService)object
	switch method {
	case "IsUpdateAvailable":
		update_service_push_available(L, service)
		return 1, true
	case "ApplyUpdate":
		vm.PushBoolean(L, update_service_apply_now(service))
		return 1, true
	}
	return 0, false
}

Register_UpdateService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&UpdateService_Class,
		update_service_construct,
		update_service_destroy,
		creatable = false,
		get       = update_service_get,
		namecall  = update_service_namecall,
	)
}

// Self-updates are only meaningful for the editor and the client, and only for
// stamped release builds. Developer builds (`odin run`, no RUNTIME_GIT_COMMIT)
// never disable the system indirectly by being unstamped.
update_service_enabled :: proc() -> bool {
	when target.IS_SERVER {
		return false
	} else {
		return len(globals.RUNTIME_GIT_COMMIT) > 0 && len(globals.RUNTIME_UPDATE_URL) > 0
	}
}

update_status_string :: proc(status: UpdateStatus) -> string {
	switch status {
	case .Up_To_Date:      return "up_to_date"
	case .Update_Available: return "update_available"
	case .Check_Failed:     return "check_failed"
	}
	return "check_failed"
}

update_report_destroy :: proc(report: ^UpdateReport) {
	delete(report.current_display)
	delete(report.current_prerelease)
	delete(report.current_git)
	delete(report.latest_version)
	delete(report.latest_tag)
	delete(report.latest_url)
	delete(report.latest_published)
	delete(report.latest_notes)
	delete(report.asset_name)
	delete(report.asset_url)
	delete(report.staged_version)
	delete(report.error)
	report^ = {}
}

update_release_destroy :: proc(release: ^GitHub_Release) {
	for &asset in release.assets {
		delete(asset.name)
		delete(asset.browser_download_url)
	}
	delete(release.assets)
	delete(release.tag_name)
	delete(release.html_url)
	delete(release.published_at)
	delete(release.body)
	release^ = {}
}

update_os_tag :: proc() -> string {
	when ODIN_OS == .Windows {
		return "windows"
	} else when ODIN_OS == .Linux {
		return "linux"
	} else when ODIN_OS == .Darwin {
		return "macos"
	}
	return "unknown"
}

update_arch_tag :: proc() -> string {
	when ODIN_ARCH == .amd64 {
		return "x86_64"
	} else when ODIN_ARCH == .arm64 {
		return "arm64"
	}
	return "unknown"
}

Update_Asset_Name :: proc(os_name, arch_name: string) -> string {
	return strings.concatenate({"kinemium-", os_name, "-", arch_name, UPDATE_ARCHIVE_EXT}, context.allocator)
}

update_strip_v :: proc(version: string) -> string {
	if strings.has_prefix(version, "v") {
		return strings.clone(version[1:])
	}
	return strings.clone(version)
}

// Returns >0 when a is newer, 0 when equal, <0 when a is older. Only the
// major/minor/patch triple and the presence of a prerelease identifier take
// part in the comparison (a release always beats a prerelease of the same
// triple, and pre-release identifiers compare lexically).
Update_Version_Compare :: proc(a, b: string) -> int {
	amajor, aminor, apatch, aprerelease, aok := update_parse_version(a)
	bmajor, bminor, bpatch, bprerelease, bok := update_parse_version(b)

	if aok != bok {
		if !aok {
			return -1
		}
		return 1
	}

	if !aok && !bok {
		return 0
	}

	if amajor != bmajor {
		return -1 if amajor < bmajor else 1
	}
	if aminor != bminor {
		return -1 if aminor < bminor else 1
	}
	if apatch != bpatch {
		return -1 if apatch < bpatch else 1
	}

	switch {
	case aprerelease == bprerelease:
		return 0
	case bprerelease == "":
		return -1
	case aprerelease == "":
		return 1
	case aprerelease > bprerelease:
		return 1
	case aprerelease < bprerelease:
		return -1
	}
	return 0
}

update_parse_version :: proc(version: string) -> (major, minor, patch: int, prerelease: string, ok: bool) {
	text := strings.trim_space(version)
	if len(text) == 0 {
		return 0, 0, 0, "", false
	}
	if strings.has_prefix(text, "v") {
		text = text[1:]
	}

	if dash := strings.index(text, "-"); dash >= 0 {
		prerelease = strings.trim_space(text[dash + 1:])
		text = text[:dash]
	}
	if plus := strings.index(text, "+"); plus >= 0 {
		text = text[:plus]
	}

	parts := strings.split(text, ".")
	defer delete(parts)
	if len(parts) == 0 || len(parts[0]) == 0 {
		return 0, 0, 0, prerelease, false
	}

	for index in 0 ..< min(len(parts), 3) {
		value, parsed := strconv.parse_int(parts[index], 10)
		if !parsed {
			return 0, 0, 0, prerelease, false
		}
		switch index {
		case 0:
			major = value
		case 1:
			minor = value
		case 2:
			patch = value
		}
	}
	return major, minor, patch, prerelease, true
}

// Sends an HTTP GET with an explicit User-Agent. The GitHub API rejects
// requests without one, so this path (not HttpService_GetAsync) is used for
// manifest lookups.
update_http_get :: proc(url: string) -> (body: string, status: int, ok: bool) {
	req: http_client.Request
	http_client.request_init(&req, .Get)
	defer http_client.request_destroy(&req)

	user_agent := fmt.tprintf("Kinemium/%s", globals.RUNTIME_VERSION_DISPLAY)
	defer delete(user_agent)
	key := http.headers_set(&req.headers, "User-Agent", user_agent)
	defer delete(key)

	response, request_error := http_client.request(&req, url)
	if request_error != nil {
		return "", 0, false
	}
	defer http_client.response_destroy(&response)

	response_body, body_allocated, body_error := http_client.response_body(&response, allocator = context.allocator)
	if body_error != nil {
		return "", 0, false
	}
	defer http_client.body_destroy(response_body, body_allocated, context.allocator)

	#partial switch value in response_body {
	case http_client.Body_Plain:
		return strings.clone(string(value), context.allocator), int(response.status), http.status_is_success(response.status)
	case:
		return "", int(response.status), false
	}
}

update_decode_release :: proc(body: string) -> (GitHub_Release, bool) {
	release: GitHub_Release
	err := json.unmarshal_string(body, &release, allocator = context.allocator)
	if err != nil {
		update_release_destroy(&release)
		return release, false
	}
	return release, true
}

update_pick_asset :: proc(release: GitHub_Release) -> (name, url: string, size: i64, ok: bool) {
	expected := Update_Asset_Name(update_os_tag(), update_arch_tag())
	defer delete(expected)

	for asset in release.assets {
		if asset.name == expected {
			return strings.clone(asset.name), strings.clone(asset.browser_download_url), asset.size, true
		}
	}
	return "", "", 0, false
}

// Root directory that keeps all self-update state:
//   <user data>/Kinemium/updates/pending/<tag>/...
//   <tag>/pending.version        - marker written once a bundle is staged
update_update_roots :: proc() -> (updates_dir, pending_root: string, ok: bool) {
	data_dir, err := os.user_data_dir(context.allocator)
	if err != nil {
		return "", "", false
	}
	defer delete(data_dir)

	kinemium_dir, join_err := filepath.join([]string{data_dir, "Kinemium"}, context.allocator)
	if join_err != nil {
		return "", "", false
	}
	defer delete(kinemium_dir)

	updates_dir, join_err = filepath.join([]string{kinemium_dir, UPDATE_DIR_NAME}, context.allocator)
	if join_err != nil {
		return "", "", false
	}

	pending_root, join_err = filepath.join([]string{updates_dir, UPDATE_PENDING_NAME}, context.allocator)
	if join_err != nil {
		delete(updates_dir)
		return "", "", false
	}

	if os.make_directory_all(pending_root) != nil && !os.is_directory(pending_root) {
		delete(updates_dir)
		delete(pending_root)
		return "", "", false
	}
	return updates_dir, pending_root, true
}

update_sanitize_tag :: proc(tag: string) -> string {
	builder := strings.builder_make()
	for rune_value in tag {
		switch {
		case 'a' <= rune_value && rune_value <= 'z',
		     'A' <= rune_value && rune_value <= 'Z',
		     '0' <= rune_value && rune_value <= '9',
		     rune_value == '_',
		     rune_value == '-',
		     rune_value == '.':
			strings.write_rune(&builder, rune_value)
		case:
			strings.write_rune(&builder, '_')
		}
	}
	return strings.to_string(builder)
}

update_is_engine_name :: proc(name: string) -> bool {
	if !strings.has_prefix(name, "kinemium") {
		return false
	}
	when ODIN_OS == .Windows {
		return update_has_suffix_ci(name, ".exe")
	} else {
		return !strings.contains(name, ".")
	}
}

update_has_suffix_ci :: proc(s, suffix: string) -> bool {
	if len(suffix) > len(s) {
		return false
	}
	offset := len(s) - len(suffix)
	for index in 0 ..< len(suffix) {
		c := s[offset + index]
		expected := suffix[index]
		if 'A' <= c && c <= 'Z' {
			c += 'a' - 'A'
		}
		if 'A' <= expected && expected <= 'Z' {
			expected += 'a' - 'A'
		}
		if c != expected {
			return false
		}
	}
	return true
}

update_pending_has_engine :: proc(dir: string) -> bool {
	entries, err := os.read_directory_by_path(dir, 64, context.allocator)
	if err != nil {
		return false
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		if entry.type == os.File_Type.Directory || entry.name == UPDATE_PENDING_VERSION_NAME {
			continue
		}
		if update_is_engine_name(entry.name) {
			return true
		}
	}

	// POSIX artifacts carry no extension: any regular file counts as the payload.
	when ODIN_OS != .Windows {
		for entry in entries {
			if entry.type != os.File_Type.Directory && entry.name != UPDATE_PENDING_VERSION_NAME {
				return true
			}
		}
	}
	return false
}

update_locate_engine_executable :: proc(dir: string) -> (path: string, ok: bool) {
	entries, err := os.read_directory_by_path(dir, 64, context.allocator)
	if err != nil {
		return "", false
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		if entry.type == os.File_Type.Directory || entry.name == UPDATE_PENDING_VERSION_NAME {
			continue
		}
		if update_is_engine_name(entry.name) {
			return update_join_dir(dir, entry.name), true
		}
	}

	when ODIN_OS != .Windows {
		for entry in entries {
			if entry.type != os.File_Type.Directory && entry.name != UPDATE_PENDING_VERSION_NAME {
				return update_join_dir(dir, entry.name), true
			}
		}
	}
	return "", false
}

update_join_dir :: proc(base_dir, name: string) -> string {
	joined, join_err := filepath.join([]string{base_dir, name}, context.allocator)
	if join_err != nil {
		return ""
	}
	return joined
}

// Downloads the update bundle and stages it into the pending directory, writing
// pending.version as the ready marker. Never frees `report`; ownership stays
// with the caller.
update_service_stage_to_dir :: proc(service: ^UpdateService, report: UpdateReport) -> bool {
	if service == nil || len(report.asset_url) == 0 {
		return false
	}

	http_object := Service_Get_Service(&service.service, "HttpService")
	if http_object == nil {
		return false
	}
	http_service := cast(^HttpService)http_object

	data, ok := HttpService_GetAsync(http_service, report.asset_url)
	if !ok {
		return false
	}
	defer delete(data)

	temp_dir, temp_err := os.make_directory_temp("", "kinemium-update-*", context.allocator)
	if temp_err != nil {
		return false
	}
	defer {
		_ = os.remove_all(temp_dir)
		delete(temp_dir)
	}

	zip_path, join_err := filepath.join([]string{temp_dir, "bundle.zip"}, context.allocator)
	if join_err != nil {
		return false
	}
	defer delete(zip_path)

	if err := os.write_entire_file_from_string(zip_path, data); err != nil {
		return false
	}

	handle, opened := kineffi.Zip_Open(zip_path)
	if !opened {
		return false
	}
	defer _ = kineffi.Zip_Close(handle)

	updates_dir, pending_root, roots_ok := update_update_roots()
	if !roots_ok {
		return false
	}
	defer delete(updates_dir)
	defer delete(pending_root)

	tag_safe := update_sanitize_tag(report.latest_tag)
	defer delete(tag_safe)

	tag_dir: string
	tag_dir, join_err = filepath.join([]string{pending_root, tag_safe}, context.allocator)
	if join_err != nil {
		return false
	}
	defer delete(tag_dir)

	_ = os.remove_all(tag_dir)
	if os.make_directory_all(tag_dir) != nil {
		return false
	}
	cleanup_on_failure := true
	defer if cleanup_on_failure {
		_ = os.remove_all(tag_dir)
	}

	if !kineffi.Zip_Extract_All(handle, tag_dir, false) {
		return false
	}
	if !update_pending_has_engine(tag_dir) {
		fmt.eprintln("[UpdateService] staged bundle contains no engine executable:", tag_dir)
		return false
	}

	version_path: string
	version_path, join_err = filepath.join([]string{tag_dir, UPDATE_PENDING_VERSION_NAME}, context.allocator)
	if join_err != nil {
		return false
	}
	defer delete(version_path)

	if err := os.write_entire_file_from_string(version_path, report.latest_tag); err != nil {
		return false
	}

	cleanup_on_failure = false
	return true
}

// Scans the pending directory, cleaning up stale partial stages, and returns
// the first ready update. Callers own the returned strings.
Update_Pending_Read :: proc() -> (version, tag_dir: string, ok: bool) {
	updates_dir, pending_root, roots_ok := update_update_roots()
	if !roots_ok {
		return "", "", false
	}
	defer delete(updates_dir)
	defer delete(pending_root)

	entries, err := os.read_directory_by_path(pending_root, 64, context.allocator)
	if err != nil {
		return "", "", false
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		if entry.type != os.File_Type.Directory {
			continue
		}

		version_path, join_err := filepath.join([]string{pending_root, entry.name, UPDATE_PENDING_VERSION_NAME}, context.allocator)
		if join_err != nil {
			continue
		}

		data, read_err := os.read_entire_file(version_path, context.allocator)
		delete(version_path)
		if read_err != nil {
			// Partial or abandoned stage: drop it.
			_ = os.remove_all(entry.fullpath)
			continue
		}

		version = strings.clone(strings.trim_space(string(data)))
		delete(data)
		return version, strings.clone(entry.fullpath, context.allocator), true
	}
	return "", "", false
}

update_forwarded_args :: proc(args: []string) -> []string {
	result := make([dynamic]string, 0, len(args))
	for argument in args[1:] {
		if argument == "--update" || argument == "--no-update" {
			continue
		}
		append(&result, argument)
	}
	return result[:]
}

// Launches the staged engine executable as a one-shot installer:
//   <new exe> --apply-update <pending dir> <application exe> -- <original args>
// The installer process is the freshly downloaded binary, so the running
// application's files are free to be replaced once it exits.
Update_Service_Spawn_Helper :: proc(pending_dir: string) -> bool {
	pending_executable, found := update_locate_engine_executable(pending_dir)
	if !found {
		fmt.eprintln("[UpdateService] could not locate the staged engine executable")
		return false
	}
	defer delete(pending_executable)

	target_executable, path_error := os.get_executable_path(context.temp_allocator)
	if path_error != nil {
		fmt.eprintln("[UpdateService] could not resolve the current executable path")
		return false
	}

	forwarded := update_forwarded_args(os.args)
	defer delete(forwarded)

	command := make([dynamic]string, 0, 4 + len(forwarded))
	append(&command, pending_executable)
	append(&command, "--apply-update")
	append(&command, pending_dir)
	append(&command, target_executable)
	append(&command, "--")
	for argument in forwarded {
		append(&command, argument)
	}

	process, start_error := os.process_start(
		os.Process_Desc {
			command = command[:],
			stdin   = os.stdin,
			stdout  = os.stdout,
			stderr  = os.stderr,
		},
	)
	delete(command)
	if start_error != nil {
		fmt.eprintln("[UpdateService] failed to start the update installer:", start_error)
		return false
	}
	_ = process
	fmt.println("[UpdateService] update installer launched")
	return true
}

// Applies a pending update at a clean application exit: if a bundle is staged,
// it spawns the installer helper and lets the process terminate normally.
Update_Service_Shutdown :: proc() {
	if !update_service_enabled() {
		return
	}

	version, pending_dir, ready := Update_Pending_Read()
	defer if len(version) > 0 { delete(version) }
	defer if len(pending_dir) > 0 { delete(pending_dir) }
	if !ready {
		return
	}

	if !Update_Service_Spawn_Helper(pending_dir) {
		fmt.eprintln("[UpdateService] failed to launch the update installer for", version)
	}
}

// Replaces the files of `target_exe` (application executable path) with the
// staged bundle. Used both by the `--apply-update` installer process and by
// the tests. `pending.version` is never copied into the destination.
Update_Swap_Bundle :: proc(pending_dir, target_exe: string) -> bool {
	if len(pending_dir) == 0 || len(target_exe) == 0 {
		return false
	}

	exe_dir := filepath.dir(target_exe)
	target_base := filepath.base(target_exe)

	entries, err := os.read_directory_by_path(pending_dir, 256, context.allocator)
	if err != nil {
		return false
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	all_ok := true
	for entry in entries {
		if entry.type == os.File_Type.Directory || entry.name == UPDATE_PENDING_VERSION_NAME {
			continue
		}

		src, join_err := filepath.join([]string{pending_dir, entry.name}, context.allocator)
		if join_err != nil {
			all_ok = false
			continue
		}

		dest_name := entry.name
		if update_is_engine_name(entry.name) && entry.name != target_base {
			dest_name = target_base
		}

		dest: string
		dest, join_err = filepath.join([]string{exe_dir, dest_name}, context.allocator)
		if join_err != nil {
			delete(src)
			all_ok = false
			continue
		}

		if !update_replace_file(src, dest) {
			fmt.eprintln("[UpdateService] failed replacing", dest)
			all_ok = false
		}
		delete(src)
		delete(dest)
	}
	return all_ok
}

update_replace_file :: proc(src, dest: string) -> bool {
	when ODIN_OS == .Windows {
		// A mapped image (or an antivirus scan) can hold the destination open
		// for a short while, so move it aside with retries before installing
		// the replacement. The stale aside is cleaned up best-effort.
		aside_path := strings.concatenate({dest, UPDATE_STALE_SUFFIX})
		defer delete(aside_path)

		moved_aside := false
		for attempt in 0 ..< 60 {
			_ = os.remove(aside_path)
			if !os.exists(dest) {
				moved_aside = true
				break
			}
			if os.rename(dest, aside_path) == nil {
				moved_aside = true
				break
			}
			time.sleep(250 * time.Millisecond)
		}
		if !moved_aside {
			return false
		}
		if os.rename(src, dest) != nil {
			return false
		}
		_ = os.remove(aside_path)
		return true
	} else {
		return os.rename(src, dest) == nil
	}
}

// Primary entry point for the `--apply-update <pending dir> <app exe> [-- args]`
// flag: swaps the bundle into place, relaunches the application with the
// original arguments, and returns. The staging directory is left behind for the
// next boot to sweep away (a running installer cannot delete its own image).
Update_Apply_Pending :: proc(pending_dir, target_exe: string, forwarded_args: []string) -> bool {
	if !Update_Swap_Bundle(pending_dir, target_exe) {
		return false
	}

	command := make([dynamic]string, 0, 1 + len(forwarded_args))
	append(&command, target_exe)
	for argument in forwarded_args {
		append(&command, argument)
	}

	process, start_error := os.process_start(
		os.Process_Desc {
			command = command[:],
			stdin   = os.stdin,
			stdout  = os.stdout,
			stderr  = os.stderr,
		},
	)
	delete(command)
	if start_error != nil {
		fmt.eprintln("[UpdateService] failed to relaunch after update:", start_error)
		return false
	}
	_ = process
	return true
}

// Forces a check plus stage plus install and exits. Used by `--update`.
Update_Service_Run_Now :: proc(service: ^UpdateService) {
	if service == nil || !update_service_enabled() {
		fmt.eprintln("[UpdateService] updates are disabled for this build")
		return
	}

	report, ok := update_fetch_report()
	defer update_report_destroy(&report)
	if !ok {
		fmt.eprintln("[UpdateService] update check failed:", report.error)
		return
	}
	if !report.available {
		fmt.println("[UpdateService] already up to date at", report.current_display)
		return
	}

	if !update_service_stage_to_dir(service, report) {
		fmt.eprintln("[UpdateService] failed to stage update", report.latest_version)
		return
	}

	version, pending_dir, ready := Update_Pending_Read()
	defer delete(version)
	defer delete(pending_dir)
	if !ready {
		return
	}

	fmt.println("[UpdateService] installing", version, "...")
	if Update_Service_Spawn_Helper(pending_dir) {
		os.exit(0)
	}
	fmt.eprintln("[UpdateService] failed to launch the update installer")
}

// Spawns a background thread that opportunistically checks and stages the
// latest release at startup. When `apply_now` is set (--update), the check and
// install path runs synchronously instead.
Update_Service_Startup_Check :: proc(service: ^UpdateService, apply_now: bool) {
	if service == nil || !update_service_enabled() {
		return
	}
	if apply_now {
		Update_Service_Run_Now(service)
		return
	}
	if service.background_started {
		return
	}
	service.background_started = true

	background_thread := thread.create(update_service_background_main)
	background_thread.data = service
	thread.start(background_thread)
}

update_service_background_main :: proc(t: ^thread.Thread) {
	service := cast(^UpdateService)t.data
	if service == nil {
		return
	}
	report, ok := update_fetch_report()
	defer update_report_destroy(&report)
	if !ok || !report.available {
		return
	}
	update_service_stage_to_dir(service, report)
}

// First thing called from main: if the process was started as the one-shot
// installer (--apply-update <pending dir> <app exe> [-- args]), it swaps the
// bundle in, relaunches the application, and exits the process. Returns true
// only when an update command was handled (i.e. the process terminated).
Update_Handle_Command_Line :: proc() -> bool {
	apply_index := -1
	for argument, index in os.args {
		if argument == "--apply-update" {
			apply_index = index
		}
	}
	if apply_index < 0 {
		return false
	}
	if apply_index + 3 > len(os.args) {
		fmt.eprintln("--apply-update requires: --apply-update <pending dir> <application executable> [-- args]")
		os.exit(1)
	}

	pending_dir := os.args[apply_index + 1]
	application_exe := os.args[apply_index + 2]
	forwarded: []string
	if apply_index + 3 < len(os.args) && os.args[apply_index + 3] == "--" {
		forwarded = os.args[apply_index + 4:]
	}

	if !Update_Apply_Pending(pending_dir, application_exe, forwarded) {
		fmt.eprintln("Kinemium update application failed")
		os.exit(1)
	}
	os.exit(0)
}

// Startup hook: resolves the UpdateService on the registry and runs either the
// synchronous `--update` install path or the background opportunistic check.
// `enabled` is false for playtests; `apply_now`/`no_update` mirror the
// `--update`/`--no-update` flags.
Update_Service_Boot :: proc(registry: ^Registry, enabled, apply_now, no_update: bool) {
	if registry == nil || !enabled || !update_service_enabled() || no_update {
		return
	}
	object := Ensure_Service(registry, "UpdateService")
	if object == nil {
		return
	}
	Update_Service_Startup_Check(cast(^UpdateService)object, apply_now)
}

// Fetches a fresh manifest and compares it against the running build. All
// strings are allocated on `context.allocator`; callers own the report.
update_fetch_report :: proc() -> (UpdateReport, bool) {
	report := UpdateReport{}

	report.current_major = globals.RUNTIME_SEMANTIC_MAJOR
	report.current_minor = globals.RUNTIME_SEMANTIC_MINOR
	report.current_patch = globals.RUNTIME_SEMANTIC_PATCH
	report.current_display = strings.clone(globals.RUNTIME_VERSION_DISPLAY)
	report.current_prerelease = strings.clone(globals.RUNTIME_SEMANTIC_PRERELEASE)
	report.current_git = strings.clone(globals.RUNTIME_GIT_COMMIT)

	version, pending_dir, staged := Update_Pending_Read()
	if staged {
		report.staged_ready = true
		report.staged_version = version
	} else {
		if len(version) > 0 {
			delete(version)
		}
	}
	if len(pending_dir) > 0 {
		delete(pending_dir)
	}

	if len(globals.RUNTIME_UPDATE_URL) == 0 {
		report.status = .Check_Failed
		report.error = strings.clone("update source URL is not configured")
		return report, false
	}

	body, status, http_ok := update_http_get(globals.RUNTIME_UPDATE_URL)
	defer if body != "" { delete(body) }
	if !http_ok {
		report.status = .Check_Failed
		report.error = strings.clone("could not reach the update server")
		return report, false
	}
	if status != 200 {
		report.status = .Check_Failed
		report.error = fmt.aprintf("update server returned HTTP %d", status)
		return report, false
	}

	release, decoded := update_decode_release(body)
	if !decoded {
		report.status = .Check_Failed
		report.error = strings.clone("could not parse the update manifest")
		return report, false
	}
	defer update_release_destroy(&release)

	report.latest_tag = strings.clone(release.tag_name)
	report.latest_version = update_strip_v(release.tag_name)
	report.latest_url = strings.clone(release.html_url)
	report.latest_published = strings.clone(release.published_at)
	report.latest_notes = strings.clone(release.body)

	if name, url, size, found := update_pick_asset(release); found {
		report.asset_name = name
		report.asset_url = url
		report.asset_size = size
	} else {
		report.status = .Check_Failed
		report.error = fmt.aprintf(
			"no release asset for this platform (expected %s)",
			Update_Asset_Name(update_os_tag(), update_arch_tag()),
		)
		report.available = false
		return report, false
	}

	if Update_Version_Compare(report.latest_version, globals.RUNTIME_VERSION_DISPLAY) > 0 {
		report.status = .Update_Available
		report.available = true
	} else {
		report.status = .Up_To_Date
	}
	return report, true
}

// Keeps a TTL-bounded snapshot of the last successful manifest check so the UI
// can re-query without hammering the GitHub API.
update_service_cache_sync :: proc(service: ^UpdateService, force_recheck := false) -> bool {
	if service == nil {
		return false
	}
	if !force_recheck && service.cached_valid && time.to_unix_seconds(time.now()) - service.cached_time < UPDATE_CHECK_TTL_SECONDS {
		return true
	}

	fresh, ok := update_fetch_report()
	if !ok {
		// Transient failure: keep serving a previous healthy snapshot.
		if service.cached_valid {
			return true
		}
		update_report_destroy(&service.cached)
		service.cached = fresh
		service.cached_valid = false
		service.cached_time = time.to_unix_seconds(time.now())
		return false
	}

	update_report_destroy(&service.cached)
	service.cached = fresh
	service.cached_valid = true
	service.cached_time = time.to_unix_seconds(time.now())
	return true
}

update_service_apply_now :: proc(service: ^UpdateService) -> bool {
	if service == nil || !update_service_enabled() {
		return false
	}
	if !update_service_cache_sync(service, force_recheck = true) || !service.cached_valid {
		return false
	}
	if !service.cached.available {
		return false
	}
	if !update_service_stage_to_dir(service, service.cached) {
		return false
	}

	delete(service.cached.staged_version)
	service.cached.staged_ready = true
	service.cached.staged_version = strings.clone(service.cached.latest_version)
	return true
}

update_push_current_table :: proc(L: ^vm.State, report: UpdateReport) {
	vm.NewTable(L, 0, 6)

	vm.PushString(L, report.current_display)
	vm.SetField(L, -2, "display")

	vm.PushInteger(L, i64(report.current_major))
	vm.SetField(L, -2, "major")
	vm.PushInteger(L, i64(report.current_minor))
	vm.SetField(L, -2, "minor")
	vm.PushInteger(L, i64(report.current_patch))
	vm.SetField(L, -2, "patch")

	if len(report.current_prerelease) > 0 {
		vm.PushString(L, report.current_prerelease)
		vm.SetField(L, -2, "prerelease")
	}
	if len(report.current_git) > 0 {
		vm.PushString(L, report.current_git)
		vm.SetField(L, -2, "git")
	}

	vm.SetReadOnly(L, -1)
}

update_push_latest_table :: proc(L: ^vm.State, report: UpdateReport) {
	if len(report.latest_tag) == 0 {
		vm.PushNil(L)
		return
	}

	vm.NewTable(L, 0, 8)

	vm.PushString(L, report.latest_version)
	vm.SetField(L, -2, "version")
	vm.PushString(L, report.latest_tag)
	vm.SetField(L, -2, "tag")
	vm.PushString(L, report.latest_url)
	vm.SetField(L, -2, "release_url")
	vm.PushString(L, report.latest_published)
	vm.SetField(L, -2, "published")
	vm.PushString(L, report.latest_notes)
	vm.SetField(L, -2, "notes")
	vm.PushString(L, report.asset_name)
	vm.SetField(L, -2, "asset_name")
	vm.PushString(L, report.asset_url)
	vm.SetField(L, -2, "asset_url")
	vm.PushInteger(L, report.asset_size)
	vm.SetField(L, -2, "asset_size")

	vm.SetReadOnly(L, -1)
}

update_push_staged_table :: proc(L: ^vm.State, report: UpdateReport) {
	vm.NewTable(L, 0, 2)

	vm.PushBoolean(L, report.staged_ready)
	vm.SetField(L, -2, "ready")
	if len(report.staged_version) > 0 {
		vm.PushString(L, report.staged_version)
		vm.SetField(L, -2, "version")
	}

	vm.SetReadOnly(L, -1)
}

update_service_push_available :: proc(L: ^vm.State, service: ^UpdateService) {
	if service == nil || !update_service_enabled() {
		vm.PushNil(L)
		return
	}

	cached := update_service_cache_sync(service)
	report := service.cached

	if !cached || !service.cached_valid {
		vm.NewTable(L, 0, 3)
		vm.PushBoolean(L, false)
		vm.SetField(L, -2, "available")
		vm.PushString(L, "check_failed")
		vm.SetField(L, -2, "status")
		vm.PushString(L, report.error)
		vm.SetField(L, -2, "error")
		return
	}

	vm.NewTable(L, 0, 6)

	vm.PushBoolean(L, report.available)
	vm.SetField(L, -2, "available")

	vm.PushString(L, update_status_string(report.status))
	vm.SetField(L, -2, "status")

	update_push_current_table(L, report)
	vm.SetField(L, -2, "current")

	update_push_latest_table(L, report)
	vm.SetField(L, -2, "latest")

	update_push_staged_table(L, report)
	vm.SetField(L, -2, "staged")

	if len(report.error) > 0 {
		vm.PushString(L, report.error)
		vm.SetField(L, -2, "error")
	}

	vm.SetReadOnly(L, -1)
}
