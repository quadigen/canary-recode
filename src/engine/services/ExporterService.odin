#+build !js

package services

// wire:service global="ExporterService"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import fsutil "../fsutil"
import serializer "../serializer"
import target "../target"
import vm "../vm"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

ExporterService_Class := classes.Class_Info {
	name   = "ExporterService",
	parent = &Service_Class,
}

ExporterService :: struct {
	using service: Service,
}

Exporter_Kind :: enum {
	Server,
	Client,
	Both,
	Singleplayer,
}

Exporter_Options :: struct {
	output_name: string,
	icon_path:   string,
	console:     Export_Console,
	clean:       bool,
}

exporter_output_name :: proc(
	kind, candidate: Exporter_Kind,
	p: Target_Platform,
	output_name: string,
) -> string {
	if output_name == "" {
		base := "KinemiumClient"
		switch candidate {
		case .Server:
			base = "KinemiumServer"
		case .Singleplayer:
			base = "KinemiumGame"
		case .Client, .Both:
		}
		return fmt.tprintf("%s%s", base, p.ext)
	}
	name := output_name
	if p.ext != "" &&
	   len(name) > len(p.ext) &&
	   strings.equal_fold(name[len(name) - len(p.ext):], p.ext) {
		name = name[:len(name) - len(p.ext)]
	}
	suffix := "-server" if kind == .Both && candidate == .Server else ""
	return fmt.tprintf("%s%s%s", name, suffix, p.ext)
}

exporter_remove_previous :: proc(folder: string, written: []string) -> bool {
	entries, err := os.read_directory_by_path(folder, -1, context.allocator)
	if err != nil {
		return false
	}
	defer os.file_info_slice_delete(entries, context.allocator)
	outer: for entry in entries {
		if entry.type != .Regular {
			continue
		}
		for current in written {
			if strings.equal_fold(entry.name, current) {
				continue outer
			}
		}
		path, join_err := filepath.join([]string{folder, entry.name}, context.temp_allocator)
		if join_err != nil {
			continue
		}
		file, open_err := os.open(path)
		if open_err != nil {
			continue
		}
		size, size_err := os.file_size(file)
		tail: [PAYLOAD_TAIL_SIZE]u8
		count: int
		if size_err == nil && size >= PAYLOAD_TAIL_SIZE {
			count, _ = os.read_at(file, tail[:], size - PAYLOAD_TAIL_SIZE)
		}
		os.close(file)
		if count == PAYLOAD_TAIL_SIZE &&
		   string(tail[PAYLOAD_LEN_FIELD:]) == PAYLOAD_MAGIC &&
		   payload_read_le_u64(tail[:], 0) <= u64(size - PAYLOAD_TAIL_SIZE) &&
		   os.remove(path) != nil {
			return false
		}
	}
	return true
}

Exporter_Bake :: proc(
	folder, address: string,
	port: u16,
	game_name: string,
	map_bytes: []u8,
	kind: Exporter_Kind,
	p: Target_Platform,
	options: Exporter_Options = {},
) -> (
	ok: bool,
	message: string,
) {
	if kind != .Singleplayer && address == "" {
		return false, "Address must not be empty"
	}
	if kind != .Singleplayer && port == 0 {
		return false, "Port must be between 1 and 65535"
	}
	if folder == "" {
		return false, "Destination folder must not be empty"
	}
	if options.output_name != "" && !Project_Name_Is_Valid(options.output_name) {
		return false, "Output name must be a file name"
	}
	if fsutil.Make_Directory_All(folder) != nil && !os.is_directory(folder) {
		return false, fmt.tprintf("Could not create the destination folder %s", folder)
	}
	targets: [dynamic]Exporter_Kind
	defer delete(targets)
	if kind == .Both {
		append(&targets, Exporter_Kind.Server, Exporter_Kind.Client)
	} else {
		append(&targets, kind)
	}
	written: [dynamic]string
	defer delete(written)
	for candidate in targets {
		template_kind := Template_Kind.Server if candidate == .Server else Template_Kind.Client
		mode := target.Mode.Server if candidate == .Server else target.Mode.Client
		if candidate == .Singleplayer {
			mode = .Singleplayer
		}
		file_name := exporter_output_name(kind, candidate, p, options.output_name)
		destination, join_err := filepath.join([]string{folder, file_name}, context.allocator)
		if join_err != nil {
			return false, fmt.tprintf("Could not build the destination path for %v", candidate)
		}
		exe_ok, exe_problem := ExportToExecutable(
			template_kind,
			p,
			destination,
			mode,
			address,
			port,
			game_name,
			map_bytes,
			options.console,
			options.icon_path,
		)
		delete(destination)
		if !exe_ok {
			return false, exe_problem
		}
		append(&written, file_name)
	}
	if options.clean && !exporter_remove_previous(folder, written[:]) {
		return false, "Could not remove a previous export"
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
	case "Singleplayer":
		return .Singleplayer, true
	}
	return .Server, false
}

exporter_string_option :: proc(L: ^vm.State, key: string) -> string {
	vm.GetField(L, 9, key)
	value := vm.ArgOptionalString(L, -1)
	vm.Pop(L, 1)
	return value
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
			return vm.RaiseError(
					L,
					"ExporterService:ExportExecutable() requires Internals capability",
				),
				true
		}
		kind_name := vm.ArgString(L, 2)
		folder := vm.ArgString(L, 3)
		address := vm.ArgString(L, 4)
		port := i32(vm.ArgNumber(L, 5))
		game_file := vm.ArgString(L, 6)
		platform := Template_Host_Platform()
		if !vm.IsNoneOrNil(L, 7) {
			os_name := vm.ArgString(L, 7)
			arch_name := vm.ArgString(L, 8)
			p, ok := Template_Platform_From(os_name, arch_name)
			if !ok {
				return vm.RaiseError(
						L,
						fmt.tprintf("ExporterService: unknown platform %s", os_name),
					),
					true
			}
			platform = p
		}
		kind, kind_ok := exporter_kind_from_string(kind_name)
		if folder == "" ||
		   game_file == "" ||
		   !kind_ok ||
		   (kind != .Singleplayer && address == "") {
			return vm.RaiseError(
					L,
					"ExporterService:ExportExecutable(target, folder, address, port, fileName) expects target Server|Client|Both|Singleplayer, a folder, network settings for multiplayer, and a .kine file",
				),
				true
		}
		if kind != .Singleplayer && (port < 1 || port > 65535) {
			return vm.RaiseError(
					L,
					"ExporterService:ExportExecutable port must be between 1 and 65535",
				),
				true
		}
		map_bytes, read_ok := os.read_entire_file_from_path(game_file, context.allocator)
		if read_ok != nil {
			return vm.RaiseError(
					L,
					"ExporterService:ExportExecutable could not read the exported kine file",
				),
				true
		}
		defer delete(map_bytes)
		game_name := filepath.base(game_file)
		options: Exporter_Options
		map_data := map_bytes
		defer if raw_data(map_data) != raw_data(map_bytes) {delete(map_data)}
		if vm.IsTable(L, 9) {
			options.output_name = exporter_string_option(L, "outputName")
			options.icon_path = exporter_string_option(L, "icon")
			if title := exporter_string_option(L, "title"); title != "" {
				game_name = title
			}
			if vm.GetField(L, 9, "console") == .Boolean {
				options.console = .Show if vm.ArgBoolean(L, -1) else .Hide
			}
			vm.Pop(L, 1)
			vm.GetField(L, 9, "clean")
			options.clean = vm.ArgOptionalBoolean(L, -1)
			vm.Pop(L, 1)
			compression := exporter_string_option(L, "compression")
			if compression == "None" || compression == "Best" {
				repack_err: serializer.Error
				map_data, repack_err = serializer.Repack_File_Data(
					map_bytes,
					19 if compression == "Best" else 0,
				)
				defer serializer.Error_Delete(&repack_err)
				if !serializer.Error_Is_None(repack_err) {
					return vm.RaiseError(L, "Could not apply export compression"), true
				}
			}
		}
		bake_ok, message := Exporter_Bake(
			folder,
			address,
			u16(port),
			game_name,
			map_data,
			kind,
			platform,
			options,
		)
		if !bake_ok {
			return vm.RaiseError(
					L,
					fmt.tprintf("ExporterService:ExportExecutable failed: %s", message),
				),
				true
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
