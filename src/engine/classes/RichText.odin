package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import "core:fmt"
import "core:strconv"
import "core:strings"

Rich_Text_Style :: struct {
	color:                                 datatypes.Color3,
	has_color:                             bool,
	transparency:                          f32,
	has_transparency:                      bool,
	size:                                  f32,
	underline, strike:                     bool,
	face:                                  string,
	weight:                                i32,
	italic:                                bool,
	baseline_shift:                        i32,
	has_stroke:                            bool,
	stroke_color:                          datatypes.Color3,
	stroke_thickness, stroke_transparency: f32,
	has_mark:                              bool,
	mark_color:                            datatypes.Color3,
	mark_transparency:                     f32,
}

Rich_Text_Span :: struct {
	start, end: int,
	style:      Rich_Text_Style,
}

Rich_Text_Run :: struct {
	text:               cstring,
	width, size, shift: f32,
	typeface:           ^kineffi.KineSkiaTypeface,
	style:              Rich_Text_Style,
}

Rich_Text_Font_Key :: struct {
	face:   string,
	weight: i32,
	italic: bool,
}

Rich_Text_Document :: struct {
	text:           [dynamic]u8,
	spans:          [dynamic]Rich_Text_Span,
	faces:          map[string]^kineffi.KineSkiaTypeface,
	resolved_faces: map[Rich_Text_Font_Key]^kineffi.KineSkiaTypeface,
}

rich_text_append :: proc(doc: ^Rich_Text_Document, value: string, style: Rich_Text_Style) {
	if len(value) == 0 {return}
	start := len(doc.text)
	append(&doc.text, ..transmute([]u8)value)
	if len(doc.spans) > 0 && doc.spans[len(doc.spans) - 1].style == style {
		doc.spans[len(doc.spans) - 1].end = len(doc.text)
	} else {
		append(&doc.spans, Rich_Text_Span{start, len(doc.text), style})
	}
}

rich_text_color :: proc(value: string) -> (color: datatypes.Color3, ok: bool) {
	if len(value) == 4 && value[0] == '#' {
		n, valid := strconv.parse_u64(value[1:], 16)
		if valid {return {f32((n >> 8) & 15) / 15, f32((n >> 4) & 15) / 15, f32(n & 15) / 15}, true}
	}
	if len(value) == 7 && value[0] == '#' {
		n, valid := strconv.parse_u64(value[1:], 16)
		if valid {return {f32((n >> 16) & 255) / 255, f32((n >> 8) & 255) / 255, f32(n & 255) / 255}, true}
	}
	if strings.has_prefix(value, "rgb(") && strings.has_suffix(value, ")") {
		body := value[4:len(value) - 1]
		channels: [3]f32
		for i in 0 ..< 3 {
			part := body
			if i < 2 {
				comma := strings.index_byte(body, ',')
				if comma < 0 {return}
				part = body[:comma]
				body = body[comma + 1:]
			}
			n, valid := strconv.parse_i64(strings.trim_space(part), 10)
			if !valid || n < 0 || n > 255 {return}
			channels[i] = f32(n) / 255
		}
		return {channels[0], channels[1], channels[2]}, true
	}
	return
}

rich_text_attributes :: proc(tag, attributes: string, style: ^Rich_Text_Style) -> bool {
	body := attributes
	for len(body) > 0 {
		body = strings.trim_space(body)
		if len(body) == 0 {break}
		eq := strings.index_byte(body, '=')
		if eq <= 0 {return false}
		key := strings.trim_space(body[:eq])
		body = strings.trim_space(body[eq + 1:])
		if len(body) < 2 || (body[0] != '"' && body[0] != '\'') {return false}
		end := strings.index_byte(body[1:], body[0])
		if end < 0 {return false}
		value := body[1:end + 1]
		body = body[end + 2:]
		switch key {
		case "color":
			color, ok := rich_text_color(value)
			if !ok {return false}
			switch tag {
			case "stroke":
				style.stroke_color = color
			case "mark":
				style.mark_color = color
			case:
				style.color, style.has_color = color, true
			}
		case "size":
			size, ok := strconv.parse_f64(value)
			if !ok || !(size >= 1 && size <= 512) {return false}
			style.size = f32(size)
		case "transparency":
			t, ok := strconv.parse_f64(value)
			if !ok || !(t >= 0 && t <= 1) {return false}
			switch tag {
			case "stroke":
				style.stroke_transparency = f32(t)
			case "mark":
				style.mark_transparency = f32(t)
			case:
				style.transparency, style.has_transparency = f32(t), true
			}
		case "face", "family":
			if len(value) > 128 {return false}
			style.face = value
		case "weight":
			weight, ok := rich_text_weight(value)
			if !ok {return false}
			style.weight = weight
		case "style":
			switch value {
			case "Italic", "italic":
				style.italic = true
			case "Normal", "normal":
				style.italic = false
			case:
				return false
			}
		case "thickness":
			thickness, ok := strconv.parse_f64(value)
			if !ok || !(thickness >= 0 && thickness <= 32) {return false}
			style.stroke_thickness = f32(thickness)
		}
	}
	return true
}

rich_text_parse :: proc(source: string) -> Rich_Text_Document {
	doc: Rich_Text_Document
	style: Rich_Text_Style
	Entry :: struct {
		tag:   string,
		style: Rich_Text_Style,
	}
	stack: [64]Entry
	depth := 0
	i := 0
	for i < len(source) {
		if source[i] == '<' {
			end := strings.index_byte(source[i:min(i + 4097, len(source))], '>')
			if end > 0 && end <= 4096 {
				body := strings.trim_space(source[i + 1:i + end])
				consumed := false
				if body == "br" || body == "br/" || body == "br /" {
					rich_text_append(&doc, "\n", style)
					consumed = true
				} else if strings.has_prefix(body, "/") {
					if depth > 0 && stack[depth - 1].tag == strings.trim_space(body[1:]) {
						depth -= 1
						style = stack[depth].style
						consumed = true
					}
				} else if depth < len(stack) {
					tag := body
					attrs := ""
					for c, j in body {
						if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
							tag, attrs = body[:j], body[j:]
							break
						}
					}
					next := style
					switch tag {
					case "font":
						consumed = rich_text_attributes(tag, attrs, &next)
					case "b":
						next.weight = 700; consumed = true
					case "i":
						next.italic = true; consumed = true
					case "sup":
						next.baseline_shift = 1; consumed = true
					case "sub":
						next.baseline_shift = -1; consumed = true
					case "stroke":
						next.has_stroke = true
						next.stroke_color = {0, 0, 0}
						next.stroke_thickness = 1
						next.stroke_transparency = 0
						consumed = rich_text_attributes(tag, attrs, &next)
					case "mark":
						next.has_mark = true
						next.mark_color = {1, 1, 0}
						next.mark_transparency = 0.5
						consumed = rich_text_attributes(tag, attrs, &next)
					case "u":
						next.underline = true; consumed = true
					case "s":
						next.strike = true; consumed = true
					}
					if consumed {
						stack[depth] = {tag, style}
						depth += 1
						style = next
					}
				}
				if consumed {i += end + 1; continue}
			}
		}
		if source[i] == '&' {
			end := strings.index_byte(source[i:min(i + 7, len(source))], ';')
			if end > 0 {
				entity := source[i:i + end + 1]
				decoded := ""
				switch entity {
				case "&lt;":
					decoded = "<"
				case "&gt;":
					decoded = ">"
				case "&amp;":
					decoded = "&"
				case "&quot;":
					decoded = "\""
				case "&apos;":
					decoded = "'"
				}
				if decoded != "" {
					rich_text_append(&doc, decoded, style)
					i += end + 1
					continue
				}
			}
		}
		start := i
		i += 1
		for i < len(source) && source[i] != '<' && source[i] != '&' {i += 1}
		rich_text_append(&doc, source[start:i], style)
	}
	return doc
}

rich_text_size :: proc(label: ^TextLabel, style: Rich_Text_Style, font_size: f32) -> f32 {
	size := style.size * font_size / max(1, label.text_size) if style.size > 0 else font_size
	return size * 0.7 if style.baseline_shift != 0 else size
}

rich_text_weight :: proc(value: string) -> (i32, bool) {
	switch value {
	case "Thin", "thin":
		return 100, true
	case "ExtraLight", "extralight":
		return 200, true
	case "Light", "light":
		return 300, true
	case "Regular", "regular", "Normal", "normal":
		return 400, true
	case "Medium", "medium":
		return 500, true
	case "SemiBold", "semibold":
		return 600, true
	case "Bold", "bold":
		return 700, true
	case "ExtraBold", "extrabold":
		return 800, true
	case "Black", "black":
		return 900, true
	}
	n, ok := strconv.parse_i64(value, 10)
	return i32(n), ok && n >= 100 && n <= 900
}

rich_text_font_family :: proc(name: string) -> string {
	switch name {
	case "Gotham", "Montserrat":
		return "Montserrat-Regular.ttf"
	case "SourceSans", "SourceSans3":
		return "SourceSans3-Regular.ttf"
	case "Arial", "Arimo":
		return "Arimo-Regular.ttf"
	case "Roboto":
		return "Roboto-Regular.ttf"
	case "RobotoMono", "rbxasset://fonts/families/RobotoMono.json":
		return "RobotoMono-Regular.ttf"
	case "Code", "GoogleSansCode":
		return "GoogleSansCode-Regular.ttf"
	case "Ubuntu":
		return "Ubuntu-Regular.ttf"
	}
	if strings.has_prefix(name, BUILTIN_FONT_PREFIX) {return name[len(BUILTIN_FONT_PREFIX):]}
	if strings.has_suffix(name, ".ttf") || strings.has_suffix(name, ".otf") {return name}
	return ""
}

rich_text_font_variant :: proc(family: string, weight: i32, italic: bool) -> string {
	if len(family) == 0 {return ""}
	dash := strings.last_index_byte(family, '-')
	if dash < 0 {return ""}
	stem := family[:dash]
	suffix := "Regular"
	switch {
	case weight >= 850:
		suffix = "Black"
	case weight >= 750:
		suffix = "ExtraBold"
	case weight >= 650:
		suffix = "Bold"
	case weight >= 550:
		suffix = "SemiBold"
	case weight >= 450:
		suffix = "Medium"
	case weight <= 150:
		suffix = "Thin"
	case weight <= 250:
		suffix = "ExtraLight"
	case weight <= 350:
		suffix = "Light"
	}
	if italic {
		if suffix == "Regular" {suffix = "Italic"} else {suffix = fmt.tprintf("%sItalic", suffix)}
	}
	return fmt.tprintf("%s-%s.ttf", stem, suffix)
}

rich_text_get_face :: proc(
	doc: ^Rich_Text_Document,
	label: ^TextLabel,
	style: Rich_Text_Style,
) -> ^kineffi.KineSkiaTypeface {
	if style.face == "" && style.weight == 0 && !style.italic {return label.stored_typeface}
	if doc.resolved_faces ==
	   nil {doc.resolved_faces = make(map[Rich_Text_Font_Key]^kineffi.KineSkiaTypeface)}
	key := Rich_Text_Font_Key{style.face, style.weight, style.italic}
	if face, found := doc.resolved_faces[key]; found {return face}
	family := rich_text_font_family(style.face if style.face != "" else label.font_face.Family)
	if family == "" {family = "Montserrat-Regular.ttf"}
	weight := style.weight
	if weight == 0 {
		weight = 400
		if strings.has_suffix(family, "-Bold.ttf") {weight = 700}
	}
	variant := family
	if style.weight != 0 || style.italic {
		variant = rich_text_font_variant(family, weight, style.italic)
		if _, ok := TextLabel_Find_Builtin_Font(variant); !ok {
			variant = rich_text_font_variant("Roboto-Regular.ttf", weight, style.italic)
		}
	}
	if face, ok := doc.faces[variant]; ok {
		resolved := face if face != nil else label.stored_typeface
		if len(doc.resolved_faces) < 128 {doc.resolved_faces[key] = resolved}
		return resolved
	}
	if len(doc.faces) >= 64 {return label.stored_typeface}
	face: ^kineffi.KineSkiaTypeface
	when ODIN_OS == .JS {
		if variant == "Roboto-Regular.ttf" ||
		   variant == "Roboto-Bold.ttf" ||
		   variant == "Roboto-Italic.ttf" ||
		   variant == "Roboto-BoldItalic.ttf" ||
		   variant == "Montserrat-Regular.ttf" ||
		   variant == "Montserrat-Bold.ttf" ||
		   variant == "SourceSans3-Regular.ttf" ||
		   variant == "RobotoMono-Regular.ttf" ||
		   variant == "GoogleSansCode-Regular.ttf" {
			face = TextLabel_Load_Typeface_From_Family(
				fmt.tprintf("%s%s", BUILTIN_FONT_PREFIX, variant),
			)
		}
	} else {
		if data, ok := TextLabel_Find_Builtin_Font(variant); ok {
			face = kineffi.Kine_Skia_Typeface_LoadFromMemory(raw_data(data), uintptr(len(data)))
		}
	}
	doc.faces[strings.clone(variant)] = face
	resolved := face if face != nil else label.stored_typeface
	if len(doc.resolved_faces) < 128 {doc.resolved_faces[key] = resolved}
	return resolved
}

Rich_Text_Content :: proc(source: string) -> string {
	doc := rich_text_parse(source)
	defer {delete(doc.text); delete(doc.spans)}
	return strings.clone(string(doc.text[:]))
}

rich_text_range :: proc(
	label: ^TextLabel,
	doc: ^Rich_Text_Document,
	start, end: int,
	font_size: f32,
	line: ^Text_Line = nil,
) -> f32 {
	width: f32
	lo, hi := 0, len(doc.spans)
	for lo < hi {
		mid := (lo + hi) / 2
		if doc.spans[mid].end <= start {lo = mid + 1} else {hi = mid}
	}
	for span in doc.spans[lo:] {
		if span.start >= end {break}
		a, b := max(start, span.start), min(end, span.end)
		if a >= b {continue}
		value := string(doc.text[a:b])
		size := rich_text_size(label, span.style, font_size)
		face := rich_text_get_face(doc, label, span.style)
		ctext := strings.clone_to_cstring(value)
		w := kineffi.Kine_Skia_Typeface_MeasureText(face, ctext, size)
		width += w
		if line != nil {
			shift := -f32(span.style.baseline_shift) * size * 0.5
			style := span.style
			style.face = ""
			append(&line.rich_runs, Rich_Text_Run{ctext, w, size, shift, face, style})
			ascent := kineffi.Kine_Skia_Typeface_GetAscent(face, size)
			height := kineffi.Kine_Skia_Typeface_GetLineHeight(face, size)
			descent := max(0, line.height - line.ascent, height - ascent + shift)
			line.ascent = max(line.ascent, ascent - shift)
			line.height = line.ascent + descent
		} else {
			delete(ctext)
		}
	}
	return width
}

rich_text_append_line :: proc(
	label: ^TextLabel,
	doc: ^Rich_Text_Document,
	lines: ^[dynamic]Text_Line,
	start, end: int,
	size: f32,
) {
	line := Text_Line {
		ascent = TextLabel_Get_Ascent(label, size),
		height = TextLabel_Get_Base_Line_Height(label, size),
	}
	line.width = rich_text_range(label, doc, start, end, size, &line)
	append(lines, line)
}

rich_text_build_lines :: proc(
	label: ^TextLabel,
	source: string,
	max_width, size: f32,
	wrapped: bool,
) -> [dynamic]Text_Line {
	doc := rich_text_parse(source)
	doc.faces = make(map[string]^kineffi.KineSkiaTypeface)
	defer {delete(doc.text); delete(doc.spans); delete(doc.resolved_faces)}
	lines: [dynamic]Text_Line
	start := 0
	for i in 0 ..= len(doc.text) {
		if i < len(doc.text) && doc.text[i] != '\n' {continue}
		if !wrapped || max_width <= 0 {
			rich_text_append_line(label, &doc, &lines, start, i, size)
		} else {
			for start < i && TextLabel_Is_Break_Character(doc.text[start]) {start += 1}
			line_start, word_start := start, start
			width: f32
			cursor := start
			for cursor < i {
				for cursor < i && TextLabel_Is_Break_Character(doc.text[cursor]) {cursor += 1}
				word_start = cursor
				for cursor < i && !TextLabel_Is_Break_Character(doc.text[cursor]) {cursor += 1}
				if word_start == cursor {break}
				word_width := rich_text_range(label, &doc, word_start, cursor, size)
				gap_width := rich_text_range(label, &doc, start, word_start, size)
				if width > 0 && width + gap_width + word_width > max_width {
					rich_text_append_line(label, &doc, &lines, line_start, start, size)
					line_start = word_start
					width = word_width
				} else {width += gap_width + word_width}
				start = cursor
			}
			rich_text_append_line(label, &doc, &lines, line_start, start, size)
		}
		start = i + 1
	}
	for key, face in doc.faces {
		delete(key)
		if face != nil {append(&lines[0].rich_faces, face)}
	}
	delete(doc.faces)
	return lines
}

TextLabel_Free_Lines :: proc(lines: ^[dynamic]Text_Line) {
	for line in lines^ {
		delete(line.draw_text, lines.allocator)
		for run in line.rich_runs {delete(run.text)}
		delete(line.rich_runs)
		for face in line.rich_faces {kineffi.Kine_Skia_Typeface_Destroy(face)}
		delete(line.rich_faces)
	}
	delete(lines^)
	lines^ = nil
}
