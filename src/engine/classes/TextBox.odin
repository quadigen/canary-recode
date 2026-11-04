package classes

import "core:strings"

import sdl3 "../platform"

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import signals "../signals"
import vm "../vm"
import "core:strconv"

TEXTBOX_IS_USED := false
TEXTBOX_ERROR_COLOR :: datatypes.Color3{0.91, 0.29, 0.29}


TEXTBOX_DIAGNOSTIC_SQUIGGLE_OFFSET :: f32(1)

TextBox_Class := Class_Info {
	name   = "TextBox",
	parent = &GuiObject_Class,
}


TextBox_Diagnostic :: struct {
	line:         int,
	start_column: int,
	end_column:   int,
	message:      string,
}

Undo_Entry :: struct {
	start:       int,
	delete_text: string,
	insert_text: string,
	epoch:       int,
}

TextBox :: struct {
	using gui_object:       GuiObject,
	text:                   string,
	placeholder_text:       string,
	text_size:              f32,
	text_color3:            datatypes.Color3,
	placeholder_color3:     datatypes.Color3,
	text_transparency:      f32,
	font_face:              datatypes.Font,
	font_enum:              enums.Font,
	stored_typeface:        ^kineffi.KineSkiaTypeface,
	clear_text_on_focus:    bool,
	text_editable:          bool,
	select_all_on_focus:    bool,
	code_editor:            bool,
	show_line_numbers:      bool,
	show_minimap:           bool,
	tab_size:               int,
	auto_indent:            bool,
	max_length:             int,
	focused:                bool,
	cursor_byte:            int,
	selection_anchor:       int,
	drag_selecting:         bool,
	key_handled:            bool,
	key_down:               ^signals.Signal,
	caret_color3:           datatypes.Color3,
	selection_color3:       datatypes.Color3,
	selection_transparency: f32,
	focus_color3:           datatypes.Color3,
	focus_lost:             ^signals.Signal,
	text_changed:           ^signals.Signal,
	focus_animation:        f32,
	caret_timer:            f32,
	scroll_x:               f32,
	scroll_target_x:        f32,
	scroll_y:               f32,
	scroll_target_y:        f32,
	preferred_x:            f32,
	preferred_x_valid:      bool,
	caret_needs_scroll:     bool,
	caret_screen_position:  datatypes.Vector2,
	auto_close:             bool,
	wrap:                   bool,
	diagnostics:            [dynamic]TextBox_Diagnostic,
	undo_stack:             [dynamic]Undo_Entry,
	redo_stack:             [dynamic]Undo_Entry,
	suppress_undo:          bool,
	undo_epoch:             int,
}


text_box_focused: ^TextBox


TextBox_Focused :: proc() -> ^TextBox {
	return text_box_focused
}


TextBox_Init :: proc() -> TextBox {
	gui := GuiObject_Init()
	gui.object.class = &TextBox_Class

	font := datatypes.Font_New(DEFAULT_FONT, .Regular, .Normal)

	return TextBox {
		gui_object = gui,
		text = strings.clone(""),
		placeholder_text = strings.clone(""),
		text_size = 16,
		text_color3 = datatypes.Color3{0, 0, 0},
		placeholder_color3 = datatypes.Color3{0.5, 0.5, 0.5},
		text_transparency = 0,
		font_face = font,
		font_enum = .Legacy,
		stored_typeface = nil,
		clear_text_on_focus = false,
		text_editable = true,
		select_all_on_focus = false,
		code_editor = false,
		show_line_numbers = true,
		show_minimap = false,
		tab_size = 4,
		auto_indent = true,
		max_length = -1,
		focused = false,
		cursor_byte = 0,
		selection_anchor = 0,
		drag_selecting = false,
		key_handled = false,
		key_down = nil,
		caret_color3 = datatypes.Color3{0.25, 0.5, 1.0},
		selection_color3 = datatypes.Color3{0.25, 0.5, 1.0},
		selection_transparency = 0.65,
		focus_color3 = datatypes.Color3{0.25, 0.5, 1.0},
		focus_animation = 0,
		caret_timer = 0,
		scroll_x = 0,
		scroll_y = 0,
		scroll_target_y = 0,
		preferred_x = 0,
		preferred_x_valid = false,
		caret_needs_scroll = true,
		scroll_target_x = 0,
		caret_screen_position = datatypes.Vector2_Zero,
		auto_close = true,
		wrap = false,
	}
}


TextBox_Load_Typeface :: proc(box: ^TextBox) {
	if box == nil {
		return
	}

	TextBox_Destroy_Typeface(box)

	box.stored_typeface = TextLabel_Load_Typeface_From_Font(box.font_face)
}


TextBox_Set_Font_Memory :: proc(box: ^TextBox, data: []u8) -> bool {
	if box == nil {
		return false
	}

	font, ok := datatypes.Font_From_Memory(data, box.font_face.Weight, box.font_face.Style)
	if !ok {
		return false
	}
	defer datatypes.Font_Destroy(&font)

	datatypes.Font_Destroy(&box.font_face)

	box.font_face = datatypes.Font_Clone(font)

	box.font_enum = TextLabel_Font_Enum_From_Family(box.font_face.Family)

	TextBox_Load_Typeface(box)

	return true
}


TextBox_Destroy_Typeface :: proc(box: ^TextBox) {
	if box == nil {
		return
	}

	if box.stored_typeface != nil {
		kineffi.Kine_Skia_Typeface_Destroy(box.stored_typeface)

		box.stored_typeface = nil
	}
}


TextBox_Set_Font_Family :: proc(box: ^TextBox, family: string) {
	if box == nil {
		return
	}


	if strings.has_prefix(family, datatypes.MEMORY_FONT_PREFIX) {
		return
	}

	new_enum := TextLabel_Font_Enum_From_Family(family)

	if box.font_face.Family == family {
		box.font_enum = new_enum

		return
	}

	new_font := datatypes.Font_New(family, box.font_face.Weight, box.font_face.Style)

	datatypes.Font_Destroy(&box.font_face)

	box.font_face = new_font

	box.font_enum = new_enum

	TextBox_Load_Typeface(box)
}


TextBox_Set_Font_Enum :: proc(box: ^TextBox, font: enums.Font) {
	if box == nil {
		return
	}

	TextBox_Set_Font_Family(box, TextLabel_Font_Enum_To_Family(font))

	box.font_enum = font
}


TextBox_Set_Font_Face :: proc(box: ^TextBox, font: datatypes.Font) {
	if box == nil {
		return
	}

	if box.font_face.Family == font.Family &&
	   box.font_face.Weight == font.Weight &&
	   box.font_face.Style == font.Style &&
	   datatypes.Font_Has_Memory(box.font_face) == datatypes.Font_Has_Memory(font) {
		box.font_enum = TextLabel_Font_Enum_From_Family(font.Family)

		return
	}

	datatypes.Font_Destroy(&box.font_face)

	box.font_face = datatypes.Font_Clone(font)

	box.font_enum = TextLabel_Font_Enum_From_Family(font.Family)

	TextBox_Load_Typeface(box)
}


text_box_replace_string :: proc(target: ^string, value: string) {


	if target^ == value {
		return
	}

	replacement := strings.clone(value)

	if len(target^) > 0 {
		delete(target^)
	}

	target^ = replacement
}


text_box_restart_caret :: proc(box: ^TextBox) {
	if box == nil {
		return
	}

	box.caret_timer = 0
	box.caret_needs_scroll = true
}

undo_entry_destroy :: proc(entry: ^Undo_Entry) {
	if len(entry.delete_text) > 0 {
		delete(entry.delete_text)
	}

	if len(entry.insert_text) > 0 {
		delete(entry.insert_text)
	}
}

undo_stack_clear :: proc(stack: ^[dynamic]Undo_Entry) {
	for &entry in stack^ {
		undo_entry_destroy(&entry)
	}

	clear(stack)
}

text_box_undo_last :: proc(box: ^TextBox) -> ^Undo_Entry {
	if box == nil || len(box.undo_stack) == 0 {
		return nil
	}

	return &box.undo_stack[len(box.undo_stack) - 1]
}

text_box_fire_text_changed :: proc(box: ^TextBox) {
	if box == nil {
		return
	}


	if box.text_changed == nil {
		return
	}

	if box.object.signal_registry == nil || box.object.signal_registry.signal_registry == nil {
		return
	}

	signals.Fire(box.object.signal_registry.signal_registry.L, box.text_changed, 0)
}


text_box_fire_key_down :: proc(box: ^TextBox, registry: ^Registry, scancode: sdl3.Scancode) {
	if box == nil || registry == nil {
		return
	}

	if box.key_down == nil {
		return
	}

	if box.object.signal_registry == nil || box.object.signal_registry.signal_registry == nil {
		return
	}

	L := box.object.signal_registry.signal_registry.L

	if L == nil {
		return
	}


	input := Push_InputObject(
		L,
		registry,
		InputObject_Value {
			UserInputType = .Keyboard,
			UserInputState = .Begin,
			KeyCode = enums.Key_Code_From_Scancode(scancode),
		},
	)
	if input == nil {
		return
	}

	signals.Fire(L, box.key_down, 1)
	vm.Pop(L)


	Destroy_Hierarchy(&input.object)
}


text_box_undo :: proc(box: ^TextBox) {
	if box == nil || !box.text_editable || len(box.undo_stack) == 0 {
		return
	}

	entry := box.undo_stack[len(box.undo_stack) - 1]
	pop(&box.undo_stack)

	old := box.text

	next := strings.concatenate(
		{old[:entry.start], entry.delete_text, old[entry.start + len(entry.insert_text):]},
	)

	box.text = next

	if len(old) > 0 {
		delete(old)
	}

	box.cursor_byte = entry.start + len(entry.delete_text)

	box.selection_anchor = box.cursor_byte

	append(&box.redo_stack, entry)

	box.undo_epoch += 1

	text_box_restart_caret(box)

	text_box_fire_text_changed(box)
}

text_box_redo :: proc(box: ^TextBox) {
	if box == nil || !box.text_editable || len(box.redo_stack) == 0 {
		return
	}

	entry := box.redo_stack[len(box.redo_stack) - 1]
	pop(&box.redo_stack)

	old := box.text

	next := strings.concatenate(
		{old[:entry.start], entry.insert_text, old[entry.start + len(entry.delete_text):]},
	)

	box.text = next

	if len(old) > 0 {
		delete(old)
	}

	box.cursor_byte = entry.start + len(entry.insert_text)

	box.selection_anchor = box.cursor_byte

	append(&box.undo_stack, entry)

	box.undo_epoch += 1

	text_box_restart_caret(box)

	text_box_fire_text_changed(box)
}

text_box_line_height :: proc(box: ^TextBox) -> f32 {
	return max(box.text_size * 1.35, box.text_size + 4)
}

TextBox_Measure_Content :: proc(box: ^TextBox, available_width: f32) -> datatypes.Vector2 {
	if box == nil || box.stored_typeface == nil {
		return datatypes.Vector2_Zero
	}

	text := box.text

	line_height := text_box_line_height(box)

	max_width: f32 = 0
	line_count := 0

	start := 0
	index := 0

	for index <= len(text) {
		at_end := index == len(text)

		if at_end || text[index] == '\n' {
			line := text[start:index]
			cstrin := strings.clone_to_cstring(line)
			defer delete(cstrin)

			width := guilib.measureTextTypeface(box.stored_typeface, cstrin, box.text_size)

			max_width = max(max_width, width)
			line_count += 1
			start = index + 1
			delete(cstrin)
		}

		index += 1
	}

	if line_count == 0 {
		line_count = 1
	}

	return datatypes.Vector2{max_width, f32(line_count) * line_height}
}

text_box_decimal_digits :: proc(value: int) -> int {
	v := max(value, 1)
	result := 1

	for v >= 10 {
		v /= 10
		result += 1
	}

	return result
}

text_box_gutter_width :: proc(box: ^TextBox) -> f32 {
	if box == nil || !box.code_editor || !box.show_line_numbers {
		return 0
	}

	digits := text_box_decimal_digits(text_box_line_count(box.text))

	return f32(digits) * box.text_size * 0.62 + 18
}

text_box_measure_range :: proc(box: ^TextBox, start: int, finish: int) -> f32 {
	if box == nil {
		return 0
	}

	a := clamp(start, 0, len(box.text))
	b := clamp(finish, a, len(box.text))

	if a == b {
		return 0
	}

	value := strings.clone_to_cstring(box.text[a:b])
	defer delete(value)

	if box.stored_typeface != nil {
		return guilib.measureTextTypeface(box.stored_typeface, value, box.text_size)
	}

	return guilib.measureText(value, box.text_size, "")
}

text_box_line_start_by_index :: proc(text: string, wanted_line: int) -> int {
	if wanted_line <= 0 {
		return 0
	}

	line := 0

	for i in 0 ..< len(text) {
		if text[i] == '\n' {
			line += 1

			if line == wanted_line {
				return i + 1
			}
		}
	}

	return len(text)
}

text_box_cursor_on_line_from_x :: proc(
	box: ^TextBox,
	start: int,
	finish: int,
	target_x: f32,
	hit_glyph := false,
) -> int {
	if start >= finish {
		return start
	}

	target := max(target_x, f32(0))

	previous_index := start
	previous_width: f32 = 0

	index := start

	for index < finish {
		next := text_box_utf8_next_boundary(box.text, index)

		next = min(next, finish)

		width := text_box_measure_range(box, start, next)

		edge := hit_glyph ? width : (previous_width + width) * 0.5

		if target < edge {
			return previous_index
		}

		previous_index = next
		previous_width = width
		index = next
	}

	return hit_glyph ? text_box_utf8_prev_boundary(box.text, finish) : finish
}

text_box_cursor_from_point :: proc(
	box: ^TextBox,
	mouse_x: f32,
	mouse_y: f32,
	hit_glyph := false,
) -> int {
	if box == nil {
		return 0
	}

	if !box.code_editor {
		return text_box_cursor_from_x(box, mouse_x)
	}

	padding: f32 = 6

	line_height := text_box_line_height(box)

	y := (mouse_y - box.absolute_position.Y - padding + box.scroll_y)

	line := int(max(y / line_height, f32(0)))

	content_width := text_box_editor_content_width(box, box.absolute_size.X)

	lines := text_box_visual_lines(box, content_width)
	defer delete(lines)

	line = clamp(line, 0, max(len(lines) - 1, 0))

	chunk := lines[line]

	x := (mouse_x - box.absolute_position.X - padding - text_box_gutter_width(box) + box.scroll_x)

	return text_box_cursor_on_line_from_x(box, chunk.start, chunk.finish, x, hit_glyph)
}

text_box_set_cursor :: proc(box: ^TextBox, position: int, shift: bool) {
	if box == nil {
		return
	}

	next := clamp(position, 0, len(box.text))

	if !shift {
		box.selection_anchor = next
	}

	box.cursor_byte = next
	box.preferred_x_valid = false

	text_box_restart_caret(box)
}

text_box_move_vertical :: proc(box: ^TextBox, direction: int, shift: bool, amount: int = 1) {
	if box == nil || !box.code_editor || direction == 0 {
		return
	}

	content_width := text_box_editor_content_width(box, box.absolute_size.X)

	lines := text_box_visual_lines(box, content_width)
	defer delete(lines)

	line_count := len(lines)

	if line_count == 0 {
		return
	}

	current := text_box_visual_index_at(lines[:], box.cursor_byte)

	target_x: f32

	if box.preferred_x_valid {
		target_x = box.preferred_x
	} else {
		target_x = text_box_measure_range(box, lines[current].start, box.cursor_byte)

		box.preferred_x = target_x
		box.preferred_x_valid = true
	}

	target := clamp(current + direction * max(amount, 1), 0, line_count - 1)

	next := text_box_cursor_on_line_from_x(
		box,
		lines[target].start,
		lines[target].finish,
		target_x,
	)

	if !shift {
		box.selection_anchor = next
	}

	box.cursor_byte = next

	text_box_restart_caret(box)
}

text_box_is_word_byte :: proc(c: u8) -> bool {
	return(
		(c >= 'a' && c <= 'z') ||
		(c >= 'A' && c <= 'Z') ||
		(c >= '0' && c <= '9') ||
		c == '_' ||
		c >= 0x80 \
	)
}

text_box_is_bracket :: proc(c: u8) -> bool {
	return c == '(' || c == ')' || c == '[' || c == ']' || c == '{' || c == '}'
}

text_box_bracket_pair :: proc(text: string, index: int) -> int {
	if index < 0 || index >= len(text) || !text_box_is_bracket(text[index]) {
		return -1
	}

	open, close := byte(0), byte(0)
	backward := false

	switch text[index] {
	case '(':
		open, close = '(', ')'
	case ')':
		open, close = '(', ')'
		backward = true
	case '[':
		open, close = '[', ']'
	case ']':
		open, close = '[', ']'
		backward = true
	case '{':
		open, close = '{', '}'
	case '}':
		open, close = '{', '}'
		backward = true
	case:
		return -1
	}

	depth := 0

	if backward {
		i := index
		for i >= 0 {
			c := text[i]

			if c == close {
				depth += 1
			} else if c == open {
				depth -= 1

				if depth == 0 {
					return i
				}
			}

			i -= 1
		}
	} else {
		for i in index ..< len(text) {
			c := text[i]

			if c == open {
				depth += 1
			} else if c == close {
				depth -= 1

				if depth == 0 {
					return i
				}
			}
		}
	}

	return -1
}

text_box_bracket_highlight :: proc(box: ^TextBox) -> (first: int, second: int, has: bool) {
	if box == nil || len(box.text) == 0 {
		return -1, -1, false
	}

	p := box.cursor_byte

	if p < len(box.text) && text_box_is_bracket(box.text[p]) {
		matched := text_box_bracket_pair(box.text, p)
		return p, matched, true
	}

	if p > 0 && text_box_is_bracket(box.text[p - 1]) {
		matched := text_box_bracket_pair(box.text, p - 1)
		return p - 1, matched, true
	}

	return -1, -1, false
}

text_box_auto_close :: proc(box: ^TextBox, c: u8) -> bool {
	if box == nil {
		return false
	}

	p := box.cursor_byte
	has_next := p < len(box.text)
	next_char: u8

	if has_next {
		next_char = box.text[p]
	}

	closer := byte(0)
	is_open := false
	is_quote := false

	switch c {
	case '(':
		closer = ')'
		is_open = true
	case '[':
		closer = ']'
		is_open = true
	case '{':
		closer = '}'
		is_open = true
	case ')', ']', '}':
		if has_next && next_char == c {
			box.selection_anchor = p + 1
			box.cursor_byte = p + 1
			box.preferred_x_valid = false
			text_box_restart_caret(box)
			return true
		}

		text_box_insert(box, string([]u8{c}))
		return true
	case '"', '\'', '`':
		is_quote = true
		closer = c

		if has_next && next_char == c {
			box.selection_anchor = p + 1
			box.cursor_byte = p + 1
			box.preferred_x_valid = false
			text_box_restart_caret(box)
			return true
		}
	case:
		text_box_insert(box, string([]u8{c}))
		return true
	}

	sel_start, sel_finish, selected := text_box_selection_bounds(box)

	if selected {
		pair := strings.concatenate(
			{string([]u8{c}), box.text[sel_start:sel_finish], string([]u8{closer})},
		)
		defer delete(pair)

		text_box_replace_range(box, sel_start, sel_finish, pair)

		return true
	}

	if is_open &&
	   has_next &&
	   (next_char == c || next_char == closer || text_box_is_word_byte(next_char)) {
		text_box_insert(box, string([]u8{c}))
		return true
	}

	if is_quote && has_next && text_box_is_word_byte(next_char) {
		text_box_insert(box, string([]u8{c}))
		return true
	}

	pair := strings.concatenate({string([]u8{c}), string([]u8{closer})})
	defer delete(pair)

	text_box_insert(box, pair)

	box.cursor_byte -= 1
	box.selection_anchor = box.cursor_byte
	box.preferred_x_valid = false
	text_box_restart_caret(box)
	return true
}

text_box_handle_text :: proc(box: ^TextBox, value: string) {
	if box == nil || len(value) == 0 {
		return
	}

	if box.code_editor && box.auto_close && len(value) == 1 {
		if text_box_auto_close(box, value[0]) {
			return
		}
	}

	text_box_insert(box, value)
}

text_box_render_code_editor :: proc(
	box: ^TextBox,
	rect: guilib.Rect,
	ctx: ^Class_Step_Context,
	dt: f32,
) {
	surface := ctx.renderer.SkiaSurface

	padding: f32 = 6

	line_height := text_box_line_height(box)

	line_count := text_box_line_count(box.text)

	gutter := text_box_gutter_width(box)

	minimap_width: f32 = 0

	if box.show_minimap && rect.width >= 250 {
		minimap_width = 64
	}

	content_x := rect.x + padding + gutter

	content_width := text_box_editor_content_width(box, rect.width)

	content_height := max(rect.height - padding * 2, f32(0))

	lines := text_box_visual_lines(box, content_width)
	defer delete(lines)

	highlight := syntax_highlighter_for_box(box)

	if highlight != nil {
		syntax_highlighter_ensure(highlight, box.text)
	}

	visual_line_count := len(lines)

	caret_line := text_box_visual_index_at(lines[:], box.cursor_byte)

	caret_x_local := text_box_measure_range(box, lines[caret_line].start, box.cursor_byte)

	total_height := f32(visual_line_count) * line_height

	max_scroll_y := max(total_height - content_height, f32(0))

	if box.focused {
		box.caret_timer += dt

		for box.caret_timer >= 1.2 {
			box.caret_timer -= 1.2
		}
	}

	if box.focused && box.caret_needs_scroll {
		top := f32(caret_line) * line_height

		bottom := top + line_height

		if top < box.scroll_target_y {
			box.scroll_target_y = top
		} else if bottom > box.scroll_target_y + content_height {
			box.scroll_target_y = bottom - content_height
		}

		visible_x := caret_x_local - box.scroll_target_x

		if visible_x < 0 {
			box.scroll_target_x = caret_x_local
		} else if visible_x > content_width {
			box.scroll_target_x = caret_x_local - content_width
		}

		box.scroll_target_x = max(box.scroll_target_x, f32(0))

		box.caret_needs_scroll = false
	}

	box.scroll_target_y = clamp(box.scroll_target_y, f32(0), max_scroll_y)

	scroll_lerp := min(dt * 20, f32(1))

	box.scroll_x += (box.scroll_target_x - box.scroll_x) * scroll_lerp

	box.scroll_y += (box.scroll_target_y - box.scroll_y) * scroll_lerp


	box.caret_screen_position = datatypes.Vector2 {
		content_x + caret_x_local - box.scroll_x,
		rect.y + padding + f32(caret_line) * line_height - box.scroll_y,
	}

	guilib.save(surface)
	defer guilib.restore(surface)

	guilib.clipRect(
		surface,
		guilib.Rect {
			x = rect.x,
			y = rect.y,
			width = rect.width - minimap_width,
			height = rect.height,
		},
	)

	if box.focused {
		current_y := rect.y + padding + f32(caret_line) * line_height - box.scroll_y

		guilib.drawRect(
			surface,
			guilib.Rect {
				x = rect.x,
				y = current_y,
				width = rect.width - minimap_width,
				height = line_height,
				color = box.focus_color3,
				bgTransparency = 0.94,
			},
		)
	}

	selection_start, selection_finish, selected := text_box_selection_bounds(box)
	selected_word: string
	if selected &&
	   box.focused &&
	   !text_box_is_word_at(box.text, selection_start - 1) &&
	   !text_box_is_word_at(box.text, selection_finish) {
		word := box.text[selection_start:selection_finish]
		// Restrict occurrence highlights to short, whole identifiers.
		if len(word) <= 128 {
			selected_word = word
			for i in 0 ..< len(word) {
				if !text_box_is_word_byte(word[i]) {
					selected_word = ""
					break
				}
			}
		}
	}

	bracket_first := -1
	bracket_second := -1
	bracket_found := false

	if box.focused {
		bracket_first, bracket_second, bracket_found = text_box_bracket_highlight(box)
	}

	for line, index in lines {
		y := rect.y + padding + f32(index) * line_height - box.scroll_y

		if y + line_height >= rect.y && y <= rect.y + rect.height {
			baseline := y + (line_height - box.text_size) * 0.5 + box.text_size

			starts_text_line :=
				line.start == 0 || (line.start > 0 && box.text[line.start - 1] == '\n')

			if box.show_line_numbers && starts_text_line {
				number_buffer: [32]u8

				number := strconv.write_int(
					number_buffer[:],
					i64(text_box_line_number(box.text, line.start)),
					10,
				)

				number_text := strings.clone_to_cstring(number)
				defer delete(number_text)

				number_width := guilib.measureTextTypeface(
					box.stored_typeface,
					number_text,
					box.text_size * 0.8,
				)

				if box.stored_typeface == nil {
					number_width = guilib.measureText(number_text, box.text_size * 0.8, "")
				}

				guilib.drawText(
					surface,
					number_text,
					guilib.TextParams {
						x = rect.x + gutter - number_width - 7,
						y = baseline,
						TextSize = box.text_size * 0.8,
						color = box.placeholder_color3,
						transparency = 0.2,
						typeface = box.stored_typeface,
					},
				)
			}

			draw_bracket(
				box,
				surface,
				content_x,
				y,
				line_height,
				line,
				bracket_first,
				bracket_second < 0,
			)

			draw_bracket(box, surface, content_x, y, line_height, line, bracket_second, false)

			if selected &&
			   (selected_word != "" ||
					   (selection_start <= line.finish && selection_finish > line.start)) {
				guilib.save(surface)
				guilib.clipRect(
					surface,
					{
						x = content_x,
						y = y,
						width = max(rect.x + rect.width - minimap_width - content_x, 0),
						height = line_height,
					},
				)
				text_box_draw_code_selection(
					box,
					surface,
					line,
					content_x - box.scroll_x,
					y,
					line_height,
					selection_start,
					selection_finish,
					selected_word,
				)
				guilib.restore(surface)
			}

			if highlight != nil {
				text_box_draw_syntax_line(
					box,
					highlight,
					surface,
					content_x,
					baseline,
					line.start,
					line.finish,
				)
			} else if line.finish > line.start {
				chunk := strings.clone_to_cstring(box.text[line.start:line.finish])
				defer delete(chunk)

				guilib.drawText(
					surface,
					chunk,
					guilib.TextParams {
						x = content_x - box.scroll_x,
						y = baseline,
						TextSize = box.text_size,
						color = box.text_color3,
						transparency = box.text_transparency,
						typeface = box.stored_typeface,
					},
				)
			}

			if len(box.diagnostics) > 0 {
				for diagnostic in box.diagnostics {
					start, finish := text_box_diagnostic_span(box, diagnostic)

					if start > line.finish || finish < line.start {
						continue
					}

					if line.start == line.finish && start != line.start {
						continue
					}

					a := max(start, line.start)
					b := min(finish, line.finish)

					x1 := text_box_measure_range(box, line.start, a)
					x2 := text_box_measure_range(box, line.start, b)

					text_box_draw_diagnostic_squiggle(
						surface,
						content_x + x1 - box.scroll_x,
						content_x + x2 - box.scroll_x,
						y + line_height + TEXTBOX_DIAGNOSTIC_SQUIGGLE_OFFSET,
						TEXTBOX_ERROR_COLOR,
					)
				}
			}
		}
	}

	if box.focused {
		caret_y := rect.y + padding + f32(caret_line) * line_height - box.scroll_y

		caret_x := content_x + caret_x_local - box.scroll_x

		visible := box.caret_timer < 0.6

		if visible {
			guilib.drawLine(
				surface,
				caret_x,
				caret_y + 2,
				caret_x,
				caret_y + line_height - 2,
				1.5,
				box.caret_color3,
				box.text_transparency,
			)
		}
	}

	if minimap_width > 0 {
		map_x := rect.x + rect.width - minimap_width

		position := 0
		map_line := 0

		for {
			finish := text_box_line_end(box.text, position)

			y := rect.y + (f32(map_line) / f32(max(line_count, 1))) * rect.height

			length := finish - position

			width := clamp(f32(length), f32(2), minimap_width - 8)

			guilib.drawRect(
				surface,
				guilib.Rect {
					x = map_x + 4,
					y = y,
					width = width,
					height = 1,
					color = box.text_color3,
					bgTransparency = 0.72,
				},
			)

			if finish >= len(box.text) {
				break
			}

			position = finish + 1
			map_line += 1
		}
	}
}

text_box_draw_code_selection :: proc(
	box: ^TextBox,
	surface: ^kineffi.KineSkiaSurface,
	line: Visual_Line,
	x, y, line_height: f32,
	selection_start, selection_finish: int,
	word: string,
) {
	height := max(line_height - 2, 0)
	if height == 0 {return}

	if word != "" {
		for offset := line.start; offset + len(word) <= line.finish; {
			match := strings.index(box.text[offset:line.finish], word)
			if match < 0 {break}
			start := offset + match
			finish := start + len(word)
			offset = finish
			if start == selection_start ||
			   text_box_is_word_at(box.text, start - 1) ||
			   text_box_is_word_at(box.text, finish) {continue}

			left := text_box_measure_range(box, line.start, start)
			right := text_box_measure_range(box, line.start, finish)
			width := right - left
			if width <= 0 {continue}
			guilib.drawRoundedRectStroke(
				surface,
				{
					x = x + left,
					y = y + 1,
					width = width,
					height = height,
					color = box.selection_color3,
					bgTransparency = 1 - (1 - box.selection_transparency) * 0.7,
				},
				min(3, width * 0.5, height * 0.5),
				1,
			)
		}
	}

	start := max(selection_start, line.start)
	finish := min(selection_finish, line.finish)
	newline_selected :=
		line.finish < len(box.text) &&
		box.text[line.finish] == '\n' &&
		selection_start <= line.finish &&
		selection_finish > line.finish
	if start >= finish && !newline_selected {return}

	left := text_box_measure_range(box, line.start, start)
	right := text_box_measure_range(box, line.start, finish)
	width := max(right - left, 0) + (newline_selected ? f32(5) : 0)
	if width == 0 {return}
	guilib.drawRoundedRect(
		surface,
		{
			x = x + left,
			y = y + 1,
			width = width,
			height = height,
			color = box.selection_color3,
			bgTransparency = box.selection_transparency,
		},
		min(3, width * 0.5, height * 0.5),
	)
}

draw_bracket :: proc(
	box: ^TextBox,
	surface: ^kineffi.KineSkiaSurface,
	content_x: f32,
	y: f32,
	line_height: f32,
	line: Visual_Line,
	bracket_index: int,
	unmatched: bool,
) {
	if box == nil || surface == nil || bracket_index < line.start || bracket_index >= line.finish {
		return
	}

	x_start := text_box_measure_range(box, line.start, bracket_index)

	x_end := text_box_measure_range(box, line.start, bracket_index + 1)

	color := datatypes.Color3{0.35, 0.6, 1.0}

	transparency: f32 = 0.45

	if unmatched {
		color = datatypes.Color3{1, 0.35, 0.35}
		transparency = 0.35
	}

	guilib.drawRect(
		surface,
		guilib.Rect {
			x = content_x + x_start - box.scroll_x,
			y = y + 1,
			width = max(x_end - x_start, f32(2)),
			height = line_height - 2,
			color = color,
			bgTransparency = transparency,
		},
	)
}

text_box_draw_syntax_segment :: proc(
	box: ^TextBox,
	surface: ^kineffi.KineSkiaSurface,
	content_x: f32,
	baseline: f32,
	line_start: int,
	segment_start: int,
	segment_finish: int,
	color3: datatypes.Color3,
) {
	if box == nil || surface == nil || segment_finish <= segment_start {
		return
	}

	segment := box.text[segment_start:segment_finish]

	value := strings.clone_to_cstring(segment)
	defer delete(value)

	x := content_x + text_box_measure_range(box, line_start, segment_start) - box.scroll_x

	guilib.drawText(
		surface,
		value,
		guilib.TextParams {
			x = x,
			y = baseline,
			TextSize = box.text_size,
			color = color3,
			transparency = box.text_transparency,
			typeface = box.stored_typeface,
		},
	)
}

text_box_draw_syntax_line :: proc(
	box: ^TextBox,
	highlighter: ^SyntaxHighlighter,
	surface: ^kineffi.KineSkiaSurface,
	content_x: f32,
	baseline: f32,
	line_start: int,
	line_finish: int,
) {
	if box == nil || highlighter == nil || surface == nil || line_finish <= line_start {
		return
	}

	spans := highlighter.spans[:]

	cursor := line_start

	for index in 0 ..< len(spans) {
		span := spans[index]

		if span.finish <= cursor {
			continue
		}

		if span.start >= line_finish {
			break
		}

		span_start := max(span.start, cursor)
		span_finish := min(span.finish, line_finish)

		if span_start >= span_finish {
			continue
		}

		if span_start > cursor {
			text_box_draw_syntax_segment(
				box,
				surface,
				content_x,
				baseline,
				line_start,
				cursor,
				span_start,
				box.text_color3,
			)
		}

		text_box_draw_syntax_segment(
			box,
			surface,
			content_x,
			baseline,
			line_start,
			span_start,
			span_finish,
			span.color3,
		)

		cursor = max(cursor, span_finish)
	}

	if cursor < line_finish {
		text_box_draw_syntax_segment(
			box,
			surface,
			content_x,
			baseline,
			line_start,
			cursor,
			line_finish,
			box.text_color3,
		)
	}
}

text_box_word_left :: proc(text: string, index: int) -> int {
	if index <= 0 {
		return 0
	}

	i := text_box_utf8_prev_boundary(text, index)

	for i > 0 && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n') {
		i = text_box_utf8_prev_boundary(text, i)
	}

	if text_box_is_word_byte(text[i]) {
		for i > 0 {
			previous := text_box_utf8_prev_boundary(text, i)

			if !text_box_is_word_byte(text[previous]) {
				break
			}

			i = previous
		}
	}

	return i
}

text_box_word_right :: proc(text: string, index: int) -> int {
	if index >= len(text) {
		return len(text)
	}

	i := index

	if text_box_is_word_byte(text[i]) {
		for i < len(text) && text_box_is_word_byte(text[i]) {
			i = text_box_utf8_next_boundary(text, i)
		}
	} else {
		i = text_box_utf8_next_boundary(text, i)
	}

	for i < len(text) && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n') {
		i = text_box_utf8_next_boundary(text, i)
	}

	return i
}

text_box_select_word_at :: proc(box: ^TextBox, position: int) {
	if box == nil || len(box.text) == 0 {
		return
	}

	i := clamp(position, 0, len(box.text))

	if i == len(box.text) {
		text_box_set_cursor(box, i, false)
		return
	}

	if !text_box_is_word_byte(box.text[i]) {
		box.selection_anchor = i
		box.cursor_byte = box.text[i] == '\n' ? i : text_box_utf8_next_boundary(box.text, i)
		text_box_restart_caret(box)

		return
	}

	start := i
	finish := text_box_utf8_next_boundary(box.text, i)

	for start > 0 {
		previous := text_box_utf8_prev_boundary(box.text, start)

		if !text_box_is_word_byte(box.text[previous]) {
			break
		}

		start = previous
	}

	for finish < len(box.text) && text_box_is_word_byte(box.text[finish]) {
		finish = text_box_utf8_next_boundary(box.text, finish)
	}

	box.selection_anchor = start
	box.cursor_byte = finish

	text_box_restart_caret(box)
}

text_box_select_line_at :: proc(box: ^TextBox, position: int) {
	start := text_box_line_start(box.text, position)

	finish := text_box_line_end(box.text, position)

	if finish < len(box.text) {
		finish += 1
	}

	box.selection_anchor = start
	box.cursor_byte = finish

	text_box_restart_caret(box)
}

text_box_utf8_prev_boundary :: proc(text: string, index: int) -> int {
	if index <= 0 {
		return 0
	}

	i := min(index, len(text)) - 1

	for i > 0 && (text[i] & 0xC0) == 0x80 {
		i -= 1
	}

	return i
}


text_box_utf8_next_boundary :: proc(text: string, index: int) -> int {
	if index >= len(text) {
		return len(text)
	}

	i := index + 1

	for i < len(text) && (text[i] & 0xC0) == 0x80 {
		i += 1
	}

	return i
}


text_box_utf8_count :: proc(text: string) -> int {
	count := 0
	index := 0

	for index < len(text) {
		index = text_box_utf8_next_boundary(text, index)

		count += 1
	}

	return count
}


text_box_utf8_prefix_bytes :: proc(text: string, character_count: int) -> int {
	if character_count <= 0 {
		return 0
	}

	index := 0
	count := 0

	for index < len(text) && count < character_count {
		index = text_box_utf8_next_boundary(text, index)

		count += 1
	}

	return index
}


text_box_utf8_index_at :: proc(text: string, byte_index: int) -> int {


	target := clamp(byte_index, 0, len(text))

	count := 0
	index := 0

	for index < target {
		index = text_box_utf8_next_boundary(text, index)

		count += 1
	}

	return count
}


text_box_is_word_at :: proc(text: string, index: int) -> bool {
	if index < 0 || index >= len(text) {
		return false
	}

	return text_box_is_word_byte(text[index])
}


text_box_character_offset :: proc(box: ^TextBox, position: f64) -> int {
	return text_box_utf8_prefix_bytes(box.text, max(int(position) - 1, 0))
}


text_box_word_range_at :: proc(text: string, cursor: int) -> (start: int, finish: int) {


	inside := clamp(cursor, 0, len(text))

	start = inside
	finish = inside


	if start > 0 && !text_box_is_word_at(text, start) && text_box_is_word_at(text, start - 1) {
		start -= 1
	}

	finish = start

	for start > 0 && text_box_is_word_at(text, start - 1) {
		start -= 1
	}

	for finish < len(text) && text_box_is_word_at(text, finish) {
		finish += 1
	}


	for {
		separator := start - 1

		if separator < 0 || text[separator] != '.' {
			break
		}

		segment_start := separator

		for segment_start > 0 && text_box_is_word_at(text, segment_start - 1) {
			segment_start -= 1
		}


		if segment_start == separator {
			break
		}

		start = segment_start
	}

	return start, finish
}


text_box_selection_bounds :: proc(box: ^TextBox) -> (start: int, finish: int, selected: bool) {
	if box == nil {
		return 0, 0, false
	}

	a := clamp(box.selection_anchor, 0, len(box.text))

	b := clamp(box.cursor_byte, 0, len(box.text))

	if a == b {
		return a, b, false
	}

	if a > b {
		temp := a
		a = b
		b = temp
	}

	return a, b, true
}


text_box_clear_selection :: proc(box: ^TextBox) {
	if box == nil {
		return
	}

	box.selection_anchor = box.cursor_byte
}


text_box_select_all :: proc(box: ^TextBox) {
	if box == nil {
		return
	}

	box.selection_anchor = 0
	box.cursor_byte = len(box.text)

	text_box_restart_caret(box)
}


text_box_set_text :: proc(box: ^TextBox, value: string) {
	if box == nil {
		return
	}

	source := value

	if box.max_length >= 0 {
		end := text_box_utf8_prefix_bytes(source, box.max_length)

		source = source[:end]
	}


	if source == box.text {
		return
	}

	text_box_replace_string(&box.text, source)

	undo_stack_clear(&box.undo_stack)
	undo_stack_clear(&box.redo_stack)

	box.cursor_byte = clamp(box.cursor_byte, 0, len(box.text))

	box.selection_anchor = box.cursor_byte

	text_box_restart_caret(box)

	text_box_fire_text_changed(box)
}


text_box_erase :: proc(box: ^TextBox, start: int, finish: int) {
	if box == nil {
		return
	}

	clamped_start := clamp(start, 0, len(box.text))

	clamped_finish := clamp(finish, clamped_start, len(box.text))

	if clamped_start == clamped_finish {
		return
	}

	if !box.suppress_undo {
		undo_stack_clear(&box.redo_stack)

		deleted := strings.clone(box.text[clamped_start:clamped_finish])

		top := text_box_undo_last(box)
		merged := false

		if top != nil && top.epoch == box.undo_epoch {
			if len(top.insert_text) == 0 && top.start + len(top.delete_text) == clamped_start {
				combined := strings.concatenate({top.delete_text, deleted})

				undo_entry_destroy(top)
				top.delete_text = combined
				merged = true
			} else if len(top.insert_text) == 0 &&
			   clamped_finish == top.start &&
			   clamped_start < top.start {
				combined := strings.concatenate({deleted, top.delete_text})

				combined_start := clamped_start

				undo_entry_destroy(top)
				top.start = combined_start
				top.delete_text = combined
				merged = true
			}
		}

		if !merged {
			append(
				&box.undo_stack,
				Undo_Entry {
					start = clamped_start,
					delete_text = deleted,
					insert_text = "",
					epoch = box.undo_epoch,
				},
			)
		} else {
			delete(deleted)
		}
	}

	next := strings.concatenate({box.text[:clamped_start], box.text[clamped_finish:]})

	if len(box.text) > 0 {
		delete(box.text)
	}

	box.text = next

	box.cursor_byte = clamped_start

	box.selection_anchor = clamped_start

	text_box_restart_caret(box)

	text_box_fire_text_changed(box)
}


text_box_delete_selection :: proc(box: ^TextBox) -> bool {
	start, finish, selected := text_box_selection_bounds(box)

	if !selected {
		return false
	}

	text_box_erase(box, start, finish)

	return true
}


text_box_insert :: proc(box: ^TextBox, value: string) {
	if box == nil || !box.text_editable || len(value) == 0 {
		return
	}

	_ = text_box_delete_selection(box)

	insert_value := value

	if box.max_length >= 0 {
		current_length := text_box_utf8_count(box.text)

		remaining := box.max_length - current_length

		if remaining <= 0 {
			return
		}

		end := text_box_utf8_prefix_bytes(insert_value, remaining)

		insert_value = insert_value[:end]

		if len(insert_value) == 0 {
			return
		}
	}

	box.cursor_byte = clamp(box.cursor_byte, 0, len(box.text))

	if !box.suppress_undo {
		undo_stack_clear(&box.redo_stack)

		top := text_box_undo_last(box)
		merged := false

		if top != nil && top.epoch == box.undo_epoch {
			if len(top.insert_text) > 0 &&
			   !strings.contains(top.insert_text, "\n") &&
			   !strings.contains(insert_value, "\n") &&
			   top.start + len(top.insert_text) == box.cursor_byte {
				combined := strings.concatenate({top.insert_text, insert_value})


				if len(top.insert_text) > 0 {
					delete(top.insert_text)
				}
				top.insert_text = combined
				merged = true
			} else if len(top.delete_text) > 0 &&
			   len(top.insert_text) == 0 &&
			   top.start == box.cursor_byte {
				top.insert_text = strings.clone(insert_value)
				merged = true
			}
		}

		if !merged {
			append(
				&box.undo_stack,
				Undo_Entry {
					start = box.cursor_byte,
					delete_text = "",
					insert_text = strings.clone(insert_value),
					epoch = box.undo_epoch,
				},
			)
		}
	}

	next := strings.concatenate(
		{box.text[:box.cursor_byte], insert_value, box.text[box.cursor_byte:]},
	)

	if len(box.text) > 0 {
		delete(box.text)
	}

	box.text = next

	box.cursor_byte += len(insert_value)

	box.selection_anchor = box.cursor_byte

	text_box_restart_caret(box)

	text_box_fire_text_changed(box)
}

text_box_clear_diagnostics :: proc(box: ^TextBox) {
	if box == nil {
		return
	}

	for &diagnostic in box.diagnostics {
		if diagnostic.message != "" {
			delete(diagnostic.message)
		}
	}

	clear(&box.diagnostics)
}

text_box_append_diagnostic :: proc(
	box: ^TextBox,
	line: int,
	start_column: int,
	end_column: int,
	message: string,
) {
	if box == nil {
		return
	}

	append(
		&box.diagnostics,
		TextBox_Diagnostic {
			line = max(line, 1),
			start_column = max(start_column, 1),
			end_column = max(end_column, start_column),
			message = strings.clone(message),
		},
	)
}

text_box_diagnostic_span :: proc(
	box: ^TextBox,
	diagnostic: TextBox_Diagnostic,
) -> (
	start: int,
	finish: int,
) {
	if box == nil {
		return 0, 0
	}

	line_start := text_box_line_start_by_index(box.text, diagnostic.line - 1)

	if line_start >= len(box.text) {
		return len(box.text), len(box.text)
	}

	line_finish := text_box_line_end(box.text, line_start)
	line_text := box.text[line_start:line_finish]

	start = line_start + text_box_utf8_prefix_bytes(line_text, diagnostic.start_column - 1)

	if diagnostic.end_column > diagnostic.start_column {
		finish = line_start + text_box_utf8_prefix_bytes(line_text, diagnostic.end_column - 1)
	} else {
		finish = line_start + text_box_utf8_prefix_bytes(line_text, diagnostic.start_column)
	}

	finish = clamp(finish, start, line_finish)

	return
}

text_box_diagnostic_at_byte :: proc(box: ^TextBox, byte_index: int) -> ^TextBox_Diagnostic {
	if box == nil {
		return nil
	}

	for &diagnostic in box.diagnostics {
		start, finish := text_box_diagnostic_span(box, diagnostic)

		if byte_index >= start && byte_index <= finish {
			return &diagnostic
		}
	}

	return nil
}

text_box_push_diagnostic :: proc(L: ^vm.State, diagnostic: ^TextBox_Diagnostic) {
	vm.NewTable(L, 0, 4)

	vm.PushNumber(L, f64(diagnostic.line))
	vm.SetField(L, -2, "Line")

	vm.PushNumber(L, f64(diagnostic.start_column))
	vm.SetField(L, -2, "Column")

	vm.PushNumber(L, f64(diagnostic.end_column))
	vm.SetField(L, -2, "EndColumn")

	vm.PushString(L, diagnostic.message)
	vm.SetField(L, -2, "Message")
}

text_box_draw_diagnostic_squiggle :: proc(
	surface: ^kineffi.KineSkiaSurface,
	start_x: f32,
	finish_x: f32,
	y: f32,
	color: datatypes.Color3,
) {
	if surface == nil {
		return
	}

	x0 := min(start_x, finish_x)
	x1 := max(start_x, finish_x)

	if x1 - x0 < 4 {
		x1 = x0 + 4
	}

	STEP :: f32(3)
	AMPLITUDE :: f32(1.25)

	x := x0
	up := true

	for x < x1 {
		next := min(x + STEP, x1)

		y0 := y + (up ? -AMPLITUDE : AMPLITUDE)
		y1 := y + (up ? AMPLITUDE : -AMPLITUDE)

		guilib.drawLine(surface, x, y0, next, y1, 1.4, color, 0)

		x = next
		up = !up
	}
}

text_box_line_start :: proc(text: string, index: int) -> int {
	i := clamp(index, 0, len(text))
	for i > 0 && text[i - 1] != '\n' {
		i -= 1
	}
	return i
}

text_box_line_end :: proc(text: string, index: int) -> int {
	i := clamp(index, 0, len(text))
	for i < len(text) && text[i] != '\n' {
		i += 1
	}
	return i
}

text_box_line_number :: proc(text: string, index: int) -> int {
	line := 1
	for i in 0 ..< clamp(index, 0, len(text)) {
		if text[i] == '\n' {
			line += 1
		}
	}
	return line
}

text_box_line_count :: proc(text: string) -> int {
	count := 1
	for c in text {
		if c == '\n' {
			count += 1
		}
	}
	return count
}

Visual_Line :: struct {
	start:  int,
	finish: int,
}

text_box_editor_content_width :: proc(box: ^TextBox, width: f32) -> f32 {
	if box == nil {
		return 0
	}

	padding: f32 = 6

	content := max(width - padding * 2 - text_box_gutter_width(box), f32(0))

	if box.show_minimap && width >= 250 {
		content = max(content - 64, f32(0))
	}

	return content
}

text_box_visual_lines :: proc(box: ^TextBox, content_width: f32) -> [dynamic]Visual_Line {
	result := make([dynamic]Visual_Line)

	text := box.text

	if len(text) == 0 {
		append(&result, Visual_Line{start = 0, finish = 0})
		return result
	}

	position := 0

	for position <= len(text) {
		line_end := text_box_line_end(text, position)

		if !box.wrap || content_width <= f32(0) || line_end == position {
			append(&result, Visual_Line{start = position, finish = line_end})

			if line_end >= len(text) {
				break
			}

			position = line_end + 1
			continue
		}

		chunk_start := position
		last_fit := position
		pos := position

		for pos < line_end {
			next := text_box_utf8_next_boundary(text, pos)
			next = min(next, line_end)

			if next == pos {
				break
			}

			width := text_box_measure_range(box, chunk_start, next)

			if width > content_width {
				split := last_fit

				if split == chunk_start {
					split = next
				}

				if split > chunk_start {
					append(&result, Visual_Line{start = chunk_start, finish = split})
				}

				chunk_start = split
				pos = split
				last_fit = split
			} else {
				last_fit = next
				pos = next
			}
		}

		append(&result, Visual_Line{start = chunk_start, finish = line_end})

		if line_end >= len(text) {
			break
		}

		position = line_end + 1
	}

	if len(result) == 0 {
		append(&result, Visual_Line{start = 0, finish = 0})
	}

	return result
}

text_box_visual_line_count :: proc(box: ^TextBox, content_width: f32) -> int {
	lines := text_box_visual_lines(box, content_width)
	defer delete(lines)
	return len(lines)
}

text_box_visual_index_at :: proc(lines: []Visual_Line, offset: int) -> int {
	if len(lines) == 0 {
		return 0
	}

	for line, i in lines {
		if offset >= line.start && offset <= line.finish {
			return i
		}
	}

	return len(lines) - 1
}

text_box_indent :: proc(text: string, index: int) -> string {
	start := text_box_line_start(text, index)
	i := start
	for i < len(text) && (text[i] == ' ' || text[i] == '\t') {
		i += 1
	}
	return text[start:i]
}

text_box_replace_range :: proc(box: ^TextBox, start, finish: int, value: string) {
	if box == nil || !box.text_editable {
		return
	}
	box.cursor_byte = start
	box.selection_anchor = finish
	text_box_erase(box, start, finish)
	text_box_insert(box, value)
}

text_box_indent_selection :: proc(box: ^TextBox, unindent: bool) {
	if box == nil || !box.text_editable {
		return
	}

	selection_start, selection_finish, selected := text_box_selection_bounds(box)

	if !selected {
		if unindent {
			start := text_box_line_start(box.text, box.cursor_byte)

			finish := text_box_line_end(box.text, box.cursor_byte)

			remove := 0

			if start < finish && box.text[start] == '\t' {
				remove = 1
			} else {
				for remove < max(box.tab_size, 1) &&
				    start + remove < finish &&
				    box.text[start + remove] == ' ' {
					remove += 1
				}
			}

			if remove > 0 {
				old_cursor := box.cursor_byte

				text_box_erase(box, start, start + remove)

				box.cursor_byte = max(start, old_cursor - remove)

				box.selection_anchor = box.cursor_byte
			}

			return
		}

		line_start := text_box_line_start(box.text, box.cursor_byte)

		column := text_box_utf8_count(box.text[line_start:box.cursor_byte])

		tab_size := max(box.tab_size, 1)

		amount := tab_size - column % tab_size

		spaces := strings.repeat(" ", amount)
		defer delete(spaces)

		text_box_insert(box, spaces)

		return
	}

	region_start := text_box_line_start(box.text, selection_start)

	selection_last := selection_finish

	if selection_last > selection_start &&
	   selection_last > 0 &&
	   box.text[selection_last - 1] == '\n' {
		selection_last -= 1
	}

	region_finish := text_box_line_end(box.text, selection_last)

	if region_finish < len(box.text) {
		region_finish += 1
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	position := region_start

	for position < region_finish {
		line_end := text_box_line_end(box.text, position)

		line_end = min(line_end, region_finish)

		if unindent {
			remove := 0

			if position < line_end && box.text[position] == '\t' {
				remove = 1
			} else {
				for remove < max(box.tab_size, 1) &&
				    position + remove < line_end &&
				    box.text[position + remove] == ' ' {
					remove += 1
				}
			}

			_ = strings.write_string(&builder, box.text[position + remove:line_end])
		} else {
			for _ in 0 ..< max(box.tab_size, 1) {
				_ = strings.write_byte(&builder, ' ')
			}

			_ = strings.write_string(&builder, box.text[position:line_end])
		}

		if line_end < region_finish && line_end < len(box.text) && box.text[line_end] == '\n' {
			_ = strings.write_byte(&builder, '\n')

			position = line_end + 1
		} else {
			break
		}
	}

	replacement := strings.to_string(builder)

	text_box_replace_range(box, region_start, region_finish, replacement)

	box.selection_anchor = region_start
	box.cursor_byte = (region_start + len(replacement))

	text_box_restart_caret(box)
}

text_box_toggle_comment :: proc(box: ^TextBox) {
	if box == nil || !box.text_editable {
		return
	}

	selection_start, selection_finish, selected := text_box_selection_bounds(box)

	if !selected {
		selection_start = box.cursor_byte

		selection_finish = box.cursor_byte
	}

	region_start := text_box_line_start(box.text, selection_start)

	last_position := selection_finish

	if last_position > selection_start &&
	   last_position > 0 &&
	   box.text[last_position - 1] == '\n' {
		last_position -= 1
	}

	region_finish := text_box_line_end(box.text, last_position)

	all_commented := true
	has_content := false

	position := region_start

	for position <= region_finish {
		line_end := text_box_line_end(box.text, position)

		first := position

		for first < line_end && (box.text[first] == ' ' || box.text[first] == '\t') {
			first += 1
		}

		if first < line_end {
			has_content = true

			if first + 1 >= line_end || box.text[first] != '-' || box.text[first + 1] != '-' {
				all_commented = false
				break
			}
		}

		if line_end >= region_finish || line_end >= len(box.text) {
			break
		}

		position = line_end + 1
	}

	if !has_content {
		all_commented = false
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	position = region_start

	for position <= region_finish {
		line_end := text_box_line_end(box.text, position)

		first := position

		for first < line_end && (box.text[first] == ' ' || box.text[first] == '\t') {
			first += 1
		}

		_ = strings.write_string(&builder, box.text[position:first])

		if first < line_end {
			if all_commented {
				remove := 2

				if first + 2 < line_end && box.text[first + 2] == ' ' {
					remove = 3
				}

				_ = strings.write_string(&builder, box.text[first + remove:line_end])
			} else {
				_ = strings.write_string(&builder, "-- ")

				_ = strings.write_string(&builder, box.text[first:line_end])
			}
		}

		if line_end >= region_finish || line_end >= len(box.text) {
			break
		}

		_ = strings.write_byte(&builder, '\n')

		position = line_end + 1
	}

	replacement := strings.to_string(builder)

	text_box_replace_range(box, region_start, region_finish, replacement)

	box.selection_anchor = region_start

	box.cursor_byte = region_start + len(replacement)

	text_box_restart_caret(box)
}

text_box_insert_newline :: proc(box: ^TextBox) {
	if box == nil || !box.text_editable {
		return
	}

	indentation := text_box_indent(box.text, box.cursor_byte)

	if !box.auto_indent {
		text_box_insert(box, "\n")
		return
	}

	line_start := text_box_line_start(box.text, box.cursor_byte)

	before := strings.trim_space(box.text[line_start:box.cursor_byte])

	increase_indent := false

	if len(before) > 0 {
		last := before[len(before) - 1]

		increase_indent =
			(last == '{' ||
				last == '[' ||
				last == '(' ||
				strings.has_suffix(before, "then") ||
				strings.has_suffix(before, "do"))
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	_ = strings.write_byte(&builder, '\n')

	_ = strings.write_string(&builder, indentation)

	if increase_indent {
		for _ in 0 ..< max(box.tab_size, 1) {
			_ = strings.write_byte(&builder, ' ')
		}
	}

	text_box_insert(box, strings.to_string(builder))
}

text_box_duplicate_line :: proc(box: ^TextBox) {
	if box == nil || !box.text_editable {
		return
	}

	start := text_box_line_start(box.text, box.cursor_byte)

	finish := text_box_line_end(box.text, box.cursor_byte)

	column := box.cursor_byte - start

	if finish < len(box.text) {
		insertion := finish + 1

		line := strings.clone(box.text[start:insertion])
		defer delete(line)

		text_box_replace_range(box, insertion, insertion, line)

		box.cursor_byte = insertion + min(column, finish - start)
	} else {
		line := strings.clone(box.text[start:finish])
		defer delete(line)

		duplicate := strings.concatenate({"\n", line})
		defer delete(duplicate)

		text_box_replace_range(box, finish, finish, duplicate)

		box.cursor_byte = finish + 1 + min(column, finish - start)
	}

	box.selection_anchor = box.cursor_byte

	text_box_restart_caret(box)
}

text_box_delete_line :: proc(box: ^TextBox) {
	if box == nil || !box.text_editable {
		return
	}
	start := text_box_line_start(box.text, box.cursor_byte)
	end := text_box_line_end(box.text, box.cursor_byte)
	if end < len(box.text) {
		end += 1
	} else if start > 0 {
		start -= 1
	}
	text_box_erase(box, start, end)
}


text_box_copy_selection :: proc(box: ^TextBox) {
	if box == nil {
		return
	}

	start, finish, selected := text_box_selection_bounds(box)

	if !selected {
		return
	}

	value := strings.clone_to_cstring(box.text[start:finish])

	defer delete(value)

	_ = sdl3.SetClipboardText(value)
}


text_box_cut_selection :: proc(box: ^TextBox) {
	if box == nil || !box.text_editable {
		return
	}

	start, finish, selected := text_box_selection_bounds(box)

	if !selected {
		return
	}

	text_box_copy_selection(box)

	text_box_erase(box, start, finish)
}


text_box_paste :: proc(box: ^TextBox) {
	if box == nil || !box.text_editable {
		return
	}

	clipboard := sdl3.GetClipboardText()

	if clipboard == nil {
		return
	}

	defer sdl3.free(rawptr(clipboard))

	text_box_insert(box, string(cstring(clipboard)))
}


TextBox_focus :: proc(box: ^TextBox) {
	if box == nil {
		return
	}

	if text_box_focused == box {
		box.focused = true
		text_box_restart_caret(box)
		return
	}

	if text_box_focused != nil {
		TextBox_blur(text_box_focused)
	}

	text_box_focused = box
	box.focused = true
	box.drag_selecting = false

	if box.clear_text_on_focus && box.text_editable {
		text_box_set_text(box, "")
	}

	box.cursor_byte = len(box.text)

	box.selection_anchor = box.cursor_byte

	if box.select_all_on_focus {
		text_box_select_all(box)
	}

	text_box_restart_caret(box)

	if box.text_editable {
		window := sdl3.GetKeyboardFocus()

		if window != nil {
			_ = sdl3.StartTextInput(window)
			TEXTBOX_IS_USED = true
		}
	}
}


TextBox_blur :: proc(box: ^TextBox, enter_pressed: bool = false) {
	if box == nil {
		return
	}

	was_focused := box.focused
	box.focused = false
	box.drag_selecting = false
	box.caret_timer = 0
	if was_focused &&
	   box.object.signal_registry != nil &&
	   box.object.signal_registry.signal_registry != nil {
		if box.focus_lost == nil {
			box.focus_lost = signals.Create(box.object.signal_registry.signal_registry)
		}
		vm_state := box.object.signal_registry.signal_registry.L
		vm.PushBoolean(vm_state, enter_pressed)
		signals.Fire(vm_state, box.focus_lost, 1)
		vm.Pop(vm_state, 1)
	}

	if text_box_focused == box {
		text_box_focused = nil

		window := sdl3.GetKeyboardFocus()

		if window != nil {
			_ = sdl3.StopTextInput(window)
			TEXTBOX_IS_USED = false
		}
	}
}


text_box_effectively_visible :: proc(box: ^TextBox) -> bool {
	if box == nil {
		return false
	}

	current := &box.object

	for current != nil {
		if Is_A(current, "GuiObject") {
			gui := cast(^GuiObject)current

			if !gui.visible {
				return false
			}
		}

		if Is_A(current, "ScreenGui") {
			screen := cast(^ScreenGui)current

			if !screen.enabled {
				return false
			}
		}

		current = current.parent
	}

	return true
}


text_box_measure_prefix :: proc(box: ^TextBox, byte_index: int) -> f32 {
	if box == nil || len(box.text) == 0 {
		return 0
	}

	clamped_index := clamp(byte_index, 0, len(box.text))

	if clamped_index == 0 {
		return 0
	}

	text := strings.clone_to_cstring(box.text[:clamped_index])

	defer delete(text)

	if box.stored_typeface != nil {
		return guilib.measureTextTypeface(box.stored_typeface, text, box.text_size)
	}

	return guilib.measureText(text, box.text_size, "")
}


text_box_cursor_from_x :: proc(box: ^TextBox, mouse_x: f32) -> int {
	if box == nil || len(box.text) == 0 {
		return 0
	}

	padding: f32 = 6

	target := mouse_x - box.absolute_position.X - padding + box.scroll_x

	target = max(target, f32(0))

	previous_index := 0
	previous_width: f32 = 0
	index := 0

	for index < len(box.text) {
		next_index := text_box_utf8_next_boundary(box.text, index)

		width := text_box_measure_prefix(box, next_index)

		middle := (previous_width + width) * 0.5

		if target < middle {
			return previous_index
		}

		previous_index = next_index

		previous_width = width

		index = next_index
	}

	return len(box.text)
}


TextBox_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	box := new(TextBox)

	box^ = TextBox_Init()

	box.name = "TextBox"

	TextBox_Load_Typeface(box)

	return &box.object
}


TextBox_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	box := cast(^TextBox)object

	if text_box_focused == box {
		TextBox_blur(box)
	}

	if len(box.text) > 0 {
		delete(box.text)
	}

	if len(box.placeholder_text) > 0 {
		delete(box.placeholder_text)
	}

	text_box_clear_diagnostics(box)
	delete(box.diagnostics)

	TextBox_Destroy_Typeface(box)

	datatypes.Font_Destroy(&box.font_face)

	undo_stack_clear(&box.undo_stack)
	undo_stack_clear(&box.redo_stack)

	GuiObject_Free_Signals(cast(^GuiObject)object)
	if box.focus_lost != nil {
		signals.Destroy(box.focus_lost)
		box.focus_lost = nil
	}
	if box.text_changed != nil {
		signals.Destroy(box.text_changed)
		box.text_changed = nil
	}

	if box.key_down != nil {
		signals.Destroy(box.key_down)
		box.key_down = nil
	}

	Object_Destroy(object)

	free(box)
}


TextBox_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	box := cast(^TextBox)object

	switch key {
	case "FocusLost":
		if box.object.signal_registry == nil || box.object.signal_registry.signal_registry == nil {
			return false
		}
		if box.focus_lost == nil {
			box.focus_lost = signals.Create(box.object.signal_registry.signal_registry)
		}
		signals.Push(L, box.focus_lost)
		return true

	case "TextChanged":
		if box.object.signal_registry == nil || box.object.signal_registry.signal_registry == nil {
			return false
		}
		if box.text_changed == nil {
			box.text_changed = signals.Create(box.object.signal_registry.signal_registry)
		}
		signals.Push(L, box.text_changed)
		return true

	case "KeyDown":
		if box.object.signal_registry == nil || box.object.signal_registry.signal_registry == nil {
			return false
		}
		if box.key_down == nil {
			box.key_down = signals.Create(box.object.signal_registry.signal_registry)
		}
		signals.Push(L, box.key_down)
		return true

	case "KeyHandled":
		vm.PushBoolean(L, box.key_handled)
		return true

	case "CaretScreenPosition":
		if datatype_registry == nil {
			return false
		}
		datatypes.Push_Vector2(L, datatype_registry, box.caret_screen_position)
		return true

	case "CursorPosition":
		vm.PushNumber(L, f64(text_box_utf8_index_at(box.text, box.cursor_byte) + 1))
		return true

	case "SelectionStart":
		start, finish, selected := text_box_selection_bounds(box)

		_ = finish

		if !selected {
			start = box.cursor_byte
		}

		vm.PushNumber(L, f64(text_box_utf8_index_at(box.text, start) + 1))
		return true

	case "SelectionEnd":
		start, finish, selected := text_box_selection_bounds(box)

		if !selected {
			finish = box.cursor_byte
		}

		_ = start

		vm.PushNumber(L, f64(text_box_utf8_index_at(box.text, finish) + 1))
		return true

	case "Text":
		vm.PushString(L, box.text)
		return true

	case "PlaceholderText":
		vm.PushString(L, box.placeholder_text)
		return true

	case "Font":
		if datatypes.Font_Has_Memory(box.font_face) {
			if datatype_registry == nil {
				return false
			}

			datatypes.Push_Font(L, datatype_registry, box.font_face)
		} else if enum_registry != nil {
			if !enums.Push_Item_By_Value(L, enum_registry, "Font", i64(box.font_enum)) {
				vm.PushString(L, box.font_face.Family)
			}
		} else {
			vm.PushString(L, box.font_face.Family)
		}
		return true

	case "FontFace":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Font(L, datatype_registry, box.font_face)

		return true

	case "TextSize":
		vm.PushNumber(L, f64(box.text_size))
		return true

	case "TextColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(L, datatype_registry, box.text_color3)

		return true

	case "CodeEditor":
		vm.PushBoolean(L, box.code_editor)
		return true

	case "ShowLineNumbers":
		vm.PushBoolean(L, box.show_line_numbers)
		return true

	case "ShowMinimap":
		vm.PushBoolean(L, box.show_minimap)
		return true

	case "TabSize":
		vm.PushNumber(L, f64(box.tab_size))
		return true

	case "AutoIndent":
		vm.PushBoolean(L, box.auto_indent)
		return true

	case "AutoClose":
		vm.PushBoolean(L, box.auto_close)
		return true

	case "WordWrap":
		vm.PushBoolean(L, box.wrap)
		return true

	case "LineCount":
		vm.PushNumber(L, f64(text_box_line_count(box.text)))
		return true

	case "DiagnosticCount":
		vm.PushNumber(L, f64(len(box.diagnostics)))
		return true

	case "PlaceholderColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(L, datatype_registry, box.placeholder_color3)

		return true

	case "TextTransparency":
		vm.PushNumber(L, f64(box.text_transparency))
		return true

	case "ClearTextOnFocus":
		vm.PushBoolean(L, box.clear_text_on_focus)
		return true

	case "TextEditable":
		vm.PushBoolean(L, box.text_editable)
		return true

	case "SelectAllOnFocus":
		vm.PushBoolean(L, box.select_all_on_focus)
		return true

	case "MaxLength":
		vm.PushNumber(L, f64(box.max_length))
		return true

	case "CaretColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(L, datatype_registry, box.caret_color3)

		return true

	case "SelectionColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(L, datatype_registry, box.selection_color3)

		return true

	case "SelectionTransparency":
		vm.PushNumber(L, f64(box.selection_transparency))

		return true

	case "FocusColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(L, datatype_registry, box.focus_color3)

		return true

	case "SelectedText":
		start, finish, selected := text_box_selection_bounds(box)

		if selected {
			vm.PushString(L, box.text[start:finish])
		} else {
			vm.PushString(L, "")
		}

		return true

	case "CaptureFocus",
	     "ReleaseFocus",
	     "IsFocused",
	     "SelectAll",
	     "ClearSelection",
	     "CopySelection",
	     "Undo",
	     "Redo":
		vm.PushUserdataMethod(L, key)

		return true
	}

	return GuiObject_get(L, object, datatype_registry, enum_registry, key)
}


TextBox_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	box := cast(^TextBox)object

	Gui_Layout_Mark_Dirty()

	switch key {

	case "KeyHandled":
		box.key_handled = vm.ArgBoolean(L, value_index)
		return true

	case "CursorPosition":
		text_box_set_cursor(
			box,
			text_box_character_offset(box, vm.ArgNumber(L, value_index)),
			true,
		)

		return true

	case "SelectionStart":
		box.selection_anchor = text_box_character_offset(box, vm.ArgNumber(L, value_index))

		text_box_restart_caret(box)

		return true

	case "SelectionEnd":
		text_box_set_cursor(
			box,
			text_box_character_offset(box, vm.ArgNumber(L, value_index)),
			true,
		)

		return true

	case "Text":
		text_box_set_text(box, vm.ArgString(L, value_index))

		return true

	case "CodeEditor":
		box.code_editor = vm.ArgBoolean(L, value_index)

		box.scroll_x = 0
		box.scroll_target_x = 0
		box.scroll_y = 0
		box.scroll_target_y = 0
		box.caret_needs_scroll = true

		return true

	case "ShowLineNumbers":
		box.show_line_numbers = vm.ArgBoolean(L, value_index)
		return true

	case "ShowMinimap":
		box.show_minimap = vm.ArgBoolean(L, value_index)
		return true

	case "TabSize":
		box.tab_size = clamp(int(vm.ArgNumber(L, value_index)), 1, 16)
		return true

	case "AutoIndent":
		box.auto_indent = vm.ArgBoolean(L, value_index)
		return true

	case "AutoClose":
		box.auto_close = vm.ArgBoolean(L, value_index)
		return true

	case "WordWrap":
		box.wrap = vm.ArgBoolean(L, value_index)

		if box.code_editor {
			box.caret_needs_scroll = true
		}

		return true

	case "PlaceholderText":
		text_box_replace_string(&box.placeholder_text, vm.ArgString(L, value_index))

		return true

	case "Font":
		if enum_registry != nil && vm.IsUserdataType(L, value_index, &enum_registry.item_binding) {
			item := enums.Arg_Item(L, value_index, enum_registry, "Font")
			if item == nil {
				return true
			}

			TextBox_Set_Font_Enum(box, enums.Font(item.value))
		} else if datatype_registry != nil &&
		   vm.IsUserdataType(L, value_index, &datatype_registry.font) {


			TextBox_Set_Font_Face(box, datatypes.Arg_Font(L, value_index, datatype_registry))
		} else {
			TextBox_Set_Font_Family(box, vm.ArgString(L, value_index))
		}

		return true

	case "FontFace":
		if datatype_registry == nil {
			return false
		}

		TextBox_Set_Font_Face(box, datatypes.Arg_Font(L, value_index, datatype_registry))

		return true

	case "TextSize":
		box.text_size = max(f32(vm.ArgNumber(L, value_index)), f32(1))

		return true

	case "TextColor3":
		if datatype_registry == nil {
			return false
		}

		box.text_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)

		return true

	case "PlaceholderColor3":
		if datatype_registry == nil {
			return false
		}

		box.placeholder_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)

		return true

	case "TextTransparency":
		box.text_transparency = clamp(f32(vm.ArgNumber(L, value_index)), f32(0), f32(1))

		return true

	case "ClearTextOnFocus":
		box.clear_text_on_focus = vm.ArgBoolean(L, value_index)

		return true

	case "TextEditable":
		box.text_editable = vm.ArgBoolean(L, value_index)

		if box.focused {
			window := sdl3.GetKeyboardFocus()

			if window != nil {
				if box.text_editable {
					_ = sdl3.StartTextInput(window)
					TEXTBOX_IS_USED = true
				} else {
					_ = sdl3.StopTextInput(window)
					TEXTBOX_IS_USED = false
				}
			}
		}

		return true

	case "SelectAllOnFocus":
		box.select_all_on_focus = vm.ArgBoolean(L, value_index)

		return true

	case "MaxLength":
		requested := int(vm.ArgNumber(L, value_index))

		box.max_length = max(requested, -1)

		if box.max_length >= 0 && text_box_utf8_count(box.text) > box.max_length {
			end := text_box_utf8_prefix_bytes(box.text, box.max_length)

			text_box_set_text(box, box.text[:end])
		}

		return true

	case "CaretColor3":
		if datatype_registry == nil {
			return false
		}

		box.caret_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)

		return true

	case "SelectionColor3":
		if datatype_registry == nil {
			return false
		}

		box.selection_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)

		return true

	case "SelectionTransparency":
		box.selection_transparency = clamp(f32(vm.ArgNumber(L, value_index)), f32(0), f32(1))

		return true

	case "FocusColor3":
		if datatype_registry == nil {
			return false
		}

		box.focus_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)

		return true
	}

	return GuiObject_set(L, object, datatype_registry, enum_registry, key, value_index)
}


TextBox_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	box := cast(^TextBox)object

	switch method {

	case "CaptureFocus":
		TextBox_focus(box)
		return 0, true

	case "ReleaseFocus":
		TextBox_blur(box)
		return 0, true

	case "IsFocused":
		vm.PushBoolean(L, box.focused)

		return 1, true

	case "SelectAll":
		text_box_select_all(box)
		return 0, true

	case "ClearSelection":
		text_box_clear_selection(box)
		return 0, true

	case "CopySelection":
		text_box_copy_selection(box)
		return 0, true

	case "Undo":
		text_box_undo(box)
		return 0, true

	case "Redo":
		text_box_redo(box)
		return 0, true

	case "InsertText":
		text_box_insert(box, vm.ArgString(L, 2))

		return 0, true

	case "ReplaceRange":
		text_box_replace_range(
			box,
			text_box_character_offset(box, vm.ArgNumber(L, 2)),
			text_box_character_offset(box, vm.ArgNumber(L, 3)),
			vm.ArgString(L, 4),
		)

		return 0, true

	case "ClearDiagnostics":
		text_box_clear_diagnostics(box)
		return 0, true

	case "SetDiagnostics":
		text_box_clear_diagnostics(box)

		if vm.IsTable(L, 2) {
			count := vm.RawLen(L, 2)

			for index in 1 ..= count {
				if vm.RawGetIndex(L, 2, index) == .Table {
					line := 1
					start_column := 1
					end_column := 1
					message := ""

					vm.GetField(L, -1, "Line")
					if number, ok := vm.ToNumber(L, -1); ok {
						line = int(number)
					}
					vm.Pop(L)

					vm.GetField(L, -1, "Column")
					if number, ok := vm.ToNumber(L, -1); ok {
						start_column = int(number)
					}
					vm.Pop(L)

					vm.GetField(L, -1, "EndColumn")
					if number, ok := vm.ToNumber(L, -1); ok {
						end_column = int(number)
					}
					vm.Pop(L)

					vm.GetField(L, -1, "Message")
					if value, ok := vm.ToString(L, -1); ok {
						message = value
					}
					vm.Pop(L)

					text_box_append_diagnostic(box, line, start_column, end_column, message)
				}

				vm.Pop(L)
			}
		}

		return 0, true

	case "DiagnosticAtCursor":
		if diagnostic := text_box_diagnostic_at_byte(box, box.cursor_byte); diagnostic != nil {
			text_box_push_diagnostic(L, diagnostic)
		} else {
			vm.PushNil(L)
		}

		return 1, true

	case "DiagnosticAtPoint":
		x := f32(vm.ArgNumber(L, 2))
		y := f32(vm.ArgNumber(L, 3))

		line_height := text_box_line_height(box)
		padding: f32 = 6
		gutter := text_box_gutter_width(box)

		content_width := text_box_editor_content_width(box, box.absolute_size.X)

		lines := text_box_visual_lines(box, content_width)
		defer delete(lines)

		index := int((y - padding + box.scroll_y) / line_height)

		if index < 0 || index >= len(lines) {
			vm.PushNil(L)
			return 1, true
		}

		line := lines[index]
		local_x := x - padding - gutter + box.scroll_x

		for &diagnostic in box.diagnostics {
			start, finish := text_box_diagnostic_span(box, diagnostic)

			if start > line.finish || finish < line.start {
				continue
			}

			if line.start == line.finish && start != line.start {
				continue
			}

			a := max(start, line.start)
			b := min(finish, line.finish)

			x1 := text_box_measure_range(box, line.start, a)
			x2 := text_box_measure_range(box, line.start, b)

			if x2 - x1 < 4 {
				x2 = x1 + 4
			}

			if local_x >= x1 - 2 && local_x <= x2 + 2 {
				text_box_push_diagnostic(L, &diagnostic)
				return 1, true
			}
		}

		vm.PushNil(L)
		return 1, true

	case "GetWordRangeAtCursor":
		start, finish := text_box_word_range_at(box.text, box.cursor_byte)

		vm.NewTable(L, 2, 0)
		vm.PushNumber(L, f64(text_box_utf8_index_at(box.text, start) + 1))
		vm.SetField(L, -2, "start")
		vm.PushNumber(L, f64(text_box_utf8_index_at(box.text, finish) + 1))
		vm.SetField(L, -2, "finish")
		vm.PushString(L, box.text[start:finish])
		vm.SetField(L, -2, "text")

		return 1, true

	case "GetLineAtCursor":
		start := text_box_line_start(box.text, box.cursor_byte)

		finish := text_box_line_end(box.text, box.cursor_byte)

		vm.NewTable(L, 2, 0)

		vm.PushNumber(L, f64(text_box_line_number(box.text, box.cursor_byte)))
		vm.SetField(L, -2, "line")

		vm.PushNumber(L, f64(text_box_utf8_index_at(box.text, start) + 1))
		vm.SetField(L, -2, "start")

		vm.PushNumber(L, f64(text_box_utf8_index_at(box.text, finish) + 1))
		vm.SetField(L, -2, "finish")

		vm.PushString(L, box.text[start:finish])
		vm.SetField(L, -2, "text")

		return 1, true
	}

	return 0, false
}


TextBox_render :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	rect, visible := GuiObject_get_rect(object, ctx)

	if !visible {
		return
	}

	GuiObject_render(object, ctx)

	box := cast(^TextBox)object

	surface := ctx.renderer.SkiaSurface

	padding: f32 = 6

	dt := clamp(f32(ctx.delta_time), f32(0), f32(0.1))

	if box.code_editor {
		text_box_render_code_editor(box, rect, ctx, dt)
		return
	}

	focus_target: f32 = 0

	if box.focused {
		focus_target = 1
	}

	focus_lerp := min(dt * 14, f32(1))

	box.focus_animation += (focus_target - box.focus_animation) * focus_lerp

	if box.focused {
		box.caret_timer += dt

		for box.caret_timer >= 1.2 {
			box.caret_timer -= 1.2
		}
	} else {
		box.caret_timer = 0
	}


	display_text := box.text

	display_color := box.text_color3

	if len(box.text) == 0 && len(box.placeholder_text) > 0 {
		display_text = box.placeholder_text

		display_color = box.placeholder_color3
	}


	caret_width: f32 = 0

	if box.focused {
		caret_width = text_box_measure_prefix(box, box.cursor_byte)
	}

	available_width := max(rect.width - padding * 2, f32(0))


	if box.focused {
		desired := box.scroll_target_x

		visible_caret := caret_width - desired

		if visible_caret > available_width {
			desired = caret_width - available_width
		} else if visible_caret < 0 {
			desired = caret_width
		}

		total_width := text_box_measure_prefix(box, len(box.text))

		max_scroll := max(total_width - available_width, f32(0))

		box.scroll_target_x = clamp(desired, f32(0), max_scroll)
	} else {
		box.scroll_target_x = 0
	}


	scroll_lerp := min(dt * 20, f32(1))

	box.scroll_x += (box.scroll_target_x - box.scroll_x) * scroll_lerp


	baseline := rect.y + (rect.height - box.text_size) * 0.5 + box.text_size

	guilib.save(surface)
	defer guilib.restore(surface)

	guilib.clipRect(surface, rect)


	selection_start, selection_finish, has_selection := text_box_selection_bounds(box)

	if has_selection && len(box.text) > 0 {
		start_width := text_box_measure_prefix(box, selection_start)

		end_width := text_box_measure_prefix(box, selection_finish)

		selection_x := rect.x + padding + start_width - box.scroll_x

		selection_width := max(end_width - start_width, f32(0))

		guilib.drawRect(
			surface,
			guilib.Rect {
				x = selection_x,
				y = rect.y + 3,
				width = selection_width,
				height = max(rect.height - 6, f32(0)),
				color = box.selection_color3,
				bgTransparency = box.selection_transparency,
			},
		)
	}


	if len(display_text) > 0 {
		highlight: ^SyntaxHighlighter

		if len(box.text) > 0 {
			highlight = syntax_highlighter_for_box(box)
		}

		if highlight != nil {
			syntax_highlighter_ensure(highlight, box.text)

			text_box_draw_syntax_line(
				box,
				highlight,
				surface,
				rect.x + padding - box.scroll_x,
				baseline,
				0,
				len(box.text),
			)
		} else {
			text := strings.clone_to_cstring(display_text)

			defer delete(text)

			guilib.drawText(
				surface,
				text,
				guilib.TextParams {
					x = rect.x + padding - box.scroll_x,
					y = baseline,
					TextSize = box.text_size,
					color = display_color,
					transparency = box.text_transparency,
					typeface = box.stored_typeface,
				},
			)
		}
	}


	if box.focused {
		caret_alpha: f32 = 1
		t := box.caret_timer

		if t < 0.50 {
			caret_alpha = 1
		} else if t < 0.65 {
			caret_alpha = 1 - (t - 0.50) / 0.15
		} else if t < 1.05 {
			caret_alpha = 0
		} else {
			caret_alpha = (t - 1.05) / 0.15
		}

		caret_alpha = clamp(caret_alpha, f32(0), f32(1))

		caret_x := rect.x + padding + caret_width - box.scroll_x

		vertical_padding := min(f32(4), rect.height * 0.2)

		caret_transparency := 1 - (1 - box.text_transparency) * caret_alpha

		guilib.drawLine(
			surface,
			caret_x,
			rect.y + vertical_padding,
			caret_x,
			rect.y + rect.height - vertical_padding,
			1.5,
			box.caret_color3,
			caret_transparency,
		)
	}


	if box.focus_animation > 0.001 {
		focus_width := rect.width * box.focus_animation

		focus_x := rect.x + (rect.width - focus_width) * 0.5

		guilib.drawRect(
			surface,
			guilib.Rect {
				x = focus_x,
				y = rect.y + rect.height - 2,
				width = focus_width,
				height = 2,
				color = box.focus_color3,
				bgTransparency = 1 - box.focus_animation,
			},
		)
	}
}


TextBox_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^TextBox)source

	dst := cast(^TextBox)destination

	text_box_replace_string(&dst.text, src.text)

	text_box_replace_string(&dst.placeholder_text, src.placeholder_text)

	text_box_clear_diagnostics(dst)

	for diagnostic in src.diagnostics {
		text_box_append_diagnostic(
			dst,
			diagnostic.line,
			diagnostic.start_column,
			diagnostic.end_column,
			diagnostic.message,
		)
	}

	TextBox_Destroy_Typeface(dst)

	datatypes.Font_Destroy(&dst.font_face)

	dst.font_face = datatypes.Font_Clone(src.font_face)

	dst.font_enum = src.font_enum

	TextBox_Load_Typeface(dst)

	dst.text_size = src.text_size

	dst.text_color3 = src.text_color3

	dst.placeholder_color3 = src.placeholder_color3

	dst.text_transparency = src.text_transparency

	dst.clear_text_on_focus = src.clear_text_on_focus

	dst.text_editable = src.text_editable

	dst.select_all_on_focus = src.select_all_on_focus

	dst.max_length = src.max_length

	dst.caret_color3 = src.caret_color3

	dst.selection_color3 = src.selection_color3

	dst.selection_transparency = src.selection_transparency

	dst.focus_color3 = src.focus_color3

	dst.focused = false

	dst.cursor_byte = len(dst.text)

	dst.selection_anchor = dst.cursor_byte

	dst.drag_selecting = false

	dst.focus_animation = 0

	dst.caret_timer = 0

	dst.scroll_x = 0

	dst.scroll_target_x = 0
}


text_box_from_hit :: proc(
	registry: ^Registry,
	x: f32,
	y: f32,
) -> (
	box: ^TextBox,
	local_x, local_y: f32,
	ok: bool,
) {
	if registry == nil {
		return
	}

	hit := GuiObject_hit_test(registry, x, y)

	current: ^Object
	if hit.target != nil {
		current = &hit.target.object
	}

	for current != nil {
		if Is_A(current, "TextBox") {
			return cast(^TextBox)current, hit.x, hit.y, true
		}

		current = current.parent
	}

	return
}


TextBox_Handle_Event :: proc(registry: ^Registry, L: ^vm.State, event: sdl3.Event) {
	if registry == nil {
		return
	}

	#partial switch event.type {


	case .MOUSE_BUTTON_DOWN:
		if event.button.button != sdl3.BUTTON_LEFT {
			return
		}

		clicked, point_x, point_y, _ := text_box_from_hit(registry, event.button.x, event.button.y)


		if clicked == nil {
			if text_box_focused != nil {
				TextBox_blur(text_box_focused)
			}

			return
		}

		was_focused := clicked.focused

		if text_box_focused != nil && text_box_focused != clicked {
			TextBox_blur(text_box_focused)
		}

		TextBox_focus(clicked)

		if !clicked.focused {
			return
		}


		if event.button.clicks >= 2 {
			if clicked.code_editor {
				word_click := event.button.clicks == 2
				cursor := text_box_cursor_from_point(clicked, point_x, point_y, word_click)
				if word_click {
					text_box_select_word_at(clicked, cursor)
				} else {
					text_box_select_line_at(clicked, cursor)
				}
			} else {
				text_box_select_all(clicked)
			}

			clicked.drag_selecting = false

			return
		}


		if !was_focused && clicked.select_all_on_focus {
			clicked.drag_selecting = false

			return
		}

		cursor := text_box_cursor_from_point(clicked, point_x, point_y)

		modifiers := sdl3.GetModState()

		shift := .LSHIFT in modifiers || .RSHIFT in modifiers

		if !shift {
			clicked.selection_anchor = cursor
		}

		clicked.cursor_byte = cursor

		clicked.drag_selecting = true

		text_box_restart_caret(clicked)


	case .MOUSE_MOTION:
		box := text_box_focused

		if box == nil || !box.focused || !box.drag_selecting {
			return
		}

		point_x, point_y, _ := GuiObject_pointer_point(
			registry,
			&box.gui_object,
			f32(event.motion.x),
			f32(event.motion.y),
		)

		box.cursor_byte = text_box_cursor_from_point(box, point_x, point_y)

		text_box_restart_caret(box)


	case .MOUSE_BUTTON_UP:
		if event.button.button != sdl3.BUTTON_LEFT {
			return
		}

		if text_box_focused != nil {
			text_box_focused.drag_selecting = false
		}


	case .MOUSE_WHEEL:
		box := text_box_focused

		if box == nil || !box.focused || !box.code_editor {
			return
		}

		modifiers := sdl3.GetModState()

		ctrl := .LCTRL in modifiers || .RCTRL in modifiers

		shift := .LSHIFT in modifiers || .RSHIFT in modifiers

		padding: f32 = 6

		line_height := text_box_line_height(box)

		delta_x := event.wheel.x

		delta_y := event.wheel.y

		content_width := text_box_editor_content_width(box, box.absolute_size.X)

		content_height := max(box.absolute_size.Y - padding * 2, f32(0))

		if ctrl || shift {
			if abs(delta_x) < 0.001 {
				delta_x = delta_y
				delta_y = 0
			}
		}

		if abs(delta_x) > 0.001 {
			box.scroll_target_x = max(box.scroll_target_x - delta_x * box.text_size * 3, f32(0))
		}

		if abs(delta_y) > 0.001 {
			box.scroll_target_y -= delta_y * line_height * 3

			max_scroll_y := max(
				f32(text_box_visual_line_count(box, content_width)) * line_height - content_height,
				f32(0),
			)

			box.scroll_target_y = clamp(box.scroll_target_y, f32(0), max_scroll_y)
		}


	case .TEXT_INPUT:
		box := text_box_focused

		if box == nil || !box.focused || !box.text_editable || event.text.text == nil {
			return
		}

		text_box_handle_text(box, string(event.text.text))


	case .KEY_DOWN:
		box := text_box_focused

		if box == nil || !box.focused {
			return
		}


		box.key_handled = false

		text_box_fire_key_down(box, registry, event.key.scancode)

		if box.key_handled {
			return
		}

		modifiers := event.key.mod

		shift := .LSHIFT in modifiers || .RSHIFT in modifiers


		shortcut :=
			.LCTRL in modifiers || .RCTRL in modifiers || .LGUI in modifiers || .RGUI in modifiers


		if shortcut {
			#partial switch event.key.scancode {

			case .A:
				text_box_select_all(box)

				return

			case .C:
				text_box_copy_selection(box)

				return

			case .X:
				if box.text_editable {
					text_box_cut_selection(box)
				}

				return

			case .V:
				if box.text_editable {
					text_box_paste(box)
				}

				return

			case .D:
				if box.code_editor {
					text_box_duplicate_line(box)
				}
				return

			case .SLASH:
				if box.code_editor {
					text_box_toggle_comment(box)
				}
				return

			case .L:
				if box.code_editor {
					text_box_delete_line(box)
				}
				return

			case .Z:
				if box.code_editor {
					if shift {
						text_box_redo(box)
					} else {
						text_box_undo(box)
					}
				}
				return

			case .Y:
				if box.code_editor {
					text_box_redo(box)
				}
				return

			case:
			}
		}

		#partial switch event.key.scancode {

		case .UP:
			text_box_move_vertical(box, -1, shift)

		case .DOWN:
			text_box_move_vertical(box, 1, shift)

		case .TAB:
			if box.code_editor {
				text_box_indent_selection(box, shift)
			}


		case .BACKSPACE:
			if !box.text_editable {
				return
			}

			if text_box_delete_selection(box) {
				return
			}

			if box.cursor_byte > 0 {
				previous := text_box_utf8_prev_boundary(box.text, box.cursor_byte)

				text_box_erase(box, previous, box.cursor_byte)
			}


		case .DELETE:
			if !box.text_editable {
				return
			}

			if text_box_delete_selection(box) {
				return
			}

			if box.cursor_byte < len(box.text) {
				next := text_box_utf8_next_boundary(box.text, box.cursor_byte)

				text_box_erase(box, box.cursor_byte, next)
			}


		case .LEFT:
			selection_start, selection_finish, selected := text_box_selection_bounds(box)

			_ = selection_finish

			if selected && !shift {
				box.cursor_byte = selection_start

				box.selection_anchor = selection_start
			} else {
				old_cursor := box.cursor_byte

				if !shift {
					box.selection_anchor = old_cursor
				}

				if shortcut {
					box.cursor_byte = text_box_word_left(box.text, old_cursor)
				} else {
					box.cursor_byte = text_box_utf8_prev_boundary(box.text, old_cursor)
				}

				if !shift {
					box.selection_anchor = box.cursor_byte
				}
			}

			text_box_restart_caret(box)


		case .RIGHT:
			selection_start, selection_finish, selected := text_box_selection_bounds(box)

			_ = selection_start

			if selected && !shift {
				box.cursor_byte = selection_finish

				box.selection_anchor = selection_finish
			} else {
				old_cursor := box.cursor_byte

				if !shift {
					box.selection_anchor = old_cursor
				}

				if shortcut {
					box.cursor_byte = text_box_word_right(box.text, old_cursor)
				} else {
					box.cursor_byte = text_box_utf8_next_boundary(box.text, old_cursor)
				}

				if !shift {
					box.selection_anchor = box.cursor_byte
				}
			}

			text_box_restart_caret(box)


		case .HOME:
			old_cursor := box.cursor_byte

			target := 0

			if !shortcut && box.code_editor {
				target = text_box_line_start(box.text, old_cursor)
			}

			if shift {
				if box.selection_anchor == box.cursor_byte {
					box.selection_anchor = old_cursor
				}

				box.cursor_byte = target
			} else {
				box.cursor_byte = target
				box.selection_anchor = target
			}

			box.preferred_x_valid = false

			text_box_restart_caret(box)


		case .END:
			old_cursor := box.cursor_byte

			end := len(box.text)

			if !shortcut && box.code_editor {
				end = text_box_line_end(box.text, old_cursor)
			}

			if shift {
				if box.selection_anchor == box.cursor_byte {
					box.selection_anchor = old_cursor
				}

				box.cursor_byte = end
			} else {
				box.cursor_byte = end
				box.selection_anchor = end
			}

			box.preferred_x_valid = false

			text_box_restart_caret(box)


		case .RETURN, .KP_ENTER:
			if box.code_editor {
				text_box_insert_newline(box)
			} else {
				TextBox_blur(box, true)
			}


		case .ESCAPE:
			TextBox_blur(box)
		}
	}
}


Register_TextBox :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&TextBox_Class,
		TextBox_construct,
		TextBox_destroy,
		get = TextBox_get,
		set = TextBox_set,
		namecall = TextBox_namecall,
		clone = TextBox_clone,
		properties = []string {
			"Text",
			"Font",
			"FontFace",
			"PlaceholderText",
			"TextSize",
			"TextColor3",
			"PlaceholderColor3",
			"TextTransparency",
			"ClearTextOnFocus",
			"TextEditable",
			"SelectAllOnFocus",
			"MaxLength",
			"CaretColor3",
			"SelectionColor3",
			"SelectionTransparency",
			"FocusColor3",
			"CodeEditor",
			"ShowLineNumbers",
			"ShowMinimap",
			"TabSize",
			"AutoIndent",
			"AutoClose",
			"WordWrap",
			"SelectedText",
			"LineCount",
			"DiagnosticCount",
			"CursorPosition",
			"SelectionStart",
			"SelectionEnd",
			"CaretScreenPosition",
			"KeyHandled",
		},
		methods = []string {
			"CaptureFocus",
			"ReleaseFocus",
			"IsFocused",
			"SelectAll",
			"ClearSelection",
			"CopySelection",
			"Undo",
			"Redo",
			"InsertText",
			"ReplaceRange",
			"GetWordRangeAtCursor",
			"GetLineAtCursor",
			"SetDiagnostics",
			"ClearDiagnostics",
			"DiagnosticAtCursor",
			"DiagnosticAtPoint",
		},
		events = []string{"FocusLost", "TextChanged", "KeyDown"},
	)
}
