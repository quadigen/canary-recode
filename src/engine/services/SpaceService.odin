#+build !js
// wire:service
package services


import "core:fmt"
import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"


SpaceService :: struct {
	using service: Service,
}

SpaceService_Class := classes.Class_Info {
	name   = "SpaceService",
	parent = &Service_Class,
}

space_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(SpaceService)
	service.service = Service_Init(&SpaceService_Class, "SpaceService", data_model)
	return &service.object
}

space_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "ListSpaces",
	     "GetSpaceProfile",
	     "UpdateSpaceProfile",
	     "UploadSpaceAvatar",
	     "UploadSpaceBanner",
	     "ListSpaceEmojis",
	     "UploadSpaceEmoji",
	     "DeleteSpaceEmoji",
	     "GetService":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

space_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^SpaceService)object
	switch method {
	case "ListSpaces":
		return kinemium_domain_call(
				L,
				&service.service,
				2,
				"GET",
				"/spaces",
				kinemium_options_empty(),
			),
			true

	case "GetSpaceProfile":
		{
			path := strings.concatenate(
				{"/spaces/", kinemium_url_encode(vm.ArgString(L, 3)), "/profile"},
				context.temp_allocator,
			)
			return kinemium_domain_call(
					L,
					&service.service,
					2,
					"GET",
					path,
					kinemium_options_empty(),
				),
				true
		}

	case "UpdateSpaceProfile":
		{
			path := strings.concatenate(
				{"/spaces/", kinemium_url_encode(vm.ArgString(L, 3)), "/profile"},
				context.temp_allocator,
			)
			return kinemium_domain_call(
					L,
					&service.service,
					2,
					"PATCH",
					path,
					kinemium_options_json(L, 4),
				),
				true
		}

	case "UploadSpaceAvatar":
		{
			path := strings.concatenate(
				{"/spaces/", kinemium_url_encode(vm.ArgString(L, 3)), "/avatar"},
				context.temp_allocator,
			)
			return kinemium_upload_image_call(L, &service.service, 2, 4, "POST", path), true
		}

	case "UploadSpaceBanner":
		{
			path := strings.concatenate(
				{"/spaces/", kinemium_url_encode(vm.ArgString(L, 3)), "/banner"},
				context.temp_allocator,
			)
			return kinemium_upload_image_call(L, &service.service, 2, 4, "POST", path), true
		}

	case "ListSpaceEmojis":
		{
			path := strings.concatenate(
				{"/spaces/", kinemium_url_encode(vm.ArgString(L, 3)), "/emojis"},
				context.temp_allocator,
			)
			return kinemium_domain_call(
					L,
					&service.service,
					2,
					"GET",
					path,
					kinemium_options_empty(),
				),
				true
		}

	case "UploadSpaceEmoji":
		{
			room_id := vm.ArgString(L, 3)
			shortcode := vm.ArgString(L, 4)
			contents := vm.ArgString(L, 5)
			mime, detected := kinemium_image_type(contents)
			if !detected {
				vm.PushBoolean(L, false)
				vm.PushString(L, "Unsupported image. Use PNG, JPEG, GIF or WebP.")
				kinemium_push_meta(L, Kinemium_Meta{})
				return 3, true
			}

			file_field := "file"
			filename := ""
			if vm.IsTable(L, 6) {
				vm.GetField(L, 6, "fileField")
				if vm.IsString(L, -1) &&
				   vm.ArgString(L, -1) != "" {file_field = vm.ArgString(L, -1)}
				vm.Pop(L)
				vm.GetField(L, 6, "filename")
				if vm.IsString(L, -1) && vm.ArgString(L, -1) != "" {filename = vm.ArgString(L, -1)}
				vm.Pop(L)
			}
			if filename == "" {
				ext := "png"
				if index := strings.last_index_byte(mime, '/'); index >= 0 {ext = mime[index + 1:]}
				filename = strings.concatenate({shortcode, ".", ext}, context.temp_allocator)
			}

			path := strings.concatenate(
				{"/spaces/", kinemium_url_encode(room_id), "/emojis"},
				context.temp_allocator,
			)
			parts := [2]Kinemium_Multipart_Part {
				{name = "shortcode", value = shortcode},
				{name = file_field, filename = filename, content_type = mime, value = contents},
			}
			return kinemium_multipart_call(L, &service.service, 2, "POST", path, parts[:]), true
		}

	case "DeleteSpaceEmoji":
		{
			path := strings.concatenate(
				{
					"/spaces/",
					kinemium_url_encode(vm.ArgString(L, 3)),
					"/emojis/",
					kinemium_url_encode(vm.ArgString(L, 4)),
				},
				context.temp_allocator,
			)
			return kinemium_domain_call(
					L,
					&service.service,
					2,
					"DELETE",
					path,
					kinemium_options_empty(),
				),
				true
		}
	}
	return 0, false
}

space_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^SpaceService)object)
}

Register_SpaceService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&SpaceService_Class,
		space_service_construct,
		space_service_destroy,
		creatable = false,
		get = space_service_get,
		namecall = space_service_namecall,
	)
}
