package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"
import "core:strings"

EDITABLE_IMAGE_MAX_SIZE :: 1024

EditableImage_Class := Class_Info {
	name   = "Image",
	parent = &Instance_Class,
}

EditableImage_Instance_Class := Class_Info {
	name   = "EditableImage",
	parent = &EditableImage_Class,
}
Animated_Image_Class := Class_Info {
	name   = "Animated",
	parent = &EditableImage_Class,
}

EditableImage :: struct {
	using object:     Object,
	width, height:    int,
	pixels:           []u8,
	source:           string,
	attached_labels:  [dynamic]^ImageLabel,
	attached_buttons: [dynamic]^ImageButton,
}

EditableImage_Resize :: proc(image: ^EditableImage, width, height: int) {
	if image.width == width && image.height == height {return}
	delete(image.pixels)
	image.width, image.height = width, height
	image.pixels = make([]u8, width * height * 4)
}

editable_image_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return editable_image_construct_class(&EditableImage_Class, renderer, data_model)
}

editable_image_construct_class :: proc(
	class_context: rawptr,
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	class := cast(^Class_Info)class_context
	image := new(EditableImage)
	image.object = Object_Init(class, class.name)
	EditableImage_Resize(image, 1, 1)
	return &image.object
}

editable_image_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^EditableImage)source, cast(^EditableImage)destination
	EditableImage_Resize(dst, src.width, src.height)
	copy(dst.pixels, src.pixels)
	Image_Set_Source(dst, src.source)
}

editable_image_detach_consumers :: proc(image: ^EditableImage) {
	for label in image.attached_labels {
		if label != nil && label.editable_image == image {
			label.editable_image = nil
			ImageLabel_Set_Image(label, "")
			gui_invalidate_draw(&label.object)
			surfacegui_mark_dirty_for(&label.object)
			Gui_Render_Mark_Dirty()
		}
	}
	clear(&image.attached_labels)
	for button in image.attached_buttons {
		if button != nil && button.source_image == image {
			button.source_image = nil
			ImageButton_Refresh_Bound_Image(button)
		}
	}
	clear(&image.attached_buttons)
}

editable_image_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	image := cast(^EditableImage)object
	editable_image_detach_consumers(image)
	delete(image.attached_labels)
	delete(image.attached_buttons)
	delete(image.source)
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
	case "Source":
		vm.PushString(L, image.source)
	case "ReadPixelsBuffer",
	     "WritePixelsBuffer",
	     "DrawRectangle",
	     "DrawCircle",
	     "DrawLine",
	     "DrawImage":
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
	if key == "Source" {
		Image_Set_Source(cast(^EditableImage)object, vm.ArgString(L, index))
		return true
	}
	if key != "Size" {return false}
	size := datatypes.Arg_Vector2(L, index, dt)
	if !(size.X >= 1 &&
		   size.Y >= 1 &&
		   size.X <= EDITABLE_IMAGE_MAX_SIZE &&
		   size.Y <= EDITABLE_IMAGE_MAX_SIZE) {
		_ = vm.RaiseError(L, "invalid Image size")
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
	switch method {
	case "DrawRectangle", "DrawCircle", "DrawLine", "DrawImage":
		return editable_image_draw(L, cast(^EditableImage)object, dt, en, method), true
	case "ReadPixelsBuffer", "WritePixelsBuffer":
	case:
		return 0, false
	}
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

editable_image_byte :: proc(v: f32) -> u8 {
	return u8(math.round(clamp(v, 0, 1) * 255))
}

editable_image_combine :: proc(
	image: ^EditableImage,
	x, y: int,
	source: [4]f32,
	coverage: f32,
	mode: enums.ImageCombineType,
	alpha_mode: enums.ImageAlphaType,
) {
	if coverage <= 0 || x < 0 || y < 0 || x >= image.width || y >= image.height {return}
	i := (y * image.width + x) * 4
	dest: [4]f32
	for j in 0 ..< 4 {dest[j] = f32(image.pixels[i + j]) / 255}
	output := source
	if mode == .Overwrite {
		for j in 0 ..< 4 {output[j] = dest[j] + (source[j] - dest[j]) * coverage}
	} else {
		alpha := source[3] * coverage
		oa := alpha + dest[3] * (1 - alpha)
		output[3] = oa
		for j in 0 ..< 3 {
			blend := source[j]
			#partial switch mode {
			case .Add:
				blend = min(1, dest[j] + source[j])
			case .Multiply:
				blend = dest[j] * source[j]
			}
			if oa > 0 {
				output[j] =
					(source[j] * alpha * (1 - dest[3]) +
						blend * alpha * dest[3] +
						dest[j] * dest[3] * (1 - alpha)) /
					oa
			} else {output[j] = 0}
		}
	}
	if alpha_mode == .LockCanvasAlpha {output[3] = dest[3]}
	if alpha_mode == .LockCanvasColor {
		for j in 0 ..< 3 {output[j] = dest[j]}
	}
	for j in 0 ..< 4 {image.pixels[i + j] = editable_image_byte(output[j])}
}

editable_image_finite :: proc(v: f32) -> bool {return v == v && abs(v) < 1.0e9}

editable_image_draw :: proc(
	L: ^vm.State,
	image: ^EditableImage,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> i32 {
	p := datatypes.Arg_Vector2(L, 2, dt)
	if !editable_image_finite(p.X) ||
	   !editable_image_finite(p.Y) {return vm.RaiseError(L, "invalid draw position")}
	mode := enums.ImageCombineType.Overwrite
	alpha_mode := enums.ImageAlphaType.Default
	if method == "DrawImage" {
		input := Object_From_Argument(L, 3)
		if input == nil || !Is_A(input, "Image") {return vm.RaiseError(L, "expected Image")}
		src := cast(^EditableImage)input
		mode = .AlphaBlend
		if !vm.IsNoneOrNil(
			L,
			4,
		) {mode = enums.ImageCombineType(enums.Arg_Item(L, 4, en, "ImageCombineType").value)}
		if !vm.IsNoneOrNil(
			L,
			5,
		) {alpha_mode = enums.ImageAlphaType(enums.Arg_Item(L, 5, en, "ImageAlphaType").value)}

		pixels := src.pixels
		if src == image {
			pixels = make([]u8, len(src.pixels))
			copy(pixels, src.pixels)
		}
		defer if src == image {delete(pixels)}
		for y in 0 ..< src.height {
			for x in 0 ..< src.width {
				i := (y * src.width + x) * 4
				rgba: [4]f32
				for j in 0 ..< 4 {rgba[j] = f32(pixels[i + j]) / 255}
				editable_image_combine(
					image,
					int(p.X) + x,
					int(p.Y) + y,
					rgba,
					1,
					mode,
					alpha_mode,
				)
			}
		}
		return 0
	}
	q: datatypes.Vector2
	radius: f32
	if method == "DrawCircle" {
		radius = f32(vm.ArgNumber(L, 3))
		if !editable_image_finite(radius) ||
		   radius < 0 {return vm.RaiseError(L, "invalid circle radius")}
	} else {
		q = datatypes.Arg_Vector2(L, 3, dt)
		if !editable_image_finite(q.X) ||
		   !editable_image_finite(q.Y) {return vm.RaiseError(L, "invalid draw geometry")}
		if method == "DrawRectangle" &&
		   (q.X < 0 || q.Y < 0) {return vm.RaiseError(L, "invalid rectangle size")}
	}
	color := datatypes.Arg_Color3(L, 4, dt)
	transparency := f32(vm.ArgOptionalNumber(L, 5, 0))
	if !editable_image_finite(transparency) {return vm.RaiseError(L, "invalid transparency")}
	rgba := [4]f32{color.R, color.G, color.B, 1 - clamp(transparency, 0, 1)}
	if !vm.IsNoneOrNil(
		L,
		6,
	) {mode = enums.ImageCombineType(enums.Arg_Item(L, 6, en, "ImageCombineType").value)}
	aa := method != "DrawRectangle"
	alpha_arg := 7
	if aa {
		if !vm.IsNoneOrNil(
			L,
			7,
		) {aa = enums.AntiAliasing(enums.Arg_Item(L, 7, en, "AntiAliasing").value) == .Enabled}
		alpha_arg = 8
	}
	if !vm.IsNoneOrNil(
		L,
		alpha_arg,
	) {alpha_mode = enums.ImageAlphaType(enums.Arg_Item(L, alpha_arg, en, "ImageAlphaType").value)}
	x0, y0, x1, y1: f32
	switch method {
	case "DrawRectangle":
		x0, y0, x1, y1 = p.X, p.Y, p.X + q.X, p.Y + q.Y
	case "DrawCircle":
		x0, y0, x1, y1 = p.X - radius - 1, p.Y - radius - 1, p.X + radius + 1, p.Y + radius + 1
	case "DrawLine":
		x0, y0, x1, y1 = min(p.X, q.X) - 1, min(p.Y, q.Y) - 1, max(p.X, q.X) + 1, max(p.Y, q.Y) + 1
	}
	for y in int(clamp(math.floor(y0), 0, f32(image.height))) ..< int(clamp(math.ceil(y1) + 1, 0, f32(image.height))) {
		for x in int(clamp(math.floor(x0), 0, f32(image.width))) ..< int(clamp(math.ceil(x1) + 1, 0, f32(image.width))) {
			coverage: f32
			if method == "DrawRectangle" {
				coverage =
					1 if f32(x) >= p.X && f32(x) < p.X + q.X && f32(y) >= p.Y && f32(y) < p.Y + q.Y else 0
			} else {
				dx, dy := f32(x) - p.X, f32(y) - p.Y
				distance: f32
				if method == "DrawCircle" {
					distance = math.sqrt(dx * dx + dy * dy) - radius
				} else {
					vx, vy := q.X - p.X, q.Y - p.Y
					length := vx * vx + vy * vy
					t: f32
					if length > 0 {t = clamp((dx * vx + dy * vy) / length, 0, 1)}
					dx, dy = dx - t * vx, dy - t * vy
					distance = math.sqrt(dx * dx + dy * dy) - 0.5
				}
				coverage = clamp(0.5 - distance, 0, 1) if aa else (1 if distance <= 0 else 0)
			}
			editable_image_combine(image, x, y, rgba, coverage, mode, alpha_mode)
		}
	}
	return 0
}

Image_Set_Source :: proc(image: ^EditableImage, uri: string) {
	if image == nil || image.source == uri {return}
	value := strings.clone(uri)
	delete(image.source)
	image.source = value
	for label in image.attached_labels {
		if label != nil && label.editable_image == image {
			ImageLabel_Refresh_Bound_Image(label)
		}
	}
	for button in image.attached_buttons {
		if button != nil && button.source_image == image {
			ImageButton_Refresh_Bound_Image(button)
		}
	}
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
		clone = editable_image_clone,
		properties = []string{"Size", "Source"},
		methods = []string {
			"ReadPixelsBuffer",
			"WritePixelsBuffer",
			"DrawRectangle",
			"DrawCircle",
			"DrawLine",
			"DrawImage",
		},
	)
	image_classes := [?]^Class_Info{&EditableImage_Instance_Class, &Animated_Image_Class}
	for class in image_classes {
		Register_Class(
			registry,
			class,
			editable_image_construct,
			editable_image_destroy,
			get = editable_image_get,
			set = editable_image_set,
			namecall = editable_image_namecall,
			construct_with_ctx = editable_image_construct_class,
			construct_ctx = class,
		)
	}
}
