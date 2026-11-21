package services


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
	switch key {
	case "CreateImage",
	     "CreateImageAsync",
	     "CreateEditableImage",
	     "CreateEditableMesh",
	     "CreateEditableSound":
	case:
		return false
	}
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
	image_class := "Image"
	source_uri := ""
	source_owned := false
	defer if source_owned {delete(source_uri)}
	switch method {
	case "CreateEditableSound":
		rate, channels, frames: f64 = 44100, 1, 1
		if !vm.IsNoneOrNil(L, 2) {
			if !vm.IsTable(L, 2) {return vm.RaiseError(L, "expected sound options"), true}
			vm.GetField(L, 2, "SampleRate")
			if !vm.IsNil(L, -1) {rate = vm.ArgNumber(L, -1)}
			vm.Pop(L)
			vm.GetField(L, 2, "Channels")
			if !vm.IsNil(L, -1) {channels = vm.ArgNumber(L, -1)}
			vm.Pop(L)
			vm.GetField(L, 2, "FrameCount")
			if !vm.IsNil(L, -1) {frames = vm.ArgNumber(L, -1)}
			vm.Pop(L)
		}
		if !classes.EditableSound_Valid_Format(
			rate,
			channels,
			frames,
		) {return vm.RaiseError(L, "invalid EditableSound format or frame count"), true}
		created, ok := classes.Push_New(object.signal_registry, &vm.VM{L = L}, "EditableSound")
		if !ok {return vm.RaiseError(L, "could not create EditableSound"), true}
		classes.EditableSound_Resize(
			cast(^classes.EditableSound)created,
			int(rate),
			int(channels),
			int(frames),
		)
		return 1, true
	case "CreateEditableMesh":
		if !vm.IsNoneOrNil(L, 2) &&
		   !vm.IsTable(L, 2) {return vm.RaiseError(L, "expected mesh options"), true}
		_, ok := classes.Push_New(object.signal_registry, &vm.VM{L = L}, "EditableMesh")
		if !ok {return vm.RaiseError(L, "could not create EditableMesh"), true}
		return 1, true
	case "CreateImage", "CreateEditableImage":
		if method == "CreateEditableImage" {image_class = "EditableImage"}
		if !vm.IsNoneOrNil(L, 2) {
			if !vm.IsTable(L, 2) {return vm.RaiseError(L, "expected image options"), true}
			vm.GetField(L, 2, "Size")
			if !vm.IsNil(L, -1) {
				size := datatypes.Arg_Vector2(L, -1, dt)
				if !asset_service_valid_image_size(size) {
					return vm.RaiseError(L, "invalid Image size"), true
				}
				width, height = c.int(size.X), c.int(size.Y)
			}
			vm.Pop(L)
			vm.GetField(L, 2, "Source")
			if !vm.IsNoneOrNil(L, -1) {
				if dt != nil && vm.IsUserdataType(L, -1, &dt.content) {
					source_uri = datatypes.Arg_Content(L, -1, dt).uri
				} else {
					source_uri = vm.ArgString(L, -1)
				}
			}
			vm.Pop(L)
			vm.GetField(L, 2, "Buffer")
			if !vm.IsNoneOrNil(L, -1) {
				buffer, found := vm.ToBuffer(L, -1)
				if !found || len(buffer) == 0 || len(buffer) > 64 * 1024 * 1024 {
					return vm.RaiseError(L, "expected a nonempty image buffer"), true
				}
				if datatypes.Animated_Format(buffer) != "" {
					animated, ok := datatypes.Animated_From_Bytes(buffer)
					if !ok {return vm.RaiseError(L, "could not register animated Image"), true}
					source_uri = animated.uri
					source_owned = true
					if method == "CreateImage" {image_class = "Animated"}
				} else {
					channels: c.int
					if stb.info_from_memory(
						   raw_data(buffer),
						   c.int(len(buffer)),
						   &width,
						   &height,
						   &channels,
					   ) ==
						   0 ||
					   !asset_service_valid_image_size({f32(width), f32(height)}) {
						return vm.RaiseError(L, "image buffer is invalid or too large"), true
					}
					decoded = stb.load_from_memory(
						raw_data(buffer),
						c.int(len(buffer)),
						&width,
						&height,
						&channels,
						4,
					)
					if decoded ==
					   nil {return vm.RaiseError(L, "could not decode image buffer"), true}
				}
			}
			vm.Pop(L)
		}
	case "CreateImageAsync":
		uri: string
		if dt != nil && vm.IsUserdataType(L, 2, &dt.content) {
			uri = datatypes.Arg_Content(L, 2, dt).uri
		} else {
			uri = vm.ArgString(L, 2)
		}
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
		if datatypes.Animated_Format(bytes) != "" {
			source_uri = uri
			image_class = "Animated"
			break
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
	image_object, ok := classes.Push_New(object.signal_registry, &vm.VM{L = L}, image_class)
	if !ok {
		if decoded != nil {stb.image_free(decoded)}
		return vm.RaiseError(L, "could not create Image"), true
	}
	image := cast(^classes.EditableImage)image_object
	classes.EditableImage_Resize(image, int(width), int(height))
	if source_uri != "" {classes.Image_Set_Source(image, source_uri)}
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
		methods = []string {
			"CreateImage",
			"CreateImageAsync",
			"CreateEditableImage",
			"CreateEditableMesh",
			"CreateEditableSound",
		},
	)
}
