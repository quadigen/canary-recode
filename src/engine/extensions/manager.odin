package extensions


import classes "../classes"
import datatypes "../datatypes"
import debuglog "../debuglog"
import enums "../enum"
import services "../services"
import signals "../signals"
import vm "../vm"
import "core:fmt"
import "core:strings"


DEFAULT_EXTENSION_DIRECTORY :: "extensions"

Extension_State :: enum {
	Discovered,
	Loaded,
	Running,
	Failed,
	Unloaded,
}

Extension_State_Name :: proc(state: Extension_State) -> string {
	switch state {
	case .Discovered:
		return "discovered"
	case .Loaded:
		return "loaded"
	case .Running:
		return "running"
	case .Failed:
		return "failed"
	case .Unloaded:
		return "unloaded"
	}
	return "unknown"
}


class_registrations: map[^classes.Class_Info]^Class_Registration

Class_Registration :: struct {
	extension:  ^Extension_Record,
	info:       ^classes.Class_Info,
	descriptor: ^classes.Class_Descriptor,
	name:       string,
	desc:       KNE_Class_Desc,
	properties: [dynamic]string,
	methods:    [dynamic]string,
	events:     [dynamic]string,
	registered: bool,
	is_service: bool,
}

Extension_Record :: struct {
	ctx:          ^Context,
	manifest:     Manifest,
	directory:    string,
	library_path: string,
	library:      Platform_Library,
	desc:         ^KNE_Extension_Desc,
	state:        Extension_State,
	classes:      [dynamic]^Class_Registration,
	closures:     [dynamic]^Native_Function_Closure,
	globals:      [dynamic]string,
	callbacks:    [dynamic]^Retained_Callback,
	result_roots: [dynamic]i32,
	connections:  [dynamic]^signals.KinemiumConnection,
	bridges:      [dynamic]^Signal_Bridge,
	datatypes:    [dynamic]^Extension_Datatype,
	last_error:   string,
}

Context :: struct {
	class_registry:    ^classes.Registry,
	service_registry:  ^services.Registry,
	datatype_registry: ^datatypes.Registry,
	enum_registry:     ^enums.Registry,
	vm_state:          ^vm.VM,
	records:           [dynamic]^Extension_Record,
	host:              ^Host_State,
	directory:         string,
	last_error:        string,
	instance_data:     map[^classes.Object]rawptr,
}


Context_Init :: proc(
	context_state: ^Context,
	class_registry: ^classes.Registry,
	service_registry: ^services.Registry,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	vm_state: ^vm.VM,
) {
	assert(context_state != nil)
	context_state.class_registry = class_registry
	context_state.service_registry = service_registry
	context_state.datatype_registry = datatype_registry
	context_state.enum_registry = enum_registry
	context_state.vm_state = vm_state
	context_state.instance_data = make(map[^classes.Object]rawptr)
	context_state.host = host_state_create(context_state)
}

Context_Destroy :: proc(context_state: ^Context) {
	if context_state == nil {
		return
	}

	Unload_All(context_state)

	if context_state.instance_data != nil {
		delete(context_state.instance_data)
		context_state.instance_data = nil
	}

	for record in context_state.records {
		free_record(record)
	}
	delete(context_state.records)
	context_state.records = nil

	delete(context_state.directory)
	context_state.directory = ""
	delete(context_state.last_error)
	context_state.last_error = ""

	if context_state.host != nil {
		host_state_destroy(context_state.host)
		context_state.host = nil
	}
}

@(private)
free_record :: proc(record: ^Extension_Record) {
	if record == nil {
		return
	}

	for registration in record.classes {
		if registration == nil {
			continue
		}
		delete(registration.name)
		for property in registration.properties {
			delete(property)
		}
		delete(registration.properties)
		for method in registration.methods {
			delete(method)
		}
		delete(registration.methods)
		for event in registration.events {
			delete(event)
		}
		delete(registration.events)
		if registration.info != nil {
			delete(registration.info.ancestors)
			free(registration.info)
			registration.info = nil
		}
		free(registration)
	}
	delete(record.classes)

	for closure in record.closures {
		free(closure)
	}
	delete(record.closures)

	for name in record.globals {
		delete(name)
	}
	delete(record.globals)

	for callback in record.callbacks {
		free(callback)
	}
	delete(record.callbacks)
	delete(record.result_roots)

	for connection in record.connections {
		free(connection)
	}
	delete(record.connections)

	for bridge in record.bridges {
		free(bridge)
	}
	delete(record.bridges)

	for datatype in record.datatypes {
		free(datatype)
	}
	delete(record.datatypes)

	delete(record.library.path)
	delete(record.library_path)
	delete(record.directory)
	delete(record.last_error)
	Manifest_Destroy(&record.manifest)
	free(record)
}





Discover_Default :: proc(context_state: ^Context) -> (loaded: int, err: string) {
	return Discover(context_state, DEFAULT_EXTENSION_DIRECTORY)
}


Load_Directory :: proc(context_state: ^Context, directory: string) -> (^Extension_Record, string) {
	if context_state == nil || context_state.host == nil {
		return nil, strings.clone("the extension system is not initialized")
	}
	manifest, manifest_err := Manifest_Load(directory)
	if manifest_err != "" {
		return nil, manifest_err
	}
	return load_record(context_state, &manifest)
}

@(private)
load_record :: proc(
	context_state: ^Context,
	manifest: ^Manifest,
) -> (
	record: ^Extension_Record,
	err: string,
) {
	record = new(Extension_Record)
	record.ctx = context_state
	record.manifest = manifest^
	manifest^ = {}
	record.directory = strings.clone(record.manifest.directory)
	record.state = .Discovered

	if record.manifest.api_major != KNE_ABI_MAJOR {
		err = fmt.aprintf(
			"%s needs KNE API %d, this engine implements %d",
			record.manifest.id,
			record.manifest.api_major,
			KNE_ABI_MAJOR,
		)
		free_record(record)
		return nil, err
	}
	if record.manifest.api_minor > KNE_ABI_MINOR {
		err = fmt.aprintf(
			"%s needs KNE API %d.%d, this engine implements %d.%d",
			record.manifest.id,
			record.manifest.api_major,
			record.manifest.api_minor,
			KNE_ABI_MAJOR,
			KNE_ABI_MINOR,
		)
		free_record(record)
		return nil, err
	}

	library_path, path_err := resolve_library_path(&record.manifest)
	if path_err != "" {
		free_record(record)
		return nil, path_err
	}
	record.library_path = library_path

	debuglog.Log(fmt.tprintf("KNE: mapping %s", record.manifest.id))
	library, load_err := platform_load(library_path)
	debuglog.Log(fmt.tprintf("KNE: mapped %s", record.manifest.id))
	if load_err != "" {
		free_record(record)
		return nil, load_err
	}
	record.library = library

	symbol, found := platform_symbol(library, record.manifest.entry)
	if !found {
		err = fmt.aprintf("%s does not export %q", library_path, record.manifest.entry)
		platform_unload(&record.library)
		free_record(record)
		return nil, err
	}

	debuglog.Log(fmt.tprintf("KNE: calling entry of %s", record.manifest.id))
	entry := cast(KNE_Entry_Fn)symbol
	desc := entry(&context_state.host.host)
	debuglog.Log(fmt.tprintf("KNE: entry returned for %s", record.manifest.id))
	if desc == nil {
		err = fmt.aprintf("%s returned no extension description", library_path)
		platform_unload(&record.library)
		free_record(record)
		return nil, err
	}
	if desc.size < u32(size_of(KNE_Extension_Desc)) {
		err = fmt.aprintf(
			"%s describes an entry struct of %d bytes, this engine needs at least %d",
			library_path,
			desc.size,
			size_of(KNE_Extension_Desc),
		)
		platform_unload(&record.library)
		free_record(record)
		return nil, err
	}
	if desc.abi_major != KNE_ABI_MAJOR {
		err = fmt.aprintf(
			"%s was built for KNE ABI %d, this engine implements %d",
			library_path,
			desc.abi_major,
			KNE_ABI_MAJOR,
		)
		platform_unload(&record.library)
		free_record(record)
		return nil, err
	}
	if desc.abi_minor > KNE_ABI_MINOR {
		err = fmt.aprintf(
			"%s requires KNE ABI %d.%d, this engine implements %d.%d",
			library_path,
			desc.abi_major,
			desc.abi_minor,
			KNE_ABI_MAJOR,
			KNE_ABI_MINOR,
		)
		platform_unload(&record.library)
		free_record(record)
		return nil, err
	}

	record.desc = desc
	append(&context_state.records, record)
	record.state = .Loaded

	debuglog.Log(fmt.tprintf("KNE: on_load %s", record.manifest.id))
	if desc.on_load != nil && desc.on_load(rawptr(record)) == 0 {
		err = fmt.aprintf("%s failed to initialize (on_load returned 0)", record.manifest.id)
		record.last_error = strings.clone(err)
		unload_record(context_state, record)
		return nil, err
	}
	if desc.on_start != nil && desc.on_start(rawptr(record)) == 0 {
		err = fmt.aprintf("%s failed to start (on_start returned 0)", record.manifest.id)
		record.last_error = strings.clone(err)
		unload_record(context_state, record)
		return nil, err
	}

	record.state = .Running
	debuglog.Log(
		fmt.tprintf(
			"KNE: loaded %s %s (%s)",
			record.manifest.id,
			record.manifest.version,
			record.library_path,
		),
	)
	return record, ""
}




Find :: proc(context_state: ^Context, id: string) -> ^Extension_Record {
	if context_state == nil {
		return nil
	}
	for index := len(context_state.records) - 1; index >= 0; index -= 1 {
		record := context_state.records[index]
		if record == nil || record.state == .Unloaded || record.state == .Failed {
			continue
		}
		if record.manifest.id == id {
			return record
		}
	}
	return nil
}

Active_Count :: proc(context_state: ^Context) -> int {
	count := 0
	if context_state == nil {
		return 0
	}
	for record in context_state.records {
		if record != nil && record.state != .Unloaded {
			count += 1
		}
	}
	return count
}

Unload :: proc(context_state: ^Context, id: string) -> string {
	record := Find(context_state, id)
	if record == nil {
		return strings.concatenate({"unknown extension ", id})
	}
	return unload_record(context_state, record)
}

Reload :: proc(context_state: ^Context, id: string) -> string {
	record := Find(context_state, id)
	if record == nil {
		return strings.concatenate({"unknown extension ", id})
	}

	directory := strings.clone(record.directory)
	defer delete(directory)

	if unload_err := unload_record(context_state, record); unload_err != "" {
		return unload_err
	}

	_, load_err := Load_Directory(context_state, directory)
	return load_err
}

Unload_All :: proc(context_state: ^Context) {
	if context_state == nil {
		return
	}

	for index := len(context_state.records) - 1; index >= 0; index -= 1 {
		record := context_state.records[index]
		if record == nil || record.state == .Unloaded {
			continue
		}
		_ = unload_record(context_state, record)
	}
}

@(private)
unload_record :: proc(context_state: ^Context, record: ^Extension_Record) -> string {
	if record == nil || record.state == .Unloaded {
		return ""
	}

	desc := record.desc

	if record.state == .Running && desc != nil && desc.on_stop != nil {
		desc.on_stop(rawptr(record))
	}


	release_extension_resources(context_state, record)
	release_globals(context_state, record)
	destroy_extension_instances(context_state, record)

	for registration in record.classes {
		if registration == nil || !registration.registered {
			continue
		}
		delete_key(&class_registrations, registration.info)
		classes.Unregister_Class(context_state.class_registry, registration.descriptor)
		if registration.is_service {
			services.Unregister_Service(context_state.service_registry, registration.name)
		}
		registration.descriptor = nil
		registration.registered = false
		if registration.info != nil {
			delete(registration.info.ancestors)
			free(registration.info)
			registration.info = nil
		}
	}

	if desc != nil && desc.on_unload != nil {
		desc.on_unload(rawptr(record))
	}

	unload_err := platform_unload(&record.library)
	record.desc = nil
	record.state = .Unloaded
	if unload_err != "" {
		record.last_error = strings.clone(unload_err)
		return unload_err
	}

	debuglog.Log(fmt.tprintf("KNE: unloaded %s", record.manifest.id))
	return ""
}

@(private)
release_globals :: proc(context_state: ^Context, record: ^Extension_Record) {
	if len(record.globals) == 0 {
		return
	}
	if context_state.vm_state != nil && context_state.vm_state.L != nil {
		L := context_state.vm_state.L
		for name in record.globals {
			vm.PushNil(L)
			vm.SetGlobalFromStack(context_state.vm_state, name)
		}
	}
	for name in record.globals {
		delete(name)
	}
	delete(record.globals)
	record.globals = nil
}

@(private)
destroy_extension_instances :: proc(context_state: ^Context, record: ^Extension_Record) {
	if context_state.class_registry == nil {
		return
	}

	for registration in record.classes {
		if registration == nil || registration.descriptor == nil {
			continue
		}
		instances := registration.descriptor.instances
		snapshot := make([]^classes.Object, len(instances), context.temp_allocator)
		copy(snapshot, instances[:])
		for object in snapshot {
			if object == nil {
				continue
			}
			classes.Destroy_Hierarchy(object)
		}
	}


	classes.Flush_Pending_Destroy(context_state.class_registry)


	if context_state.instance_data == nil {
		return
	}
	stale := make(
		[dynamic]^classes.Object,
		0,
		len(context_state.instance_data),
		context.temp_allocator,
	)
	for object, _ in context_state.instance_data {
		if object == nil || object.destroyed {
			append(&stale, object)
			continue
		}
		if registration := class_registrations[object.class]; registration != nil {
			if registration.extension == record {
				append(&stale, object)
			}
		}
	}
	for object in stale {
		if object != nil {
			delete_key(&context_state.instance_data, object)
		}
	}
}


Step :: proc(context_state: ^Context, delta_time: f32) {
	if context_state == nil {
		return
	}
	for record in context_state.records {
		if record == nil || record.state != .Running || record.desc == nil {
			continue
		}
		first_root := len(record.result_roots)
		defer release_result_roots(record, first_root)
		if record.desc.on_update != nil {
			record.desc.on_update(rawptr(record), f64(delta_time))
		}
		for registration in record.classes {
			if registration == nil ||
			   registration.descriptor == nil ||
			   registration.desc.step == nil {
				continue
			}
			instances := registration.descriptor.instances

			snapshot := make([]^classes.Object, len(instances), context.temp_allocator)
			copy(snapshot, instances[:])
			for object in snapshot {
				if object == nil || object.destroyed {
					continue
				}
				registration.desc.step(rawptr(record), rawptr(object), f64(delta_time))
			}
		}
	}
}
