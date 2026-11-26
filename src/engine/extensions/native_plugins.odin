package extensions

import native_api "../native_api"
import tracy "../util/odin-tracy"
import "core:fmt"
import "core:strings"

native_plugin_load :: proc(
	ctx: ^Context,
	record: ^Extension_Record,
) -> (
	^Extension_Record,
	string,
) {
	if record == nil || ctx == nil {return nil, strings.clone("invalid native plugin context")}
	if record.manifest.api_major != native_api.ABI_MAJOR ||
	   record.manifest.api_minor > native_api.ABI_MINOR {
		err := fmt.aprintf(
			"plugin %s requires unsupported native ABI %d.%d",
			record.manifest.id,
			record.manifest.api_major,
			record.manifest.api_minor,
		)
		free_record(record)
		return nil, err
	}
	for existing in ctx.records {
		if existing != nil &&
		   existing.state != .Unloaded &&
		   existing.state != .Failed &&
		   existing.manifest.id == record.manifest.id {
			err := fmt.aprintf("plugin %s is already loaded", record.manifest.id)
			free_record(record)
			return nil, err
		}
	}
	library_path, path_err := resolve_library_path(&record.manifest)
	if path_err != "" {
		free_record(record)
		return nil, path_err
	}
	record.library_path = library_path
	library, load_err := platform_load(library_path)
	if load_err != "" {
		free_record(record)
		return nil, load_err
	}
	record.library = library
	symbol, found := platform_symbol(library, "Kinemium_PluginEntry")
	if !found {
		err := fmt.aprintf("%s does not export Kinemium_PluginEntry", library_path)
		_ = platform_unload(&record.library)
		free_record(record)
		return nil, err
	}
	entry := cast(native_api.Plugin_Entry_Fn)symbol
	descriptor := entry()
	if descriptor == nil ||
	   descriptor.size < u32(size_of(native_api.Plugin_Descriptor)) ||
	   descriptor.abi_major != native_api.ABI_MAJOR ||
	   descriptor.abi_minor > native_api.ABI_MINOR ||
	   descriptor.id == nil ||
	   string(descriptor.id) != record.manifest.id {
		err := fmt.aprintf("%s has an invalid native plugin descriptor", library_path)
		_ = platform_unload(&record.library)
		free_record(record)
		return nil, err
	}
	ctx.next_native_id += 1
	if ctx.next_native_id == 0 {ctx.next_native_id += 1}
	record.native_id = ctx.next_native_id
	record.native_desc = descriptor
	native_api.Context_Borrow(&record.native_view, &ctx.native_context, record)
	record.native_view.plugin_id = strings.clone(record.manifest.id)
	append(&ctx.records, record)
	record.state = .Loaded
	record.native_load_called = true
	if descriptor.on_load != nil && !descriptor.on_load(&record.native_view) {
		err := fmt.aprintf("native plugin %s on_load failed", record.manifest.id)
		_ = native_plugin_unload_record(ctx, record)
		return nil, err
	}
	if descriptor.on_start != nil && !descriptor.on_start(&record.native_view) {
		err := fmt.aprintf("native plugin %s on_start failed", record.manifest.id)
		_ = native_plugin_unload_record(ctx, record)
		return nil, err
	}
	record.state = .Running
	return record, ""
}

native_plugin_unload_record :: proc(ctx: ^Context, record: ^Extension_Record) -> string {
	if ctx == nil || record == nil || record.state == .Unloaded {return ""}
	descriptor := record.native_desc
	if record.state == .Running && descriptor != nil && descriptor.on_stop != nil {
		descriptor.on_stop(&record.native_view)
	}
	if record.native_load_called && descriptor != nil && descriptor.on_unload != nil {
		descriptor.on_unload(&record.native_view)
	}
	native_api.Context_Destroy(&record.native_view)
	record.native_desc = nil
	record.native_load_called = false
	err := platform_unload(&record.library)
	record.state = .Unloaded
	if err != "" {
		delete(record.last_error)
		record.last_error = strings.clone(err)
		return err
	}
	return ""
}

native_plugin_find :: proc(ctx: ^Context, id: u64) -> ^Extension_Record {
	if ctx == nil || id == 0 {return nil}
	for record in ctx.records {
		if record != nil && record.native_id == id {
			return record
		}
	}
	return nil
}

native_plugin_load_api :: proc "c" (opaque: rawptr, path: cstring, out: ^u64) -> bool {
	context = tracy.DefaultContext()
	ctx := cast(^Context)opaque
	if ctx == nil || path == nil || out == nil {return false}
	manifest, err := Manifest_Load(string(path))
	if err != "" {
		native_api.SetError(&ctx.native_context, err)
		delete(err)
		return false
	}
	if manifest.api_major != native_api.ABI_MAJOR {
		native_api.SetError(
			&ctx.native_context,
			"extension manifest is not a native SDK v2 plugin",
		)
		Manifest_Destroy(&manifest)
		return false
	}
	record, load_err := load_record(ctx, &manifest)
	if load_err != "" {
		native_api.SetError(&ctx.native_context, load_err)
		delete(load_err)
		return false
	}
	out^ = record.native_id
	return true
}

native_plugin_unload_api :: proc "c" (opaque: rawptr, handle: u64) -> bool {
	context = tracy.DefaultContext()
	ctx := cast(^Context)opaque
	record := native_plugin_find(ctx, handle)
	if record == nil || record.native_desc == nil || record.state == .Unloaded {return false}
	err := native_plugin_unload_record(ctx, record)
	if err != "" {
		native_api.SetError(&ctx.native_context, err)
		delete(err)
		return false
	}
	return true
}

native_plugin_reload_api :: proc "c" (opaque: rawptr, handle: u64) -> bool {
	context = tracy.DefaultContext()
	ctx := cast(^Context)opaque
	record := native_plugin_find(ctx, handle)
	if record == nil || record.native_desc == nil || record.state == .Unloaded {return false}
	dir := strings.clone(record.directory)
	defer delete(dir)
	err := native_plugin_unload_record(ctx, record)
	if err != "" {
		native_api.SetError(&ctx.native_context, err)
		delete(err)
		return false
	}
	manifest, manifest_err := Manifest_Load(dir)
	if manifest_err != "" {
		native_api.SetError(&ctx.native_context, manifest_err)
		delete(manifest_err)
		return false
	}
	_, load_err := load_record(ctx, &manifest)
	if load_err != "" {
		native_api.SetError(&ctx.native_context, load_err)
		delete(load_err)
		return false
	}
	return true
}

native_plugin_count_api :: proc "c" (opaque: rawptr) -> u64 {
	context = tracy.DefaultContext()
	ctx := cast(^Context)opaque
	if ctx == nil {return 0}
	count: u64
	for record in ctx.records {
		if record != nil && record.native_desc != nil && record.state == .Running {
			count += 1
		}
	}
	return count
}

native_plugin_info_api :: proc "c" (
	opaque: rawptr,
	handle: u64,
	out: ^native_api.Plugin_Info,
) -> bool {
	context = tracy.DefaultContext()
	ctx := cast(^Context)opaque
	record := native_plugin_find(ctx, handle)
	if record == nil || out == nil {return false}
	out^ = native_api.Plugin_Info {
		handle    = record.native_id,
		active    = record.native_desc != nil && record.state == .Running,
		api_major = record.manifest.api_major,
		api_minor = record.manifest.api_minor,
	}
	return true
}

Native_Plugin_Hooks :: native_api.Plugin_Manager_Hooks {
	load   = native_plugin_load_api,
	unload = native_plugin_unload_api,
	reload = native_plugin_reload_api,
	count  = native_plugin_count_api,
	info   = native_plugin_info_api,
}
