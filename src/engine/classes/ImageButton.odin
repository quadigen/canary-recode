package classes

import assetstore "../assetstore"
import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

ImageButton_Class := Class_Info {
	name   = "ImageButton",
	parent = &GuiButton_Class,
}

ImageButton :: struct {
	using gui_button:   GuiButton,
	image:              string,
	owned_image:        string,
	stored_image:       ^kineffi.KineSkiaImage,
	icon_pack_revision: u64,
	aseprite_playback:  ^Aseprite_Image_Playback,
	animated_source:    bool,
	source_image:       ^EditableImage,
	image_transparency: f32,
	image_color3:       datatypes.Color3,
	image_rect_offset:  datatypes.Vector2,
	image_rect_size:    datatypes.Vector2,
	resample_mode:      enums.ResampleMode,
	scale_type:         enums.ScaleType,
	slice_center:       datatypes.Rect,
	slice_scale:        f32,
	tile_size:          datatypes.UDim2,
}

ImageButton_Init :: proc() -> ImageButton {
	button := GuiButton_Init()
	button.object.class = &ImageButton_Class

	return ImageButton {
		gui_button = button,
		image = "",
		owned_image = "",
		stored_image = nil,
		image_transparency = 0,
		image_color3 = datatypes.Color3{R = 1, G = 1, B = 1},
		image_rect_offset = datatypes.Vector2{X = 0, Y = 0},
		image_rect_size = datatypes.Vector2{X = 0, Y = 0},
		resample_mode = .Default,
		scale_type = .Stretch,
		slice_scale = 1,
		tile_size = datatypes.UDim2{},
	}
}

ImageButton_to_image_label :: proc(button: ^ImageButton) -> ImageLabel {
	return ImageLabel {
		gui_object = button.gui_object,
		image = button.image,
		owned_image = button.owned_image,
		stored_image = button.stored_image,
		icon_pack_revision = button.icon_pack_revision,
		aseprite_playback = button.aseprite_playback,
		animated_source = button.animated_source,
		editable_image = button.source_image,
		image_transparency = button.image_transparency,
		image_color3 = button.image_color3,
		image_rect_offset = button.image_rect_offset,
		image_rect_size = button.image_rect_size,
		resample_mode = button.resample_mode,
		scale_type = button.scale_type,
		slice_center = button.slice_center,
		slice_scale = button.slice_scale,
		tile_size = button.tile_size,
	}
}

ImageButton_sync_image_label :: proc(button: ^ImageButton, label: ^ImageLabel) {
	button.image = label.image

	button.owned_image = label.owned_image

	button.stored_image = label.stored_image
	button.icon_pack_revision = label.icon_pack_revision
	button.aseprite_playback = label.aseprite_playback
	button.animated_source = label.animated_source

	button.image_transparency = label.image_transparency

	button.image_color3 = label.image_color3

	button.image_rect_offset = label.image_rect_offset

	button.image_rect_size = label.image_rect_size

	button.resample_mode = label.resample_mode

	button.scale_type = label.scale_type
	button.slice_center = label.slice_center
	button.slice_scale = label.slice_scale

	button.tile_size = label.tile_size
}

ImageButton_is_image_property :: proc(key: string) -> bool {
	switch key {
	case "Image",
	     "ImageContent",
	     "IsLoaded",
	     "ImageTransparency",
	     "ImageColor3",
	     "ImageRectOffset",
	     "ImageRectSize",
	     "ResampleMode",
	     "ScaleType",
	     "SliceCenter",
	     "SliceScale",
	     "TileSize":
		return true
	}

	return false
}

ImageButton_Unbind_Image :: proc(button: ^ImageButton) {
	if button == nil || button.source_image == nil {return}
	source := button.source_image
	for i := 0; i < len(source.attached_buttons); {
		if source.attached_buttons[i] == button {
			source.attached_buttons[i] = source.attached_buttons[len(source.attached_buttons) - 1]
			resize(&source.attached_buttons, len(source.attached_buttons) - 1)
		} else {
			i += 1
		}
	}
	button.source_image = nil
}

ImageButton_Refresh_Bound_Image :: proc(button: ^ImageButton) {
	if button == nil {return}
	label := ImageButton_to_image_label(button)
	ImageLabel_Destroy_Stored_Image(&label)
	delete(label.owned_image)
	label.owned_image = ""
	label.image = ""
	if button.source_image != nil && button.source_image.source != "" {
		label.owned_image = assetstore.Resolve_Ugc_Asset(button.source_image.source, .Texture)
		label.image = label.owned_image
		ImageLabel_Load_Image(&label, label.image)
	}
	ImageButton_sync_image_label(button, &label)
	gui_invalidate_draw(&button.object)
	surfacegui_mark_dirty_for(&button.object)
	Gui_Render_Mark_Dirty()
}

ImageButton_Bind_Image :: proc(button: ^ImageButton, source: ^EditableImage) {
	if button == nil || button.source_image == source {return}
	ImageButton_Unbind_Image(button)
	button.source_image = source
	if source != nil {append(&source.attached_buttons, button)}
	ImageButton_Refresh_Bound_Image(button)
}

ImageButton_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	button := new(ImageButton)

	button^ = ImageButton_Init()

	button.name = "ImageButton"

	return &button.object
}

ImageButton_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	button := cast(^ImageButton)object
	ImageButton_Unbind_Image(button)

	label := ImageButton_to_image_label(button)

	ImageLabel_Destroy_Stored_Image(&label)

	GuiButton_Free_Signals(cast(^GuiButton)object)

	button.stored_image = nil

	delete(button.owned_image)

	button.owned_image = ""

	button.image = ""

	Object_Destroy(object)

	free(button)
}

ImageButton_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	button := cast(^ImageButton)object

	if ImageButton_is_image_property(key) {
		label := ImageButton_to_image_label(button)

		return ImageLabel_get(L, &label.object, datatype_registry, enum_registry, key)
	}

	return GuiButton_get(L, object, datatype_registry, enum_registry, key)
}

ImageButton_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	button := cast(^ImageButton)object

	if ImageButton_is_image_property(key) {
		if key == "Image" {
			if source := Object_From_Argument(L, value_index); source != nil {
				if !Is_A_Class(source, &EditableImage_Class) {
					_ = vm.RaiseError(L, "expected an Image instance or an image URI")
					return true
				}
				ImageButton_Bind_Image(button, cast(^EditableImage)source)
				return true
			}
		}
		if key == "Image" || key == "ImageContent" {
			is_content :=
				datatype_registry != nil &&
				vm.IsUserdataType(L, value_index, &datatype_registry.content)
			if !is_content {
				if key == "ImageContent" {
					_ = vm.RaiseError(L, "expected Content")
					return true
				}
				_ = vm.ArgString(L, value_index)
			}
			ImageButton_Unbind_Image(button)
		}
		label := ImageButton_to_image_label(button)

		result := ImageLabel_set(
			L,
			&label.object,
			datatype_registry,
			enum_registry,
			key,
			value_index,
		)

		ImageButton_sync_image_label(button, &label)

		return result
	}

	return GuiButton_set(L, object, datatype_registry, enum_registry, key, value_index)
}

ImageButton_render :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	if !GuiButton_update(object, ctx) {
		return
	}

	button := cast(^ImageButton)object

	label := ImageButton_to_image_label(button)

	if button.auto_button_color {
		#partial switch button.gui_state {
		case .Hover:
			label.bg_color.R = clamp(label.bg_color.R * 1.08, 0, 1)

			label.bg_color.G = clamp(label.bg_color.G * 1.08, 0, 1)

			label.bg_color.B = clamp(label.bg_color.B * 1.08, 0, 1)

		case .Press:
			label.bg_color.R *= 0.82
			label.bg_color.G *= 0.82
			label.bg_color.B *= 0.82

		case:
		}
	}

	ImageLabel_render(&label.object, ctx)
	button.stored_image = label.stored_image
	button.icon_pack_revision = label.icon_pack_revision
	button.aseprite_playback = label.aseprite_playback
	button.animated_source = label.animated_source
}

ImageButton_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^ImageButton)source

	dst := cast(^ImageButton)destination

	GuiButton_clone(source, destination)

	src_label := ImageButton_to_image_label(src)

	dst_label := ImageButton_to_image_label(dst)

	src_label.editable_image = nil
	ImageLabel_clone(&src_label.object, &dst_label.object)

	ImageButton_sync_image_label(dst, &dst_label)
	if src.source_image != nil {ImageButton_Bind_Image(dst, src.source_image)}
}

Register_ImageButton :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&ImageButton_Class,
		ImageButton_construct,
		ImageButton_destroy,
		get = ImageButton_get,
		set = ImageButton_set,
		clone = ImageButton_clone,
		properties = []string {
			"Image",
			"ImageContent",
			"IsLoaded",
			"ImageTransparency",
			"ImageColor3",
			"ImageRectOffset",
			"ImageRectSize",
			"ResampleMode",
			"ScaleType",
			"SliceCenter",
			"SliceScale",
			"TileSize",
		},
	)
}
