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
	using gui_object:              GuiObject,
	// The public string is a borrowed, zero-copy view of text_buffer.
	// Never free text: the TextBox owns text_buffer for both editor modes.
	text:                          string,
	text_buffer:                   []u8,
	line_starts:                   [dynamic]int,
	line_index_ready:              bool,
	line_widths:                   [dynamic]f32,
	line_widths_valid:             bool,
	bracket_cache_valid:           bool,
	bracket_cache_cursor:          int,
	bracket_cache_revision:        u64,
	bracket_cache_first:           int,
	bracket_cache_second:          int,
	bracket_cache_has:             bool,
	visual_lines:                  [dynamic]Visual_Line,
	visual_dirty:                  bool,
	visual_cached_width:           f32,
	visual_cached_wrap:            bool,
	visual_cached_text_size:       f32,
	visual_cached_tab_size:        int,
	visual_cached_typeface:        ^kineffi.KineSkiaTypeface,
	text_revision:                 u64,
	highlight_revision:            u64,
	highlight_ref:                 ^SyntaxHighlighter,
	syntax_highlight_max_bytes:    int,
	max_undo_entries:              int,
	single_full_width:             f32,
	single_full_width_valid:       bool,
	single_prefix_byte:            int,
	single_prefix_width:           f32,
	single_prefix_valid:           bool,
	single_draw_start:             int,
	single_draw_x:                 f32,
	single_draw_valid:             bool,
	content_measure_width:         f32,
	content_measure_height:        f32,
	content_measure_valid:         bool,
	placeholder_text:              string,
	text_size:                     f32,
	text_x_alignment:              enums.TextXAlignment,
	text_y_alignment:              enums.TextYAlignment,
	text_color3:                   datatypes.Color3,
	placeholder_color3:            datatypes.Color3,
	text_transparency:             f32,
	font_face:                     datatypes.Font,
	font_enum:                     enums.Font,
	stored_typeface:               ^kineffi.KineSkiaTypeface,
	clear_text_on_focus:           bool,
	text_editable:                 bool,
	select_all_on_focus:           bool,
	relative_line_numbers:         bool,
	highlight_current_line:        bool,
	bracket_matching:              bool,
	tab_spaces:                    bool,
	show_indent_guides:            bool,
	highlight_active_indent_guide: bool,
	show_whitespace:               bool,
	show_scrollbar:                bool,
	show_gutter_separator:         bool,
	smooth_scrolling:              bool,
	smart_home:                    bool,
	smart_backspace:               bool,
	auto_indent_brackets:          bool,
	find_visible:                  bool,
	find_cursor_byte:              int,
	find_input_active:             bool,
	find_query:                    string,
	find_case_sensitive:           bool,
	show_find_highlights:          bool,
	find_match_color3:             datatypes.Color3,
	line_number_color3:            datatypes.Color3,
	current_line_color3:           datatypes.Color3,
	indent_guide_color3:           datatypes.Color3,
	bracket_match_color3:          datatypes.Color3,
	gutter_color3:                 datatypes.Color3,
	minimap_color3:                datatypes.Color3,
	scrollbar_color3:              datatypes.Color3,
	editor_padding:                f32,
	editor_line_height:            f32,
	minimap_width:                 f32,
	scrollbar_width:               f32,
	mouse_wheel_scroll_lines:      f32,
	scrollbar_dragging:            bool,
	scrollbar_drag_offset:         f32,
	code_editor:                   bool,
	multi_line:                    bool,
	show_line_numbers:             bool,
	show_minimap:                  bool,
	tab_size:                      int,
	auto_indent:                   bool,
	max_length:                    int,
	focused:                       bool,
	cursor_byte:                   int,
	selection_anchor:              int,
	drag_selecting:                bool,
	key_handled:                   bool,
	key_down:                      ^signals.Signal,
	caret_color3:                  datatypes.Color3,
	selection_color3:              datatypes.Color3,
	selection_transparency:        f32,
	focus_color3:                  datatypes.Color3,
	focus_lost:                    ^signals.Signal,
	focus_gained:                  ^signals.Signal,
	text_changed:                  ^signals.Signal,
	focus_animation:               f32,
	caret_timer:                   f32,
	scroll_x:                      f32,
	scroll_target_x:               f32,
	scroll_y:                      f32,
	scroll_target_y:               f32,
	preferred_x:                   f32,
	preferred_x_valid:             bool,
	caret_needs_scroll:            bool,
	caret_screen_position:         datatypes.Vector2,
	auto_close:                    bool,
	wrap:                          bool,
	diagnostics:                   [dynamic]TextBox_Diagnostic,
	undo_stack:                    [dynamic]Undo_Entry,
	redo_stack:                    [dynamic]Undo_Entry,
	suppress_undo:                 bool,
	undo_epoch:                    int,
}


text_box_focused: ^TextBox
text_box_highlighter_last_box: ^TextBox


TextBox_Focused :: proc() -> ^TextBox {
	return text_box_focused
}


TextBox_Init :: proc() -> TextBox {
	gui := GuiObject_Init()
	gui.object.class = &TextBox_Class

	font := datatypes.Font_New(DEFAULT_FONT, .Regular, .Normal)

	return TextBox {
		gui_object = gui,
		text = "",
		text_buffer = nil,
		visual_dirty = true,
		line_index_ready = false,
		syntax_highlight_max_bytes = 2 * 1024 * 1024,
		max_undo_entries = 1000,
		placeholder_text = strings.clone(""),
		text_size = 16,
		text_x_alignment = .Left,
		text_y_alignment = .Center,
		text_color3 = datatypes.Color3{0, 0, 0},
		placeholder_color3 = datatypes.Color3{0.5, 0.5, 0.5},
		text_transparency = 0,
		font_face = font,
		font_enum = .Legacy,
		stored_typeface = nil,
		clear_text_on_focus = false,
		text_editable = true,
		select_all_on_focus = false,
		relative_line_numbers = false,
		highlight_current_line = true,
		bracket_matching = true,
		show_indent_guides = true,
		highlight_active_indent_guide = true,
		show_whitespace = false,
		show_scrollbar = true,
		show_gutter_separator = true,
		smooth_scrolling = true,
		smart_home = true,
		smart_backspace = true,
		auto_indent_brackets = true,
		find_visible = false,
		find_cursor_byte = 0,
		find_input_active = false,
		find_query = strings.clone(""),
		find_case_sensitive = false,
		show_find_highlights = true,
		find_match_color3 = datatypes.Color3{0.92, 0.68, 0.25},
		line_number_color3 = datatypes.Color3{0.54, 0.57, 0.63},
		current_line_color3 = datatypes.Color3{0.30, 0.48, 0.73},
		indent_guide_color3 = datatypes.Color3{0.47, 0.52, 0.61},
		bracket_match_color3 = datatypes.Color3{0.45, 0.63, 0.95},
		gutter_color3 = datatypes.Color3{0.93, 0.94, 0.96},
		minimap_color3 = datatypes.Color3{0.93, 0.94, 0.96},
		scrollbar_color3 = datatypes.Color3{0.54, 0.57, 0.64},
		editor_padding = 8,
		editor_line_height = 0,
		minimap_width = 76,
		scrollbar_width = 8,
		mouse_wheel_scroll_lines = 3,
		tab_spaces = true,
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
	box.visual_dirty = true
	box.single_full_width_valid = false
	box.single_prefix_valid = false
	box.content_measure_valid = false
	box.line_widths_valid = false
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


// Reusable capacity-backed UTF-8 storage. text is a read-only slice of this buffer.
// The byte offsets used by the old API are unchanged; contents need no terminating NUL.
text_box_buffer_reserve :: proc(box: ^TextBox, required: int) {
	if required <= len(box.text_buffer) {return}
	capacity := max(len(box.text_buffer), 256)
	for capacity < required {capacity = max(capacity * 2, required)}
	old_length := len(box.text)
	next := make([]u8, capacity)
	for i in 0 ..< old_length {next[i] = box.text_buffer[i]}
	if len(box.text_buffer) > 0 {delete(box.text_buffer)}
	box.text_buffer = next
	box.text = ""
	if old_length > 0 {box.text = transmute(string)box.text_buffer[:old_length]}
}

text_box_after_buffer_edit :: proc(box: ^TextBox) {
	box.text_revision += 1
	box.visual_dirty = true
	box.single_full_width_valid = false
	box.single_prefix_valid = false
	box.single_draw_valid = false
	box.content_measure_valid = false
	box.caret_needs_scroll = true
}

// Binary search over physical line starts (0-based line index).
text_box_line_upper_bound :: proc(starts: []int, position: int) -> int {
	low, high := 0, len(starts)
	for low < high {
		mid := low + (high - low) / 2
		if starts[mid] <= position {low = mid + 1} else {high = mid}
	}
	return low
}

text_box_line_index_ensure :: proc(box: ^TextBox) {
	if box.line_index_ready {return}
	clear(&box.line_starts)
	append(&box.line_starts, 0)
	for i in 0 ..< len(box.text) {
		if box.text[i] == '\n' {append(&box.line_starts, i + 1)}
	}
	box.line_index_ready = true
}

text_box_line_index_replace :: proc(box: ^TextBox, start, finish: int, inserted: string) {
	text_box_line_index_ensure(box)
	first := text_box_line_upper_bound(box.line_starts[:], start)
	after := text_box_line_upper_bound(box.line_starts[:], finish)
	inserted_lines := 0
	for c in transmute([]u8)inserted {if c == '\n' {inserted_lines += 1}}

	old_count := len(box.line_starts)
	tail := old_count - after
	new_count := first + inserted_lines + tail
	delta := len(inserted) - (finish - start)
	target_tail := first + inserted_lines
	if new_count > old_count {
		resize(&box.line_starts, new_count)
		for i := tail; i > 0; i -= 1 {
			box.line_starts[target_tail + i - 1] = box.line_starts[after + i - 1] + delta
		}
	} else {
		for i in 0 ..< tail {
			box.line_starts[target_tail + i] = box.line_starts[after + i] + delta
		}
		resize(&box.line_starts, new_count)
	}
	output := first
	for c, i in transmute([]u8)inserted {
		if c == '\n' {
			box.line_starts[output] = start + i + 1
			output += 1
		}
	}
}

text_box_cached_line_number :: proc(box: ^TextBox, position: int) -> int {
	text_box_line_index_ensure(box)
	return max(text_box_line_upper_bound(box.line_starts[:], clamp(position, 0, len(box.text))), 1)
}

text_box_cached_line_start :: proc(box: ^TextBox, number: int) -> int {
	text_box_line_index_ensure(box)
	if number < 0 {return 0}
	if number >= len(box.line_starts) {return len(box.text)}
	return box.line_starts[number]
}

text_box_cached_line_count :: proc(box: ^TextBox) -> int {
	text_box_line_index_ensure(box)
	return len(box.line_starts)
}

// Recalculate widths for only the physical lines changed by an edit. Widths for
// unaffected lines remain valid even when their byte offsets move.
text_box_line_widths_replace :: proc(box: ^TextBox, old_first, old_last: int) {
	if !box.line_widths_valid {return}
	first := clamp(old_first, 0, len(box.line_widths))
	last := clamp(old_last, first, max(len(box.line_widths) - 1, 0))
	old_after := last + 1
	new_count := len(box.line_starts)
	tail := len(box.line_widths) - old_after
	changed_count := new_count - first - tail
	if changed_count < 1 {box.line_widths_valid = false; return}
	new_tail := first + changed_count
	if new_count > len(box.line_widths) {
		resize(&box.line_widths, new_count)
		for i := tail; i > 0; i -= 1 {
			box.line_widths[new_tail + i - 1] = box.line_widths[old_after + i - 1]
		}
	} else {
		for i in 0 ..< tail {
			box.line_widths[new_tail + i] = box.line_widths[old_after + i]
		}
		resize(&box.line_widths, new_count)
	}
	for i := first; i < new_tail; i += 1 {
		start := box.line_starts[i]
		finish := len(box.text)
		if i + 1 < len(box.line_starts) {finish = box.line_starts[i + 1] - 1}
		box.line_widths[i] = text_box_measure_range(box, start, finish)
	}
}

text_box_buffer_set :: proc(box: ^TextBox, value: string) {
	// Clone first: callers can pass a substring of the old, owned buffer.
	source := strings.clone(value)
	defer {if len(source) > 0 {delete(source)}}
	text_box_buffer_reserve(box, len(source))
	for c, i in transmute([]u8)source {box.text_buffer[i] = c}
	box.text = ""
	if len(source) > 0 {box.text = transmute(string)box.text_buffer[:len(source)]}
	box.line_index_ready = false
	box.line_widths_valid = false
	text_box_after_buffer_edit(box)
}

text_box_buffer_replace :: proc(box: ^TextBox, first, last: int, replacement: string) {
	start := clamp(first, 0, len(box.text))
	finish := clamp(last, start, len(box.text))
	if finish == start && len(replacement) == 0 {return}
	// Keep an owned copy so replacement may alias this buffer, including during growth.
	inserted := strings.clone(replacement)
	defer {if len(inserted) > 0 {delete(inserted)}}
	old_length := len(box.text)
	delta := len(inserted) - (finish - start)
	new_length := old_length + delta
	cached_full := box.single_full_width_valid
	full_before := box.single_full_width
	cached_prefix := box.single_prefix_valid
	prefix_before := box.single_prefix_byte
	prefix_width_before := box.single_prefix_width
	cached_draw := box.single_draw_valid
	draw_before := box.single_draw_start
	draw_x_before := box.single_draw_x
	change_width: f32 = 0
	if !box.code_editor && (cached_full || cached_prefix || cached_draw || box.line_widths_valid) {
		change_width =
			text_box_measure_text(box, inserted) - text_box_measure_range(box, start, finish)
	}
	text_box_line_index_ensure(box)
	old_first_line := text_box_line_upper_bound(box.line_starts[:], start) - 1
	old_last_line := text_box_line_upper_bound(box.line_starts[:], finish) - 1
	text_box_line_index_replace(box, start, finish, inserted)
	text_box_buffer_reserve(box, new_length)
	if delta > 0 {
		for i := old_length; i > finish; i -= 1 {
			box.text_buffer[i - 1 + delta] = box.text_buffer[i - 1]
		}
	} else if delta < 0 {
		for i := finish; i < old_length; i += 1 {
			box.text_buffer[i + delta] = box.text_buffer[i]
		}
	}
	for c, i in transmute([]u8)inserted {box.text_buffer[start + i] = c}
	box.text = ""
	if new_length > 0 {box.text = transmute(string)box.text_buffer[:new_length]}
	if !box.code_editor && len(box.line_starts) == 1 && box.line_widths_valid {
		box.line_widths[0] = max(box.line_widths[0] + change_width, f32(0))
	} else {
		text_box_line_widths_replace(box, old_first_line, old_last_line)
	}
	text_box_after_buffer_edit(box)
	if !box.code_editor {
		if cached_full {
			box.single_full_width = max(full_before + change_width, f32(0))
			box.single_full_width_valid = true
		}
		if cached_prefix {
			if finish <= prefix_before {
				box.single_prefix_byte = prefix_before + delta
				box.single_prefix_width = max(prefix_width_before + change_width, f32(0))
				box.single_prefix_valid = true
			} else if start > prefix_before {
				box.single_prefix_byte = prefix_before
				box.single_prefix_width = prefix_width_before
				box.single_prefix_valid = true
			}
		}
		if cached_draw {
			if finish <= draw_before {
				box.single_draw_start = draw_before + delta
				box.single_draw_x = max(draw_x_before + change_width, f32(0))
				box.single_draw_valid = true
			} else if start >= draw_before {
				box.single_draw_start = draw_before
				box.single_draw_x = draw_x_before
				box.single_draw_valid = true
			}
		}
	}
}

text_box_undo_trim :: proc(box: ^TextBox) {
	limit := max(box.max_undo_entries, 0)
	if limit == 0 {undo_stack_clear(&box.undo_stack); return}
	if len(box.undo_stack) <= limit {return}
	remove_count := len(box.undo_stack) - limit
	for i in 0 ..< remove_count {undo_entry_destroy(&box.undo_stack[i])}
	for i := remove_count; i < len(box.undo_stack); i += 1 {
		box.undo_stack[i - remove_count] = box.undo_stack[i]
	}
	resize(&box.undo_stack, limit)
}

text_box_restart_caret :: proc(box: ^TextBox) {
	if box == nil {
		return
	}

	box.caret_timer = 0
	box.caret_needs_scroll = true
	gui_invalidate_draw(&box.object)
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

text_box_fire_text_changed :: proc(box: ^TextBox, L: ^vm.State = nil) {
	if box == nil {
		return
	}

	Gui_Layout_Mark_Dirty()
	surfacegui_mark_dirty_for(&box.object)

	if box.object.signal_registry == nil || box.object.signal_registry.signal_registry == nil {
		return
	}

	state := L if L != nil else box.object.signal_registry.signal_registry.L
	if state == nil {return}

	signals.Fire(state, box.text_changed, 0)
	if !box.object.destroyed {
		Object_Fire_Property_Changed(&box.object, "Text", state)
	}
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

	text_box_buffer_replace(
		box,
		entry.start,
		entry.start + len(entry.insert_text),
		entry.delete_text,
	)

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

	text_box_buffer_replace(
		box,
		entry.start,
		entry.start + len(entry.delete_text),
		entry.insert_text,
	)

	box.cursor_byte = entry.start + len(entry.insert_text)

	box.selection_anchor = box.cursor_byte

	append(&box.undo_stack, entry)

	box.undo_epoch += 1

	text_box_restart_caret(box)

	text_box_fire_text_changed(box)
}

text_box_line_height :: proc(box: ^TextBox) -> f32 {
	if box != nil && box.code_editor && box.editor_line_height > 0 {
		return max(box.editor_line_height, box.text_size)
	}
	return max(box.text_size * 1.35, box.text_size + 4)
}

text_box_editor_minimap_width :: proc(box: ^TextBox, width: f32) -> f32 {
	if box == nil || !box.code_editor || !box.show_minimap || width < 220 {return 0}
	return min(box.minimap_width, width * 0.3)
}

text_box_editor_max_scroll_y :: proc(box: ^TextBox) -> f32 {
	content_width := text_box_editor_content_width(box, box.absolute_size.X)
	return max(
		f32(text_box_visual_line_count(box, content_width)) * text_box_line_height(box) -
		max(box.absolute_size.Y - box.editor_padding * 2, f32(0)),
		f32(0),
	)
}

TextBox_Measure_Content :: proc(box: ^TextBox, available_width: f32) -> datatypes.Vector2 {
	if box == nil || box.stored_typeface == nil {return datatypes.Vector2_Zero}
	if box.content_measure_valid {
		return datatypes.Vector2{box.content_measure_width, box.content_measure_height}
	}
	text_box_line_index_ensure(box)
	if !box.line_widths_valid {
		clear(&box.line_widths)
		for i in 0 ..< len(box.line_starts) {
			start := box.line_starts[i]
			finish := len(box.text)
			if i + 1 < len(box.line_starts) {finish = box.line_starts[i + 1] - 1}
			append(&box.line_widths, text_box_measure_range(box, start, finish))
		}
		box.line_widths_valid = true
	}
	widest: f32 = 0
	for width in box.line_widths {widest = max(widest, width)}
	box.content_measure_width = widest
	box.content_measure_height = f32(len(box.line_starts)) * text_box_line_height(box)
	box.content_measure_valid = true
	return datatypes.Vector2{widest, box.content_measure_height}
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

	digits := text_box_decimal_digits(text_box_cached_line_count(box))

	return f32(digits) * box.text_size * 0.62 + 24
}

// Display controls without changing the original text or its byte offsets.
// For syntax runs, start skips the prefix while retaining its tab column.
text_box_display_cstring :: proc(text: string, tab_size: int, start := 0) -> cstring {
	bytes := transmute([]u8)text
	has_control := false
	for value in bytes[start:] {
		if value < ' ' || value == 0x7f {
			has_control = true
			break
		}
	}
	if !has_control {
		return strings.clone_to_cstring(text[start:])
	}

	spaces := "                "
	size := clamp(tab_size, 1, len(spaces))
	column := 0
	display := strings.builder_make()
	defer strings.builder_destroy(&display)
	for value, index in bytes {
		if value == '\t' {
			width := size - column % size
			if index >= start {
				strings.write_string(&display, spaces[:width])
			}
			column += width
		} else if value >= ' ' && value != 0x7f {
			if index >= start {
				strings.write_byte(&display, value)
			}
			if value & 0xc0 != 0x80 {
				column += 1
			}
		}
	}
	return strings.clone_to_cstring(strings.to_string(display))
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

	return text_box_measure_text(box, box.text[a:b])
}

text_box_measure_text :: proc(box: ^TextBox, text: string) -> f32 {
	if len(text) == 0 {return 0}
	value := text_box_display_cstring(text, box.tab_size)
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
	if box == nil || start >= finish {return start}
	target := max(target_x, f32(0))
	if target <= 0 {return start}
	last_width := text_box_measure_range(box, start, finish)
	if target >= last_width {
		if hit_glyph {return text_box_utf8_prev_boundary(box.text, finish)}
		return finish
	}
	lo, hi := start, finish
	for text_box_utf8_next_boundary(box.text, lo) < hi {
		middle := lo + (hi - lo) / 2
		for middle > lo && (box.text[middle] & 0xC0) == 0x80 {middle -= 1}
		if middle <= lo {middle = text_box_utf8_next_boundary(box.text, lo)}
		if text_box_measure_range(box, start, middle) < target {lo = middle} else {hi = middle}
	}
	if hit_glyph {return lo}
	left := text_box_measure_range(box, start, lo)
	right := text_box_measure_range(box, start, hi)
	if target < (left + right) * 0.5 {return lo}
	return hi
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

	if !box.code_editor && !box.multi_line {
		return text_box_cursor_from_x(box, mouse_x)
	}

	padding := box.editor_padding

	line_height := text_box_line_height(box)

	y := (mouse_y - box.absolute_position.Y - padding + box.scroll_y)

	line := int(max(y / line_height, f32(0)))

	content_width := text_box_editor_content_width(box, box.absolute_size.X)

	lines := text_box_visual_lines(box, content_width)

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

// Move to a 1-based physical line and UTF-8 character column, optionally
// selecting a number of characters from that position. The caret and viewport
// are updated even when this textbox is not the currently focused input.
// Call TextBox_focus before this procedure when the caller requests focus:
// TextBox_focus resets the caret position as part of its focus lifecycle.
TextBox_Go_To_Line :: proc(
	box: ^TextBox,
	line_number: int,
	column_number: int = 1,
	selection_length: int = 0,
) {
	if box == nil {return}

	text_box_line_index_ensure(box)
	line_index := clamp(line_number - 1, 0, max(len(box.line_starts) - 1, 0))
	start := box.line_starts[line_index]
	finish := len(box.text)
	if line_index + 1 < len(box.line_starts) {
		finish = box.line_starts[line_index + 1] - 1
	}
	// Treat CRLF as a single line ending instead of navigating into the CR.
	if finish > start && box.text[finish - 1] == '\r' {finish -= 1}

	line_text := box.text[start:finish]
	column_bytes := text_box_utf8_prefix_bytes(line_text, max(column_number - 1, 0))
	position := start + column_bytes
	selection_bytes := text_box_utf8_prefix_bytes(
		box.text[position:finish],
		max(selection_length, 0),
	)

	text_box_set_cursor(box, position + selection_bytes, false)
	if selection_bytes > 0 {box.selection_anchor = position}

	if box.code_editor || box.multi_line {
		content_width := text_box_editor_content_width(box, box.absolute_size.X)
		lines := text_box_visual_lines(box, content_width)
		if len(lines) > 0 {
			visual_index := text_box_visual_index_at(lines, box.cursor_byte)
			line_height := text_box_line_height(box)
			viewport_height := max(box.absolute_size.Y - box.editor_padding * 2, f32(0))
			max_scroll := max(f32(len(lines)) * line_height - viewport_height, f32(0))

			// Center the destination when space permits; otherwise clamp to the
			// nearest valid position. Move both target and current offsets so a
			// search-result click is immediate even with smooth scrolling enabled.
			center_offset := max((viewport_height - line_height) * 0.5, f32(0))
			box.scroll_target_y = clamp(
				f32(visual_index) * line_height - center_offset,
				f32(0),
				max_scroll,
			)
			box.scroll_y = box.scroll_target_y

			if box.wrap {
				box.scroll_target_x = 0
				box.scroll_x = 0
			} else {
				caret_x := text_box_measure_range(box, lines[visual_index].start, box.cursor_byte)
				viewport_width := max(content_width, f32(0))
				if caret_x < box.scroll_target_x ||
				   caret_x > box.scroll_target_x + viewport_width {
					box.scroll_target_x = max(caret_x - viewport_width * 0.25, f32(0))
				}
				box.scroll_x = box.scroll_target_x
			}
		}
	}

	box.caret_needs_scroll = false
	gui_invalidate_draw(&box.object)
}

text_box_move_vertical :: proc(box: ^TextBox, direction: int, shift: bool, amount: int = 1) {
	if box == nil || (!box.code_editor && !box.multi_line) || direction == 0 {
		return
	}

	content_width := text_box_editor_content_width(box, box.absolute_size.X)

	lines := text_box_visual_lines(box, content_width)

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
	if box == nil {return -1, -1, false}
	if box.bracket_cache_valid &&
	   box.bracket_cache_revision == box.text_revision &&
	   box.bracket_cache_cursor == box.cursor_byte {
		return box.bracket_cache_first, box.bracket_cache_second, box.bracket_cache_has
	}
	first, second = -1, -1
	has = false
	if len(box.text) > 0 {
		p := box.cursor_byte
		if p < len(box.text) && text_box_is_bracket(box.text[p]) {
			first = p
		} else if p > 0 && text_box_is_bracket(box.text[p - 1]) {
			first = p - 1
		}
		if first >= 0 {
			second = text_box_bracket_pair(box.text, first)
			has = true
		}
	}
	box.bracket_cache_cursor = box.cursor_byte
	box.bracket_cache_revision = box.text_revision
	box.bracket_cache_first = first
	box.bracket_cache_second = second
	box.bracket_cache_has = has
	box.bracket_cache_valid = true
	return first, second, has
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


// Only ASCII case folding is used; Luau identifiers and typical queries are ASCII.
text_box_find_byte_equal :: proc(a, b: u8, case_sensitive: bool) -> bool {
	if case_sensitive {
		return a == b
	}

	ca := a
	cb := b

	if ca >= 'A' && ca <= 'Z' {ca += 32}
	if cb >= 'A' && cb <= 'Z' {cb += 32}

	return ca == cb
}

text_box_find_range :: proc(box: ^TextBox, from, to: int) -> int {
	if box == nil || len(box.find_query) == 0 {return -1}
	query := box.find_query
	finish := min(to, len(box.text)) - len(query)
	for p := max(from, 0); p <= finish; p += 1 {
		match := true
		for j in 0 ..< len(query) {
			if !text_box_find_byte_equal(box.text[p + j], query[j], box.find_case_sensitive) {
				match = false
				break
			}
		}
		if match {return p}
	}
	return -1
}

text_box_find_previous_range :: proc(box: ^TextBox, from, to: int) -> int {
	if box == nil || len(box.find_query) == 0 {return -1}
	query := box.find_query
	finish := min(to, len(box.text) - len(query))
	if finish < from {return -1}
	for p := finish; p >= max(from, 0); p -= 1 {
		match := true
		for j in 0 ..< len(query) {
			if !text_box_find_byte_equal(box.text[p + j], query[j], box.find_case_sensitive) {
				match = false
				break
			}
		}
		if match {return p}
	}
	return -1
}

text_box_find_next :: proc(box: ^TextBox, backward := false) -> bool {
	if box == nil || len(box.find_query) == 0 {return false}
	start, finish, selected := text_box_selection_bounds(box)
	_ = selected
	found := -1
	if backward {
		found = text_box_find_previous_range(box, 0, start - 1)
		if found < 0 {
			found = text_box_find_previous_range(box, 0, len(box.text) - len(box.find_query))
		}
	} else {
		found = text_box_find_range(box, finish, len(box.text))
		if found < 0 {found = text_box_find_range(box, 0, len(box.text))}
	}
	if found < 0 {return false}
	box.selection_anchor = found
	box.cursor_byte = found + len(box.find_query)
	box.preferred_x_valid = false
	text_box_restart_caret(box)
	return true
}

text_box_open_find :: proc(box: ^TextBox) {
	if box == nil || !box.code_editor {return}
	start, finish, selected := text_box_selection_bounds(box)
	if selected && finish - start <= 128 && !strings.contains(box.text[start:finish], "\n") {
		text_box_replace_string(&box.find_query, box.text[start:finish])
	}
	if !box.focused {TextBox_focus(box)}
	box.find_visible = true
	box.find_input_active = true
	box.find_cursor_byte = len(box.find_query)
	if !box.text_editable {
		window := sdl3.GetKeyboardFocus()
		if window != nil {
			_ = sdl3.StartTextInput(window)
			TEXTBOX_IS_USED = true
		}
	}
	gui_invalidate_draw(&box.object)
}

text_box_close_find :: proc(box: ^TextBox) {
	if box == nil {return}
	box.find_visible = false
	box.find_input_active = false
	if !box.text_editable && box.focused {
		window := sdl3.GetKeyboardFocus()
		if window != nil {
			_ = sdl3.StopTextInput(window)
			TEXTBOX_IS_USED = false
		}
	}
	gui_invalidate_draw(&box.object)
}

text_box_editor_scrollbar_thumb :: proc(box: ^TextBox) -> (y, height, max_scroll: f32) {
	padding := box.editor_padding
	available := max(box.absolute_size.Y - padding * 2, f32(1))
	max_scroll = text_box_editor_max_scroll_y(box)
	content_height := available + max_scroll
	height = min(max(available * available / max(content_height, f32(1)), f32(22)), available)
	y = box.absolute_position.Y + padding
	if max_scroll > 0 {
		y += (available - height) * clamp(box.scroll_target_y / max_scroll, f32(0), f32(1))
	}
	return
}

text_box_editor_scrollbar_to_mouse :: proc(box: ^TextBox, pointer_y: f32) {
	thumb_y, thumb_height, max_scroll := text_box_editor_scrollbar_thumb(box)
	_ = thumb_y
	if max_scroll == 0 {return}
	track_top := box.absolute_position.Y + box.editor_padding
	track_height := max(box.absolute_size.Y - 2 * box.editor_padding - thumb_height, f32(1))
	fraction := clamp(
		(pointer_y - box.scrollbar_drag_offset - track_top) / track_height,
		f32(0),
		f32(1),
	)
	box.scroll_target_y = fraction * max_scroll
	if !box.smooth_scrolling {box.scroll_y = box.scroll_target_y}
	gui_invalidate_draw(&box.object)
}

text_box_editor_scroll_from_minimap :: proc(box: ^TextBox, pointer_y: f32) {
	if box == nil {return}
	max_scroll := text_box_editor_max_scroll_y(box)
	fraction := clamp(
		(pointer_y - box.absolute_position.Y) / max(box.absolute_size.Y, f32(1)),
		f32(0),
		f32(1),
	)
	box.scroll_target_y = fraction * max_scroll
	if !box.smooth_scrolling {box.scroll_y = box.scroll_target_y}
	gui_invalidate_draw(&box.object)
}

text_box_editor_find_hit :: proc(box: ^TextBox, x, y: f32) -> bool {
	if box == nil || !box.code_editor || !box.find_visible {return false}
	panel_width := min(f32(300), max(box.absolute_size.X - 20, f32(0)))
	left := box.absolute_position.X + box.absolute_size.X - panel_width - 10
	return(
		x >= left &&
		x < left + panel_width &&
		y >= box.absolute_position.Y + 8 &&
		y <= box.absolute_position.Y + 40 \
	)
}

text_box_draw_editor_guide :: proc(
	box: ^TextBox,
	surface: ^kineffi.KineSkiaSurface,
	line: Visual_Line,
	y, content_x, line_height: f32,
	active_indent: int,
) {
	if !box.show_indent_guides || line.start >= line.finish {return}
	tab_size := max(box.tab_size, 1)
	column := 0
	offset := line.start
	for offset < line.finish && (box.text[offset] == ' ' || box.text[offset] == '\t') {
		if box.text[offset] == '\t' {
			column += tab_size - column % tab_size
		} else {
			column += 1
		}
		offset += 1
	}
	if column < tab_size {return}
	one_space := text_box_measure_text(box, " ")
	for level := tab_size; level <= column; level += tab_size {
		x := content_x + one_space * f32(level) - box.scroll_x
		color := box.indent_guide_color3
		transparency: f32 = 0.81
		if box.highlight_active_indent_guide && level == active_indent {
			color = box.bracket_match_color3
			transparency = 0.37
		}
		guilib.drawLine(surface, x, y, x, y + line_height, 1, color, transparency)
	}
}

text_box_draw_editor_whitespace :: proc(
	box: ^TextBox,
	surface: ^kineffi.KineSkiaSurface,
	line: Visual_Line,
	content_x, y, line_height: f32,
) {
	if !box.show_whitespace {return}
	for i := line.start; i < line.finish; i += 1 {
		if box.text[i] != ' ' && box.text[i] != '\t' {continue}
		left := text_box_measure_range(box, line.start, i)
		right := text_box_measure_range(box, line.start, i + 1)
		x := content_x + (left + right) * 0.5 - box.scroll_x
		cy := y + line_height * 0.56
		if box.text[i] == ' ' {
			guilib.drawRect(
				surface,
				guilib.Rect {
					x = x,
					y = cy,
					width = 1.5,
					height = 1.5,
					color = box.line_number_color3,
					bgTransparency = 0.34,
				},
			)
		} else {
			guilib.drawLine(surface, x - 3, cy, x + 3, cy, 1, box.line_number_color3, 0.42)
		}
	}
}

text_box_draw_editor_find :: proc(
	box: ^TextBox,
	surface: ^kineffi.KineSkiaSurface,
	line: Visual_Line,
	x, y, line_height: f32,
) {
	if !box.show_find_highlights || len(box.find_query) == 0 || len(box.find_query) > 128 {return}
	offset := line.start
	for offset < line.finish {
		match := text_box_find_range(box, offset, line.finish)
		if match < 0 {break}
		left := text_box_measure_range(box, line.start, match)
		right := text_box_measure_range(box, line.start, match + len(box.find_query))
		guilib.drawRect(
			surface,
			guilib.Rect {
				x = x + left,
				y = y + 1,
				width = max(right - left, f32(1)),
				height = max(line_height - 2, f32(0)),
				color = box.find_match_color3,
				bgTransparency = 0.69,
			},
		)
		offset = match + max(len(box.find_query), 1)
	}
}

text_box_render_find_panel :: proc(
	box: ^TextBox,
	surface: ^kineffi.KineSkiaSurface,
	rect: guilib.Rect,
) {
	if !box.find_visible || rect.width < 100 || rect.height < 48 {return}
	width := min(f32(300), max(rect.width - 20, f32(0)))
	left := rect.x + rect.width - width - 10
	top := rect.y + 8
	guilib.drawRoundedRect(
		surface,
		guilib.Rect {
			x = left,
			y = top,
			width = width,
			height = 32,
			color = box.gutter_color3,
			bgTransparency = 0.02,
		},
		4,
	)
	border_color := box.indent_guide_color3
	border_transparency: f32 = 0.52
	if box.find_input_active {
		border_color = box.bracket_match_color3
		border_transparency = 0.28
	}
	guilib.drawRoundedRectStroke(
		surface,
		guilib.Rect {
			x = left,
			y = top,
			width = width,
			height = 32,
			color = border_color,
			bgTransparency = border_transparency,
		},
		4,
		1,
	)
	label := strings.clone_to_cstring("Find")
	defer delete(label)
	guilib.drawText(
		surface,
		label,
		guilib.TextParams {
			x = left + 9,
			y = top + 22,
			TextSize = box.text_size * 0.8,
			color = box.line_number_color3,
			typeface = box.stored_typeface,
		},
	)
	query := box.find_query
	skip := 0
	if len(query) > 90 {
		skip = len(query) - 90
		for skip < len(query) && (query[skip] & 0xC0) == 0x80 {skip += 1}
		query = query[skip:]
	}
	display := text_box_display_cstring(query, box.tab_size)
	defer delete(display)
	guilib.save(surface)
	guilib.clipRect(
		surface,
		guilib.Rect{x = left + 46, y = top, width = max(width - 56, f32(0)), height = 32},
	)
	guilib.drawText(
		surface,
		display,
		guilib.TextParams {
			x = left + 47,
			y = top + 22,
			TextSize = box.text_size * 0.85,
			color = box.text_color3,
			typeface = box.stored_typeface,
		},
	)
	if box.find_input_active && box.caret_timer < 0.6 {
		end := clamp(box.find_cursor_byte - skip, 0, len(query))
		prefix := text_box_display_cstring(query[:end], box.tab_size)
		caret_width := guilib.measureText(prefix, box.text_size * 0.85, "")
		if box.stored_typeface != nil {
			caret_width = guilib.measureTextTypeface(
				box.stored_typeface,
				prefix,
				box.text_size * 0.85,
			)
		}
		delete(prefix)
		x := left + 47 + caret_width
		guilib.drawLine(surface, x, top + 7, x, top + 26, 1.5, box.caret_color3, 0)
	}
	guilib.restore(surface)
}

text_box_render_code_editor :: proc(
	box: ^TextBox,
	rect: guilib.Rect,
	ctx: ^Class_Step_Context,
	dt: f32,
) {
	surface := ctx.renderer.SkiaSurface
	padding := box.editor_padding
	line_height := text_box_line_height(box)
	gutter := text_box_gutter_width(box)
	minimap_width := text_box_editor_minimap_width(box, rect.width)
	scrollbar_width: f32 = 0
	if box.show_scrollbar {scrollbar_width = box.scrollbar_width}
	editor_right := rect.x + rect.width - minimap_width - scrollbar_width
	content_x := rect.x + padding + gutter
	content_width := text_box_editor_content_width(box, rect.width)
	content_height := max(rect.height - padding * 2, f32(0))
	lines := text_box_visual_lines(box, content_width)
	if len(lines) == 0 {return}

	highlight: ^SyntaxHighlighter
	if box.code_editor &&
	   (box.syntax_highlight_max_bytes == 0 || len(box.text) <= box.syntax_highlight_max_bytes) {
		highlight = syntax_highlighter_for_box(box)
	}
	if highlight != nil &&
	   (box.highlight_ref != highlight ||
			   box.highlight_revision != box.text_revision ||
			   text_box_highlighter_last_box != box) {
		syntax_highlighter_ensure(highlight, box.text)
		box.highlight_ref = highlight
		box.highlight_revision = box.text_revision
		text_box_highlighter_last_box = box
	}

	caret_line := text_box_visual_index_at(lines[:], box.cursor_byte)
	caret_x_local := text_box_measure_range(box, lines[caret_line].start, box.cursor_byte)
	total_height := f32(len(lines)) * line_height
	max_scroll_y := max(total_height - content_height, f32(0))
	if box.focused {
		box.caret_timer += dt
		for box.caret_timer >= 1.2 {box.caret_timer -= 1.2}
	}
	if box.focused && box.caret_needs_scroll {
		top := f32(caret_line) * line_height
		bottom := top + line_height
		if top < box.scroll_target_y {
			box.scroll_target_y = top
		} else if bottom > box.scroll_target_y + content_height {
			box.scroll_target_y = bottom - content_height
		}
		if !box.wrap {
			visible_x := caret_x_local - box.scroll_target_x
			if visible_x < 0 {box.scroll_target_x = caret_x_local}
			if visible_x > content_width {box.scroll_target_x = caret_x_local - content_width}
		}
		box.caret_needs_scroll = false
	}
	box.scroll_target_y = clamp(box.scroll_target_y, f32(0), max_scroll_y)
	if box.wrap {box.scroll_target_x = 0}
	box.scroll_target_x = max(box.scroll_target_x, f32(0))
	scroll_lerp: f32 = 1
	if box.smooth_scrolling {scroll_lerp = min(dt * 20, f32(1))}
	box.scroll_x += (box.scroll_target_x - box.scroll_x) * scroll_lerp
	box.scroll_y += (box.scroll_target_y - box.scroll_y) * scroll_lerp
	box.caret_screen_position = datatypes.Vector2 {
		content_x + caret_x_local - box.scroll_x,
		rect.y + padding + f32(caret_line) * line_height - box.scroll_y,
	}
	ctx.gui_dynamic =
		ctx.gui_dynamic ||
		abs(box.scroll_x - box.scroll_target_x) > 0.05 ||
		abs(box.scroll_y - box.scroll_target_y) > 0.05

	guilib.save(surface)
	defer guilib.restore(surface)
	guilib.clipRect(surface, rect)

	if gutter > 0 {
		guilib.drawRect(
			surface,
			guilib.Rect {
				x = rect.x,
				y = rect.y,
				width = gutter + padding,
				height = rect.height,
				color = box.gutter_color3,
				bgTransparency = 0,
			},
		)
		if box.show_gutter_separator {
			guilib.drawLine(
				surface,
				rect.x + gutter + padding - 1,
				rect.y,
				rect.x + gutter + padding - 1,
				rect.y + rect.height,
				1,
				box.line_number_color3,
				0.80,
			)
		}
	}
	if box.code_editor && box.highlight_current_line && box.focused {
		current_y := rect.y + padding + f32(caret_line) * line_height - box.scroll_y
		guilib.drawRect(
			surface,
			guilib.Rect {
				x = rect.x,
				y = current_y,
				width = max(editor_right - rect.x, f32(0)),
				height = line_height,
				color = box.current_line_color3,
				bgTransparency = 0.90,
			},
		)
	}

	selection_start, selection_finish, selected := text_box_selection_bounds(box)
	selected_word: string
	if box.code_editor &&
	   selected &&
	   box.focused &&
	   !text_box_is_word_at(box.text, selection_start - 1) &&
	   !text_box_is_word_at(box.text, selection_finish) {
		word := box.text[selection_start:selection_finish]
		if len(word) <= 128 {
			selected_word = word
			for i in 0 ..< len(word) {
				if !text_box_is_word_byte(word[i]) {selected_word = ""; break}
			}
		}
	}
	bracket_first, bracket_second := -1, -1
	if box.code_editor && box.focused && box.bracket_matching {
		bracket_first, bracket_second, _ = text_box_bracket_highlight(box)
	}

	current_line_number := text_box_cached_line_number(box, box.cursor_byte)
	first_visible := clamp(int(max(box.scroll_y / line_height, f32(0))), 0, len(lines) - 1)
	last_visible := clamp(
		int((box.scroll_y + rect.height) / line_height) + 2,
		first_visible,
		len(lines),
	)
	real_number := text_box_cached_line_number(box, lines[first_visible].start)
	active_indent := 0
	if box.code_editor && box.highlight_active_indent_guide {
		line_start := text_box_line_start(box.text, box.cursor_byte)
		for i := line_start;
		    i < len(box.text) && (box.text[i] == ' ' || box.text[i] == '\t');
		    i += 1 {
			if box.text[i] == '\t' {
				active_indent += max(box.tab_size, 1) - active_indent % max(box.tab_size, 1)
			} else {active_indent += 1}
		}
		active_indent = active_indent / max(box.tab_size, 1) * max(box.tab_size, 1)
	}
	// Only draw the viewport's lines, and clip text independently of the gutter.
	for index := first_visible; index < last_visible; index += 1 {
		line := lines[index]
		y := rect.y + padding + f32(index) * line_height - box.scroll_y
		baseline := y + (line_height - box.text_size) * 0.5 + box.text_size
		starts_text_line := line.start == 0 || (line.start > 0 && box.text[line.start - 1] == '\n')
		if starts_text_line {
			if index != first_visible {real_number += 1}
			if gutter > 0 {
				shown := real_number
				if box.relative_line_numbers && shown != current_line_number {
					shown = abs(shown - current_line_number)
				}
				number_buffer: [32]u8
				number := strconv.write_int(number_buffer[:], i64(shown), 10)
				number_text := strings.clone_to_cstring(number)
				text_size := box.text_size * 0.8
				number_width := guilib.measureText(number_text, text_size, "")
				if box.stored_typeface != nil {
					number_width = guilib.measureTextTypeface(
						box.stored_typeface,
						number_text,
						text_size,
					)
				}
				number_color := box.line_number_color3
				number_transparency: f32 = 0.16
				if real_number == current_line_number && box.focused {
					number_color = box.text_color3
					number_transparency = 0
				}
				guilib.drawText(
					surface,
					number_text,
					guilib.TextParams {
						x = rect.x + padding + gutter - number_width - 12,
						y = baseline,
						TextSize = text_size,
						color = number_color,
						transparency = number_transparency,
						typeface = box.stored_typeface,
					},
				)
				delete(number_text)
			}
		}
		guilib.save(surface)
		guilib.clipRect(
			surface,
			guilib.Rect {
				x = content_x,
				y = y,
				width = max(editor_right - content_x, f32(0)),
				height = line_height + 3,
			},
		)
		if box.code_editor {
			text_box_draw_editor_guide(
				box,
				surface,
				line,
				y,
				content_x,
				line_height,
				active_indent,
			)
			text_box_draw_editor_find(box, surface, line, content_x - box.scroll_x, y, line_height)
		}
		if box.code_editor && box.focused && box.bracket_matching {
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
		}
		if selected {
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
			text_box_draw_segment(
				box,
				surface,
				content_x,
				baseline,
				line.start,
				line.start,
				line.finish,
				box.text_color3,
			)
		}
		if box.code_editor {text_box_draw_editor_whitespace(box, surface, line, content_x, y, line_height)}
		if box.code_editor && len(box.diagnostics) > 0 {
			for diagnostic in box.diagnostics {
				start, finish := text_box_diagnostic_span(box, diagnostic)
				if start > line.finish || finish < line.start {continue}
				if line.start == line.finish && start != line.start {continue}
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
		guilib.restore(surface)
	}
	if box.focused && box.caret_timer < 0.6 && !box.find_input_active {
		caret_y := rect.y + padding + f32(caret_line) * line_height - box.scroll_y
		caret_x := content_x + caret_x_local - box.scroll_x
		guilib.save(surface)
		guilib.clipRect(
			surface,
			guilib.Rect {
				x = content_x,
				y = rect.y,
				width = max(editor_right - content_x, f32(0)),
				height = rect.height,
			},
		)
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
		guilib.restore(surface)
	}
	if len(box.text) == 0 && len(box.placeholder_text) > 0 {
		placeholder := strings.clone_to_cstring(box.placeholder_text)
		guilib.drawText(
			surface,
			placeholder,
			guilib.TextParams {
				x = content_x,
				y = rect.y + padding + line_height * 0.80,
				TextSize = box.text_size,
				color = box.placeholder_color3,
				typeface = box.stored_typeface,
			},
		)
		delete(placeholder)
	}
	if minimap_width > 0 {
		map_x := rect.x + rect.width - minimap_width
		guilib.drawRect(
			surface,
			guilib.Rect {
				x = map_x,
				y = rect.y,
				width = minimap_width,
				height = rect.height,
				color = box.minimap_color3,
				bgTransparency = 0,
			},
		)
		text_box_line_index_ensure(box)
		physical_lines := len(box.line_starts)
		// Sample directly from the line index: no O(document size) scan per frame.
		row_step := max(int(f32(physical_lines) / max(rect.height * 0.7, f32(1))), 1)
		for map_line := 0; map_line < physical_lines; map_line += row_step {
			position := box.line_starts[map_line]
			finish := len(box.text)
			if map_line + 1 < physical_lines {finish = box.line_starts[map_line + 1] - 1}
			y := rect.y + (f32(map_line) / f32(max(physical_lines, 1))) * rect.height
			width := clamp(f32(finish - position) * 0.48, f32(2), max(minimap_width - 8, f32(2)))
			guilib.drawRect(
				surface,
				guilib.Rect {
					x = map_x + 4,
					y = y,
					width = width,
					height = 1,
					color = box.text_color3,
					bgTransparency = 0.70,
				},
			)
		}
		viewport_height := min(
			rect.height,
			rect.height * content_height / max(total_height, f32(1)),
		)
		viewport_top := rect.y
		if max_scroll_y > 0 {
			viewport_top +=
				(rect.height - viewport_height) *
				clamp(box.scroll_y / max_scroll_y, f32(0), f32(1))
		}
		guilib.drawRect(
			surface,
			guilib.Rect {
				x = map_x,
				y = viewport_top,
				width = minimap_width,
				height = viewport_height,
				color = box.line_number_color3,
				bgTransparency = 0.88,
			},
		)
	}
	if box.show_scrollbar && box.scrollbar_width > 0 && max_scroll_y > 0 {
		thumb_y, thumb_height, _ := text_box_editor_scrollbar_thumb(box)
		guilib.drawRoundedRect(
			surface,
			guilib.Rect {
				x = editor_right,
				y = thumb_y,
				width = box.scrollbar_width,
				height = thumb_height,
				color = box.scrollbar_color3,
				bgTransparency = 0.39,
			},
			min(box.scrollbar_width * 0.5, f32(4)),
		)
	}
	if box.code_editor {text_box_render_find_panel(box, surface, rect)}
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
	width := max(right - left, f32(0))
	if newline_selected {width += 5}
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

	color := box.bracket_match_color3

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

text_box_draw_segment :: proc(
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

	value := text_box_display_cstring(
		box.text[line_start:segment_finish],
		box.tab_size,
		segment_start - line_start,
	)
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

	lo := 0
	hi := len(spans)
	for lo < hi {
		mid := lo + (hi - lo) / 2
		if spans[mid].finish <= line_start {lo = mid + 1} else {hi = mid}
	}

	for index := lo; index < len(spans); index += 1 {
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
			text_box_draw_segment(
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

		text_box_draw_segment(
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
		text_box_draw_segment(
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
		box.cursor_byte = i
		if box.text[i] != '\n' {
			box.cursor_byte = text_box_utf8_next_boundary(box.text, i)
		}
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


text_box_set_text :: proc(box: ^TextBox, value: string, L: ^vm.State = nil) {
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

	text_box_buffer_set(box, source)

	undo_stack_clear(&box.undo_stack)
	undo_stack_clear(&box.redo_stack)

	box.cursor_byte = clamp(box.cursor_byte, 0, len(box.text))

	box.selection_anchor = box.cursor_byte

	text_box_restart_caret(box)

	text_box_fire_text_changed(box, L)
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

	text_box_buffer_replace(box, clamped_start, clamped_finish, "")
	text_box_undo_trim(box)

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

	text_box_buffer_replace(box, box.cursor_byte, box.cursor_byte, insert_value)
	text_box_undo_trim(box)

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

	line_start := text_box_cached_line_start(box, diagnostic.line - 1)

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

		y0 := y + AMPLITUDE
		y1 := y - AMPLITUDE
		if up {
			y0 = y - AMPLITUDE
			y1 = y + AMPLITUDE
		}

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

	padding := box.editor_padding

	content := max(width - padding * 2 - text_box_gutter_width(box), f32(0))
	content = max(content - text_box_editor_minimap_width(box, width), f32(0))
	if box.show_scrollbar {
		content = max(content - box.scrollbar_width, f32(0))
	}

	return content
}

text_box_visual_lines :: proc(box: ^TextBox, content_width: f32) -> []Visual_Line {
	if box == nil {return nil}
	if !box.visual_dirty &&
	   abs(box.visual_cached_width - content_width) < f32(0.5) &&
	   box.visual_cached_wrap == box.wrap &&
	   box.visual_cached_text_size == box.text_size &&
	   box.visual_cached_tab_size == box.tab_size &&
	   box.visual_cached_typeface == box.stored_typeface {
		return box.visual_lines[:]
	}
	text_box_line_index_ensure(box)
	clear(&box.visual_lines)
	text := box.text
	for line_index in 0 ..< len(box.line_starts) {
		start := box.line_starts[line_index]
		finish := len(text)
		if line_index + 1 < len(box.line_starts) {
			finish = box.line_starts[line_index + 1] - 1
		}
		if !box.wrap ||
		   content_width <= 0 ||
		   start == finish ||
		   text_box_measure_range(box, start, finish) <= content_width {
			append(&box.visual_lines, Visual_Line{start, finish})
			continue
		}
		chunk := start
		for chunk < finish {
			low, high := chunk + 1, finish
			best := text_box_utf8_next_boundary(text, chunk)
			for low <= high {
				mid := low + (high - low) / 2
				candidate := min(mid, finish)
				for candidate < finish && (text[candidate] & 0xC0) == 0x80 {
					candidate += 1
				}
				if candidate <= chunk {candidate = text_box_utf8_next_boundary(text, chunk)}
				if text_box_measure_range(box, chunk, candidate) <= content_width {
					best = candidate
					low = candidate + 1
				} else {
					high = mid - 1
				}
			}
			append(&box.visual_lines, Visual_Line{chunk, best})
			chunk = best
		}
	}
	if len(box.visual_lines) == 0 {append(&box.visual_lines, Visual_Line{0, 0})}
	box.visual_cached_width = content_width
	box.visual_cached_wrap = box.wrap
	box.visual_cached_text_size = box.text_size
	box.visual_cached_tab_size = box.tab_size
	box.visual_cached_typeface = box.stored_typeface
	box.visual_dirty = false
	return box.visual_lines[:]
}
text_box_visual_line_count :: proc(box: ^TextBox, content_width: f32) -> int {
	return len(text_box_visual_lines(box, content_width))
}
text_box_visual_index_at :: proc(lines: []Visual_Line, offset: int) -> int {
	if len(lines) == 0 {return 0}
	low, high := 0, len(lines)
	for low < high {
		mid := low + (high - low) / 2
		if lines[mid].finish < offset {low = mid + 1} else {high = mid}
	}
	return clamp(low, 0, len(lines) - 1)
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

		if !box.tab_spaces {
			text_box_insert(box, "\t")
			return
		}

		line_start := text_box_line_start(box.text, box.cursor_byte)

		tab_size := max(box.tab_size, 1)
		prefix := text_box_display_cstring(box.text[line_start:box.cursor_byte], tab_size)
		column := text_box_utf8_count(string(prefix))
		delete(prefix)

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
			if !box.tab_spaces {
				_ = strings.write_byte(&builder, '\t')
			} else {
				for _ in 0 ..< max(box.tab_size, 1) {
					_ = strings.write_byte(&builder, ' ')
				}
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
		highlighter := syntax_highlighter_for_box(box)
		luau := highlighter == nil || highlighter.language == .Luau

		increase_indent =
			(last == '{' ||
				last == '[' ||
				last == '(' ||
				(luau && (strings.has_suffix(before, "then") || strings.has_suffix(before, "do"))))
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	_ = strings.write_byte(&builder, '\n')

	_ = strings.write_string(&builder, indentation)

	if increase_indent {
		if box.tab_spaces {
			for _ in 0 ..< max(box.tab_size, 1) {
				_ = strings.write_byte(&builder, ' ')
			}
		} else {
			_ = strings.write_byte(&builder, '\t')
		}
	}

	if box.auto_indent_brackets && increase_indent && box.cursor_byte < len(box.text) {
		closer := box.text[box.cursor_byte]
		last := before[len(before) - 1]
		if (last == '{' && closer == '}') ||
		   (last == '[' && closer == ']') ||
		   (last == '(' && closer == ')') {
			_ = strings.write_byte(&builder, '\n')
			_ = strings.write_string(&builder, indentation)
			text_box_insert(box, strings.to_string(builder))
			box.cursor_byte -= len(indentation) + 1
			box.selection_anchor = box.cursor_byte
			text_box_restart_caret(box)
			return
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


text_box_fire_focused :: proc(box: ^TextBox) {
	if box.focus_gained != nil &&
	   box.signal_registry != nil &&
	   box.signal_registry.signal_registry != nil {
		signals.Fire(box.signal_registry.signal_registry.L, box.focus_gained, 0)
	}
}

TextBox_focus :: proc(box: ^TextBox, notify := true) {
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
	if notify {text_box_fire_focused(box)}
}


TextBox_blur :: proc(box: ^TextBox, enter_pressed: bool = false) {
	if box == nil {
		return
	}

	was_focused := box.focused
	box.focused = false
	gui_invalidate_draw(&box.object)
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
	if box == nil {return 0}
	position := clamp(byte_index, 0, len(box.text))
	if position == 0 {return 0}
	if position == len(box.text) && box.single_full_width_valid {
		return box.single_full_width
	}
	width: f32
	if !box.code_editor &&
	   box.single_prefix_valid &&
	   abs(position - box.single_prefix_byte) <= 4096 {
		if position >= box.single_prefix_byte {
			width =
				box.single_prefix_width +
				text_box_measure_range(box, box.single_prefix_byte, position)
		} else {
			width =
				box.single_prefix_width -
				text_box_measure_range(box, position, box.single_prefix_byte)
		}
		width = max(width, f32(0))
	} else {
		width = text_box_measure_range(box, 0, position)
	}
	if !box.code_editor {
		box.single_prefix_byte = position
		box.single_prefix_width = width
		box.single_prefix_valid = true
		if position == len(box.text) {
			box.single_full_width = width
			box.single_full_width_valid = true
		}
	}
	return width
}

text_box_horizontal_offset :: proc(box: ^TextBox, width, text_width: f32) -> f32 {
	spare := max(width - text_width, 0)
	switch box.text_x_alignment {
	case .Left:
		return 0
	case .Center:
		return spare * 0.5
	case .Right:
		return spare
	}
	return 0
}

text_box_cursor_from_x :: proc(box: ^TextBox, mouse_x: f32) -> int {
	if box == nil || len(box.text) == 0 {return 0}
	padding: f32 = 6
	offset: f32
	if box.text_x_alignment != .Left {
		offset = text_box_horizontal_offset(
			box,
			box.absolute_size.X - 2 * padding,
			text_box_measure_prefix(box, len(box.text)),
		)
	}
	target := max(mouse_x - box.absolute_position.X - padding - offset + box.scroll_x, f32(0))
	if target <= 0 {return 0}
	if target >= text_box_measure_prefix(box, len(box.text)) {return len(box.text)}

	lo, hi := 0, len(box.text)
	for text_box_utf8_next_boundary(box.text, lo) < hi {
		middle := lo + (hi - lo) / 2
		for middle > lo && (box.text[middle] & 0xC0) == 0x80 {middle -= 1}
		if middle <= lo {middle = text_box_utf8_next_boundary(box.text, lo)}
		if text_box_measure_prefix(box, middle) < target {lo = middle} else {hi = middle}
	}
	left := text_box_measure_prefix(box, lo)
	right := text_box_measure_prefix(box, hi)
	if target < (left + right) * 0.5 {return lo}
	return hi
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
	if text_box_highlighter_last_box == box {text_box_highlighter_last_box = nil}

	if text_box_focused == box {
		TextBox_blur(box)
	}

	if len(box.text_buffer) > 0 {delete(box.text_buffer)}
	delete(box.line_starts)
	delete(box.line_widths)
	delete(box.visual_lines)

	if len(box.placeholder_text) > 0 {
		delete(box.placeholder_text)
	}
	if len(box.find_query) > 0 {
		delete(box.find_query)
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
	if box.focus_gained != nil {signals.Destroy(box.focus_gained)}
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
	case "Focused":
		if box.signal_registry == nil || box.signal_registry.signal_registry == nil {return false}
		if box.focus_gained ==
		   nil {box.focus_gained = signals.Create(box.signal_registry.signal_registry)}
		signals.Push(L, box.focus_gained)
		return true
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

	case "TextXAlignment":
		return enums.Push_Item_By_Value(
			L,
			enum_registry,
			"TextXAlignment",
			i64(box.text_x_alignment),
		)
	case "TextYAlignment":
		return enums.Push_Item_By_Value(
			L,
			enum_registry,
			"TextYAlignment",
			i64(box.text_y_alignment),
		)
	case "Text":
		vm.PushString(L, box.text)
		return true
	case "TextBufferCapacity":
		vm.PushNumber(L, f64(len(box.text_buffer)))
		return true
	case "TextByteLength":
		vm.PushNumber(L, f64(len(box.text)))
		return true
	case "SyntaxHighlightMaxBytes":
		vm.PushNumber(L, f64(box.syntax_highlight_max_bytes))
		return true
	case "MaxUndoEntries":
		vm.PushNumber(L, f64(box.max_undo_entries))
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

	case "ShowIndentGuides":
		vm.PushBoolean(L, box.show_indent_guides)
		return true
	case "HighlightActiveIndentGuide":
		vm.PushBoolean(L, box.highlight_active_indent_guide)
		return true
	case "ShowWhitespace":
		vm.PushBoolean(L, box.show_whitespace)
		return true
	case "ShowScrollbar":
		vm.PushBoolean(L, box.show_scrollbar)
		return true
	case "ShowGutterSeparator":
		vm.PushBoolean(L, box.show_gutter_separator)
		return true
	case "SmoothScrolling":
		vm.PushBoolean(L, box.smooth_scrolling)
		return true
	case "SmartHome":
		vm.PushBoolean(L, box.smart_home)
		return true
	case "SmartBackspace":
		vm.PushBoolean(L, box.smart_backspace)
		return true
	case "AutoIndentBrackets":
		vm.PushBoolean(L, box.auto_indent_brackets)
		return true
	case "FindVisible":
		vm.PushBoolean(L, box.find_visible)
		return true
	case "FindQuery":
		vm.PushString(L, box.find_query)
		return true
	case "FindCaseSensitive":
		vm.PushBoolean(L, box.find_case_sensitive)
		return true
	case "ShowFindHighlights":
		vm.PushBoolean(L, box.show_find_highlights)
		return true
	case "EditorPadding":
		vm.PushNumber(L, f64(box.editor_padding))
		return true
	case "EditorLineHeight":
		vm.PushNumber(L, f64(box.editor_line_height))
		return true
	case "MinimapWidth":
		vm.PushNumber(L, f64(box.minimap_width))
		return true
	case "ScrollbarWidth":
		vm.PushNumber(L, f64(box.scrollbar_width))
		return true
	case "MouseWheelScrollLines":
		vm.PushNumber(L, f64(box.mouse_wheel_scroll_lines))
		return true
	case "ScrollX":
		vm.PushNumber(L, f64(box.scroll_target_x))
		return true
	case "ScrollY":
		vm.PushNumber(L, f64(box.scroll_target_y))
		return true
	case "FindMatchColor3":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, box.find_match_color3)
		return true
	case "LineNumberColor3":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, box.line_number_color3)
		return true
	case "CurrentLineColor3":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, box.current_line_color3)
		return true
	case "IndentGuideColor3":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, box.indent_guide_color3)
		return true
	case "BracketMatchColor3":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, box.bracket_match_color3)
		return true
	case "GutterColor3":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, box.gutter_color3)
		return true
	case "MinimapColor3":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, box.minimap_color3)
		return true
	case "ScrollbarColor3":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, box.scrollbar_color3)
		return true
	case "CodeEditor":
		vm.PushBoolean(L, box.code_editor)
		return true

	case "RelativeLineNumbers":
		vm.PushBoolean(L, box.relative_line_numbers)
		return true

	case "HighlightCurrentLine":
		vm.PushBoolean(L, box.highlight_current_line)
		return true

	case "BracketMatching":
		vm.PushBoolean(L, box.bracket_matching)
		return true

	case "TabSpaces":
		vm.PushBoolean(L, box.tab_spaces)
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

	case "MultiLine":
		vm.PushBoolean(L, box.multi_line)
		return true

	case "WordWrap", "TextWrapped":
		vm.PushBoolean(L, box.wrap)
		return true

	case "LineCount":
		vm.PushNumber(L, f64(text_box_cached_line_count(box)))
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

	case "FindNext",
	     "FindPrevious",
	     "OpenFind",
	     "CloseFind",
	     "GoToLine",
	     "PositionAtPoint",
	     "CaptureFocus",
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

	// Let inherited setters detect unchanged position and size before
	// invalidating layout. Text metrics have their own invalidation below.
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

	case "TextXAlignment":
		box.text_x_alignment = enums.TextXAlignment(
			enums.Arg_Item(L, value_index, enum_registry, "TextXAlignment").value,
		)
		Gui_Render_Mark_Dirty()
		return true
	case "TextYAlignment":
		box.text_y_alignment = enums.TextYAlignment(
			enums.Arg_Item(L, value_index, enum_registry, "TextYAlignment").value,
		)
		Gui_Render_Mark_Dirty()
		return true
	case "TextBufferCapacity":
		reserve := clamp(int(vm.ArgNumber(L, value_index)), 0, 256 * 1024 * 1024)
		text_box_buffer_reserve(box, reserve)
		return true
	case "SyntaxHighlightMaxBytes":
		box.syntax_highlight_max_bytes = clamp(
			int(vm.ArgNumber(L, value_index)),
			0,
			128 * 1024 * 1024,
		)
		Gui_Render_Mark_Dirty()
		return true
	case "MaxUndoEntries":
		box.max_undo_entries = clamp(int(vm.ArgNumber(L, value_index)), 0, 100000)
		text_box_undo_trim(box)
		return true
	case "Text":
		text_box_set_text(box, vm.ArgString(L, value_index), L)

		return true

	case "ShowIndentGuides":
		box.show_indent_guides = vm.ArgBoolean(L, value_index)
		Gui_Render_Mark_Dirty()
		return true
	case "HighlightActiveIndentGuide":
		box.highlight_active_indent_guide = vm.ArgBoolean(L, value_index)
		Gui_Render_Mark_Dirty()
		return true
	case "ShowWhitespace":
		box.show_whitespace = vm.ArgBoolean(L, value_index)
		Gui_Render_Mark_Dirty()
		return true
	case "ShowScrollbar":
		box.show_scrollbar = vm.ArgBoolean(L, value_index)
		Gui_Layout_Mark_Dirty()
		return true
	case "ShowGutterSeparator":
		box.show_gutter_separator = vm.ArgBoolean(L, value_index)
		Gui_Render_Mark_Dirty()
		return true
	case "SmoothScrolling":
		box.smooth_scrolling = vm.ArgBoolean(L, value_index)
		Gui_Render_Mark_Dirty()
		return true
	case "SmartHome":
		box.smart_home = vm.ArgBoolean(L, value_index)
		return true
	case "SmartBackspace":
		box.smart_backspace = vm.ArgBoolean(L, value_index)
		return true
	case "AutoIndentBrackets":
		box.auto_indent_brackets = vm.ArgBoolean(L, value_index)
		return true
	case "FindVisible":
		if vm.ArgBoolean(L, value_index) {
			box.find_visible = true
			box.find_input_active = false
			Gui_Render_Mark_Dirty()
		} else {
			text_box_close_find(box)
		}
		return true
	case "FindQuery":
		text_box_replace_string(&box.find_query, vm.ArgString(L, value_index))
		box.find_cursor_byte = len(box.find_query)
		Gui_Render_Mark_Dirty()
		return true
	case "FindCaseSensitive":
		box.find_case_sensitive = vm.ArgBoolean(L, value_index)
		Gui_Render_Mark_Dirty()
		return true
	case "ShowFindHighlights":
		box.show_find_highlights = vm.ArgBoolean(L, value_index)
		Gui_Render_Mark_Dirty()
		return true
	case "EditorPadding":
		box.editor_padding = clamp(f32(vm.ArgNumber(L, value_index)), f32(0), f32(48))
		Gui_Layout_Mark_Dirty()
		box.caret_needs_scroll = true
		return true
	case "EditorLineHeight":
		box.editor_line_height = clamp(f32(vm.ArgNumber(L, value_index)), f32(0), f32(128))
		box.content_measure_valid = false
		Gui_Layout_Mark_Dirty()
		box.caret_needs_scroll = true
		return true
	case "MinimapWidth":
		box.minimap_width = clamp(f32(vm.ArgNumber(L, value_index)), f32(24), f32(200))
		Gui_Layout_Mark_Dirty()
		return true
	case "ScrollbarWidth":
		box.scrollbar_width = clamp(f32(vm.ArgNumber(L, value_index)), f32(2), f32(24))
		Gui_Layout_Mark_Dirty()
		return true
	case "MouseWheelScrollLines":
		box.mouse_wheel_scroll_lines = clamp(f32(vm.ArgNumber(L, value_index)), f32(0.1), f32(30))
		return true
	case "ScrollX":
		box.scroll_target_x = max(f32(vm.ArgNumber(L, value_index)), f32(0))
		Gui_Render_Mark_Dirty()
		return true
	case "ScrollY":
		box.scroll_target_y = clamp(
			f32(vm.ArgNumber(L, value_index)),
			f32(0),
			text_box_editor_max_scroll_y(box),
		)
		Gui_Render_Mark_Dirty()
		return true
	case "FindMatchColor3":
		if datatype_registry == nil {return false}
		box.find_match_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		Gui_Render_Mark_Dirty()
		return true
	case "LineNumberColor3":
		if datatype_registry == nil {return false}
		box.line_number_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		Gui_Render_Mark_Dirty()
		return true
	case "CurrentLineColor3":
		if datatype_registry == nil {return false}
		box.current_line_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		Gui_Render_Mark_Dirty()
		return true
	case "IndentGuideColor3":
		if datatype_registry == nil {return false}
		box.indent_guide_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		Gui_Render_Mark_Dirty()
		return true
	case "BracketMatchColor3":
		if datatype_registry == nil {return false}
		box.bracket_match_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		Gui_Render_Mark_Dirty()
		return true
	case "GutterColor3":
		if datatype_registry == nil {return false}
		box.gutter_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		Gui_Render_Mark_Dirty()
		return true
	case "MinimapColor3":
		if datatype_registry == nil {return false}
		box.minimap_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		Gui_Render_Mark_Dirty()
		return true
	case "ScrollbarColor3":
		if datatype_registry == nil {return false}
		box.scrollbar_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		Gui_Render_Mark_Dirty()
		return true
	case "CodeEditor":
		box.code_editor = vm.ArgBoolean(L, value_index)
		Gui_Layout_Mark_Dirty()

		box.scroll_x = 0
		box.scroll_target_x = 0
		box.scroll_y = 0
		box.scroll_target_y = 0
		box.caret_needs_scroll = true

		return true

	case "RelativeLineNumbers":
		box.relative_line_numbers = vm.ArgBoolean(L, value_index)
		Gui_Render_Mark_Dirty()
		return true

	case "HighlightCurrentLine":
		box.highlight_current_line = vm.ArgBoolean(L, value_index)
		Gui_Render_Mark_Dirty()
		return true

	case "BracketMatching":
		box.bracket_matching = vm.ArgBoolean(L, value_index)
		Gui_Render_Mark_Dirty()
		return true

	case "TabSpaces":
		box.tab_spaces = vm.ArgBoolean(L, value_index)
		Gui_Render_Mark_Dirty()
		return true

	case "ShowLineNumbers":
		box.show_line_numbers = vm.ArgBoolean(L, value_index)
		Gui_Render_Mark_Dirty()
		return true

	case "ShowMinimap":
		box.show_minimap = vm.ArgBoolean(L, value_index)
		Gui_Render_Mark_Dirty()
		return true

	case "TabSize":
		box.tab_size = clamp(int(vm.ArgNumber(L, value_index)), 1, 16)
		box.visual_dirty = true
		box.content_measure_valid = false
		box.single_full_width_valid = false
		box.single_prefix_valid = false
		box.single_draw_valid = false
		box.line_widths_valid = false
		text_box_restart_caret(box)
		Gui_Layout_Mark_Dirty()
		return true

	case "AutoIndent":
		box.auto_indent = vm.ArgBoolean(L, value_index)
		return true

	case "AutoClose":
		box.auto_close = vm.ArgBoolean(L, value_index)
		return true

	case "MultiLine":
		value := vm.ArgBoolean(L, value_index)
		if box.multi_line != value {
			box.multi_line = value
			box.visual_dirty = true
			box.content_measure_valid = false
			box.scroll_x, box.scroll_y = 0, 0
			box.scroll_target_x, box.scroll_target_y = 0, 0
			text_box_restart_caret(box)
			Gui_Layout_Mark_Dirty()
		}
		return true

	case "WordWrap", "TextWrapped":
		box.wrap = vm.ArgBoolean(L, value_index)
		Gui_Layout_Mark_Dirty()

		if box.code_editor || box.multi_line {
			box.scroll_x = 0
			box.scroll_target_x = 0
			box.caret_needs_scroll = true
		}

		return true

	case "PlaceholderText":
		text_box_replace_string(&box.placeholder_text, vm.ArgString(L, value_index))
		Gui_Layout_Mark_Dirty()

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

		Gui_Layout_Mark_Dirty()
		return true

	case "FontFace":
		if datatype_registry == nil {
			return false
		}

		TextBox_Set_Font_Face(box, datatypes.Arg_Font(L, value_index, datatype_registry))
		Gui_Layout_Mark_Dirty()

		return true

	case "TextSize":
		size := max(f32(vm.ArgNumber(L, value_index)), f32(1))
		if box.text_size != size {
			box.text_size = size
			box.visual_dirty = true
			box.content_measure_valid = false
			box.single_full_width_valid = false
			box.single_prefix_valid = false
			box.single_draw_valid = false
			box.line_widths_valid = false
			Gui_Layout_Mark_Dirty()
		}

		return true

	case "TextColor3":
		if datatype_registry == nil {
			return false
		}

		box.text_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		Gui_Render_Mark_Dirty()

		return true

	case "PlaceholderColor3":
		if datatype_registry == nil {
			return false
		}

		box.placeholder_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		Gui_Render_Mark_Dirty()

		return true

	case "TextTransparency":
		box.text_transparency = clamp(f32(vm.ArgNumber(L, value_index)), f32(0), f32(1))
		Gui_Render_Mark_Dirty()

		return true

	case "ClearTextOnFocus":
		box.clear_text_on_focus = vm.ArgBoolean(L, value_index)

		return true

	case "TextEditable":
		box.text_editable = vm.ArgBoolean(L, value_index)

		if box.focused {
			window := sdl3.GetKeyboardFocus()

			if window != nil {
				if box.text_editable || box.find_input_active {
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

			text_box_set_text(box, box.text[:end], L)
		}

		return true

	case "CaretColor3":
		if datatype_registry == nil {
			return false
		}

		box.caret_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		Gui_Render_Mark_Dirty()

		return true

	case "SelectionColor3":
		if datatype_registry == nil {
			return false
		}

		box.selection_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		Gui_Render_Mark_Dirty()

		return true

	case "SelectionTransparency":
		box.selection_transparency = clamp(f32(vm.ArgNumber(L, value_index)), f32(0), f32(1))
		Gui_Render_Mark_Dirty()

		return true

	case "FocusColor3":
		if datatype_registry == nil {
			return false
		}

		box.focus_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		Gui_Render_Mark_Dirty()

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

	case "FindNext":
		vm.PushBoolean(L, text_box_find_next(box, false))
		return 1, true
	case "FindPrevious":
		vm.PushBoolean(L, text_box_find_next(box, true))
		return 1, true
	case "OpenFind":
		text_box_open_find(box)
		return 0, true
	case "CloseFind":
		text_box_close_find(box)
		return 0, true
	case "GoToLine":
		// GoToLine(line, column?, selectionLength?, focus?)
		// line/column are 1-based, selectionLength counts UTF-8 characters.
		line := max(int(vm.ArgNumber(L, 2)), 1)
		column := 1
		selection_length := 0
		focus := false
		if vm.StackTop(L) >= 3 {
			if number, ok := vm.ToNumber(L, 3); ok {column = max(int(number), 1)}
		}
		if vm.StackTop(L) >= 4 {
			if number, ok := vm.ToNumber(L, 4); ok {selection_length = max(int(number), 0)}
		}
		if vm.StackTop(L) >= 5 {focus = vm.ArgBoolean(L, 5)}
		if focus && !box.focused {TextBox_focus(box)}
		TextBox_Go_To_Line(box, line, column, selection_length)
		return 0, true
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

	case "PositionAtPoint":
		x := box.absolute_position.X + f32(vm.ArgNumber(L, 2))
		y := box.absolute_position.Y + f32(vm.ArgNumber(L, 3))
		vm.PushNumber(
			L,
			f64(text_box_utf8_index_at(box.text, text_box_cursor_from_point(box, x, y, true)) + 1),
		)
		return 1, true

	case "DiagnosticAtPoint":
		x := f32(vm.ArgNumber(L, 2))
		y := f32(vm.ArgNumber(L, 3))

		line_height := text_box_line_height(box)
		padding := box.editor_padding
		gutter := text_box_gutter_width(box)

		content_width := text_box_editor_content_width(box, box.absolute_size.X)

		lines := text_box_visual_lines(box, content_width)

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

		vm.PushNumber(L, f64(text_box_cached_line_number(box, box.cursor_byte)))
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

	ctx.gui_dynamic = ctx.gui_dynamic || box.focused || box.focus_animation > 0.001
	if box.code_editor || box.multi_line {
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
	ctx.gui_dynamic = ctx.gui_dynamic || abs(box.scroll_target_x - box.scroll_x) > 0.01


	text_x := rect.x + padding
	if box.text_x_alignment != .Left {
		text_width := text_box_measure_text(box, display_text)
		if len(box.text) > 0 {text_width = text_box_measure_prefix(box, len(box.text))}
		text_x += text_box_horizontal_offset(box, available_width, text_width)
	}
	spare_height := max(rect.height - box.text_size, 0)
	baseline := rect.y + box.text_size
	switch box.text_y_alignment {
	case .Top:
		baseline += min(padding, spare_height)
	case .Center:
		baseline += (rect.height - box.text_size) * 0.5
	case .Bottom:
		baseline += max(spare_height - padding, 0)
	}

	guilib.save(surface)
	defer guilib.restore(surface)

	guilib.clipRect(surface, rect)


	selection_start, selection_finish, has_selection := text_box_selection_bounds(box)

	if has_selection && len(box.text) > 0 {
		start_width := text_box_measure_prefix(box, selection_start)

		end_width := text_box_measure_prefix(box, selection_finish)

		selection_x := text_x + start_width - box.scroll_x

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
		draw_start := 0
		draw_end := len(display_text)
		draw_offset: f32 = 0
		if len(box.text) > 8192 && len(display_text) == len(box.text) {
			if box.focused {
				if !box.single_draw_valid ||
				   box.cursor_byte < box.single_draw_start + 1024 ||
				   box.cursor_byte > box.single_draw_start + 6144 {
					begin := max(box.cursor_byte - 4096, 0)
					for begin > 0 && begin < len(box.text) && (box.text[begin] & 0xC0) == 0x80 {
						begin -= 1
					}

					box.single_draw_start = begin
					box.single_draw_x = text_box_measure_prefix(box, begin)
					box.single_draw_valid = true
				}
				draw_start = box.single_draw_start
				draw_offset = box.single_draw_x
			}
			draw_end = min(draw_start + 8192, len(box.text))
			for draw_end < len(box.text) && (box.text[draw_end] & 0xC0) == 0x80 {
				draw_end -= 1
			}
		}
		highlight: ^SyntaxHighlighter
		if len(box.text) > 0 &&
		   (box.syntax_highlight_max_bytes == 0 ||
				   len(box.text) <= box.syntax_highlight_max_bytes) {
			highlight = syntax_highlighter_for_box(box)
		}
		if highlight != nil &&
		   (box.highlight_ref != highlight ||
				   box.highlight_revision != box.text_revision ||
				   text_box_highlighter_last_box != box) {
			syntax_highlighter_ensure(highlight, box.text)
			box.highlight_ref = highlight
			box.highlight_revision = box.text_revision
			text_box_highlighter_last_box = box
		}
		if highlight != nil {
			text_box_draw_syntax_line(
				box,
				highlight,
				surface,
				text_x + draw_offset,
				baseline,
				draw_start,
				draw_end,
			)
		} else {
			text := text_box_display_cstring(display_text[draw_start:draw_end], box.tab_size)
			defer delete(text)
			guilib.drawText(
				surface,
				text,
				guilib.TextParams {
					x = text_x + draw_offset - box.scroll_x,
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

		caret_x := text_x + caret_width - box.scroll_x

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

	text_box_buffer_set(dst, src.text)

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
	dst.text_x_alignment = src.text_x_alignment
	dst.text_y_alignment = src.text_y_alignment

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
	dst.code_editor = src.code_editor
	dst.relative_line_numbers = src.relative_line_numbers
	dst.highlight_current_line = src.highlight_current_line
	dst.bracket_matching = src.bracket_matching
	dst.tab_spaces = src.tab_spaces
	dst.show_line_numbers = src.show_line_numbers
	dst.show_minimap = src.show_minimap
	dst.tab_size = src.tab_size
	dst.auto_indent = src.auto_indent
	dst.auto_close = src.auto_close
	dst.wrap = src.wrap
	dst.show_indent_guides = src.show_indent_guides
	dst.highlight_active_indent_guide = src.highlight_active_indent_guide
	dst.show_whitespace = src.show_whitespace
	dst.show_scrollbar = src.show_scrollbar
	dst.show_gutter_separator = src.show_gutter_separator
	dst.smooth_scrolling = src.smooth_scrolling
	dst.smart_home = src.smart_home
	dst.smart_backspace = src.smart_backspace
	dst.auto_indent_brackets = src.auto_indent_brackets
	dst.find_visible = src.find_visible
	dst.find_case_sensitive = src.find_case_sensitive
	dst.show_find_highlights = src.show_find_highlights
	text_box_replace_string(&dst.find_query, src.find_query)
	dst.find_match_color3 = src.find_match_color3
	dst.line_number_color3 = src.line_number_color3
	dst.current_line_color3 = src.current_line_color3
	dst.indent_guide_color3 = src.indent_guide_color3
	dst.bracket_match_color3 = src.bracket_match_color3
	dst.gutter_color3 = src.gutter_color3
	dst.minimap_color3 = src.minimap_color3
	dst.scrollbar_color3 = src.scrollbar_color3
	dst.editor_padding = src.editor_padding
	dst.editor_line_height = src.editor_line_height
	dst.minimap_width = src.minimap_width
	dst.scrollbar_width = src.scrollbar_width
	dst.mouse_wheel_scroll_lines = src.mouse_wheel_scroll_lines
	dst.syntax_highlight_max_bytes = src.syntax_highlight_max_bytes
	dst.max_undo_entries = src.max_undo_entries
	dst.multi_line = src.multi_line

	dst.focused = false

	dst.cursor_byte = len(dst.text)

	dst.selection_anchor = dst.cursor_byte

	dst.drag_selecting = false

	dst.focus_animation = 0

	dst.caret_timer = 0

	dst.scroll_x = 0

	dst.scroll_target_x = 0
	dst.scroll_y = 0
	dst.scroll_target_y = 0
	dst.find_input_active = false
	dst.find_cursor_byte = len(dst.find_query)
	dst.scrollbar_dragging = false
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

		TextBox_focus(clicked, notify = false)
		defer if !was_focused &&
		   clicked.focused &&
		   !clicked.destroyed {text_box_fire_focused(clicked)}

		if !clicked.focused {
			return
		}


		if event.button.clicks >= 2 {
			if clicked.code_editor || clicked.multi_line {
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

		if clicked.code_editor {
			if text_box_editor_find_hit(clicked, point_x, point_y) {
				clicked.find_input_active = true
				clicked.find_cursor_byte = len(clicked.find_query)
				if !clicked.text_editable {
					window := sdl3.GetKeyboardFocus()
					if window != nil {
						_ = sdl3.StartTextInput(window)
						TEXTBOX_IS_USED = true
					}
				}
				gui_invalidate_draw(&clicked.object)
				return
			}
			clicked.find_input_active = false
			map_width := text_box_editor_minimap_width(clicked, clicked.absolute_size.X)
			map_x := clicked.absolute_position.X + clicked.absolute_size.X - map_width
			if map_width > 0 && point_x >= map_x {
				text_box_editor_scroll_from_minimap(clicked, point_y)
				return
			}
			if clicked.show_scrollbar &&
			   text_box_editor_max_scroll_y(clicked) > 0 &&
			   ((map_width > 0 && point_x >= map_x - clicked.scrollbar_width && point_x < map_x) ||
					   (map_width == 0 &&
							   point_x >=
								   clicked.absolute_position.X +
									   clicked.absolute_size.X -
									   clicked.scrollbar_width)) {
				thumb_y, thumb_height, _ := text_box_editor_scrollbar_thumb(clicked)
				clicked.scrollbar_drag_offset = thumb_height * 0.5
				if point_y >= thumb_y && point_y <= thumb_y + thumb_height {
					clicked.scrollbar_drag_offset = point_y - thumb_y
				}
				clicked.scrollbar_dragging = true
				text_box_editor_scrollbar_to_mouse(clicked, point_y)
				return
			}
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

		if box == nil || !box.focused {return}
		if box.scrollbar_dragging {
			text_box_editor_scrollbar_to_mouse(box, f32(event.motion.y))
			return
		}
		if !box.drag_selecting {return}

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
			text_box_focused.scrollbar_dragging = false
		}


	case .MOUSE_WHEEL:
		box := text_box_focused

		if box == nil || !box.focused || (!box.code_editor && !box.multi_line) {
			return
		}

		modifiers := sdl3.GetModState()

		ctrl := .LCTRL in modifiers || .RCTRL in modifiers

		shift := .LSHIFT in modifiers || .RSHIFT in modifiers

		padding := box.editor_padding

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
			box.scroll_target_x = max(
				box.scroll_target_x - delta_x * box.text_size * box.mouse_wheel_scroll_lines,
				f32(0),
			)
		}

		if abs(delta_y) > 0.001 {
			box.scroll_target_y -= delta_y * line_height * box.mouse_wheel_scroll_lines

			max_scroll_y := max(
				f32(text_box_visual_line_count(box, content_width)) * line_height - content_height,
				f32(0),
			)

			box.scroll_target_y = clamp(box.scroll_target_y, f32(0), max_scroll_y)
		}


	case .TEXT_INPUT:
		box := text_box_focused

		if box == nil || !box.focused || event.text.text == nil {return}
		if box.code_editor && box.find_input_active && box.find_visible {
			input := string(event.text.text)
			if len(box.find_query) + len(input) < 512 {
				pos := clamp(box.find_cursor_byte, 0, len(box.find_query))
				next := strings.concatenate({box.find_query[:pos], input, box.find_query[pos:]})
				text_box_replace_string(&box.find_query, next)
				box.find_cursor_byte = pos + len(input)
				delete(next)
				Gui_Render_Mark_Dirty()
			}
			return
		}
		if !box.text_editable {return}
		text_box_handle_text(box, string(event.text.text))


	case .KEY_DOWN:
		box := text_box_focused

		if box == nil || !box.focused {
			return
		}


		box.key_handled = false

		text_box_fire_key_down(box, registry, event.key.scancode)

		if box.key_handled {return}

		modifiers := event.key.mod

		shift := .LSHIFT in modifiers || .RSHIFT in modifiers


		shortcut :=
			.LCTRL in modifiers || .RCTRL in modifiers || .LGUI in modifiers || .RGUI in modifiers


		if box.code_editor && box.find_visible && box.find_input_active {
			if event.key.scancode == .ESCAPE {
				text_box_close_find(box)
				return
			}
			if event.key.scancode == .RETURN || event.key.scancode == .KP_ENTER {
				_ = text_box_find_next(box, shift)
				return
			}
			if event.key.scancode == .BACKSPACE && box.find_cursor_byte > 0 {
				last := text_box_utf8_prev_boundary(box.find_query, box.find_cursor_byte)
				next := strings.concatenate(
					{box.find_query[:last], box.find_query[box.find_cursor_byte:]},
				)
				text_box_replace_string(&box.find_query, next)
				box.find_cursor_byte = last
				delete(next)
				Gui_Render_Mark_Dirty()
				return
			}
			if event.key.scancode == .DELETE && box.find_cursor_byte < len(box.find_query) {
				next_byte := text_box_utf8_next_boundary(box.find_query, box.find_cursor_byte)
				next := strings.concatenate(
					{box.find_query[:box.find_cursor_byte], box.find_query[next_byte:]},
				)
				text_box_replace_string(&box.find_query, next)
				delete(next)
				Gui_Render_Mark_Dirty()
				return
			}
			#partial switch event.key.scancode {
			case .LEFT:
				box.find_cursor_byte = text_box_utf8_prev_boundary(
					box.find_query,
					box.find_cursor_byte,
				)
				Gui_Render_Mark_Dirty()
				return
			case .RIGHT:
				box.find_cursor_byte = text_box_utf8_next_boundary(
					box.find_query,
					box.find_cursor_byte,
				)
				Gui_Render_Mark_Dirty()
				return
			case .HOME:
				box.find_cursor_byte = 0
				Gui_Render_Mark_Dirty()
				return
			case .END:
				box.find_cursor_byte = len(box.find_query)
				Gui_Render_Mark_Dirty()
				return
			case:
			}
			if !shortcut {return}
		}

		if shortcut {
			#partial switch event.key.scancode {
			case .F:
				if box.code_editor {text_box_open_find(box)}
				return

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

		case .PAGEUP:
			if box.code_editor {
				amount := max(int(box.absolute_size.Y / text_box_line_height(box)) - 1, 1)
				text_box_move_vertical(box, -1, shift, amount)
			}

		case .PAGEDOWN:
			if box.code_editor {
				amount := max(int(box.absolute_size.Y / text_box_line_height(box)) - 1, 1)
				text_box_move_vertical(box, 1, shift, amount)
			}

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
				if shortcut && box.code_editor {
					previous = text_box_word_left(box.text, box.cursor_byte)
				} else if box.code_editor && box.smart_backspace && box.tab_spaces {
					line_start := text_box_line_start(box.text, box.cursor_byte)
					whitespace_only := true
					for i := line_start; i < box.cursor_byte; i += 1 {
						if box.text[i] != ' ' {whitespace_only = false; break}
					}
					if whitespace_only && box.cursor_byte - line_start > 0 {
						column := box.cursor_byte - line_start
						amount := (column - 1) % max(box.tab_size, 1) + 1
						previous = box.cursor_byte - amount
					}
				}
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
				if shortcut && box.code_editor {
					next = text_box_word_right(box.text, box.cursor_byte)
				}
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

			if !shortcut && (box.code_editor || box.multi_line) {
				target = text_box_line_start(box.text, old_cursor)
				if box.smart_home {
					end := text_box_line_end(box.text, old_cursor)
					first_nonspace := target
					for first_nonspace < end &&
					    (box.text[first_nonspace] == ' ' || box.text[first_nonspace] == '\t') {
						first_nonspace += 1
					}
					if old_cursor != first_nonspace {target = first_nonspace}
				}
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

			if !shortcut && (box.code_editor || box.multi_line) {
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
			} else if box.multi_line {
				if box.text_editable {text_box_insert(box, "\n")}
			} else {
				TextBox_blur(box, true)
			}


		case .ESCAPE:
			if box.find_visible {
				text_box_close_find(box)
			} else {
				TextBox_blur(box)
			}
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
			"TextBufferCapacity",
			"TextByteLength",
			"MaxUndoEntries",
			"SyntaxHighlightMaxBytes",
			"Font",
			"FontFace",
			"PlaceholderText",
			"TextSize",
			"TextColor3",
			"PlaceholderColor3",
			"TextTransparency",
			"ClearTextOnFocus",
			"TextEditable",
			"TextXAlignment",
			"TextYAlignment",
			"SelectAllOnFocus",
			"MaxLength",
			"CaretColor3",
			"SelectionColor3",
			"SelectionTransparency",
			"FocusColor3",
			"CodeEditor",
			"RelativeLineNumbers",
			"HighlightCurrentLine",
			"BracketMatching",
			"TabSpaces",
			"ShowLineNumbers",
			"ShowMinimap",
			"TabSize",
			"AutoIndent",
			"AutoClose",
			"WordWrap",
			"MultiLine",
			"ShowIndentGuides",
			"HighlightActiveIndentGuide",
			"ShowWhitespace",
			"ShowScrollbar",
			"ShowGutterSeparator",
			"SmoothScrolling",
			"SmartHome",
			"SmartBackspace",
			"AutoIndentBrackets",
			"FindVisible",
			"FindQuery",
			"FindCaseSensitive",
			"ShowFindHighlights",
			"EditorPadding",
			"EditorLineHeight",
			"MinimapWidth",
			"ScrollbarWidth",
			"MouseWheelScrollLines",
			"ScrollX",
			"ScrollY",
			"FindMatchColor3",
			"LineNumberColor3",
			"CurrentLineColor3",
			"IndentGuideColor3",
			"BracketMatchColor3",
			"GutterColor3",
			"MinimapColor3",
			"ScrollbarColor3",
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
			"FindNext",
			"FindPrevious",
			"OpenFind",
			"CloseFind",
			"GoToLine",
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
			"PositionAtPoint",
			"DiagnosticAtPoint",
		},
		events = []string{"Focused", "FocusLost", "TextChanged", "KeyDown"},
	)
}
