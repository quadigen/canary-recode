package services

// wire:service

import "core:c"
import "core:strings"
import stb "vendor:stb/image"

import assetstore "../assetstore"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

AssetService_Class := classes.Class_Info {
	name   = "AssetService",
	parent = &Service_Class,
}

asset_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Service)
	service^ = Service_Init(&AssetService_Class, "AssetService", data_model)
	return &service.object
}

asset_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Service)object)
}

asset_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	if key != "CreateEditableImage" && key != "CreateEditableImageAsync" {return false}
	vm.PushUserdataMethod(L, key)
	return true
}

asset_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	width, height: c.int = 1, 1
	decoded: [^]u8
	switch method {
	case "CreateEditableImage":
		if !vm.IsNoneOrNil(L, 2) {
			if !vm.IsTable(L, 2) {return vm.RaiseError(L, "expected image options"), true}
			vm.GetField(L, 2, "Size")
			if !vm.IsNil(L, -1) {
				size := datatypes.Arg_Vector2(L, -1, dt)
				if !asset_service_valid_image_size(
					size,
				) {return vm.RaiseError(L, "invalid EditableImage size"), true}
				width, height = c.int(size.X), c.int(size.Y)
			}
			vm.Pop(L)
		}
	case "CreateEditableImageAsync":
		uri := datatypes.Arg_Content(L, 2, dt).uri
		bytes, found := assetstore.Resolve_Bytes(uri)
		if !found {
			if runtime_image, ok := classes.ImageLabel_Find_Runtime_Image(uri); ok {
				bytes = transmute([]u8)runtime_image
			} else if strings.has_prefix(uri, assetstore.PROJECT_ASSET_SCHEME) {
				path := assetstore.Resolve_Path(uri)
				defer delete(path)
				bytes, _ = assetstore.Read_Asset_File(path)
			}
		}
		channels: c.int
		if len(bytes) == 0 ||
		   len(bytes) > 64 * 1024 * 1024 ||
		   stb.info_from_memory(raw_data(bytes), c.int(len(bytes)), &width, &height, &channels) ==
			   0 ||
		   !asset_service_valid_image_size({f32(width), f32(height)}) {
			return vm.RaiseError(
					L,
					"image is unavailable or exceeds the editable image size limit",
				),
				true
		}
		decoded = stb.load_from_memory(
			raw_data(bytes),
			c.int(len(bytes)),
			&width,
			&height,
			&channels,
			4,
		)
		if decoded == nil {return vm.RaiseError(L, "could not decode editable image"), true}
	case:
		return 0, false
	}
	image_object, ok := classes.Push_New(object.signal_registry, &vm.VM{L = L}, "EditableImage")
	if !ok {
		if decoded != nil {stb.image_free(decoded)}
		return vm.RaiseError(L, "could not create EditableImage"), true
	}
	image := cast(^classes.EditableImage)image_object
	classes.EditableImage_Resize(image, int(width), int(height))
	if decoded != nil {
		copy(image.pixels, decoded[:len(image.pixels)])
		stb.image_free(decoded)
	}
	return 1, true
}

asset_service_valid_image_size :: proc(size: datatypes.Vector2) -> bool {
	return(
		size.X >= 1 &&
		size.X <= classes.EDITABLE_IMAGE_MAX_SIZE &&
		size.Y >= 1 &&
		size.Y <= classes.EDITABLE_IMAGE_MAX_SIZE \
	)
}

Register_AssetService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&AssetService_Class,
		asset_service_construct,
		asset_service_destroy,
		creatable = false,
		get = asset_service_get,
		namecall = asset_service_namecall,
		methods = []string{"CreateEditableImage", "CreateEditableImageAsync"},
	)
}
