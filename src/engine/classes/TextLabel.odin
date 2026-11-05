package classes

import "core:strings"

import assetstore "../assetstore"
import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"

TEXT_LABEL_FONTS := #load_directory("../assets/fonts")

BUILTIN_FONT_PREFIX :: "builtin://fonts/"

DEFAULT_FONT :: "builtin://fonts/Montserrat-Regular.ttf"

TEXT_X_LEFT :: "Left"
TEXT_X_CENTER :: "Center"
TEXT_X_RIGHT :: "Right"

TEXT_Y_TOP :: "Top"
TEXT_Y_CENTER :: "Center"
TEXT_Y_BOTTOM :: "Bottom"

TextLabel_Class := Class_Info {
	name   = "TextLabel",
	parent = &GuiObject_Class,
}

Text_Line :: struct {
	text:  string,
	width: f32,
	draw_text: cstring,
}

Text_Measure_Cache :: struct {
	valid: bool,
	width, font_size, line_height: f32,
	bounds: datatypes.Vector2,
}

Text_Render_Layout :: struct {
	measure: Text_Measure_Cache,
	lines: [dynamic]Text_Line,
	inputs: struct {
		width, height, text_size, line_height: f32,
		wrapped, scaled: bool,
	},
	font_size, line_height, ascent: f32,
	bounds: datatypes.Vector2,
}

TextLabel :: struct {
	using gui_object:         GuiObject,
	text:                     string,
	owned_text:               string,
	font_face:                datatypes.Font,
	font_enum:                enums.Font,
	stored_typeface:          ^kineffi.KineSkiaTypeface,
	text_size:                f32,
	text_color3:              datatypes.Color3,
	text_transparency:        f32,
	text_stroke_color3:       datatypes.Color3,
	text_stroke_transparency: f32,
	text_stroke_thickness:    f32,
	text_x_alignment:         string,
	text_y_alignment:         string,
	text_wrapped:             bool,
	text_scaled:              bool,
	line_height:              f32,
	text_padding:             f32,
	text_bounds:              datatypes.Vector2,
	render_layout:            Text_Render_Layout,
	rich_text:                bool,
	truncate_at_end:          bool,
}

TextLabel_Resolve_Font_Memory :: proc(family: string) -> (data: []u8, ok: bool) {
	resolved_family := family

	if len(resolved_family) == 0 {
		resolved_family = DEFAULT_FONT
	}

	if !strings.has_prefix(resolved_family, BUILTIN_FONT_PREFIX) {
		return nil, false
	}

	name := resolved_family[len(BUILTIN_FONT_PREFIX):]

	return TextLabel_Find_Builtin_Font(name)
}

TextLabel_Load_Typeface_From_Family :: proc(family: string) -> ^kineffi.KineSkiaTypeface {
	resolved_family := family

	if len(resolved_family) == 0 {
		resolved_family = DEFAULT_FONT
	}

	if strings.has_prefix(resolved_family, datatypes.MEMORY_FONT_PREFIX) {
		return nil
	}

	if data, ok := TextLabel_Resolve_Font_Memory(resolved_family); ok {
		if len(data) == 0 {
			return nil
		}

		return kineffi.Kine_Skia_Typeface_LoadFromMemory(&data[0], uintptr(len(data)))
	}

	if data, found := assetstore.Resolve_Bytes(resolved_family); found && len(data) > 0 {
		return kineffi.Kine_Skia_Typeface_LoadFromMemory(raw_data(data), uintptr(len(data)))
	}
	if assetstore.Is_Uri(resolved_family) {
		assetstore.Report_Missing_Asset(resolved_family, "Font")
		return nil
	}

	cpath := assetstore.Resolve_C_Path(resolved_family)
	defer delete(cpath)

	return kineffi.Kine_Skia_Typeface_LoadFromFile(cpath)
}

TextLabel_Load_Typeface_From_Font :: proc(font: datatypes.Font) -> ^kineffi.KineSkiaTypeface {
	if datatypes.Font_Has_Memory(font) {
		return kineffi.Kine_Skia_Typeface_LoadFromMemory(&font.Data[0], uintptr(len(font.Data)))
	}

	return TextLabel_Load_Typeface_From_Family(font.Family)
}

text_label_font_size_enum :: proc(pixels: f32) -> enums.FontSize {
	sizes := [15]f32{8, 9, 10, 11, 12, 14, 18, 24, 28, 32, 36, 42, 48, 60, 96}
	names := [15]enums.FontSize {
		.Size8,
		.Size9,
		.Size10,
		.Size11,
		.Size12,
		.Size14,
		.Size18,
		.Size24,
		.Size28,
		.Size32,
		.Size36,
		.Size42,
		.Size48,
		.Size60,
		.Size96,
	}
	best := 0
	for index in 1 ..< len(sizes) {
		if abs(sizes[index] - pixels) < abs(sizes[best] - pixels) {
			best = index
		}
	}
	return names[best]
}

text_label_font_size_pixels :: proc(value: enums.FontSize) -> f32 {
	switch value {
	case .Size8:
		return 8
	case .Size9:
		return 9
	case .Size10:
		return 10
	case .Size11:
		return 11
	case .Size12:
		return 12
	case .Size14:
		return 14
	case .Size18:
		return 18
	case .Size24:
		return 24
	case .Size36:
		return 36
	case .Size48:
		return 48
	case .Size28:
		return 28
	case .Size32:
		return 32
	case .Size42:
		return 42
	case .Size60:
		return 60
	case .Size96:
		return 96
	case:
		return 14
	}
}

TextLabel_Init :: proc() -> TextLabel {
	gui := GuiObject_Init()

	gui.object.class = &TextLabel_Class

	text := strings.clone("Hello World!")

	font := datatypes.Font_New(DEFAULT_FONT, .Regular, .Normal)

	return TextLabel {
		gui_object = gui,
		text = text,
		owned_text = text,
		font_face = font,
		font_enum = .Legacy,
		stored_typeface = nil,
		text_size = 16,
		text_color3 = datatypes.Color3{0, 0, 0},
		text_transparency = 0,
		text_stroke_color3 = datatypes.Color3{0, 0, 0},
		text_stroke_transparency = 1,
		text_stroke_thickness = 1,
		text_x_alignment = TEXT_X_CENTER,
		text_y_alignment = TEXT_Y_CENTER,
		text_wrapped = false,
		text_scaled = false,
		line_height = 1,
		text_padding = 0,
		text_bounds = datatypes.Vector2_Zero,
	}
}


TextLabel_Find_Builtin_Font :: proc(name: string) -> (data: []u8, ok: bool) {
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


TextLabel_Destroy_Typeface :: proc(label: ^TextLabel) {
	if label == nil {
		return
	}

	text_render_layout_clear(&label.render_layout)
	if label.stored_typeface != nil {
		kineffi.Kine_Skia_Typeface_Destroy(label.stored_typeface)

		label.stored_typeface = nil
	}
}


TextLabel_Load_Typeface :: proc(label: ^TextLabel) {
	if label == nil {
		return
	}

	TextLabel_Destroy_Typeface(label)

	label.stored_typeface = TextLabel_Load_Typeface_From_Font(label.font_face)
}


TextLabel_Set_Font_Memory :: proc(label: ^TextLabel, data: []u8) -> bool {
	if label == nil {
		return false
	}


	font, ok := datatypes.Font_From_Memory(data, label.font_face.Weight, label.font_face.Style)
	if !ok {
		return false
	}
	defer datatypes.Font_Destroy(&font)

	TextLabel_Set_Font_Face(label, font)

	return true
}

TextLabel_Set_Font_Family :: proc(label: ^TextLabel, family: string) {
	if label == nil {
		return
	}


	if strings.has_prefix(family, datatypes.MEMORY_FONT_PREFIX) {
		return
	}

	new_enum := TextLabel_Font_Enum_From_Family(family)

	if label.font_face.Family == family {
		label.font_enum = new_enum

		return
	}

	new_font := datatypes.Font_New(family, label.font_face.Weight, label.font_face.Style)

	datatypes.Font_Destroy(&label.font_face)

	label.font_face = new_font

	label.font_enum = new_enum

	TextLabel_Load_Typeface(label)
}


TextLabel_Set_Font_Face :: proc(label: ^TextLabel, font: datatypes.Font) {
	if label == nil {
		return
	}

	same :=
		label.font_face.Family == font.Family &&
		label.font_face.Weight == font.Weight &&
		label.font_face.Style == font.Style

	if same {
		label.font_enum = TextLabel_Font_Enum_From_Family(font.Family)

		return
	}

	datatypes.Font_Destroy(&label.font_face)

	label.font_face = datatypes.Font_Clone(font)

	label.font_enum = TextLabel_Font_Enum_From_Family(font.Family)

	TextLabel_Load_Typeface(label)
}


TextLabel_Set_Font_Enum :: proc(label: ^TextLabel, font: enums.Font) {
	if label == nil {
		return
	}

	TextLabel_Set_Font_Family(label, TextLabel_Font_Enum_To_Family(font))

	label.font_enum = font
}

TextLabel_Font_Enum_To_Family :: proc(font: enums.Font) -> string {
	#partial switch font {
	case .Legacy:
		return DEFAULT_FONT
	case .Arial:
		return DEFAULT_FONT
	case .ArialBold:
		return "builtin://fonts/Montserrat-Bold.ttf"
	case .SourceSans:
		return "builtin://fonts/SourceSans3-Regular.ttf"
	case .SourceSansBold:
		return "builtin://fonts/SourceSans3-Bold.ttf"
	case .SourceSansLight:
		return "builtin://fonts/SourceSans3-Light.ttf"
	case .SourceSansItalic:
		return "builtin://fonts/SourceSans3-Italic.ttf"
	case .Bodoni:
		return "builtin://fonts/Bembo.otf"
	case .Garamond:
		return "builtin://fonts/Bembo.otf"
	case .Cartoon:
		return "builtin://fonts/ComicNeue-Angular-Bold.ttf"
	case .Code:
		return "builtin://fonts/GoogleSansCode-Regular.ttf"
	case .Highway:
		return "builtin://fonts/HWYGOTH.ttf"
	case .SciFi:
		return "builtin://fonts/Zekton.ttf"
	case .Arcade:
		return "builtin://fonts/VCR.ttf"
	case .Fantasy:
		return "builtin://fonts/Duskfall_Gothic.ttf"
	case .Antique:
		return "builtin://fonts/RomanAntique.otf"
	case .SourceSansSemibold:
		return "builtin://fonts/SourceSans3-SemiBold.ttf"
	case .Gotham:
		return "builtin://fonts/Montserrat-Regular.ttf"
	case .GothamMedium:
		return "builtin://fonts/Montserrat-Medium.ttf"
	case .GothamBold:
		return "builtin://fonts/Montserrat-Bold.ttf"
	case .GothamBlack:
		return "builtin://fonts/Montserrat-Black.ttf"
	case .AmaticSC:
		return "builtin://fonts/AmaticSC-Regular.ttf"
	case .Bangers:
		return "builtin://fonts/Bangers-Regular.ttf"
	case .Creepster:
		return "builtin://fonts/Creepster-Regular.ttf"
	case .DenkOne:
		return "builtin://fonts/DenkOne-Regular.ttf"
	case .Fondamento:
		return "builtin://fonts/Fondamento-Regular.ttf"
	case .FredokaOne:
		return "builtin://fonts/FredokaOne-Regular.ttf"
	case .GrenzeGotisch:
		return "builtin://fonts/GrenzeGotisch-Regular.ttf"
	case .IndieFlower:
		return "builtin://fonts/IndieFlower-Regular.ttf"
	case .JosefinSans:
		return "builtin://fonts/JosefinSans-Regular.ttf"
	case .Jura:
		return "builtin://fonts/Jura-Regular.ttf"
	case .Kalam:
		return "builtin://fonts/Kalam-Regular.ttf"
	case .LuckiestGuy:
		return "builtin://fonts/LuckiestGuy-Regular.ttf"
	case .Merriweather:
		return "builtin://fonts/Merriweather-Regular.ttf"
	case .Michroma:
		return "builtin://fonts/Michroma-Regular.ttf"
	case .Nunito:
		return "builtin://fonts/Nunito-Regular.ttf"
	case .Oswald:
		return "builtin://fonts/Oswald-Regular.ttf"
	case .PatrickHand:
		return "builtin://fonts/PatrickHand-Regular.ttf"
	case .PermanentMarker:
		return "builtin://fonts/PermanentMarker-Regular.ttf"
	case .Roboto:
		return "builtin://fonts/Roboto-Regular.ttf"
	case .RobotoCondensed:
		return "builtin://fonts/Roboto_Condensed-Regular.ttf"
	case .RobotoMono:
		return "builtin://fonts/RobotoMono-Regular.ttf"
	case .Sarpanch:
		return "builtin://fonts/Sarpanch-Regular.ttf"
	case .SpecialElite:
		return "builtin://fonts/SpecialElite-Regular.ttf"
	case .TitilliumWeb:
		return "builtin://fonts/TitilliumWeb-Regular.ttf"
	case .Ubuntu:
		return "builtin://fonts/Ubuntu-Regular.ttf"
	case .Arimo:
		return "builtin://fonts/Arimo-Regular.ttf"
	case .ArimoBold:
		return "builtin://fonts/Arimo-Bold.ttf"
	case:
		return DEFAULT_FONT
	}
}

TextLabel_Font_Enum_From_Family :: proc(family: string) -> enums.Font {
	switch family {
	case DEFAULT_FONT:
		return .Legacy
	case "builtin://fonts/Montserrat-Bold.ttf":
		return .ArialBold
	case "builtin://fonts/Montserrat-Medium.ttf":
		return .GothamMedium
	case "builtin://fonts/Montserrat-Black.ttf":
		return .GothamBlack
	case "builtin://fonts/SourceSans3-Regular.ttf":
		return .SourceSans
	case "builtin://fonts/SourceSans3-Bold.ttf":
		return .SourceSansBold
	case "builtin://fonts/SourceSans3-Light.ttf":
		return .SourceSansLight
	case "builtin://fonts/SourceSans3-Italic.ttf":
		return .SourceSansItalic
	case "builtin://fonts/SourceSans3-SemiBold.ttf":
		return .SourceSansSemibold
	case "builtin://fonts/Bembo.otf":
		return .Bodoni
	case "builtin://fonts/ComicNeue-Angular-Bold.ttf":
		return .Cartoon
	case "builtin://fonts/GoogleSansCode-Regular.ttf":
		return .Code
	case "builtin://fonts/HWYGOTH.ttf":
		return .Highway
	case "builtin://fonts/Zekton.ttf":
		return .SciFi
	case "builtin://fonts/VCR.ttf":
		return .Arcade
	case "builtin://fonts/Duskfall_Gothic.ttf":
		return .Fantasy
	case "builtin://fonts/RomanAntique.otf":
		return .Antique
	case "builtin://fonts/AmaticSC-Regular.ttf":
		return .AmaticSC
	case "builtin://fonts/Bangers-Regular.ttf":
		return .Bangers
	case "builtin://fonts/Creepster-Regular.ttf":
		return .Creepster
	case "builtin://fonts/DenkOne-Regular.ttf":
		return .DenkOne
	case "builtin://fonts/Fondamento-Regular.ttf":
		return .Fondamento
	case "builtin://fonts/FredokaOne-Regular.ttf":
		return .FredokaOne
	case "builtin://fonts/GrenzeGotisch-Regular.ttf":
		return .GrenzeGotisch
	case "builtin://fonts/IndieFlower-Regular.ttf":
		return .IndieFlower
	case "builtin://fonts/JosefinSans-Regular.ttf":
		return .JosefinSans
	case "builtin://fonts/Jura-Regular.ttf":
		return .Jura
	case "builtin://fonts/Kalam-Regular.ttf":
		return .Kalam
	case "builtin://fonts/LuckiestGuy-Regular.ttf":
		return .LuckiestGuy
	case "builtin://fonts/Merriweather-Regular.ttf":
		return .Merriweather
	case "builtin://fonts/Michroma-Regular.ttf":
		return .Michroma
	case "builtin://fonts/Nunito-Regular.ttf":
		return .Nunito
	case "builtin://fonts/Oswald-Regular.ttf":
		return .Oswald
	case "builtin://fonts/PatrickHand-Regular.ttf":
		return .PatrickHand
	case "builtin://fonts/PermanentMarker-Regular.ttf":
		return .PermanentMarker
	case "builtin://fonts/Roboto-Regular.ttf":
		return .Roboto
	case "builtin://fonts/Roboto_Condensed-Regular.ttf":
		return .RobotoCondensed
	case "builtin://fonts/RobotoMono-Regular.ttf":
		return .RobotoMono
	case "builtin://fonts/Sarpanch-Regular.ttf":
		return .Sarpanch
	case "builtin://fonts/SpecialElite-Regular.ttf":
		return .SpecialElite
	case "builtin://fonts/TitilliumWeb-Regular.ttf":
		return .TitilliumWeb
	case "builtin://fonts/Ubuntu-Regular.ttf":
		return .Ubuntu
	case "builtin://fonts/Arimo-Regular.ttf":
		return .Arimo
	case "builtin://fonts/Arimo-Bold.ttf":
		return .ArimoBold
	case:
		return .Legacy
	}
}


TextLabel_Measure_Text :: proc(label: ^TextLabel, text: string, font_size: f32) -> f32 {
	if label == nil || label.stored_typeface == nil || len(text) == 0 {
		return 0
	}

	ctext := strings.clone_to_cstring(text)

	defer delete(ctext)

	return kineffi.Kine_Skia_Typeface_MeasureText(label.stored_typeface, ctext, font_size)
}


TextLabel_Get_Base_Line_Height :: proc(label: ^TextLabel, font_size: f32) -> f32 {
	if label == nil || label.stored_typeface == nil {
		return font_size
	}

	height := kineffi.Kine_Skia_Typeface_GetLineHeight(label.stored_typeface, font_size)

	if height <= 0 {
		return font_size
	}

	return height
}


TextLabel_Get_Ascent :: proc(label: ^TextLabel, font_size: f32) -> f32 {
	if label == nil || label.stored_typeface == nil {
		return font_size
	}

	ascent := kineffi.Kine_Skia_Typeface_GetAscent(label.stored_typeface, font_size)

	if ascent <= 0 {
		return font_size
	}

	return ascent
}


TextLabel_Is_Break_Character :: proc(character: u8) -> bool {
	return character == ' ' || character == '\t'
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
	end := end_index


	if start >= end {
		append(lines, Text_Line{text = "", width = 0})

		return
	}


	if wrapped {
		for start < end && TextLabel_Is_Break_Character(text[start]) {
			start += 1
		}
	}

	if start >= end {
		append(lines, Text_Line{text = "", width = 0})

		return
	}


	if !wrapped || max_width <= 0 {
		line_text := text[start:end]

		append(
			lines,
			Text_Line {
				text = line_text,
				width = TextLabel_Measure_Text(label, line_text, font_size),
			},
		)

		return
	}


	line_start := start

	word_start := start

	cursor := start

	for cursor <= end {
		at_end := cursor == end

		at_break := !at_end && TextLabel_Is_Break_Character(text[cursor])

		if !at_end && !at_break {
			cursor += 1
			continue
		}

		word_end := cursor

		candidate := text[line_start:word_end]

		candidate_width := TextLabel_Measure_Text(label, candidate, font_size)


		if candidate_width > max_width && word_start > line_start {

			line_end := word_start


			for line_end > line_start && TextLabel_Is_Break_Character(text[line_end - 1]) {
				line_end -= 1
			}

			line_text := text[line_start:line_end]

			append(
				lines,
				Text_Line {
					text = line_text,
					width = TextLabel_Measure_Text(label, line_text, font_size),
				},
			)

			line_start = word_start
		}

		if at_end {
			break
		}


		cursor += 1

		for cursor < end && TextLabel_Is_Break_Character(text[cursor]) {
			cursor += 1
		}

		word_start = cursor
	}


	if line_start <= end {
		line_end := end

		for line_end > line_start && TextLabel_Is_Break_Character(text[line_end - 1]) {
			line_end -= 1
		}

		line_text := text[line_start:line_end]

		append(
			lines,
			Text_Line {
				text = line_text,
				width = TextLabel_Measure_Text(label, line_text, font_size),
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
	lines := make([dynamic]Text_Line)

	text := label.text


	if len(text) == 0 {
		append(&lines, Text_Line{text = "", width = 0})

		return lines
	}

	paragraph_start := 0

	index := 0

	for index <= len(text) {
		at_end := index == len(text)

		is_newline := !at_end && text[index] == '\n'

		if at_end || is_newline {

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

			paragraph_start = index + 1
		}

		index += 1
	}

	return lines
}


TextLabel_Get_Bounds :: proc(
	label: ^TextLabel,
	lines: []Text_Line,
	font_size: f32,
) -> datatypes.Vector2 {
	if label == nil {
		return datatypes.Vector2_Zero
	}

	width: f32 = 0

	for line in lines {
		width = max(width, line.width)
	}

	line_height := TextLabel_Get_Base_Line_Height(label, font_size) * label.line_height

	height := line_height * f32(len(lines))

	return datatypes.Vector2{width, height}
}


TextLabel_Measure_Content :: proc(
	label: ^TextLabel,
	available_width: f32,
	measure: ^Text_Measure_Cache = nil,
) -> datatypes.Vector2 {
	if label == nil || label.stored_typeface == nil || len(label.text) == 0 {
		return datatypes.Vector2_Zero
	}

	padding := max(label.text_padding, 0)

	font_size := label.text_size

	max_width := available_width - padding * 2

	if max_width < 0 {
		max_width = 0
	}

	cache := measure if measure != nil else &label.render_layout.measure
	width := max_width if label.text_wrapped else 0
	if !cache.valid || cache.width != width ||
	   cache.font_size != font_size || cache.line_height != label.line_height {
		lines := TextLabel_Build_Lines(label, width, font_size, width > 0)
		defer delete(lines)
		cache^ = {
			valid = true,
			width = width,
			font_size = font_size,
			line_height = label.line_height,
			bounds = TextLabel_Get_Bounds(label, lines[:], font_size),
		}
	}
	bounds := cache.bounds

	return datatypes.Vector2{bounds.X + padding * 2, bounds.Y + padding * 2}
}

TextLabel_Fits_Size :: proc(
	label: ^TextLabel,
	font_size: f32,
	max_width: f32,
	max_height: f32,
) -> bool {
	lines := TextLabel_Build_Lines(label, max_width, font_size, label.text_wrapped)

	defer delete(lines)

	bounds := TextLabel_Get_Bounds(label, lines[:], font_size)

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

	if len(label.text) == 0 || max_width <= 0 || max_height <= 0 {
		return label.text_size
	}


	low: f32 = 1

	high: f32 = max(label.text_size, 256)

	best: f32 = 1

	for _ in 0 ..< 10 {
		middle := (low + high) * 0.5

		if TextLabel_Fits_Size(label, middle, max_width, max_height) {
			best = middle

			low = middle
		} else {
			high = middle
		}
	}

	return max(best, 1)
}


TextLabel_Get_Line_X :: proc(
	label: ^TextLabel,
	content_x: f32,
	content_width: f32,
	line_width: f32,
) -> f32 {
	switch label.text_x_alignment {

	case TEXT_X_CENTER:
		return content_x + (content_width - line_width) * 0.5

	case TEXT_X_RIGHT:
		return content_x + content_width - line_width

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
		return content_y + content_height - text_height

	case:
		return content_y
	}
}

TextLabel_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	label := new(TextLabel)

	label^ = TextLabel_Init()

	label.name = "TextLabel"

	TextLabel_Load_Typeface(label)

	return &label.object
}


TextLabel_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	label := cast(^TextLabel)object

	TextLabel_Destroy_Typeface(label)

	delete(label.owned_text)

	label.owned_text = ""

	label.text = ""

	datatypes.Font_Destroy(&label.font_face)

	GuiObject_Free_Signals(cast(^GuiObject)object)

	Object_Destroy(object)

	free(label)
}


TextLabel_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	label := cast(^TextLabel)object

	switch key {

	case "Text":
		vm.PushString(L, label.text)

	case "Font":
		if datatypes.Font_Has_Memory(label.font_face) {
			if datatype_registry == nil {
				return false
			}

			datatypes.Push_Font(L, datatype_registry, label.font_face)
		} else if enum_registry != nil {
			if !enums.Push_Item_By_Value(L, enum_registry, "Font", i64(label.font_enum)) {
				vm.PushString(L, label.font_face.Family)
			}
		} else {
			vm.PushString(L, label.font_face.Family)
		}

	case "FontFace":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Font(L, datatype_registry, label.font_face)

	case "FontSize":
		if enum_registry == nil {
			return false
		}
		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"FontSize",
			i64(text_label_font_size_enum(label.text_size)),
		)

	case "RichText":
		vm.PushBoolean(L, label.rich_text)

	case "TruncateAtEnd":
		vm.PushBoolean(L, label.truncate_at_end)

	case "TextSize":
		vm.PushNumber(L, f64(label.text_size))

	case "TextColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(L, datatype_registry, label.text_color3)

	case "TextTransparency":
		vm.PushNumber(L, f64(label.text_transparency))

	case "TextStrokeColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(L, datatype_registry, label.text_stroke_color3)

	case "TextStrokeTransparency":
		vm.PushNumber(L, f64(label.text_stroke_transparency))

	case "TextStrokeThickness":
		vm.PushNumber(L, f64(label.text_stroke_thickness))

	case "TextWrapped":
		vm.PushBoolean(L, label.text_wrapped)

	case "TextScaled":
		vm.PushBoolean(L, label.text_scaled)

	case "TextXAlignment":
		if enum_registry != nil {
			value: i64 =
				label.text_x_alignment == TEXT_X_RIGHT ? 1 : label.text_x_alignment == TEXT_X_CENTER ? 2 : 0
			if !enums.Push_Item_By_Value(
				L,
				enum_registry,
				"TextXAlignment",
				value,
			) {vm.PushString(L, label.text_x_alignment)}
		} else {
			vm.PushString(L, label.text_x_alignment)
		}

	case "TextYAlignment":
		if enum_registry != nil {
			value: i64 =
				label.text_y_alignment == TEXT_Y_CENTER ? 1 : label.text_y_alignment == TEXT_Y_BOTTOM ? 2 : 0
			if !enums.Push_Item_By_Value(
				L,
				enum_registry,
				"TextYAlignment",
				value,
			) {vm.PushString(L, label.text_y_alignment)}
		} else {
			vm.PushString(L, label.text_y_alignment)
		}

	case "LineHeight":
		vm.PushNumber(L, f64(label.line_height))

	case "TextPadding":
		vm.PushNumber(L, f64(label.text_padding))

	case "TextBounds":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(L, datatype_registry, label.text_bounds)

	case:
		return GuiObject_get(L, object, datatype_registry, enum_registry, key)
	}

	return true
}


text_label_affects_layout :: proc(key: string) -> bool {
	switch key {
	case "Text",
	     "Font",
	     "FontFace",
	     "FontSize",
	     "RichText",
	     "TruncateAtEnd",
	     "TextSize",
	     "TextWrapped",
	     "TextScaled",
	     "LineHeight",
	     "TextPadding":
		return true
	}
	return false
}


TextLabel_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	label := cast(^TextLabel)object

	// Only the properties that feed measurement invalidate the layout; colour,
	// transparency and alignment are render-only and are often tweened every
	// frame, so dirtying on them would defeat the clean-layout skip.
	if key != "Text" && text_label_affects_layout(key) {
		Gui_Layout_Mark_Dirty()
	}

	switch key {

	case "Text":
		value := vm.ArgString(L, value_index)
		if label.owned_text == value {return true}
		Gui_Layout_Mark_Dirty()
		text_render_layout_clear(&label.render_layout)

		copy := strings.clone(value)

		delete(label.owned_text)

		label.owned_text = copy

		label.text = copy


	case "Font":
		if enum_registry != nil && vm.IsUserdataType(L, value_index, &enum_registry.item_binding) {
			item := enums.Arg_Item(L, value_index, enum_registry, "Font")
			if item == nil {
				return true
			}

			TextLabel_Set_Font_Enum(label, enums.Font(item.value))
		} else if datatype_registry != nil &&
		   vm.IsUserdataType(L, value_index, &datatype_registry.font) {


			TextLabel_Set_Font_Face(label, datatypes.Arg_Font(L, value_index, datatype_registry))
		} else {
			TextLabel_Set_Font_Family(label, vm.ArgString(L, value_index))
		}


	case "FontFace":
		if datatype_registry == nil {
			return false
		}

		font := datatypes.Arg_Font(L, value_index, datatype_registry)

		TextLabel_Set_Font_Face(label, font)


	case "FontSize":
		if enum_registry == nil {
			return false
		}
		size_item := enums.Arg_Item(L, value_index, enum_registry, "FontSize")
		if size_item == nil {
			return false
		}
		label.text_size = text_label_font_size_pixels(enums.FontSize(size_item.value))

	case "RichText":
		label.rich_text = vm.ArgBoolean(L, value_index)

	case "TruncateAtEnd":
		label.truncate_at_end = vm.ArgBoolean(L, value_index)

	case "TextSize":
		label.text_size = max(f32(vm.ArgNumber(L, value_index)), 1)


	case "TextColor3":
		if datatype_registry == nil {
			return false
		}

		label.text_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)


	case "TextTransparency":
		label.text_transparency = clamp(f32(vm.ArgNumber(L, value_index)), 0, 1)


	case "TextStrokeColor3":
		if datatype_registry == nil {
			return false
		}

		label.text_stroke_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)


	case "TextStrokeTransparency":
		label.text_stroke_transparency = clamp(f32(vm.ArgNumber(L, value_index)), 0, 1)


	case "TextStrokeThickness":
		label.text_stroke_thickness = max(f32(vm.ArgNumber(L, value_index)), 0)


	case "TextWrapped":
		label.text_wrapped = vm.ArgBoolean(L, value_index)


	case "TextScaled":
		label.text_scaled = vm.ArgBoolean(L, value_index)


	case "TextXAlignment":
		value := ""
		if enum_registry != nil && vm.IsUserdataType(L, value_index, &enum_registry.item_binding) {
			item := enums.Arg_Item(L, value_index, enum_registry, "TextXAlignment")
			if item == nil {return true}
			value = enums.Item_Name(item)
		} else {
			value = vm.ArgString(L, value_index)
		}

		if value != TEXT_X_LEFT && value != TEXT_X_CENTER && value != TEXT_X_RIGHT {

			_ = vm.RaiseError(L, "TextXAlignment must be Left, Center, or Right")

			return true
		}

		label.text_x_alignment = value


	case "TextYAlignment":
		value := ""
		if enum_registry != nil && vm.IsUserdataType(L, value_index, &enum_registry.item_binding) {
			item := enums.Arg_Item(L, value_index, enum_registry, "TextYAlignment")
			if item == nil {return true}
			value = enums.Item_Name(item)
		} else {
			value = vm.ArgString(L, value_index)
		}

		if value != TEXT_Y_TOP && value != TEXT_Y_CENTER && value != TEXT_Y_BOTTOM {

			_ = vm.RaiseError(L, "TextYAlignment must be Top, Center, or Bottom")

			return true
		}

		label.text_y_alignment = value


	case "LineHeight":
		label.line_height = max(f32(vm.ArgNumber(L, value_index)), 0.1)


	case "TextPadding":
		label.text_padding = max(f32(vm.ArgNumber(L, value_index)), 0)


	case "TextBounds":
		_ = vm.RaiseError(L, "TextBounds is read-only")

		return true


	case:
		return GuiObject_set(L, object, datatype_registry, enum_registry, key, value_index)
	}

	return true
}


TextLabel_render :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	label := cast(^TextLabel)object
	text_label_render(label, ctx, &label.render_layout)
}

text_render_layout_free_lines :: proc(layout: ^Text_Render_Layout) {
	for line in layout.lines {
		delete(line.draw_text, layout.lines.allocator)
	}
	delete(layout.lines)
}

text_render_layout_clear :: proc(layout: ^Text_Render_Layout) {
	text_render_layout_free_lines(layout)
	layout^ = {}
}

text_label_render :: proc(label: ^TextLabel, ctx: ^Class_Step_Context, layout: ^Text_Render_Layout) {
	object := &label.object
	rect, visible := GuiObject_get_rect(object, ctx)

	if !visible {
		return
	}


	GuiObject_render(object, ctx)

	if label.stored_typeface == nil {
		label.text_bounds = datatypes.Vector2_Zero

		return
	}


	padding := max(label.text_padding, 0)

	content_x := rect.x + padding

	content_y := rect.y + padding

	content_width := max(rect.width - padding * 2, 0)

	content_height := max(rect.height - padding * 2, 0)

	if content_width <= 0 || content_height <= 0 {
		label.text_bounds = datatypes.Vector2_Zero

		return
	}


	inputs := layout.inputs
	inputs.width = content_width if label.text_wrapped || label.text_scaled else 0
	inputs.height = content_height if label.text_scaled else 0
	inputs.text_size = label.text_size
	inputs.line_height = label.line_height
	inputs.wrapped = label.text_wrapped
	inputs.scaled = label.text_scaled
	if layout.lines == nil || layout.inputs != inputs {
		text_render_layout_free_lines(layout)
		layout.inputs = inputs
		layout.font_size = TextLabel_Get_Effective_Font_Size(label, content_width, content_height)
		layout.lines = TextLabel_Build_Lines(label, content_width, layout.font_size, label.text_wrapped)
		for &line in layout.lines {
			line.draw_text = strings.clone_to_cstring(line.text, layout.lines.allocator)
		}
		layout.bounds = TextLabel_Get_Bounds(label, layout.lines[:], layout.font_size)
		layout.line_height = TextLabel_Get_Base_Line_Height(label, layout.font_size) * label.line_height
		layout.ascent = TextLabel_Get_Ascent(label, layout.font_size)
	}
	label.text_bounds = layout.bounds

	block_y := TextLabel_Get_Block_Y(label, content_y, content_height, label.text_bounds.Y)


	guilib.save(ctx.renderer.SkiaSurface)

	defer guilib.restore(ctx.renderer.SkiaSurface)

	guilib.clipRect(
		ctx.renderer.SkiaSurface,
		guilib.Rect{x = content_x, y = content_y, width = content_width, height = content_height},
	)


	shadow_object := Find_First_Child_Of_Class(object, "UIShadow")

	shadow: ^UIShadow = nil

	if shadow_object != nil {
		shadow = cast(^UIShadow)shadow_object
	}


	for line, index in layout.lines {
		line_x := TextLabel_Get_Line_X(label, content_x, content_width, line.width)

		line_top := block_y + f32(index) * layout.line_height

		baseline := line_top + layout.ascent

		ctext := line.draw_text

		text_params := guilib.TextParams {
			x            = line_x,
			y            = baseline,
			TextSize     = layout.font_size,
			color        = label.text_color3,
			transparency = label.text_transparency,
			font         = nil,
			typeface     = label.stored_typeface,
		}


		if shadow != nil && shadow.enabled && shadow.showfortext {

			short_edge := min(rect.width, rect.height)

			offset_x := shadow.offset.X_Scale * rect.width + shadow.offset.X_Offset

			offset_y := shadow.offset.Y_Scale * rect.height + shadow.offset.Y_Offset

			spread_x := shadow.spread.X_Scale * rect.width + shadow.spread.X_Offset

			spread_y := shadow.spread.Y_Scale * rect.height + shadow.spread.Y_Offset

			shadow_params := guilib.ShadowParams {
				offsetX   = offset_x,
				offsetY   = offset_y,
				blurSigma = max(f32(0), gui_resolve_udim(shadow.blur_radius, short_edge)),
				spread    = max(f32(0), (spread_x + spread_y) * 0.5),
				color     = shadow.color,
				alpha     = 1 - f32(shadow.transparency),
			}

			guilib.drawTextShadow(ctx.renderer.SkiaSurface, ctext, text_params, shadow_params)
		}


		if label.text_stroke_transparency < 1 && label.text_stroke_thickness > 0 {

			stroke_params := guilib.ShadowParams {
				offsetX   = 0,
				offsetY   = 0,
				blurSigma = 0,
				spread    = label.text_stroke_thickness,
				color     = label.text_stroke_color3,
				alpha     = 1 - label.text_stroke_transparency,
			}

			guilib.drawTextShadow(ctx.renderer.SkiaSurface, ctext, text_params, stroke_params)
		}


		guilib.drawText(ctx.renderer.SkiaSurface, ctext, text_params)

	}
}


TextLabel_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^TextLabel)source

	dst := cast(^TextLabel)destination


	delete(dst.owned_text)

	dst.owned_text = strings.clone(src.text)

	dst.text = dst.owned_text


	TextLabel_Destroy_Typeface(dst)

	datatypes.Font_Destroy(&dst.font_face)

	dst.font_face = datatypes.Font_Clone(src.font_face)

	dst.font_enum = src.font_enum

	TextLabel_Load_Typeface(dst)


	dst.text_size = src.text_size

	dst.text_color3 = src.text_color3

	dst.text_transparency = src.text_transparency

	dst.text_stroke_color3 = src.text_stroke_color3

	dst.text_stroke_transparency = src.text_stroke_transparency

	dst.text_stroke_thickness = src.text_stroke_thickness


	dst.text_x_alignment = src.text_x_alignment

	dst.text_y_alignment = src.text_y_alignment

	dst.text_wrapped = src.text_wrapped

	dst.text_scaled = src.text_scaled

	dst.line_height = src.line_height

	dst.text_padding = src.text_padding

	dst.text_bounds = src.text_bounds
}


Register_TextLabel :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&TextLabel_Class,
		TextLabel_construct,
		TextLabel_destroy,
		get = TextLabel_get,
		set = TextLabel_set,
		clone = TextLabel_clone,
		properties = []string {
			"Text",
			"Font",
			"FontFace",
			"TextSize",
			"TextColor3",
			"TextTransparency",
			"RichText",
			"TruncateAtEnd",
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
