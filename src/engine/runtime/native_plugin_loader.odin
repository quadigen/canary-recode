#+build !js
package engine_runtime


import extensions "../extensions"
import native_api "../native_api"
import services "../services"
import vm "../vm"
import "core:fmt"
import "core:os"
import "core:strings"

NATIVE_PLUGIN_DIRECTORY :: "extensions"

native_plugin_paths :: proc() -> []string {
	paths := make([dynamic]string)
	if !os.is_directory(NATIVE_PLUGIN_DIRECTORY) {return paths[:]}
	if os.is_file(NATIVE_PLUGIN_DIRECTORY + "/extension.json") {
		append(&paths, strings.clone(NATIVE_PLUGIN_DIRECTORY))
	}
	entries, err := os.read_all_directory_by_path(NATIVE_PLUGIN_DIRECTORY, context.temp_allocator)
	if err != nil {return paths[:]}
	for entry in entries {
		path := fmt.aprintf("%s/%s", NATIVE_PLUGIN_DIRECTORY, entry.name)
		if os.is_directory(path) {
			manifest_file := fmt.aprintf("%s/extension.json", path)
			if os.is_file(manifest_file) {append(&paths, path)} else {delete(path)}
			delete(manifest_file)
		} else {
			delete(path)
		}
	}
	return paths[:]
}

native_plugin_push :: proc(
	L: ^vm.State,
	manifest: ^extensions.Manifest,
	ext: ^extensions.Context,
) {
	vm.NewTable(L, 0, 12)
	vm.PushString(L, manifest.id)
	vm.SetField(L, -2, "Id")
	vm.PushString(L, manifest.name)
	vm.SetField(L, -2, "Name")
	vm.PushString(L, manifest.version)
	vm.SetField(L, -2, "Version")
	vm.PushString(L, manifest.author)
	vm.SetField(L, -2, "Author")
	vm.PushString(L, manifest.description)
	vm.SetField(L, -2, "Description")
	vm.PushString(L, manifest.library)
	vm.SetField(L, -2, "Library")
	vm.PushNumber(L, f64(manifest.api_major))
	vm.SetField(L, -2, "ApiMajor")
	vm.PushNumber(L, f64(manifest.api_minor))
	vm.SetField(L, -2, "ApiMinor")
	vm.PushBoolean(L, manifest.enabled)
	vm.SetField(L, -2, "Enabled")
	vm.PushBoolean(L, true)
	vm.SetField(L, -2, "Native")
	vm.PushBoolean(L, manifest.api_major != native_api.ABI_MAJOR)
	vm.SetField(L, -2, "Legacy")
	vm.PushBoolean(L, true)
	vm.SetField(L, -2, "UnrestrictedNativeAccess")

	record := extensions.Find(ext, manifest.id)
	running := record != nil && record.state == .Running
	vm.PushBoolean(L, running)
	vm.SetField(L, -2, "Loaded")
	vm.PushString(L, running ? "running" : "not loaded")
	vm.SetField(L, -2, "State")

	vm.NewTable(L, len(manifest.capabilities))
	for capability, i in manifest.capabilities {
		vm.PushString(L, capability)
		vm.SetArrayValue(L, -2, i + 1)
	}
	vm.SetField(L, -2, "Capabilities")
}

native_plugin_list :: proc(opaque: rawptr, L: ^vm.State) {
	ext := cast(^extensions.Context)opaque
	paths := native_plugin_paths()
	defer {
		for path in paths {delete(path)}
		delete(paths)
	}
	vm.NewTable(L, len(paths))
	next := 1
	for path in paths {
		manifest, err := extensions.Manifest_Load(path)
		if err != "" {delete(err); continue}
		if manifest.api_major == native_api.ABI_MAJOR ||
		   manifest.api_major == extensions.KNE_ABI_MAJOR {
			native_plugin_push(L, &manifest, ext)
			vm.SetArrayValue(L, -2, next)
			next += 1
		}
		extensions.Manifest_Destroy(&manifest)
	}
}

native_plugin_action :: proc(opaque: rawptr, action, id: string) -> (bool, string) {
	ext := cast(^extensions.Context)opaque
	if ext == nil || id == "" {return false, strings.clone("Invalid plugin request")}
	if action == "unload" {
		record := extensions.Find(ext, id)
		if record == nil ||
		   (record.manifest.api_major != native_api.ABI_MAJOR &&
				   record.manifest.api_major != extensions.KNE_ABI_MAJOR) {
			return false, strings.clone("Native plugin is not loaded")
		}
		err := extensions.Unload(ext, id)
		return err == "", err
	}
	if action != "load" {return false, strings.clone("Unknown native plugin action")}
	if extensions.Find(ext, id) != nil {return true, ""}
	paths := native_plugin_paths()
	defer {
		for path in paths {delete(path)}
		delete(paths)
	}
	for path in paths {
		manifest, err := extensions.Manifest_Load(path)
		if err != "" {delete(err); continue}
		matched :=
			manifest.id == id &&
			(manifest.api_major == native_api.ABI_MAJOR ||
					manifest.api_major == extensions.KNE_ABI_MAJOR)
		enabled := manifest.enabled
		extensions.Manifest_Destroy(&manifest)
		if !matched {continue}
		if !enabled {return false, strings.clone("Plugin is disabled in extension.json")}


		_, load_error := extensions.Load_Directory(ext, path)
		return load_error == "", load_error
	}
	return false, strings.clone("Native plugin not found")
}

Native_Plugin_Bridge_Install :: proc(environment: ^Environment) {
	if environment == nil || environment.mode != .Editor {
		services.PluginLoader_Set_Backend({})
		return
	}
	services.PluginLoader_Set_Backend(
		services.PluginLoader_Backend {
			ctx = &environment.extensions,
			list = native_plugin_list,
			action = native_plugin_action,
		},
	)
}
