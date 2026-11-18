package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

EDITABLE_IMAGE_MAX_SIZE :: 1024

EditableImage_Class := Class_Info {
	name   = "EditableImage",
	parent = &Instance_Class,
}

EditableImage :: struct {
	using object:    Object,
	width, height:   int,
	pixels:          []u8,
	attached_labels: [dynamic]^ImageLabel,
}

EditableImage_Resize :: proc(image: ^EditableImage, width, height: int) {
	if image.width == width && image.height == height {return}
	delete(image.pixels)
	image.width, image.height = width, height
	image.pixels = make([]u8, width * height * 4)
}

editable_image_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	image := new(EditableImage)
	image.object = Object_Init(&EditableImage_Class, "EditableImage")
	EditableImage_Resize(image, 1, 1)
	return &image.object
}

editable_image_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	image := cast(^EditableImage)object
	for label in image.attached_labels {
		if label != nil && label.editable_image == image {
			label.editable_image = nil
		}
	}
	delete(image.attached_labels)
	delete(image.pixels)
	Object_Destroy(object)
	free(image)
}

editable_image_get :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	image := cast(^EditableImage)object
	switch key {
	case "Size":
		datatypes.Push_Vector2(L, dt, {f32(image.width), f32(image.height)})
	case "ReadPixelsBuffer", "WritePixelsBuffer":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

editable_image_set :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	if key != "Size" {return false}
	size := datatypes.Arg_Vector2(L, index, dt)
	if !(size.X >= 1 &&
		   size.Y >= 1 &&
		   size.X <= EDITABLE_IMAGE_MAX_SIZE &&
		   size.Y <= EDITABLE_IMAGE_MAX_SIZE) {
		_ = vm.RaiseError(L, "invalid EditableImage size")
		return true
	}
	EditableImage_Resize(cast(^EditableImage)object, int(size.X), int(size.Y))
	return true
}

editable_image_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "ReadPixelsBuffer" && method != "WritePixelsBuffer" {return 0, false}
	image := cast(^EditableImage)object
	position := datatypes.Arg_Vector2(L, 2, dt)
	size := datatypes.Arg_Vector2(L, 3, dt)
	if !(position.X >= 0 &&
		   position.Y >= 0 &&
		   size.X >= 1 &&
		   size.Y >= 1 &&
		   position.X + size.X <= f32(image.width) &&
		   position.Y + size.Y <= f32(image.height)) {
		return vm.RaiseError(L, "pixel region is outside the image"), true
	}
	x, y, width, height := int(position.X), int(position.Y), int(size.X), int(size.Y)
	if position.X != f32(x) ||
	   position.Y != f32(y) ||
	   size.X != f32(width) ||
	   size.Y != f32(height) {
		return vm.RaiseError(L, "pixel regions must use whole numbers"), true
	}
	row_bytes := width * 4
	write := method == "WritePixelsBuffer"
	pixels: []u8
	if write {
		pixels = vm.ArgBuffer(L, 4)
		if len(pixels) != row_bytes * height {
			return vm.RaiseError(L, "incorrect pixel buffer size"), true
		}
	} else {
		pixels = make([]u8, row_bytes * height, context.temp_allocator)
	}
	for row in 0 ..< height {
		offset := ((y + row) * image.width + x) * 4
		image_row := image.pixels[offset:offset + row_bytes]
		buffer_row := pixels[row * row_bytes:(row + 1) * row_bytes]
		if write {copy(image_row, buffer_row)} else {copy(buffer_row, image_row)}
	}
	if write {return 0, true}
	vm.PushBuffer(L, pixels)
	delete(pixels, context.temp_allocator)
	return 1, true
}

Register_EditableImage :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&EditableImage_Class,
		editable_image_construct,
		editable_image_destroy,
		get = editable_image_get,
		set = editable_image_set,
		namecall = editable_image_namecall,
		properties = []string{"Size"},
		methods = []string{"ReadPixelsBuffer", "WritePixelsBuffer"},
	)
}
