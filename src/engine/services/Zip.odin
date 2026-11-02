package services
// wire:service


import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import fmt "core:fmt"

ZipService_Class := classes.Class_Info {
	name   = "ZipService",
	parent = &Service_Class,
}

ZipService :: struct {
	using service: Service,
}

ZipService_extract_to_path :: proc(zipPath: string, extractTo: string) -> int {
	archive, ok := kineffi.Zip_Open(zipPath)
	if !ok {
		fmt.println("Failed to open ZIP archive")
		return 0
	}
	defer kineffi.Zip_Close(archive)

	if !kineffi.Zip_Extract_All(archive, extractTo) {
		fmt.println("Failed to extract ZIP archive")
		return 0
	}

	return 1
}

ZipService_get_entries :: proc(zipPath: string) -> (entries: []string) {
	archive, ok := kineffi.Zip_Open(zipPath)
	if !ok {
		fmt.println("Failed to open ZIP archive")
		return nil
	}
	defer kineffi.Zip_Close(archive)

	count := kineffi.Zip_File_Count(archive)
	entries = make([]string, int(count))

	for i in 0 ..< count {
		entry, entry_ok := kineffi.Zip_File_Name(archive, i)
		if !entry_ok {
			delete(entries)
			fmt.println("Failed to get ZIP entry name")
			return nil
		}

		entries[i] = entry
	}

	return entries
}

ZipService_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ZipService)
	service.service = Service_Init(&ZipService_Class, "ZipService", data_model)
	return &service.object
}

ZipService_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^ZipService)object
	switch key {
	case "ExtractZip", "GetZipContents":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

ZipService_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^ZipService)object
	switch method {
	case "GetZipContents":
		if datatype_registry == nil {return 0, false}
		zip_path := vm.ArgString(L, 2)
		entries := ZipService_get_entries(zip_path)

		vm.NewTable(L, len(entries), 0)

		for i in 0 ..< len(entries) {
			vm.PushString(L, entries[i])
			vm.SetArrayValue(L, -2, i + 1)
		}

		return 1, true
	case "ExtractZip":
		zip_path := vm.ArgString(L, 2)
		extract_to := vm.ArgString(L, 3)

		success := ZipService_extract_to_path(zip_path, extract_to)
		vm.PushBoolean(L, success == 1)

		return 1, true
	}
	return 0, false
}

ZipService_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^ZipService)object)
}

Register_ZipService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ZipService_Class,
		ZipService_construct,
		ZipService_destroy,
		creatable = false,
		get = ZipService_get,
		namecall = ZipService_namecall,
	)
}
