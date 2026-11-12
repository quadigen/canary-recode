#+build !js
// wire:service

package services


import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import fsutil "../fsutil"
import globals "../global"
import serializer "../serializer"
import target "../target"
import vm "../vm"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

TemplateService_Class := classes.Class_Info {
	name   = "TemplateService",
	parent = &Service_Class,
}

TemplateService :: struct {
	using service: Service,
}

Template_Kind :: enum {
	Server,
	Client,
}

Template_Checkpoint :: struct {
	tag:          string,
	server_asset: GitHub_Asset,
	client_asset: GitHub_Asset,
}

Template_Checkpoint_Destroy :: proc(checkpoint: ^Template_Checkpoint) {
	delete(checkpoint.tag)
	delete(checkpoint.server_asset.name)
	delete(checkpoint.server_asset.browser_download_url)
	delete(checkpoint.client_asset.name)
	delete(checkpoint.client_asset.browser_download_url)
	checkpoint^ = {}
}

Binary_Format :: enum {
	PE,
	ELF,
	Mach_O,
}

Target_Platform :: struct {
	os_name:   string,
	arch_name: string,
	ext:       string,
	format:    Binary_Format,
}


Template_Normalize_Arch :: proc(arch_name: string) -> string {
	switch arch_name {
	case "amd64", "x86-64", "x64":
		return "x86_64"
	case "aarch64":
		return "arm64"
	}
	return arch_name
}


Template_Platform_From :: proc(os_name, arch_name: string) -> (Target_Platform, bool) {
	arch := Template_Normalize_Arch(arch_name)
	switch os_name {
	case "windows":
		return {os_name, arch, ".exe", .PE}, true
	case "linux":
		return {os_name, arch, "", .ELF}, true
	case "macos", "darwin":
		return {os_name, arch, "", .Mach_O}, true
	}
	return {}, false
}

Template_Host_Platform :: proc() -> Target_Platform {
	p, _ := Template_Platform_From(update_os_tag(), update_arch_tag())
	return p
}

Template_Asset_Name :: proc(kind: Template_Kind, p: Target_Platform) -> string {
	prefix := "server" if kind == .Server else "client"
	return strings.concatenate(
		{"kinemium-", prefix, "-", p.os_name, "-", p.arch_name, p.ext},
		context.allocator,
	)
}

Template_Validate :: proc(path: string, format: Binary_Format) -> bool {
	handle, open_error := os.open(path)
	if open_error != os.ERROR_NONE {
		return false
	}
	defer os.close(handle)
	size, size_error := os.file_size(handle)
	if size_error != os.ERROR_NONE || size < 1_000_000 {
		return false
	}
	first := [4]u8{}
	read, read_error := os.read_at(handle, first[:], 0)
	if read_error != os.ERROR_NONE || int(read) != 4 {
		return false
	}
	switch format {
	case .PE:
		return first[0] == 'M' && first[1] == 'Z'
	case .ELF:
		return first[0] == 0x7f && first[1] == 'E' && first[2] == 'L' && first[3] == 'F'
	case .Mach_O:
		return(
			(first[0] == 0xcf && first[1] == 0xfa && first[2] == 0xed && first[3] == 0xfe) ||
			(first[0] == 0xca && first[1] == 0xfe && first[2] == 0xba && first[3] == 0xbe) \
		)
	}
	return false
}

TemplateService_Cache_From_Kinemium :: proc(
	base_dir: string,
) -> (
	dir: string,
	version_file: string,
	ok: bool,
) {
	cand, join_err := filepath.join([]string{base_dir, "Kinemium", "Templates"}, context.allocator)
	if join_err != nil {
		return "", "", false
	}
	if fsutil.Make_Directory_All(cand) != nil && !os.is_directory(cand) {
		delete(cand)
		return "", "", false
	}
	vfile, vf_err := filepath.join([]string{cand, "templates.version"}, context.allocator)
	if vf_err != nil {
		delete(cand)
		return "", "", false
	}
	return cand, vfile, true
}

TemplateService_Cache_Paths :: proc() -> (dir: string, version_file: string) {
	user_dir, user_err := os.user_data_dir(context.allocator)
	if user_err == nil && len(user_dir) > 0 {
		if found_dir, found_version, ok := TemplateService_Cache_From_Kinemium(user_dir); ok {
			delete(user_dir)
			return found_dir, found_version
		}
		delete(user_dir)
	}
	cache_dir, cache_err := os.user_cache_dir(context.allocator)
	if cache_err == nil && len(cache_dir) > 0 {
		if found_dir, found_version, ok := TemplateService_Cache_From_Kinemium(cache_dir); ok {
			delete(cache_dir)
			return found_dir, found_version
		}
		delete(cache_dir)
	}
	return "", ""
}

template_version_read :: proc(version_file: string) -> (tag: string, ok: bool) {
	data, read_err := os.read_entire_file_from_path(version_file, context.allocator)
	if read_err != nil {
		return "", false
	}
	tag = strings.clone(strings.trim_space(string(data)))
	delete(data)
	return tag, true
}

template_version_write :: proc(version_file, tag: string) {
	_ = os.write_entire_file_from_string(version_file, tag)
}

Template_Fetch_Latest :: proc(p: Target_Platform) -> (checkpoint: Template_Checkpoint, ok: bool) {
	body, status, http_ok := update_http_get(globals.RUNTIME_UPDATE_URL)
	if !http_ok || status != 200 {
		return {}, false
	}
	release, release_ok := update_decode_release(body)
	delete(body)
	if !release_ok {
		return {}, false
	}
	defer update_release_destroy(&release)
	server_name := Template_Asset_Name(.Server, p)
	client_name := Template_Asset_Name(.Client, p)
	defer delete(server_name)
	defer delete(client_name)
	server_archive := fmt.tprintf("%s%s", server_name, UPDATE_ARCHIVE_EXT)
	client_archive := fmt.tprintf("%s%s", client_name, UPDATE_ARCHIVE_EXT)
	checkpoint.tag = strings.clone(release.tag_name)
	for asset in release.assets {
		if asset.name == server_archive ||
		   (asset.name == server_name && checkpoint.server_asset.name != server_archive) {
			checkpoint.server_asset = GitHub_Asset {
				name                 = strings.clone(asset.name),
				browser_download_url = strings.clone(asset.browser_download_url),
				size                 = asset.size,
			}
		}
		if asset.name == client_archive ||
		   (asset.name == client_name && checkpoint.client_asset.name != client_archive) {
			checkpoint.client_asset = GitHub_Asset {
				name                 = strings.clone(asset.name),
				browser_download_url = strings.clone(asset.browser_download_url),
				size                 = asset.size,
			}
		}
	}
	ok = checkpoint.server_asset.name != "" && checkpoint.client_asset.name != ""
	if !ok {
		Template_Checkpoint_Destroy(&checkpoint)
	}
	return checkpoint, ok
}

template_kind_asset :: proc(
	checkpoint: ^Template_Checkpoint,
	kind: Template_Kind,
) -> (
	GitHub_Asset,
	bool,
) {
	switch kind {
	case .Server:
		return checkpoint.server_asset, checkpoint.server_asset.name != ""
	case .Client:
		return checkpoint.client_asset, checkpoint.client_asset.name != ""
	}
	return {}, false
}

template_build_fallback :: proc(
	kind: Template_Kind,
	p: Target_Platform,
) -> (
	path: string,
	ok: bool,
) {
	base := "kinemium-server" if kind == .Server else "kinemium-client"
	file_name := strings.concatenate({base, p.ext})
	built_path, join_err := filepath.join([]string{"build", file_name}, context.allocator)
	delete(file_name)
	if join_err != nil {
		return "", false
	}
	if Template_Validate(built_path, p.format) {
		return built_path, true
	}
	delete(built_path)
	return "", false
}

Template_Copy_Runtime_Siblings :: proc(
	from_dir, to_dir, exclude_name: string,
	libraries_only := false,
) {
	entries, err := os.read_directory_by_path(from_dir, 64, context.allocator)
	if err != nil {
		return
	}
	defer os.file_info_slice_delete(entries, context.allocator)
	for entry in entries {
		if entry.name == exclude_name || entry.type == os.File_Type.Directory {
			continue
		}


		if strings.has_prefix(entry.name, "kinemium-server-") ||
		   strings.has_prefix(entry.name, "kinemium-client-") {
			continue
		}
		if libraries_only &&
		   !strings.has_suffix(entry.name, ".dll") &&
		   !strings.has_suffix(entry.name, ".dylib") &&
		   !strings.has_suffix(entry.name, ".so") &&
		   !strings.contains(entry.name, ".so.") {
			continue
		}
		src, src_err := filepath.join([]string{from_dir, entry.name}, context.temp_allocator)
		if src_err != nil {
			continue
		}
		dst, dst_err := filepath.join([]string{to_dir, entry.name}, context.temp_allocator)
		if dst_err != nil {
			continue
		}
		os.copy_file(dst, src)
	}
}

template_bundle_dir :: proc(cached_path, tag: string) -> string {
	safe_tag := update_sanitize_tag(tag)
	defer delete(safe_tag)
	return fmt.tprintf("%s.bundle-%s", cached_path, safe_tag)
}

template_bundle_path :: proc(bundle_dir, name: string) -> string {
	path, _ := filepath.join([]string{bundle_dir, name}, context.temp_allocator)
	return path
}

template_install_bundle :: proc(
	asset: GitHub_Asset,
	bundle_dir, asset_file_name: string,
	format: Binary_Format,
) -> bool {
	data, ok := update_download_asset(asset.browser_download_url)
	if !ok {
		return false
	}
	defer delete(data)
	if asset.size > 0 && i64(len(data)) != asset.size {
		return false
	}

	stage, err := os.make_directory_temp(
		filepath.dir(bundle_dir),
		".template-*",
		context.allocator,
	)
	if err != nil {
		return false
	}
	defer {
		_ = os.remove_all(stage)
		delete(stage)
	}
	staged_bundle := template_bundle_path(stage, "runtime")
	if fsutil.Make_Directory_All(staged_bundle) != nil {
		return false
	}
	staged_exe := template_bundle_path(staged_bundle, asset_file_name)
	if strings.has_suffix(asset.name, UPDATE_ARCHIVE_EXT) {
		zip_path := template_bundle_path(stage, "template.zip")
		if os.write_entire_file(zip_path, data) != nil {
			return false
		}
		zip, opened := kineffi.Zip_Open(zip_path)
		if !opened {
			return false
		}
		extracted := kineffi.Zip_Extract_All(zip, staged_bundle)
		_ = kineffi.Zip_Close(zip)
		if !extracted {
			return false
		}
	} else if os.write_entire_file(staged_exe, data) != nil {
		return false
	}
	if !Template_Validate(staged_exe, format) {
		return false
	}
	// Another export may have installed this release while we were downloading.
	return(
		os.rename(staged_bundle, bundle_dir) == nil ||
		Template_Validate(template_bundle_path(bundle_dir, asset_file_name), format) \
	)
}

Template_Resolve :: proc(
	kind: Template_Kind,
	p: Target_Platform,
) -> (
	path: string,
	problem: string,
) {
	asset_file_name := Template_Asset_Name(kind, p)
	defer delete(asset_file_name)

	cache_dir, cache_version := TemplateService_Cache_Paths()
	defer delete(cache_version)
	if cache_dir == "" {
		return "", "Could not locate a template cache directory"
	}
	cached_path, cached_err := filepath.join(
		[]string{cache_dir, asset_file_name},
		context.allocator,
	)
	delete(cache_dir)
	if cached_err != nil {
		return "", "Could not build the template cache path"
	}

	version_file := strings.concatenate({cached_path, ".version"}, context.allocator)
	defer delete(version_file)

	cached_tag, _ := template_version_read(version_file)
	defer delete(cached_tag)

	latest, latest_ok := Template_Fetch_Latest(p)
	if latest_ok {
		defer Template_Checkpoint_Destroy(&latest)
		bundle_dir := template_bundle_dir(cached_path, latest.tag)
		bundle_exe := template_bundle_path(bundle_dir, asset_file_name)
		if Template_Validate(bundle_exe, p.format) {
			if cached_tag != latest.tag {
				template_version_write(version_file, latest.tag)
			}
			delete(cached_path)
			return strings.clone(bundle_exe), ""
		}
		asset, asset_ok := template_kind_asset(&latest, kind)
		if cached_tag == latest.tag &&
		   asset.name == asset_file_name &&
		   Template_Validate(cached_path, p.format) {
			return cached_path, ""
		}
		if asset_ok && template_install_bundle(asset, bundle_dir, asset_file_name, p.format) {
			template_version_write(version_file, latest.tag)
			delete(cached_path)
			return strings.clone(bundle_exe), ""
		}
	}

	if cached_tag != "" {
		bundle_dir := template_bundle_dir(cached_path, cached_tag)
		bundle_exe := template_bundle_path(bundle_dir, asset_file_name)
		if Template_Validate(bundle_exe, p.format) {
			delete(cached_path)
			return strings.clone(bundle_exe), ""
		}
	}
	if Template_Validate(cached_path, p.format) {
		return cached_path, ""
	}

	host := Template_Host_Platform()
	if p.os_name == host.os_name && p.arch_name == host.arch_name {
		if local, local_ok := template_build_fallback(kind, p); local_ok {
			return local, ""
		}
	}
	delete(cached_path)
	return "", fmt.tprintf(
		"Could not obtain %v template: no network and none cached or built",
		kind,
	)
}

Export_Console :: enum {
	Template,
	Show,
	Hide,
}

// Both PE32 and PE32+ put Subsystem at offset 68 of the optional header.
export_set_windows_console :: proc(image: []u8, console: Export_Console) -> bool {
	if len(image) < 64 || string(image[:2]) != "MZ" {
		return false
	}
	pe := i64(payload_read_le_u32(image, 0x3c))
	optional := pe + 24
	if optional + 70 > i64(len(image)) ||
	   string(image[pe:pe + 4]) != "PE\x00\x00" ||
	   payload_read_le_u16(image, int(pe) + 20) < 70 {
		return false
	}
	magic := payload_read_le_u16(image, int(optional))
	if magic != 0x10b && magic != 0x20b {
		return false
	}
	subsystem: u16 = 3 if console == .Show else 2
	payload_write_le_u16(image, int(optional) + 68, subsystem)
	payload_write_le_u32(image, int(optional) + 64, 0)
	return true
}

template_supports_export :: proc(template: []u8, mode: target.Mode, path_assets: bool) -> bool {
	image := transmute(string)template
	return (mode != .Singleplayer || strings.contains(image, SINGLEPLAYER_EXPORT_MARKER)) &&
	       (!path_assets || strings.contains(image, PROJECT_ASSET_EXPORT_MARKER))
}

ExportToExecutable :: proc(
	kind: Template_Kind,
	p: Target_Platform,
	destination: string,
	mode: target.Mode,
	address: string,
	port: u16,
	game_name: string,
	map_bytes: []u8,
	console: Export_Console = .Template,
	icon_path: string = "",
) -> (
	ok: bool,
	message: string,
) {
	if mode == target.Mode.Editor {
		return false, "Cannot bake an editor template"
	}
	template_path, problem := Template_Resolve(kind, p)
	template: []u8
	defer {
		delete(template_path)
		delete(template)
	}
	if template_path != "" {
		template, _ = os.read_entire_file_from_path(template_path, context.allocator)
	}

	libraries_only := false
	path_assets := serializer.Has_Path_Assets(map_bytes)
	if !template_supports_export(template, mode, path_assets) {
		host := Template_Host_Platform()
		if p.os_name != host.os_name || p.arch_name != host.arch_name {
			return false, "This export requires an updated runtime template for the target platform"
		}
		libraries_only = true
		delete(template)
		delete(template_path)
		template_path, _ = template_build_fallback(kind, p)
		template, _ = os.read_entire_file_from_path(template_path, context.allocator)
		if !template_supports_export(template, mode, path_assets) {
			delete(template)
			delete(template_path)
			template_path, _ = os.get_executable_path(context.allocator)
			template, _ = os.read_entire_file_from_path(template_path, context.allocator)
			if !template_supports_export(template, mode, path_assets) {
				return false, "Could not find a runtime template that supports this export"
			}
		}
	}
	if len(template) == 0 {
		if template_path == "" {
			return false, problem
		}
		return false, fmt.tprintf("Could not read template %s", template_path)
	}
	if icon_path != "" {
		if p.format != .PE {
			return false, "Executable icons require a Windows target"
		}
		when ODIN_OS == .Windows {
			stage, err := os.make_directory_temp(
				filepath.dir(destination),
				".export-icon-*",
				context.allocator,
			)
			if err != nil {
				return false, "Could not stage the executable icon"
			}
			defer {
				_ = os.remove_all(stage)
				delete(stage)
			}
			staged := template_bundle_path(stage, "game.exe")
			if os.write_entire_file(staged, template) != nil {
				return false, "Could not stage the executable for the icon"
			}
			if icon_error := export_embed_windows_icon(staged, icon_path); icon_error != "" {
				return false, icon_error
			}
			delete(template)
			template, err = os.read_entire_file_from_path(staged, context.allocator)
			if err != nil {
				return false, "Could not read the executable after applying the icon"
			}
		} else {
			return false, "Applying an executable icon requires running the Windows editor"
		}
	}
	if p.format == .PE && console != .Template && !export_set_windows_console(template, console) {
		return false, "Could not set the Windows executable's console subsystem"
	}
	full, append_ok := Payload_Append(
		template,
		Payload {
			mode = mode,
			address = address,
			port = port,
			name = game_name,
			map_bytes = map_bytes,
		},
	)
	if !append_ok {
		return false, "Failed to build export payload"
	}
	defer delete(full)
	if os.write_entire_file(destination, full) != nil {
		return false, fmt.tprintf("Could not write %s", destination)
	}
	when ODIN_OS == .Linux || ODIN_OS == .Darwin {
		if p.format != .PE && os.chmod(destination, transmute(os.Permissions)u32(0o755)) != nil {
			return false, fmt.tprintf("Could not make %s executable", destination)
		}
	}
	template_dir := filepath.dir(template_path)
	destination_dir := filepath.dir(destination)
	if template_dir != destination_dir {
		Template_Copy_Runtime_Siblings(
			template_dir,
			destination_dir,
			filepath.base(template_path),
			libraries_only,
		)
	}
	return true, ""
}

template_service_export_luau :: proc(L: ^vm.State, tempKind: Template_Kind, mode: target.Mode) {
	path := vm.ArgString(L, 2)
	address := vm.ArgString(L, 3)
	port := u16(vm.ArgNumber(L, 4))
	game_name := vm.ArgString(L, 5)
	map_path := vm.ArgString(L, 6)
	data, err := os.read_entire_file(map_path, context.allocator)
	_ = err
	platform := Template_Host_Platform()
	if !vm.IsNoneOrNil(L, 7) {
		os_name := vm.ArgString(L, 7)
		arch_name := vm.ArgString(L, 8)
		p, ok := Template_Platform_From(os_name, arch_name)
		if !ok {
			vm.RaiseError(L, fmt.tprintf("TemplateService: unknown platform %s", os_name))
			return
		}
		platform = p
	}

	ExportToExecutable(tempKind, platform, path, mode, address, port, game_name, data)
}

template_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^ExampleService)object
	switch key {
	case "ExportServerExe", "ExportClientExe", "ExportSinglePlayerExe":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

template_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^TemplateService)object
	switch method {
	case "ExportServerExe":
		template_service_export_luau(L, Template_Kind.Server, target.Mode.Server)

		return 1, true
	case "ExportClientExe":
		template_service_export_luau(L, Template_Kind.Client, target.Mode.Client)

		return 1, true
	case "ExportSinglePlayerExe":
		template_service_export_luau(L, Template_Kind.Client, target.Mode.Singleplayer)

		return 1, true
	}
	return 0, false
}

template_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(TemplateService)
	service.service = Service_Init(&TemplateService_Class, "TemplateService", data_model)
	return &service.object
}

template_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^TemplateService)object)
}

Register_TemplateService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&TemplateService_Class,
		template_service_construct,
		template_service_destroy,
		namecall = template_service_namecall,
		get = template_service_get,
		creatable = false,
	)
}
