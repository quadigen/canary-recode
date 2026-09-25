#+build !js

package services

// wire:service global="ExporterService"

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import target "../target"
import vm "../vm"

ExporterService_Class := classes.Class_Info {
	name   = "ExporterService",
	parent = &Service_Class,
}

ExporterService :: struct {
	using service: Service,
}

Exporter_Kind :: enum { Server, Client, Both }

Exporter_Bake :: proc(
	folder, address: string,
	port: u16,
	game_name: string,
	map_bytes: []u8,
	kind: Exporter_Kind,
) -> (ok: bool, message: string) {
	if address == "" {
		return false, "Address must not be empty"
	}
	if port < 1 || port > 65535 {
		return false, "Port must be between 1 and 65535"
	}
	if folder == "" {
		return false, "Destination folder must not be empty"
	}
	if os.make_directory_all(folder) != nil && !os.is_directory(folder) {
		return false, fmt.tprintf("Could not create the destination folder %s", folder)
	}
	targets: [dynamic]Exporter_Kind
	defer delete(targets)
	if kind == .Both {
		append(&targets, Exporter_Kind.Server, Exporter_Kind.Client)
	} else {
		append(&targets, kind)
	}
	for candidate in targets {
		template_kind := Template_Kind.Server if candidate == .Server else Template_Kind.Client
		mode := target.Mode.Server if candidate == .Server else target.Mode.Client
		base := "KinemiumServer" if candidate == .Server else "KinemiumClient"
		file_name := strings.concatenate({base, template_binary_ext()})
		destination, join_err := filepath.join([]string{folder, file_name}, context.allocator)
		delete(file_name)
		if join_err != nil {
			return false, fmt.tprintf("Could not build the destination path for %v", candidate)
		}
		exe_ok, exe_problem := ExportToExecutable(
			template_kind,
			destination,
			mode,
			address,
			port,
			game_name,
			map_bytes,
		)
		delete(destination)
		if !exe_ok {
			return false, exe_problem
		}
	}
	return true, ""
}

EXPORTER_INTERNALS_CAPABILITY :: i64(2)

exporter_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ExporterService)
	service.service = Service_Init(&ExporterService_Class, "ExporterService", data_model)
	return &service.object
}

exporter_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^ExporterService)object)
}

exporter_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "ExportExecutable":
		if !vm.ThreadHasSecurityCapability(L, EXPORTER_INTERNALS_CAPABILITY) {
			return false
		}
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

exporter_kind_from_string :: proc(kind_name: string) -> (Exporter_Kind, bool) {
	switch kind_name {
	case "Server":
		return .Server, true
	case "Client":
		return .Client, true
	case "Both":
		return .Both, true
	}
	return .Server, false
}

exporter_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "ExportExecutable":
		if !vm.ThreadHasSecurityCapability(L, EXPORTER_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "ExporterService:ExportExecutable() requires Internals capability"), true
		}
		kind_name := vm.ArgString(L, 2)
		folder := vm.ArgString(L, 3)
		address := vm.ArgString(L, 4)
		port := i32(vm.ArgNumber(L, 5))
		game_file := vm.ArgString(L, 6)
		kind, kind_ok := exporter_kind_from_string(kind_name)
		if folder == "" || address == "" || game_file == "" || !kind_ok {
			return vm.RaiseError(L, "ExporterService:ExportExecutable(target, folder, address, port, fileName) expects target Server|Client|Both, a folder, an address, a port 1-65535, and an exported .kine file"), true
		}
		if port < 1 || port > 65535 {
			return vm.RaiseError(L, "ExporterService:ExportExecutable port must be between 1 and 65535"), true
		}
		map_bytes, read_ok := os.read_entire_file_from_path(game_file, context.allocator)
		if read_ok != nil {
			return vm.RaiseError(L, "ExporterService:ExportExecutable could not read the exported kine file"), true
		}
		defer delete(map_bytes)
		game_name := filepath.base(game_file)
		bake_ok, message := Exporter_Bake(
			folder,
			address,
			u16(port),
			game_name,
			map_bytes,
			kind,
		)
		if !bake_ok {
			return vm.RaiseError(L, fmt.tprintf("ExporterService:ExportExecutable failed: %s", message)), true
		}
		vm.PushString(L, message)
		return 1, true
	}
	return 0, false
}

Register_ExporterService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ExporterService_Class,
		exporter_service_construct,
		exporter_service_destroy,
		creatable = false,
		get = exporter_service_get,
		namecall = exporter_service_namecall,
	)
}