package classes

import "core:strings"

import datatypes "../datatypes"
import enums "../enum"
import kineffi "../bindings"
import vm "../vm"

TextButton_Class := Class_Info{
	name   = "TextButton",
	parent = &GuiButton_Class,
}

TextButton :: struct {
	using gui_button: GuiButton,

	text:       string,
	owned_text: string,

	font_face: datatypes.Font,

	stored_typeface: ^kineffi.KineSkiaTypeface,

	text_size:         f32,
	text_color3:       datatypes.Color3,
	text_transparency: f32,

	text_stroke_color3:       datatypes.Color3,
	text_stroke_transparency: f32,
	text_stroke_thickness:    f32,

	text_x_alignment: string,
	text_y_alignment: string,

	text_wrapped: bool,
	text_scaled:  bool,

	line_height:  f32,
	text_padding: f32,

	text_bounds: datatypes.Vector2,
}

TextButton_Init :: proc() -> TextButton {
	button := GuiButton_Init()
	button.object.class = &TextButton_Class

	text := strings.clone("Button")

	font := datatypes.Font_New(
		DEFAULT_FONT,
		.Regular,
		.Normal,
	)

	return TextButton{
		gui_button = button,

		text       = text,
		owned_text = text,

		font_face = font,

		stored_typeface = nil,

		text_size = 16,

		text_color3 = datatypes.Color3{
			1,
			1,
			1,
		},

		text_transparency = 0,

		text_stroke_color3 = datatypes.Color3{
			0,
			0,
			0,
		},

		text_stroke_transparency = 1,
		text_stroke_thickness    = 1,

		text_x_alignment = TEXT_X_CENTER,
		text_y_alignment = TEXT_Y_CENTER,

		text_wrapped = false,
		text_scaled  = false,

		line_height  = 1,
		text_padding = 0,

		text_bounds = datatypes.Vector2_Zero,
	}
}

TextButton_to_text_label :: proc(
	button: ^TextButton,
) -> TextLabel {
	return TextLabel{
		gui_object = button.gui_object,

		text       = button.text,
		owned_text = button.owned_text,

		font_face = button.font_face,

		stored_typeface = button.stored_typeface,

		text_size         = button.text_size,
		text_color3       = button.text_color3,
		text_transparency = button.text_transparency,

		text_stroke_color3       = button.text_stroke_color3,
		text_stroke_transparency = button.text_stroke_transparency,
		text_stroke_thickness    = button.text_stroke_thickness,

		text_x_alignment = button.text_x_alignment,
		text_y_alignment = button.text_y_alignment,

		text_wrapped = button.text_wrapped,
		text_scaled  = button.text_scaled,

		line_height  = button.line_height,
		text_padding = button.text_padding,

		text_bounds = button.text_bounds,
	}
}

TextButton_sync_text_label :: proc(
	button: ^TextButton,
	label: ^TextLabel,
) {
	button.text = label.text
	button.owned_text = label.owned_text

	button.font_face = label.font_face

	button.stored_typeface = label.stored_typeface

	button.text_size = label.text_size
	button.text_color3 = label.text_color3
	button.text_transparency = label.text_transparency

	button.text_stroke_color3 = label.text_stroke_color3
	button.text_stroke_transparency = label.text_stroke_transparency
	button.text_stroke_thickness = label.text_stroke_thickness

	button.text_x_alignment = label.text_x_alignment
	button.text_y_alignment = label.text_y_alignment

	button.text_wrapped = label.text_wrapped
	button.text_scaled = label.text_scaled

	button.line_height = label.line_height
	button.text_padding = label.text_padding

	button.text_bounds = label.text_bounds
}

TextButton_is_text_property :: proc(
	key: string,
) -> bool {
	switch key {
	case "Text",
	     "Font",
	     "FontFace",
	     "TextSize",
	     "TextColor3",
	     "TextTransparency",
	     "TextStrokeColor3",
	     "TextStrokeTransparency",
	     "TextStrokeThickness",
	     "TextWrapped",
	     "TextScaled",
	     "TextXAlignment",
	     "TextYAlignment",
	     "LineHeight",
	     "TextPadding",
	     "TextBounds":
		return true
	}

	return false
}

TextButton_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	button := new(TextButton)

	button^ = TextButton_Init()
	button.name = "TextButton"

	label := TextButton_to_text_label(button)

	TextLabel_Load_Typeface(
		&label,
	)

	TextButton_sync_text_label(
		button,
		&label,
	)

	return &button.object
}

TextButton_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	button := cast(^TextButton)object

	label := TextButton_to_text_label(button)

	TextLabel_Destroy_Typeface(
		&label,
	)

	button.stored_typeface = nil

	delete(
		button.owned_text,
	)

	button.owned_text = ""
	button.text = ""

	datatypes.Font_Destroy(
		&button.font_face,
	)

	GuiButton_Free_Signals(cast(^GuiButton)object)

	Object_Destroy(
		object,
	)

	free(
		button,
	)
}

TextButton_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	button := cast(^TextButton)object

	if TextButton_is_text_property(key) {
		label := TextButton_to_text_label(button)

		return TextLabel_get(
			L,
			&label.object,
			datatype_registry,
			enum_registry,
			key,
		)
	}

	return GuiButton_get(
		L,
		object,
		datatype_registry,
		enum_registry,
		key,
	)
}

TextButton_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	button := cast(^TextButton)object

	if TextButton_is_text_property(key) {
		label := TextButton_to_text_label(button)

		result := TextLabel_set(
			L,
			&label.object,
			datatype_registry,
			enum_registry,
			key,
			value_index,
		)

		TextButton_sync_text_label(
			button,
			&label,
		)

		return result
	}

	return GuiButton_set(
		L,
		object,
		datatype_registry,
		enum_registry,
		key,
		value_index,
	)
}

TextButton_render :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) {
	if !GuiButton_update(
		object,
		ctx,
	) {
		return
	}

	button := cast(^TextButton)object

	label := TextButton_to_text_label(button)

	if button.auto_button_color {
		#partial switch button.gui_state {
		case .Hover:
			label.bg_color.R =
				clamp(
					label.bg_color.R * 1.08,
					0,
					1,
				)

			label.bg_color.G =
				clamp(
					label.bg_color.G * 1.08,
					0,
					1,
				)

			label.bg_color.B =
				clamp(
					label.bg_color.B * 1.08,
					0,
					1,
				)

		case .Press:
			label.bg_color.R *= 0.82
			label.bg_color.G *= 0.82
			label.bg_color.B *= 0.82

		case:
		}
	}

	TextLabel_render(
		&label.object,
		ctx,
	)

	button.text_bounds =
		label.text_bounds
}

TextButton_clone :: proc(
	source: ^Object,
	destination: ^Object,
) {
	src := cast(^TextButton)source
	dst := cast(^TextButton)destination

	GuiButton_clone(
		source,
		destination,
	)

	src_label :=
		TextButton_to_text_label(
			src,
		)

	dst_label :=
		TextButton_to_text_label(
			dst,
		)

	TextLabel_clone(
		&src_label.object,
		&dst_label.object,
	)

	TextButton_sync_text_label(
		dst,
		&dst_label,
	)
}

Register_TextButton :: proc(
	registry: ^Registry,
) {
	Register_Class(
		registry,
		&TextButton_Class,
		TextButton_construct,
		TextButton_destroy,

		get = TextButton_get,
		set = TextButton_set,
		clone = TextButton_clone,

		properties = []string{
			"Text",
			"Font",
			"FontFace",
			"TextSize",
			"TextColor3",
			"TextTransparency",
			"TextStrokeColor3",
			"TextStrokeTransparency",
			"TextStrokeThickness",
			"TextWrapped",
			"TextScaled",
			"TextXAlignment",
			"TextYAlignment",
			"LineHeight",
			"TextPadding",
			"TextBounds",
		},
	)
}