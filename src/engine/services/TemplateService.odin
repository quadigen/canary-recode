#+build !js

package services

// wire:service global="TemplateService"

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import classes "../classes"
import globals "../global"
import target "../target"

TemplateService_Class := classes.Class_Info {
	name   = "TemplateService",
	parent = &Service_Class,
}

TemplateService :: struct {
	using service: Service,
}

Template_Kind :: enum { Server, Client }

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

template_binary_ext :: proc() -> string {
	when ODIN_OS == .Windows {
		return ".exe"
	}
	return ""
}

Template_Asset_Name :: proc(kind: Template_Kind, os_name, arch_name: string) -> string {
	prefix := "server" if kind == .Server else "client"
	return strings.concatenate({"kinemium-", prefix, "-", os_name, "-", arch_name, template_binary_ext()}, context.allocator)
}

Template_Validate :: proc(path: string) -> bool {
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
	when ODIN_OS == .Windows {
		return first[0] == 'M' && first[1] == 'Z'
	} else when ODIN_OS == .Linux {
		return first[0] == 0x7f && first[1] == 'E' && first[2] == 'L' && first[3] == 'F'
	} else when ODIN_OS == .Darwin {
		return (first[0] == 0xcf && first[1] == 0xfa && first[2] == 0xed && first[3] == 0xfe) ||
		       (first[0] == 0xfe && first[1] == 0xed && first[2] == 0xfa && first[3] == 0xcf)
	}
	return false
}

TemplateService_Cache_From_Kinemium :: proc(base_dir: string) -> (dir: string, version_file: string, ok: bool) {
	cand, join_err := filepath.join([]string{base_dir, "Kinemium", "Templates"}, context.allocator)
	if join_err != nil {
		return "", "", false
	}
	if os.make_directory_all(cand) != nil && !os.is_directory(cand) {
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

Template_Fetch_Latest :: proc() -> (checkpoint: Template_Checkpoint, ok: bool) {
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
	os_name := update_os_tag()
	arch_name := update_arch_tag()
	server_name := Template_Asset_Name(.Server, os_name, arch_name)
	client_name := Template_Asset_Name(.Client, os_name, arch_name)
	defer delete(server_name)
	defer delete(client_name)
	checkpoint.tag = strings.clone(release.tag_name)
	for asset in release.assets {
		if asset.name == server_name {
			checkpoint.server_asset = GitHub_Asset{
				name = strings.clone(asset.name),
				browser_download_url = strings.clone(asset.browser_download_url),
				size = asset.size,
			}
		}
		if asset.name == client_name {
			checkpoint.client_asset = GitHub_Asset{
				name = strings.clone(asset.name),
				browser_download_url = strings.clone(asset.browser_download_url),
				size = asset.size,
			}
		}
	}
	ok = checkpoint.server_asset.name != "" && checkpoint.client_asset.name != ""
	if !ok {
		Template_Checkpoint_Destroy(&checkpoint)
	}
	return checkpoint, ok
}

template_kind_asset :: proc(checkpoint: ^Template_Checkpoint, kind: Template_Kind) -> (GitHub_Asset, bool) {
	switch kind {
	case .Server:
		return checkpoint.server_asset, checkpoint.server_asset.name != ""
	case .Client:
		return checkpoint.client_asset, checkpoint.client_asset.name != ""
	}
	return {}, false
}

template_build_fallback :: proc(kind: Template_Kind) -> (path: string, ok: bool) {
	base := "kinemium-server" if kind == .Server else "kinemium-client"
	file_name := strings.concatenate({base, template_binary_ext()})
	built_path, join_err := filepath.join([]string{"build", file_name}, context.allocator)
	delete(file_name)
	if join_err != nil {
		return "", false
	}
	if Template_Validate(built_path) {
		return built_path, true
	}
	delete(built_path)
	return "", false
}

Template_Copy_Runtime_Siblings :: proc(from_dir, to_dir, exclude_name: string) {
	entries, err := os.read_directory_by_path(from_dir, 64, context.allocator)
	if err != nil {
		return
	}
	defer os.file_info_slice_delete(entries, context.allocator)
	for entry in entries {
		if entry.name == exclude_name || entry.type == os.File_Type.Directory {
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

Template_Resolve :: proc(kind: Template_Kind) -> (path: string, problem: string) {
	os_name := update_os_tag()
	arch_name := update_arch_tag()
	asset_file_name := Template_Asset_Name(kind, os_name, arch_name)
	defer delete(asset_file_name)

	cache_dir, version_file := TemplateService_Cache_Paths()
	if cache_dir == "" {
		return "", "Could not locate a template cache directory"
	}
	cached_path, cached_err := filepath.join([]string{cache_dir, asset_file_name}, context.allocator)
	delete(cache_dir)
	defer delete(version_file)
	if cached_err != nil {
		return "", "Could not build the template cache path"
	}

	latest, latest_ok := Template_Fetch_Latest()
	if latest_ok {
		defer Template_Checkpoint_Destroy(&latest)
		cached_valid := Template_Validate(cached_path)
		cached_tag, cached_had := template_version_read(version_file)
		if cached_had && len(cached_tag) > 0 {
			tag_matches := cached_tag == latest.tag
			delete(cached_tag)
			if cached_valid && tag_matches {
				return cached_path, ""
			}
		}
		asset, asset_ok := template_kind_asset(&latest, kind)
		if asset_ok {
			body, download_ok := update_download_asset(asset.browser_download_url)
			if download_ok {
				_ = os.write_entire_file(cached_path, transmute([]u8)body)
				template_version_write(version_file, latest.tag)
				return cached_path, ""
			}
		}
		if cached_valid {
			return cached_path, ""
		}
	} else if Template_Validate(cached_path) {
		return cached_path, ""
	}

	if local, local_ok := template_build_fallback(kind); local_ok {
		return local, ""
	}
	delete(cached_path)
	return "", fmt.tprintf("Could not obtain %v template: no network and none cached or built", kind)
}

ExportToExecutable :: proc(
	kind: Template_Kind,
	destination: string,
	mode: target.Mode,
	address: string,
	port: u16,
	game_name: string,
	map_bytes: []u8,
) -> (ok: bool, message: string) {
	if mode == target.Mode.Editor {
		return false, "Cannot bake an editor template"
	}
	template_path, problem := Template_Resolve(kind)
	if template_path == "" {
		return false, problem
	}
	defer delete(template_path)
	template, read_err := os.read_entire_file_from_path(template_path, context.allocator)
	if read_err != nil {
		return false, fmt.tprintf("Could not read template %s", template_path)
	}
	defer delete(template)
	full, append_ok := Payload_Append(template, Payload{
		mode      = mode,
		address   = address,
		port      = port,
		name      = game_name,
		map_bytes = map_bytes,
	})
	if !append_ok {
		return false, "Failed to build export payload"
	}
	defer delete(full)
	if os.write_entire_file(destination, full) != nil {
		return false, fmt.tprintf("Could not write %s", destination)
	}
	template_dir := filepath.dir(template_path)
	destination_dir := filepath.dir(destination)
	if template_dir != destination_dir {
		Template_Copy_Runtime_Siblings(template_dir, destination_dir, filepath.base(template_path))
	}
	return true, ""
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
		creatable = false,
	)
}