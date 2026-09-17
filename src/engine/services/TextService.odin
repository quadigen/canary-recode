package services

// wire:service global="TextService"

import "core:strings"

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"


TextService_Class := classes.Class_Info{
	name   = "TextService",
	parent = &Service_Class,
}

TextService :: struct {
	using service: Service,
}

text_service_get_text_size :: proc(
	typeface: ^kineffi.KineSkiaTypeface,
	text: string,
	text_size: f32,
	max_size: datatypes.Vector2,
) -> datatypes.Vector2 {
	if typeface == nil {
		return datatypes.Vector2_Zero
	}

	line_height :=
		kineffi.Kine_Skia_Typeface_GetLineHeight(
			typeface,
			text_size,
		)

	if line_height <= 0 {
		line_height = text_size
	}

	if len(text) == 0 {
		return datatypes.Vector2_Zero
	}

	max_width :=
		max_size.X

	lines: i32 = 1
	largest_width: f32 = 0

	line_start := 0
	line_width: f32 = 0

	word_start := 0
	index := 0

	for index <= len(text) {
		at_end :=
			index == len(text)

		is_newline :=
			!at_end &&
			text[index] == '\n'

		is_break :=
			!at_end &&
			(
				text[index] == ' ' ||
				text[index] == '\t'
			)

		if !at_end &&
		   !is_newline &&
		   !is_break {
			index += 1
			continue
		}

		word_end :=
			index

		if word_end > word_start {
			word :=
				text[word_start:word_end]

			c_word :=
				strings.clone_to_cstring(
					word,
				)

			word_width :=
				kineffi.Kine_Skia_Typeface_MeasureText(
					typeface,
					c_word,
					text_size,
				)

			delete(c_word)

			space_width: f32 = 0

			if line_width > 0 {
				c_space :=
					strings.clone_to_cstring(
						" ",
					)

				space_width =
					kineffi.Kine_Skia_Typeface_MeasureText(
						typeface,
						c_space,
						text_size,
					)

				delete(c_space)
			}

			candidate_width :=
				line_width +
				space_width +
				word_width

			if max_width > 0 &&
			   line_width > 0 &&
			   candidate_width > max_width {

				largest_width =
					max(
						largest_width,
						line_width,
					)

				lines += 1
				line_width = word_width
			} else {
				line_width =
					candidate_width
			}
		}

		if is_newline {
			largest_width =
				max(
					largest_width,
					line_width,
				)

			lines += 1
			line_width = 0
		}

		index += 1

		for index < len(text) &&
		    (
			    text[index] == ' ' ||
			    text[index] == '\t'
		    ) {
			index += 1
		}

		word_start =
			index
	}

	largest_width =
		max(
			largest_width,
			line_width,
		)

	height :=
		line_height *
		f32(lines)

	if max_size.Y > 0 {
		height =
			min(
				height,
				max_size.Y,
			)
	}

	if max_width > 0 {
		largest_width =
			min(
				largest_width,
				max_width,
			)
	}

	return datatypes.Vector2{
		X = largest_width,
		Y = height,
	}
}

// -----------------------------------------------------------------------------
// Native measuring
// -----------------------------------------------------------------------------

text_service_measure_width_c :: proc(
	text: string,
	text_size: f32,
	font_path: cstring,
) -> f32 {
	if len(text) == 0 || text_size <= 0 {
		return 0
	}

	c_text := strings.clone_to_cstring(text)
	defer delete(c_text)

	return kineffi.Kine_Skia_Surface_MeasureText(
		c_text,
		text_size,
		font_path,
	)
}

text_service_measure_multiline_c :: proc(
	text: string,
	text_size: f32,
	font_path: cstring,
) -> datatypes.Vector2 {
	if len(text) == 0 || text_size <= 0 {
		return datatypes.Vector2{}
	}

	line_height :=
		kineffi.Kine_Skia_Surface_GetFontLineHeight(
			text_size,
			font_path,
		)

	max_width: f32 = 0
	line_count: i32 = 1

	line_start := 0

	for i := 0; i <= len(text); i += 1 {
		at_end := i == len(text)
		is_newline := !at_end && text[i] == '\n'

		if !at_end && !is_newline {
			continue
		}

		line := text[line_start:i]

		width := text_service_measure_width_c(
			line,
			text_size,
			font_path,
		)

		if width > max_width {
			max_width = width
		}

		if is_newline {
			line_count += 1
			line_start = i + 1
		}
	}

	return datatypes.Vector2{
		X = max_width,
		Y = line_height * f32(line_count),
	}
}


// Basic word/whitespace wrapping.
// UTF-8 text remains safe because we only split on ASCII whitespace bytes.
text_service_measure_wrapped_c :: proc(
	text: string,
	text_size: f32,
	font_path: cstring,
	max_width: f32,
) -> datatypes.Vector2 {
	if len(text) == 0 || text_size <= 0 {
		return datatypes.Vector2{}
	}

	if max_width <= 0 {
		return text_service_measure_multiline_c(
			text,
			text_size,
			font_path,
		)
	}

	line_height :=
		kineffi.Kine_Skia_Surface_GetFontLineHeight(
			text_size,
			font_path,
		)

	current_width: f32 = 0
	largest_width: f32 = 0
	line_count: i32 = 1

	i := 0

	for i < len(text) {
		if text[i] == '\n' {
			if current_width > largest_width {
				largest_width = current_width
			}

			current_width = 0
			line_count += 1
			i += 1
			continue
		}

		token_start := i

		is_whitespace :=
			text[i] == ' ' ||
			text[i] == '\t' ||
			text[i] == '\r'

		for i < len(text) {
			if text[i] == '\n' {
				break
			}

			byte_is_whitespace :=
				text[i] == ' ' ||
				text[i] == '\t' ||
				text[i] == '\r'

			if byte_is_whitespace != is_whitespace {
				break
			}

			i += 1
		}

		token := text[token_start:i]

		token_width := text_service_measure_width_c(
			token,
			text_size,
			font_path,
		)

		next_width := current_width + token_width

		if !is_whitespace &&
		   current_width > 0 &&
		   next_width > max_width {

			if current_width > largest_width {
				largest_width = current_width
			}

			current_width = token_width
			line_count += 1

			continue
		}

		if is_whitespace &&
		   current_width > 0 &&
		   next_width > max_width {

			if current_width > largest_width {
				largest_width = current_width
			}

			current_width = 0
			line_count += 1

			continue
		}

		current_width = next_width
	}

	if current_width > largest_width {
		largest_width = current_width
	}

	if largest_width > max_width {
		largest_width = max_width
	}

	return datatypes.Vector2{
		X = largest_width,
		Y = line_height * f32(line_count),
	}
}


// -----------------------------------------------------------------------------
// Luau API
// -----------------------------------------------------------------------------

text_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	_ = object
	_ = datatype_registry
	_ = enum_registry

	switch key {
	case "GetTextSize",
	     "MeasureText",
	     "GetTextWidth",
	     "GetLineHeight":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}


text_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	_ = object
	_ = enum_registry

	switch method {
	case "MeasureText":
		text := vm.ArgString(L, 2)
		text_size := f32(vm.ArgNumber(L, 3))
		font_path := vm.ArgString(L, 4)

		c_font := strings.clone_to_cstring(font_path)
		defer delete(c_font)

		bounds := text_service_measure_multiline_c(
			text,
			text_size,
			c_font,
		)

		datatypes.Push_Vector2(
			L,
			datatype_registry,
			bounds,
		)

		return 1, true


	case "GetTextSize":
		if datatype_registry == nil {
			return 0, false
		}

		text :=
			vm.ArgString(
				L,
				2,
			)

		text_size :=
			max(
				f32(vm.ArgNumber(
					L,
					3,
				)),
				1,
			)

		font_family :=
			vm.ArgString(
				L,
				4,
			)

		max_size :=
			datatypes.Arg_Vector2(
				L,
				5,
				datatype_registry,
			)

		typeface :=
			classes.TextLabel_Load_Typeface_From_Family(
				font_family,
			)

		if typeface == nil {
			_ = vm.RaiseError(
				L,
				"TextService:GetTextSize failed to load font",
			)

			return 0, true
		}

		defer kineffi.Kine_Skia_Typeface_Destroy(
			typeface,
		)

		bounds :=
			text_service_get_text_size(
				typeface,
				text,
				text_size,
				max_size,
			)

		datatypes.Push_Vector2(
			L,
			datatype_registry,
			bounds,
		)

		return 1, true


	case "GetTextWidth":
		text := vm.ArgString(L, 2)
		text_size := f32(vm.ArgNumber(L, 3))
		font_path := vm.ArgString(L, 4)

		c_font := strings.clone_to_cstring(font_path)
		defer delete(c_font)

		width := text_service_measure_width_c(
			text,
			text_size,
			c_font,
		)

		vm.PushNumber(L, f64(width))
		return 1, true


	case "GetLineHeight":
		text_size := f32(vm.ArgNumber(L, 2))
		font_path := vm.ArgString(L, 3)

		c_font := strings.clone_to_cstring(font_path)
		defer delete(c_font)

		height :=
			kineffi.Kine_Skia_Surface_GetFontLineHeight(
				text_size,
				c_font,
			)

		vm.PushNumber(L, f64(height))
		return 1, true
	}

	return 0, false
}


// -----------------------------------------------------------------------------
// Lifecycle
// -----------------------------------------------------------------------------

TextService_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	_ = renderer

	service := new(TextService)

	service.service = Service_Init(
		&TextService_Class,
		"TextService",
		data_model,
	)

	return &service.object
}

TextService_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	_ = renderer

	service := cast(^TextService)object

	classes.Object_Destroy(object)
	free(service)
}


Register_TextService_Class :: proc(
	registry: ^classes.Registry,
) {
	classes.Register_Class(
		registry,
		&TextService_Class,
		TextService_construct,
		TextService_destroy,
		creatable = false,
		get      = text_service_get,
		namecall = text_service_namecall,
	)
}