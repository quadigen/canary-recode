package classes

import "core:strings"

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import guilib "../gui"
import kineffi "../bindings"

TEXT_LABEL_FONTS :=
	#load_directory("../assets/fonts")


BUILTIN_FONT_PREFIX :: "builtin://fonts/"

DEFAULT_FONT :: "builtin://fonts/Montserrat-Regular.ttf"

TEXT_X_LEFT   :: "Left"
TEXT_X_CENTER :: "Center"
TEXT_X_RIGHT  :: "Right"

TEXT_Y_TOP    :: "Top"
TEXT_Y_CENTER :: "Center"
TEXT_Y_BOTTOM :: "Bottom"

TextLabel_Class := Class_Info{
	name   = "TextLabel",
	parent = &GuiObject_Class,
}


Text_Line :: struct {
	text:  string,
	width: f32,
}


TextLabel :: struct {
	using gui_object: GuiObject,

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

TextLabel_Resolve_Font_Memory :: proc(
	family: string,
) -> (
	data: []u8,
	ok: bool,
) {
	resolved_family := family

	if len(resolved_family) == 0 {
		resolved_family = DEFAULT_FONT
	}

	if !strings.has_prefix(
		resolved_family,
		BUILTIN_FONT_PREFIX,
	) {
		return nil, false
	}

	name :=
		resolved_family[len(BUILTIN_FONT_PREFIX):]

	return TextLabel_Find_Builtin_Font(name)
}

TextLabel_Load_Typeface_From_Family :: proc(
	family: string,
) -> ^kineffi.KineSkiaTypeface {
	resolved_family := family

	if len(resolved_family) == 0 {
		resolved_family = DEFAULT_FONT
	}

	if data, ok := TextLabel_Resolve_Font_Memory(
		resolved_family,
	); ok {
		if len(data) == 0 {
			return nil
		}

		return kineffi.Kine_Skia_Typeface_LoadFromMemory(
			&data[0],
			uintptr(len(data)),
		)
	}

	cpath :=
		strings.clone_to_cstring(
			resolved_family,
		)
	defer delete(cpath)

	return kineffi.Kine_Skia_Typeface_LoadFromFile(
		cpath,
	)
}

TextLabel_Init :: proc() -> TextLabel {
	gui := GuiObject_Init()

	gui.object.class =
		&TextLabel_Class

	text :=
		strings.clone(
			"Hello World!",
		)

	font :=
		datatypes.Font_New(
			DEFAULT_FONT,
			.Regular,
			.Normal,
		)

	return TextLabel{
		gui_object = gui,

		text       = text,
		owned_text = text,

		font_face =
			font,

		stored_typeface =
			nil,

		text_size =
			16,

		text_color3 =
			datatypes.Color3{
				1,
				1,
				1,
			},

		text_transparency =
			0,

		text_stroke_color3 =
			datatypes.Color3{
				0,
				0,
				0,
			},

		text_stroke_transparency =
			1,

		text_stroke_thickness =
			1,

		text_x_alignment =
			TEXT_X_LEFT,

		text_y_alignment =
			TEXT_Y_TOP,

		text_wrapped =
			false,

		text_scaled =
			false,

		line_height =
			1,

		text_padding =
			0,

		text_bounds =
			datatypes.Vector2_Zero,
	}
}


//
// --------------------------------------------------------------------------
// Built-in fonts
// --------------------------------------------------------------------------
//

TextLabel_Find_Builtin_Font :: proc(
	name: string,
) -> (
	data: []u8,
	ok: bool,
) {
	if len(name) == 0 {
		return nil, false
	}

	for file in TEXT_LABEL_FONTS {
		if file.name == name {
			return file.data, true
		}
	}

	return nil, false
}


TextLabel_Destroy_Typeface :: proc(
	label: ^TextLabel,
) {
	if label == nil {
		return
	}

	if label.stored_typeface != nil {
		kineffi.Kine_Skia_Typeface_Destroy(
			label.stored_typeface,
		)

		label.stored_typeface =
			nil
	}
}


TextLabel_Load_Typeface :: proc(
	label: ^TextLabel,
) {
	if label == nil {
		return
	}

	TextLabel_Destroy_Typeface(label)

	label.stored_typeface =
		TextLabel_Load_Typeface_From_Family(
			label.font_face.Family,
		)
}

TextLabel_Set_Font_Family :: proc(
	label: ^TextLabel,
	family: string,
) {
	if label == nil {
		return
	}

	if label.font_face.Family == family {
		return
	}

	new_font :=
		datatypes.Font_New(
			family,
			label.font_face.Weight,
			label.font_face.Style,
		)

	datatypes.Font_Destroy(
		&label.font_face,
	)

	label.font_face =
		new_font

	TextLabel_Load_Typeface(
		label,
	)
}


TextLabel_Set_Font_Face :: proc(
	label: ^TextLabel,
	font: datatypes.Font,
) {
	if label == nil {
		return
	}

	same :=
		label.font_face.Family == font.Family &&
		label.font_face.Weight == font.Weight &&
		label.font_face.Style == font.Style

	if same {
		return
	}

	datatypes.Font_Destroy(
		&label.font_face,
	)

	label.font_face =
		datatypes.Font_Clone(
			font,
		)

	TextLabel_Load_Typeface(
		label,
	)
}


//
// --------------------------------------------------------------------------
// Measurement
// --------------------------------------------------------------------------
//

TextLabel_Measure_Text :: proc(
	label: ^TextLabel,
	text: string,
	font_size: f32,
) -> f32 {
	if label == nil ||
	   label.stored_typeface == nil ||
	   len(text) == 0 {
		return 0
	}

	ctext :=
		strings.clone_to_cstring(
			text,
		)

	defer delete(ctext)

	return kineffi.Kine_Skia_Typeface_MeasureText(
		label.stored_typeface,
		ctext,
		font_size,
	)
}


TextLabel_Get_Base_Line_Height :: proc(
	label: ^TextLabel,
	font_size: f32,
) -> f32 {
	if label == nil ||
	   label.stored_typeface == nil {
		return font_size
	}

	height :=
		kineffi.Kine_Skia_Typeface_GetLineHeight(
			label.stored_typeface,
			font_size,
		)

	if height <= 0 {
		return font_size
	}

	return height
}


TextLabel_Get_Ascent :: proc(
	label: ^TextLabel,
	font_size: f32,
) -> f32 {
	if label == nil ||
	   label.stored_typeface == nil {
		return font_size
	}

	ascent :=
		kineffi.Kine_Skia_Typeface_GetAscent(
			label.stored_typeface,
			font_size,
		)

	if ascent <= 0 {
		return font_size
	}

	return ascent
}


//
// --------------------------------------------------------------------------
// Wrapping
// --------------------------------------------------------------------------
//

TextLabel_Is_Break_Character :: proc(
	character: u8,
) -> bool {
	return (
		character == ' ' ||
		character == '\t'
	)
}


TextLabel_Append_Paragraph :: proc(
	label: ^TextLabel,
	text: string,

	start_index: int,
	end_index: int,

	max_width: f32,
	font_size: f32,

	wrapped: bool,

	lines: ^[dynamic]Text_Line,
) {
	start := start_index
	end   := end_index

	//
	// Keep empty paragraphs as an empty line.
	//

	if start >= end {
		append(
			lines,
			Text_Line{
				text  = "",
				width = 0,
			},
		)

		return
	}

	//
	// Ignore leading spaces for wrapped paragraphs.
	//

	if wrapped {
		for start < end &&
		    TextLabel_Is_Break_Character(
			    text[start],
		    ) {
			start += 1
		}
	}

	if start >= end {
		append(
			lines,
			Text_Line{
				text  = "",
				width = 0,
			},
		)

		return
	}

	//
	// No wrapping.
	//

	if !wrapped ||
	   max_width <= 0 {
		line_text :=
			text[start:end]

		append(
			lines,
			Text_Line{
				text =
					line_text,

				width =
					TextLabel_Measure_Text(
						label,
						line_text,
						font_size,
					),
			},
		)

		return
	}

	//
	// Greedy word wrapping.
	//

	line_start :=
		start

	word_start :=
		start

	cursor :=
		start

	for cursor <= end {
		at_end :=
			cursor == end

		at_break :=
			!at_end &&
			TextLabel_Is_Break_Character(
				text[cursor],
			)

		if !at_end &&
		   !at_break {
			cursor += 1
			continue
		}

		word_end :=
			cursor

		candidate :=
			text[line_start:word_end]

		candidate_width :=
			TextLabel_Measure_Text(
				label,
				candidate,
				font_size,
			)

		//
		// Current word would push this line too wide.
		//

		if candidate_width > max_width &&
		   word_start > line_start {

			line_end :=
				word_start

			//
			// Remove trailing whitespace.
			//

			for line_end > line_start &&
			    TextLabel_Is_Break_Character(
				    text[line_end - 1],
			    ) {
				line_end -= 1
			}

			line_text :=
				text[line_start:line_end]

			append(
				lines,
				Text_Line{
					text =
						line_text,

					width =
						TextLabel_Measure_Text(
							label,
							line_text,
							font_size,
						),
				},
			)

			line_start =
				word_start
		}

		if at_end {
			break
		}

		//
		// Skip spaces before next word.
		//

		cursor += 1

		for cursor < end &&
		    TextLabel_Is_Break_Character(
			    text[cursor],
		    ) {
			cursor += 1
		}

		word_start =
			cursor
	}

	//
	// Remaining text.
	//

	if line_start <= end {
		line_end :=
			end

		for line_end > line_start &&
		    TextLabel_Is_Break_Character(
			    text[line_end - 1],
		    ) {
			line_end -= 1
		}

		line_text :=
			text[line_start:line_end]

		append(
			lines,
			Text_Line{
				text =
					line_text,

				width =
					TextLabel_Measure_Text(
						label,
						line_text,
						font_size,
					),
			},
		)
	}
}


TextLabel_Build_Lines :: proc(
	label: ^TextLabel,

	max_width: f32,
	font_size: f32,

	wrapped: bool,
) -> [dynamic]Text_Line {
	lines :=
		make(
			[dynamic]Text_Line,
		)

	text :=
		label.text

	//
	// Even empty text has one conceptual line.
	//

	if len(text) == 0 {
		append(
			&lines,
			Text_Line{
				text  = "",
				width = 0,
			},
		)

		return lines
	}

	paragraph_start :=
		0

	index :=
		0

	for index <= len(text) {
		at_end :=
			index == len(text)

		is_newline :=
			!at_end &&
			text[index] == '\n'

		if at_end ||
		   is_newline {

			TextLabel_Append_Paragraph(
				label,
				text,

				paragraph_start,
				index,

				max_width,
				font_size,

				wrapped,

				&lines,
			)

			paragraph_start =
				index + 1
		}

		index += 1
	}

	return lines
}


//
// --------------------------------------------------------------------------
// Layout
// --------------------------------------------------------------------------
//

TextLabel_Get_Bounds :: proc(
	label: ^TextLabel,
	lines: []Text_Line,
	font_size: f32,
) -> datatypes.Vector2 {
	if label == nil {
		return datatypes.Vector2_Zero
	}

	width: f32 =
		0

	for line in lines {
		width =
			max(
				width,
				line.width,
			)
	}

	line_height :=
		TextLabel_Get_Base_Line_Height(
			label,
			font_size,
		) *
		label.line_height

	height :=
		line_height *
		f32(len(lines))

	return datatypes.Vector2{
		width,
		height,
	}
}


TextLabel_Fits_Size :: proc(
	label: ^TextLabel,

	font_size: f32,

	max_width: f32,
	max_height: f32,
) -> bool {
	lines :=
		TextLabel_Build_Lines(
			label,
			max_width,
			font_size,
			label.text_wrapped,
		)

	defer delete(lines)

	bounds :=
		TextLabel_Get_Bounds(
			label,
			lines[:],
			font_size,
		)

	return bounds.X <= max_width && bounds.Y <= max_height
}


TextLabel_Get_Effective_Font_Size :: proc(
	label: ^TextLabel,

	max_width: f32,
	max_height: f32,
) -> f32 {
	if !label.text_scaled {
		return label.text_size
	}

	if len(label.text) == 0 ||
	   max_width <= 0 ||
	   max_height <= 0 {
		return label.text_size
	}

	//
	// Binary search the largest font size that fits.
	//
	// 256 is a reasonable default upper bound.
	//

	low: f32 =
		1

	high: f32 =
		max(
			label.text_size,
			256,
		)

	best: f32 =
		1

	for _ in 0 ..< 10 {
		middle :=
			(low + high) * 0.5

		if TextLabel_Fits_Size(
			label,
			middle,
			max_width,
			max_height,
		) {
			best =
				middle

			low =
				middle
		} else {
			high =
				middle
		}
	}

	return max(
		best,
		1,
	)
}


//
// --------------------------------------------------------------------------
// Alignment
// --------------------------------------------------------------------------
//

TextLabel_Get_Line_X :: proc(
	label: ^TextLabel,

	content_x: f32,
	content_width: f32,

	line_width: f32,
) -> f32 {
	switch label.text_x_alignment {

	case TEXT_X_CENTER: return content_x + (content_width - line_width) * 0.5

	case TEXT_X_RIGHT: return content_x + content_width - line_width

	case:
		return content_x
	}
}


TextLabel_Get_Block_Y :: proc(
	label: ^TextLabel,

	content_y: f32,
	content_height: f32,

	text_height: f32,
) -> f32 {
	switch label.text_y_alignment {

	case TEXT_Y_CENTER:
		return content_y + (content_height - text_height) * 0.5

	case TEXT_Y_BOTTOM:
		return content_y + content_height -text_height

	case:
		return content_y
	}
}


//
// --------------------------------------------------------------------------
// Lifecycle
// --------------------------------------------------------------------------
//

TextLabel_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	label :=
		new(TextLabel)

	label^ =
		TextLabel_Init()

	label.name =
		"TextLabel"

	TextLabel_Load_Typeface(
		label,
	)

	return &label.object
}


TextLabel_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	label :=
		cast(^TextLabel)object

	TextLabel_Destroy_Typeface(
		label,
	)

	delete(
		label.owned_text,
	)

	label.owned_text =
		""

	label.text =
		""

	datatypes.Font_Destroy(
		&label.font_face,
	)

	Object_Destroy(
		object,
	)

	free(
		label,
	)
}


//
// --------------------------------------------------------------------------
// Properties
// --------------------------------------------------------------------------
//

TextLabel_get :: proc(
	L: ^vm.State,

	object: ^Object,

	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,

	key: string,
) -> bool {
	label :=
		cast(^TextLabel)object

	switch key {

	case "Text":
		vm.PushString(
			L,
			label.text,
		)

	case "Font":
		vm.PushString(
			L,
			label.font_face.Family,
		)

	case "FontFace":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Font(
			L,
			datatype_registry,
			label.font_face,
		)

	case "TextSize":
		vm.PushNumber(
			L,
			f64(label.text_size),
		)

	case "TextColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(
			L,
			datatype_registry,
			label.text_color3,
		)

	case "TextTransparency":
		vm.PushNumber(
			L,
			f64(
				label.text_transparency,
			),
		)

	case "TextStrokeColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(
			L,
			datatype_registry,
			label.text_stroke_color3,
		)

	case "TextStrokeTransparency":
		vm.PushNumber(
			L,
			f64(
				label.text_stroke_transparency,
			),
		)

	case "TextStrokeThickness":
		vm.PushNumber(
			L,
			f64(
				label.text_stroke_thickness,
			),
		)

	case "TextWrapped":
		vm.PushBoolean(
			L,
			label.text_wrapped,
		)

	case "TextScaled":
		vm.PushBoolean(
			L,
			label.text_scaled,
		)

	case "TextXAlignment":
		if enum_registry != nil {
			value: i64 = label.text_x_alignment == TEXT_X_RIGHT ? 1 : label.text_x_alignment == TEXT_X_CENTER ? 2 : 0
			if !enums.Push_Item_By_Value(L, enum_registry, "TextXAlignment", value) { vm.PushString(L, label.text_x_alignment) }
		} else {
			vm.PushString(L, label.text_x_alignment)
		}

	case "TextYAlignment":
		if enum_registry != nil {
			value: i64 = label.text_y_alignment == TEXT_Y_CENTER ? 1 : label.text_y_alignment == TEXT_Y_BOTTOM ? 2 : 0
			if !enums.Push_Item_By_Value(L, enum_registry, "TextYAlignment", value) { vm.PushString(L, label.text_y_alignment) }
		} else {
			vm.PushString(L, label.text_y_alignment)
		}

	case "LineHeight":
		vm.PushNumber(
			L,
			f64(
				label.line_height,
			),
		)

	case "TextPadding":
		vm.PushNumber(
			L,
			f64(
				label.text_padding,
			),
		)

	case "TextBounds":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(
			L,
			datatype_registry,
			label.text_bounds,
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


TextLabel_set :: proc(
	L: ^vm.State,

	object: ^Object,

	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,

	key: string,
	value_index: int,
) -> bool {
	label :=
		cast(^TextLabel)object

	switch key {

	case "Text":
		value :=
			vm.ArgString(
				L,
				value_index,
			)

		copy :=
			strings.clone(
				value,
			)

		delete(
			label.owned_text,
		)

		label.owned_text =
			copy

		label.text =
			copy


	case "Font":
		TextLabel_Set_Font_Family(
			label,
			vm.ArgString(
				L,
				value_index,
			),
		)


	case "FontFace":
		if datatype_registry == nil {
			return false
		}

		font :=
			datatypes.Arg_Font(
				L,
				value_index,
				datatype_registry,
			)

		TextLabel_Set_Font_Face(
			label,
			font,
		)


	case "TextSize":
		label.text_size =
			max(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				1,
			)


	case "TextColor3":
		if datatype_registry == nil {
			return false
		}

		label.text_color3 =
			datatypes.Arg_Color3(
				L,
				value_index,
				datatype_registry,
			)


	case "TextTransparency":
		label.text_transparency =
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


	case "TextStrokeColor3":
		if datatype_registry == nil {
			return false
		}

		label.text_stroke_color3 =
			datatypes.Arg_Color3(
				L,
				value_index,
				datatype_registry,
			)


	case "TextStrokeTransparency":
		label.text_stroke_transparency =
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


	case "TextStrokeThickness":
		label.text_stroke_thickness =
			max(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				0,
			)


	case "TextWrapped":
		label.text_wrapped =
			vm.ArgBoolean(
				L,
				value_index,
			)


	case "TextScaled":
		label.text_scaled =
			vm.ArgBoolean(
				L,
				value_index,
			)


	case "TextXAlignment":
		value := ""
		if enum_registry != nil && vm.IsUserdataType(L, value_index, &enum_registry.item_binding) {
			item := enums.Arg_Item(L, value_index, enum_registry, "TextXAlignment")
			if item == nil { return true }
			value = enums.Item_Name(item)
		} else {
			value = vm.ArgString(L, value_index)
		}

		if value != TEXT_X_LEFT &&
		   value != TEXT_X_CENTER &&
		   value != TEXT_X_RIGHT {

			_ = vm.RaiseError(
				L,
				"TextXAlignment must be Left, Center, or Right",
			)

			return true
		}

		label.text_x_alignment =
			value


	case "TextYAlignment":
		value := ""
		if enum_registry != nil && vm.IsUserdataType(L, value_index, &enum_registry.item_binding) {
			item := enums.Arg_Item(L, value_index, enum_registry, "TextYAlignment")
			if item == nil { return true }
			value = enums.Item_Name(item)
		} else {
			value = vm.ArgString(L, value_index)
		}

		if value != TEXT_Y_TOP &&
		   value != TEXT_Y_CENTER &&
		   value != TEXT_Y_BOTTOM {

			_ = vm.RaiseError(
				L,
				"TextYAlignment must be Top, Center, or Bottom",
			)

			return true
		}

		label.text_y_alignment =
			value


	case "LineHeight":
		label.line_height =
			max(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				0.1,
			)


	case "TextPadding":
		label.text_padding =
			max(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				0,
			)


	case "TextBounds":
		_ = vm.RaiseError(
			L,
			"TextBounds is read-only",
		)

		return true


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
// --------------------------------------------------------------------------
// Rendering
// --------------------------------------------------------------------------
//

TextLabel_render :: proc(
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

	//
	// Background
	//

	GuiObject_render(
		object,
		ctx,
	)

	label :=
		cast(^TextLabel)object

	if label.stored_typeface == nil {
		label.text_bounds =
			datatypes.Vector2_Zero

		return
	}

	//
	// Content rectangle
	//

	padding :=
		max(
			label.text_padding,
			0,
		)

	content_x :=
		rect.x +
		padding

	content_y :=
		rect.y +
		padding

	content_width :=
		max(
			rect.width -
			padding * 2,
			0,
		)

	content_height :=
		max(
			rect.height -
			padding * 2,
			0,
		)

	if content_width <= 0 ||
	   content_height <= 0 {
		label.text_bounds =
			datatypes.Vector2_Zero

		return
	}

	//
	// Resolve actual font size.
	//

	font_size :=
		TextLabel_Get_Effective_Font_Size(
			label,
			content_width,
			content_height,
		)

	//
	// Build wrapped/non-wrapped lines.
	//

	lines :=
		TextLabel_Build_Lines(
			label,
			content_width,
			font_size,
			label.text_wrapped,
		)

	defer delete(lines)

	//
	// Bounds
	//

	label.text_bounds =
		TextLabel_Get_Bounds(
			label,
			lines[:],
			font_size,
		)

	line_height :=
		TextLabel_Get_Base_Line_Height(
			label,
			font_size,
		) *
		label.line_height

	ascent :=
		TextLabel_Get_Ascent(
			label,
			font_size,
		)

	block_y :=
		TextLabel_Get_Block_Y(
			label,
			content_y,
			content_height,
			label.text_bounds.Y,
		)

	//
	// Clip all text to the label's content area.
	//

	guilib.save(
		ctx.renderer.SkiaSurface,
	)

	defer guilib.restore(
		ctx.renderer.SkiaSurface,
	)

	guilib.clipRect(
		ctx.renderer.SkiaSurface,
		guilib.Rect{
			x =
				content_x,

			y =
				content_y,

			width =
				content_width,

			height =
				content_height,
		},
	)

	//
	// Optional UIShadow affecting text.
	//

	shadow_object :=
		Find_First_Child_Of_Class(
			object,
			"UIShadow",
		)

	shadow: ^UIShadow =
		nil

	if shadow_object != nil {
		shadow =
			cast(^UIShadow)shadow_object
	}

	//
	// Render lines.
	//

	for line, index in lines {
		line_x :=
			TextLabel_Get_Line_X(
				label,
				content_x,
				content_width,
				line.width,
			)

		line_top :=
			block_y +
			f32(index) *
			line_height

		baseline :=
			line_top +
			ascent

		ctext :=
			strings.clone_to_cstring(
				line.text,
			)

		text_params :=
			guilib.TextParams{
				x =
					line_x,

				y =
					baseline,

				TextSize =
					font_size,

				color =
					label.text_color3,

				transparency =
					label.text_transparency,

				font =
					nil,

				typeface =
					label.stored_typeface,
			}

		//
		// UIShadow first, so it remains behind everything.
		//

		if shadow != nil &&
		   shadow.enabled &&
		   shadow.showfortext {

			short_edge :=
				min(
					rect.width,
					rect.height,
				)

			offset_x :=
				shadow.offset.X_Scale *
				rect.width +
				shadow.offset.X_Offset

			offset_y :=
				shadow.offset.Y_Scale *
				rect.height +
				shadow.offset.Y_Offset

			spread_x :=
				shadow.spread.X_Scale *
				rect.width +
				shadow.spread.X_Offset

			spread_y :=
				shadow.spread.Y_Scale *
				rect.height +
				shadow.spread.Y_Offset

			shadow_params :=
				guilib.ShadowParams{
					offsetX =
						offset_x,

					offsetY =
						offset_y,

					blurSigma =
						max(
							f32(0),
							gui_resolve_udim(
								shadow.blur_radius,
								short_edge,
							),
						),

					spread =
						max(
							f32(0),
							(
								spread_x +
								spread_y
							) *
							0.5,
						),

					color =
						shadow.color,

					alpha =
						1 -
						f32(
							shadow.transparency,
						),
				}

			guilib.drawTextShadow(
				ctx.renderer.SkiaSurface,
				ctext,
				text_params,
				shadow_params,
			)
		}

		//
		// Text stroke.
		//
		// We can reuse the text-shadow renderer with:
		//     offset = 0
		//     blur   = 0
		//     spread = stroke thickness
		//

		if label.text_stroke_transparency < 1 &&
		   label.text_stroke_thickness > 0 {

			stroke_params :=
				guilib.ShadowParams{
					offsetX =
						0,

					offsetY =
						0,

					blurSigma =
						0,

					spread =
						label.text_stroke_thickness,

					color =
						label.text_stroke_color3,

					alpha =
						1 -
						label.text_stroke_transparency,
				}

			guilib.drawTextShadow(
				ctx.renderer.SkiaSurface,
				ctext,
				text_params,
				stroke_params,
			)
		}

		//
		// Main text.
		//

		guilib.drawText(
			ctx.renderer.SkiaSurface,
			ctext,
			text_params,
		)

		delete(ctext)
	}
}


//
// --------------------------------------------------------------------------
// Clone
// --------------------------------------------------------------------------
//

TextLabel_clone :: proc(
	source: ^Object,
	destination: ^Object,
) {
	src :=
		cast(^TextLabel)source

	dst :=
		cast(^TextLabel)destination

	//
	// Text
	//

	delete(
		dst.owned_text,
	)

	dst.owned_text =
		strings.clone(
			src.text,
		)

	dst.text =
		dst.owned_text

	//
	// Font
	//

	TextLabel_Destroy_Typeface(
		dst,
	)

	datatypes.Font_Destroy(
		&dst.font_face,
	)

	dst.font_face =
		datatypes.Font_Clone(
			src.font_face,
		)

	TextLabel_Load_Typeface(
		dst,
	)

	//
	// Appearance
	//

	dst.text_size =
		src.text_size

	dst.text_color3 =
		src.text_color3

	dst.text_transparency =
		src.text_transparency

	dst.text_stroke_color3 =
		src.text_stroke_color3

	dst.text_stroke_transparency =
		src.text_stroke_transparency

	dst.text_stroke_thickness =
		src.text_stroke_thickness

	//
	// Layout
	//

	dst.text_x_alignment =
		src.text_x_alignment

	dst.text_y_alignment =
		src.text_y_alignment

	dst.text_wrapped =
		src.text_wrapped

	dst.text_scaled =
		src.text_scaled

	dst.line_height =
		src.line_height

	dst.text_padding =
		src.text_padding

	dst.text_bounds =
		src.text_bounds
}


//
// --------------------------------------------------------------------------
// Registration
// --------------------------------------------------------------------------
//

Register_TextLabel :: proc(
	registry: ^Registry,
) {
	Register_Class(
		registry,

		&TextLabel_Class,

		TextLabel_construct,
		TextLabel_destroy,

		get =
			TextLabel_get,

		set =
			TextLabel_set,

		clone =
			TextLabel_clone,

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