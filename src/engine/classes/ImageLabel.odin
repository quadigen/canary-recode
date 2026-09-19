package classes

import "core:fmt"
import "core:c"
import strings "core:strings"

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import kineffi "../bindings"
import guilib "../gui"

IMAGE_LABEL_CLASS_ICONS :=
	#load_directory("../assets/images/icons")

IMAGE_LABEL_GLOBAL_ICONS :=
	#load_directory("../assets/images/")


BUILTIN_ICON_PREFIX :: "builtin://icons/"
BUILTIN_GLOBAL_ICON_PREFIX :: "builtin://global-icons/"
RUNTIME_IMAGE_PREFIX :: "memory://"

Runtime_Image_Asset :: struct {
	id:   string,
	data: string,
}

runtime_image_assets: [dynamic]Runtime_Image_Asset

ImageLabel_Class := Class_Info{
	name   = "ImageLabel",
	parent = &GuiObject_Class,
}


ImageLabel :: struct {
	using gui_object: GuiObject,

	image:       string,
	owned_image: string,

	stored_image: ^kineffi.KineSkiaImage,

	image_transparency: f32,
}


ImageLabel_Init :: proc() -> ImageLabel {
	gui := GuiObject_Init()

	gui.object.class = &ImageLabel_Class

	return ImageLabel{
		gui_object = gui,

		image = "",
		owned_image = "",

		stored_image = nil,

		image_transparency = 0,
	}
}

ImageLabel_Find_Class_Icon :: proc(
	name: string,
) -> ([]u8, bool) {
	for file in IMAGE_LABEL_CLASS_ICONS {
		if file.name == name {
			return file.data, true
		}
	}

	return nil, false
}

ImageLabel_Find_Global_Icon :: proc(
	name: string,
) -> ([]u8, bool) {
	for file in IMAGE_LABEL_GLOBAL_ICONS {
		if file.name == name {
			return file.data, true
		}
	}

	return nil, false
}

ImageLabel_Resolve_Builtin_Image :: proc(
	path: string,
) -> ([]u8, bool) {
	if strings.has_prefix(
		path,
		BUILTIN_ICON_PREFIX,
	) {
		name := path[len(BUILTIN_ICON_PREFIX):]

		return ImageLabel_Find_Class_Icon(
			name,
		)
	}

	if strings.has_prefix(
		path,
		BUILTIN_GLOBAL_ICON_PREFIX,
	) {
		name :=
			path[len(BUILTIN_GLOBAL_ICON_PREFIX):]

		return ImageLabel_Find_Global_Icon(
			name,
		)
	}

	return nil, false
}

ImageLabel_Destroy_Stored_Image :: proc(
	image_label: ^ImageLabel,
) {
	if image_label == nil {
		return
	}

	if image_label.stored_image != nil {
		kineffi.Kine_Skia_Image_Destroy(
			image_label.stored_image,
		)

		image_label.stored_image = nil
	}
}


ImageLabel_Load_Image :: proc(
	image_label: ^ImageLabel,
	path: string,
) {
	if image_label == nil {
		return
	}

	ImageLabel_Destroy_Stored_Image(
		image_label,
	)

	if len(path) == 0 {
		return
	}

	//
	// Built-in image.
	//
	// Examples:
	//
	// builtin://icons/Part.svg
	// builtin://global-icons/ArrowDown.svg
	//

	if strings.has_prefix(
		path,
		"builtin://",
	) {
		data, found :=
			ImageLabel_Resolve_Builtin_Image(
				path,
			)

		if !found || len(data) == 0 {
			return
		}

        image_label.stored_image =
            kineffi.Kine_Skia_Image_LoadFromMemory(
                &data[0],
                uintptr(len(data)),
            )

		return
	}

	//
	// Load from memory
	//

	if strings.has_prefix(path, RUNTIME_IMAGE_PREFIX) {
		data, found := ImageLabel_Find_Runtime_Image(path)

		if !found || len(data) == 0 {
			return
		}

		image_label.stored_image =
			kineffi.Kine_Skia_Image_LoadFromMemory(
				raw_data(data),
				uintptr(len(data)),
			)

		return
	}

	//
	// Normal filesystem image.
	//

	cpath :=
		strings.clone_to_cstring(
			path,
		)

	image_label.stored_image =
		kineffi.Kine_Skia_Image_LoadFromFile(
			cpath,
		)

	delete(cpath)
}


ImageLabel_Set_Image :: proc(
	image_label: ^ImageLabel,
	path: string,
) {
	if image_label == nil {
		return
	}

	//
	// Don't reload the exact same image.
	//

	if image_label.image == path {
		return
	}

	//
	// Copy property string.
	//

	copy := strings.clone(
		path,
	)

	delete(
		image_label.owned_image,
	)

	image_label.owned_image =
		copy

	image_label.image =
		image_label.owned_image

	//
	// Decode it.
	//

	ImageLabel_Load_Image(
		image_label,
		image_label.image,
	)
}


//
// Instance
//

ImageLabel_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	image_label :=
		new(ImageLabel)

	image_label^ =
		ImageLabel_Init()

	image_label.name =
		"ImageLabel"

	return &image_label.object
}


ImageLabel_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	image_label :=
		cast(^ImageLabel)object

	ImageLabel_Destroy_Stored_Image(
		image_label,
	)

	GuiObject_Free_Signals(cast(^GuiObject)object)

	delete(
		image_label.owned_image,
	)

	image_label.owned_image =
		""

	image_label.image =
		""

	Object_Destroy(
		object,
	)

	free(
		image_label,
	)
}

ImageLabel_Register_Runtime_Image :: proc(
	id: string,
	data: string,
) -> string {
	for &asset in runtime_image_assets {
		if asset.id == id {
			delete(asset.data)
			asset.data = strings.clone(data)
			return asset.id
		}
	}

	asset := Runtime_Image_Asset{
		id   = strings.clone(id),
		data = strings.clone(data),
	}

	append(&runtime_image_assets, asset)

	return runtime_image_assets[len(runtime_image_assets)-1].id
}

ImageLabel_Find_Runtime_Image :: proc(
	id: string,
) -> (string, bool) {
	for &asset in runtime_image_assets {
		if asset.id == id {
			return asset.data, true
		}
	}

	return "", false
}

//
// Properties
//

ImageLabel_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	image_label :=
		cast(^ImageLabel)object

	switch key {

	case "Image":
		vm.PushString(
			L,
			image_label.image,
		)

	case "ImageTransparency":
		vm.PushNumber(
			L,
			f64(
				image_label.image_transparency,
			),
		)

	case:
		return GuiObject_get(
			L,
			object,
			datatype_registry,
			enum_registry,
			key,
		)
	}

	return true
}


ImageLabel_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	image_label :=
		cast(^ImageLabel)object

	switch key {

	case "Image":
		ImageLabel_Set_Image(
			image_label,
			vm.ArgString(
				L,
				value_index,
			),
		)

	case "ImageTransparency":
		image_label.image_transparency =
			clamp(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				0,
				1,
			)

	case:
		return GuiObject_set(
			L,
			object,
			datatype_registry,
			enum_registry,
			key,
			value_index,
		)
	}

	return true
}


//
// Rendering
//

ImageLabel_render :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) {
	rect, visible :=
		GuiObject_get_rect(
			object,
			ctx,
		)

	if !visible {
		return
	}

	image_label :=
		cast(^ImageLabel)object

	image_shadow := false
	should_draw := true
	blur_sigma: f32 = 0
	has_blur := false

	if image_label.stored_image != nil {
		shadow_object :=
			Find_First_Child_Of_Class(
				object,
				"UIShadow",
			)

		blur_filter :=
			Find_First_Child_Of_Class(
				object,
				"BlurImageFilter",
			)

		if shadow_object != nil {
			shadow := cast(^UIShadow)shadow_object

			if shadow.enabled && shadow.showfortext != true {
				short_edge := min(rect.width, rect.height)
				offset_x := shadow.offset.X_Scale*rect.width + shadow.offset.X_Offset
				offset_y := shadow.offset.Y_Scale*rect.height + shadow.offset.Y_Offset
				spread_x := shadow.spread.X_Scale*rect.width + shadow.spread.X_Offset
				spread_y := shadow.spread.Y_Scale*rect.height + shadow.spread.Y_Offset

				params := guilib.ShadowParams{
					offsetX = offset_x,
					offsetY = offset_y,
					blurSigma = max(f32(0), gui_resolve_udim(shadow.blur_radius, short_edge)),
					spread = max(f32(0), (spread_x+spread_y)*0.5),
					color = shadow.color,
					alpha = 1-f32(shadow.transparency),
				}

				guilib.drawImageShadow(
					ctx.renderer.SkiaSurface,
					image_label.stored_image,
					rect,
					params,
				)

				image_shadow = true
			}
		}

		if blur_filter != nil {
			filter := cast(^BlurImageFilter)blur_filter

			if filter.enabled {
				blur_sigma = max(
					f32(0),
					gui_resolve_udim(
						filter.blur_radius,
						min(rect.width, rect.height),
					),
				)

				has_blur = true
			}
		}
	}

	GuiObject_render(
		object,
		ctx,
		image_shadow,
	)

	if image_label.stored_image != nil {
		rect.bgTransparency =
			image_label.image_transparency

		if has_blur {
			guilib.drawImageBlurred(
				ctx.renderer.SkiaSurface,
				image_label.stored_image,
				rect,
				blur_sigma,
			)
		} else {
			guilib.drawImageSized(
				ctx.renderer.SkiaSurface,
				image_label.stored_image,
				rect,
			)
		}
	}
}


//
// Cloning
//

ImageLabel_clone :: proc(
	source: ^Object,
	destination: ^Object,
) {
	src :=
		cast(^ImageLabel)source

	dst :=
		cast(^ImageLabel)destination

	ImageLabel_Destroy_Stored_Image(
		dst,
	)

	delete(
		dst.owned_image,
	)

	dst.owned_image =
		strings.clone(
			src.image,
		)

	dst.image =
		dst.owned_image

	dst.image_transparency =
		src.image_transparency

	ImageLabel_Load_Image(
		dst,
		dst.image,
	)
}


//
// Registration
//

Register_ImageLabel :: proc(
	registry: ^Registry,
) {
	Register_Class(
		registry,
		&ImageLabel_Class,
		ImageLabel_construct,
		ImageLabel_destroy,

		get = ImageLabel_get,
		set = ImageLabel_set,
		clone = ImageLabel_clone,

		properties = []string{
			"Image",
			"ImageTransparency",
		},
	)
}