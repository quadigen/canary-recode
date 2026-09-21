#+build !js

package services

// wire:service global="ContentProvider"

import "core:fmt"
import "core:os"
import "core:path/filepath"

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

ContentProvider_Class := classes.Class_Info{
	name   = "ContentProvider",
	parent = &Service_Class,
}

ContentProvider :: struct {
	using service: Service,
}

content_provider_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ContentProvider)

	service.service = Service_Init(
		&ContentProvider_Class,
		"ContentProvider",
		data_model,
	)

	return &service.object
}

ContentProvider_DownloadZip :: proc(
	service: ^ContentProvider,
	url: string,
	location: string,
	strip_root: bool = false,
) -> (bool, string) {
	http_object := Service_Get_Service(
		&service.service,
		"HttpService",
	)

	if http_object == nil {
		return false, "HttpService is unavailable"
	}

	http_service := cast(^HttpService)http_object

	data, ok := HttpService_GetAsync(
		http_service,
		url,
	)

	if !ok {
		return false, "HTTP download failed"
	}

	defer delete(data)

	temp_dir, temp_err := os.make_directory_temp(
		"",
		"kinemium-content-*",
		context.allocator,
	)

	if temp_err != nil {
		return false, fmt.tprintf(
			"Failed creating temporary directory: %v",
			temp_err,
		)
	}

	defer {
		_ = os.remove_all(temp_dir)
		delete(temp_dir)
	}

	zip_path, path_err := filepath.join(
		[]string{
			temp_dir,
			"download.zip",
		},
		context.allocator,
	)

	if path_err != nil {
		return false, "Failed creating temporary ZIP path"
	}

	defer delete(zip_path)

	if err := os.write_entire_file_from_string(
		zip_path,
		data,
	); err != nil {
		return false, fmt.tprintf(
			"Failed writing ZIP: %v",
			err,
		)
	}

	handle, opened := kineffi.Zip_Open(zip_path)

	if !opened {
		return false, "Downloaded file is not a valid ZIP"
	}

	extracted := kineffi.Zip_Extract_All(
		handle,
		location,
		strip_root,
	)

	if !extracted {
		error_message := kineffi.Zip_Last_Error(handle)
		_ = kineffi.Zip_Close(handle)

		return false, fmt.tprintf(
			"ZIP extraction failed: %s",
			error_message,
		)
	}

	if !kineffi.Zip_Close(handle) {
		return false, "Failed closing ZIP archive"
	}

	return true, ""
}

content_provider_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "DownloadZip":
		vm.PushUserdataMethod(L, key)
		return true
	}

	return false
}

content_provider_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method_name: string,
) -> (i32, bool) {
	service := cast(^ContentProvider)object

	switch method_name {
	case "DownloadZip":
		url := vm.ArgString(L, 2)
		location := vm.ArgString(L, 3)
		strip_root := vm.ArgOptionalBoolean(
			L,
			4,
			false,
		)

		ok, error_message := ContentProvider_DownloadZip(
			service,
			url,
			location,
			strip_root,
		)

		if !ok {
			return vm.RaiseError(
				L,
				fmt.tprintf(
					"ContentProvider:DownloadZip failed: %s",
					error_message,
				),
			), true
		}

		vm.PushBoolean(L, true)
		return 1, true
	}

	return 0, false
}

content_provider_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	service := cast(^ContentProvider)object

	classes.Object_Destroy(object)
	free(service)
}

Register_ContentProvider_Class :: proc(
	registry: ^classes.Registry,
) {
	classes.Register_Class(
		registry,
		&ContentProvider_Class,
		content_provider_construct,
		content_provider_destroy,
		creatable = false,
		get       = content_provider_get,
		namecall  = content_provider_namecall,
	)
}
