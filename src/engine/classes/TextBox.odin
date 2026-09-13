package classes

import "core:strings"

import sdl3 "../platform"

import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"


TextBox_Class := Class_Info{
	name   = "TextBox",
	parent = &GuiObject_Class,
}


TextBox :: struct {
	using gui_object: GuiObject,

	text:                    string,
	placeholder_text:        string,

	text_size:               f32,
	text_color3:             datatypes.Color3,
	placeholder_color3:      datatypes.Color3,
	text_transparency:       f32,

	clear_text_on_focus:     bool,
	text_editable:           bool,
	select_all_on_focus:     bool,

	max_length:              int,

	focused:                 bool,

	cursor_byte:             int,
	selection_anchor:        int,
	drag_selecting:          bool,

	caret_color3:            datatypes.Color3,
	selection_color3:        datatypes.Color3,
	selection_transparency:  f32,
	focus_color3:            datatypes.Color3,

	focus_animation:         f32,
	caret_timer:             f32,

	scroll_x:                f32,
	scroll_target_x:         f32,
}


text_box_focused: ^TextBox


TextBox_Init :: proc() -> TextBox {
	gui := GuiObject_Init()
	gui.object.class = &TextBox_Class

	return TextBox{
		gui_object             = gui,

		text                   = strings.clone(""),
		placeholder_text       = strings.clone(""),

		text_size              = 16,
		text_color3            = datatypes.Color3{0, 0, 0},
		placeholder_color3     = datatypes.Color3{0.5, 0.5, 0.5},
		text_transparency      = 0,

		clear_text_on_focus    = false,
		text_editable          = true,
		select_all_on_focus    = false,

		max_length             = -1,

		focused                = false,

		cursor_byte            = 0,
		selection_anchor       = 0,
		drag_selecting         = false,

		caret_color3           = datatypes.Color3{0.25, 0.5, 1.0},
		selection_color3       = datatypes.Color3{0.25, 0.5, 1.0},
		selection_transparency = 0.65,
		focus_color3           = datatypes.Color3{0.25, 0.5, 1.0},

		focus_animation        = 0,
		caret_timer            = 0,

		scroll_x               = 0,
		scroll_target_x        = 0,
	}
}


text_box_replace_string :: proc(
	target: ^string,
	value: string,
) {
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
}


text_box_utf8_prev_boundary :: proc(
	text: string,
	index: int,
) -> int {
	if index <= 0 {
		return 0
	}

	i := min(index, len(text)) - 1

	for i > 0 &&
	    (text[i] & 0xC0) == 0x80 {
		i -= 1
	}

	return i
}


text_box_utf8_next_boundary :: proc(
	text: string,
	index: int,
) -> int {
	if index >= len(text) {
		return len(text)
	}

	i := index + 1

	for i < len(text) &&
	    (text[i] & 0xC0) == 0x80 {
		i += 1
	}

	return i
}


text_box_utf8_count :: proc(
	text: string,
) -> int {
	count := 0
	index := 0

	for index < len(text) {
		index =
			text_box_utf8_next_boundary(
				text,
				index,
			)

		count += 1
	}

	return count
}


text_box_utf8_prefix_bytes :: proc(
	text: string,
	character_count: int,
) -> int {
	if character_count <= 0 {
		return 0
	}

	index := 0
	count := 0

	for index < len(text) &&
	    count < character_count {
		index =
			text_box_utf8_next_boundary(
				text,
				index,
			)

		count += 1
	}

	return index
}


text_box_selection_bounds :: proc(
	box: ^TextBox,
) -> (
	start: int,
	finish: int,
	selected: bool,
) {
	if box == nil {
		return 0, 0, false
	}

	a := clamp(
		box.selection_anchor,
		0,
		len(box.text),
	)

	b := clamp(
		box.cursor_byte,
		0,
		len(box.text),
	)

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


text_box_clear_selection :: proc(
	box: ^TextBox,
) {
	if box == nil {
		return
	}

	box.selection_anchor =
		box.cursor_byte
}


text_box_select_all :: proc(
	box: ^TextBox,
) {
	if box == nil {
		return
	}

	box.selection_anchor = 0
	box.cursor_byte = len(box.text)

	text_box_restart_caret(box)
}


text_box_set_text :: proc(
	box: ^TextBox,
	value: string,
) {
	if box == nil {
		return
	}

	source := value

	if box.max_length >= 0 {
		end :=
			text_box_utf8_prefix_bytes(
				source,
				box.max_length,
			)

		source = source[:end]
	}

	text_box_replace_string(
		&box.text,
		source,
	)

	box.cursor_byte = clamp(
		box.cursor_byte,
		0,
		len(box.text),
	)

	box.selection_anchor =
		box.cursor_byte

	text_box_restart_caret(box)
}


text_box_erase :: proc(
	box: ^TextBox,
	start: int,
	finish: int,
) {
	if box == nil {
		return
	}

	clamped_start := clamp(
		start,
		0,
		len(box.text),
	)

	clamped_finish := clamp(
		finish,
		clamped_start,
		len(box.text),
	)

	if clamped_start ==
	   clamped_finish {
		return
	}

	next := strings.concatenate({
		box.text[:clamped_start],
		box.text[clamped_finish:],
	})

	if len(box.text) > 0 {
		delete(box.text)
	}

	box.text = next

	box.cursor_byte =
		clamped_start

	box.selection_anchor =
		clamped_start

	text_box_restart_caret(box)
}


text_box_delete_selection :: proc(
	box: ^TextBox,
) -> bool {
	start, finish, selected :=
		text_box_selection_bounds(box)

	if !selected {
		return false
	}

	text_box_erase(
		box,
		start,
		finish,
	)

	return true
}


text_box_insert :: proc(
	box: ^TextBox,
	value: string,
) {
	if box == nil ||
	   !box.text_editable ||
	   len(value) == 0 {
		return
	}

	_ = text_box_delete_selection(box)

	insert_value := value

	if box.max_length >= 0 {
		current_length :=
			text_box_utf8_count(
				box.text,
			)

		remaining :=
			box.max_length -
			current_length

		if remaining <= 0 {
			return
		}

		end :=
			text_box_utf8_prefix_bytes(
				insert_value,
				remaining,
			)

		insert_value =
			insert_value[:end]

		if len(insert_value) == 0 {
			return
		}
	}

	box.cursor_byte = clamp(
		box.cursor_byte,
		0,
		len(box.text),
	)

	next := strings.concatenate({
		box.text[:box.cursor_byte],
		insert_value,
		box.text[box.cursor_byte:],
	})

	if len(box.text) > 0 {
		delete(box.text)
	}

	box.text = next

	box.cursor_byte +=
		len(insert_value)

	box.selection_anchor =
		box.cursor_byte

	text_box_restart_caret(box)
}


text_box_copy_selection :: proc(
	box: ^TextBox,
) {
	if box == nil {
		return
	}

	start, finish, selected :=
		text_box_selection_bounds(box)

	if !selected {
		return
	}

	value :=
		strings.clone_to_cstring(
			box.text[start:finish],
		)

	defer delete(value)

	_ = sdl3.SetClipboardText(
		value,
	)
}


text_box_cut_selection :: proc(
	box: ^TextBox,
) {
	if box == nil ||
	   !box.text_editable {
		return
	}

	start, finish, selected :=
		text_box_selection_bounds(box)

	if !selected {
		return
	}

	text_box_copy_selection(box)

	text_box_erase(
		box,
		start,
		finish,
	)
}


text_box_paste :: proc(
	box: ^TextBox,
) {
	if box == nil ||
	   !box.text_editable {
		return
	}

	clipboard :=
		sdl3.GetClipboardText()

	if clipboard == nil {
		return
	}

	defer sdl3.free(
		rawptr(clipboard),
	)

	text_box_insert(
		box,
		string(cstring(clipboard)),
	)
}


TextBox_focus :: proc(
	box: ^TextBox,
) {
	if box == nil {
		return
	}

	if text_box_focused == box {
		box.focused = true
		text_box_restart_caret(box)
		return
	}

	if text_box_focused != nil {
		TextBox_blur(
			text_box_focused,
		)
	}

	text_box_focused = box
	box.focused = true
	box.drag_selecting = false

	if box.clear_text_on_focus &&
	   box.text_editable {
		text_box_set_text(
			box,
			"",
		)
	}

	box.cursor_byte =
		len(box.text)

	box.selection_anchor =
		box.cursor_byte

	if box.select_all_on_focus {
		text_box_select_all(box)
	}

	text_box_restart_caret(box)

	if box.text_editable {
		window :=
			sdl3.GetKeyboardFocus()

		if window != nil {
			_ =
				sdl3.StartTextInput(
					window,
				)
		}
	}
}


TextBox_blur :: proc(
	box: ^TextBox,
) {
	if box == nil {
		return
	}

	box.focused = false
	box.drag_selecting = false
	box.caret_timer = 0

	if text_box_focused == box {
		text_box_focused = nil

		window :=
			sdl3.GetKeyboardFocus()

		if window != nil {
			_ =
				sdl3.StopTextInput(
					window,
				)
		}
	}
}


text_box_effectively_visible :: proc(
	box: ^TextBox,
) -> bool {
	if box == nil {
		return false
	}

	current := &box.object

	for current != nil {
		if Is_A(
			current,
			"GuiObject",
		) {
			gui :=
				cast(^GuiObject)current

			if !gui.visible {
				return false
			}
		}

		if Is_A(
			current,
			"ScreenGui",
		) {
			screen :=
				cast(^ScreenGui)current

			if !screen.enabled {
				return false
			}
		}

		current =
			current.parent
	}

	return true
}


text_box_contains_point :: proc(
	box: ^TextBox,
	x: f32,
	y: f32,
) -> bool {
	if !text_box_effectively_visible(box) {
		return false
	}

	position := box.absolute_position
	size := box.absolute_size

	return x >= position.X &&
	       y >= position.Y &&
	       x <= position.X + size.X &&
	       y <= position.Y + size.Y
}


text_box_measure_prefix :: proc(
	box: ^TextBox,
	byte_index: int,
) -> f32 {
	if box == nil ||
	   len(box.text) == 0 {
		return 0
	}

	clamped_index := clamp(
		byte_index,
		0,
		len(box.text),
	)

	if clamped_index == 0 {
		return 0
	}

	text :=
		strings.clone_to_cstring(
			box.text[:clamped_index],
		)

	defer delete(text)

	return guilib.measureText(
		text,
		box.text_size,
		"",
	)
}


text_box_cursor_from_x :: proc(
	box: ^TextBox,
	mouse_x: f32,
) -> int {
	if box == nil ||
	   len(box.text) == 0 {
		return 0
	}

	padding: f32 = 6

	target :=
		mouse_x -
		box.absolute_position.X -
		padding +
		box.scroll_x

	target = max(
		target,
		f32(0),
	)

	previous_index := 0
	previous_width: f32 = 0
	index := 0

	for index < len(box.text) {
		next_index :=
			text_box_utf8_next_boundary(
				box.text,
				index,
			)

		width :=
			text_box_measure_prefix(
				box,
				next_index,
			)

		middle :=
			(previous_width + width) *
			0.5

		if target < middle {
			return previous_index
		}

		previous_index =
			next_index

		previous_width =
			width

		index =
			next_index
	}

	return len(box.text)
}


TextBox_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	box := new(TextBox)

	box^ =
		TextBox_Init()

	box.name =
		"TextBox"

	return &box.object
}


TextBox_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	box :=
		cast(^TextBox)object

	if text_box_focused == box {
		TextBox_blur(box)
	}

	if len(box.text) > 0 {
		delete(box.text)
	}

	if len(box.placeholder_text) > 0 {
		delete(box.placeholder_text)
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
	box :=
		cast(^TextBox)object

	switch key {

	case "Text":
		vm.PushString(
			L,
			box.text,
		)
		return true

	case "PlaceholderText":
		vm.PushString(
			L,
			box.placeholder_text,
		)
		return true

	case "TextSize":
		vm.PushNumber(
			L,
			f64(box.text_size),
		)
		return true

	case "TextColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(
			L,
			datatype_registry,
			box.text_color3,
		)

		return true

	case "PlaceholderColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(
			L,
			datatype_registry,
			box.placeholder_color3,
		)

		return true

	case "TextTransparency":
		vm.PushNumber(
			L,
			f64(box.text_transparency),
		)
		return true

	case "ClearTextOnFocus":
		vm.PushBoolean(
			L,
			box.clear_text_on_focus,
		)
		return true

	case "TextEditable":
		vm.PushBoolean(
			L,
			box.text_editable,
		)
		return true

	case "SelectAllOnFocus":
		vm.PushBoolean(
			L,
			box.select_all_on_focus,
		)
		return true

	case "MaxLength":
		vm.PushNumber(
			L,
			f64(box.max_length),
		)
		return true

	case "CaretColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(
			L,
			datatype_registry,
			box.caret_color3,
		)

		return true

	case "SelectionColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(
			L,
			datatype_registry,
			box.selection_color3,
		)

		return true

	case "SelectionTransparency":
		vm.PushNumber(
			L,
			f64(
				box.selection_transparency,
			),
		)

		return true

	case "FocusColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(
			L,
			datatype_registry,
			box.focus_color3,
		)

		return true

	case "SelectedText":
		start, finish, selected :=
			text_box_selection_bounds(
				box,
			)

		if selected {
			vm.PushString(
				L,
				box.text[start:finish],
			)
		} else {
			vm.PushString(
				L,
				"",
			)
		}

		return true

	case "CaptureFocus",
	     "ReleaseFocus",
	     "IsFocused",
	     "SelectAll",
	     "ClearSelection",
	     "CopySelection":
		vm.PushUserdataMethod(
			L,
			key,
		)

		return true
	}

	return GuiObject_get(
		L,
		object,
		datatype_registry,
		enum_registry,
		key,
	)
}


TextBox_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	box :=
		cast(^TextBox)object

	switch key {

	case "Text":
		text_box_set_text(
			box,
			vm.ArgString(
				L,
				value_index,
			),
		)

		return true

	case "PlaceholderText":
		text_box_replace_string(
			&box.placeholder_text,
			vm.ArgString(
				L,
				value_index,
			),
		)

		return true

	case "TextSize":
		box.text_size = max(
			f32(
				vm.ArgNumber(
					L,
					value_index,
				),
			),
			f32(1),
		)

		return true

	case "TextColor3":
		if datatype_registry == nil {
			return false
		}

		box.text_color3 =
			datatypes.Arg_Color3(
				L,
				value_index,
				datatype_registry,
			)

		return true

	case "PlaceholderColor3":
		if datatype_registry == nil {
			return false
		}

		box.placeholder_color3 =
			datatypes.Arg_Color3(
				L,
				value_index,
				datatype_registry,
			)

		return true

	case "TextTransparency":
		box.text_transparency =
			clamp(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				f32(0),
				f32(1),
			)

		return true

	case "ClearTextOnFocus":
		box.clear_text_on_focus =
			vm.ArgBoolean(
				L,
				value_index,
			)

		return true

	case "TextEditable":
		box.text_editable =
			vm.ArgBoolean(
				L,
				value_index,
			)

		if box.focused {
			window :=
				sdl3.GetKeyboardFocus()

			if window != nil {
				if box.text_editable {
					_ =
						sdl3.StartTextInput(
							window,
						)
				} else {
					_ =
						sdl3.StopTextInput(
							window,
						)
				}
			}
		}

		return true

	case "SelectAllOnFocus":
		box.select_all_on_focus =
			vm.ArgBoolean(
				L,
				value_index,
			)

		return true

	case "MaxLength":
		requested :=
			int(
				vm.ArgNumber(
					L,
					value_index,
				),
			)

		box.max_length =
			max(
				requested,
				-1,
			)

		if box.max_length >= 0 &&
		   text_box_utf8_count(
			   box.text,
		   ) > box.max_length {
			end :=
				text_box_utf8_prefix_bytes(
					box.text,
					box.max_length,
				)

			text_box_set_text(
				box,
				box.text[:end],
			)
		}

		return true

	case "CaretColor3":
		if datatype_registry == nil {
			return false
		}

		box.caret_color3 =
			datatypes.Arg_Color3(
				L,
				value_index,
				datatype_registry,
			)

		return true

	case "SelectionColor3":
		if datatype_registry == nil {
			return false
		}

		box.selection_color3 =
			datatypes.Arg_Color3(
				L,
				value_index,
				datatype_registry,
			)

		return true

	case "SelectionTransparency":
		box.selection_transparency =
			clamp(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				f32(0),
				f32(1),
			)

		return true

	case "FocusColor3":
		if datatype_registry == nil {
			return false
		}

		box.focus_color3 =
			datatypes.Arg_Color3(
				L,
				value_index,
				datatype_registry,
			)

		return true
	}

	return GuiObject_set(
		L,
		object,
		datatype_registry,
		enum_registry,
		key,
		value_index,
	)
}


TextBox_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	box :=
		cast(^TextBox)object

	switch method {

	case "CaptureFocus":
		TextBox_focus(box)
		return 0, true

	case "ReleaseFocus":
		TextBox_blur(box)
		return 0, true

	case "IsFocused":
		vm.PushBoolean(
			L,
			box.focused,
		)

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
	}

	return 0, false
}


TextBox_render :: proc(
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

	GuiObject_render(
		object,
		ctx,
	)

	box :=
		cast(^TextBox)object

	surface :=
		ctx.renderer.SkiaSurface

	padding: f32 = 6

	dt :=
		clamp(
			f32(ctx.delta_time),
			f32(0),
			f32(0.1),
		)

	//
	// Focus animation
	//

	focus_target: f32 = 0

	if box.focused {
		focus_target = 1
	}

	focus_lerp :=
		min(
			dt * 14,
			f32(1),
		)

	box.focus_animation +=
		(
			focus_target -
			box.focus_animation
		) *
		focus_lerp

	//
	// Caret timer
	//

	if box.focused {
		box.caret_timer += dt

		for box.caret_timer >= 1.2 {
			box.caret_timer -= 1.2
		}
	} else {
		box.caret_timer = 0
	}

	//
	// Display text
	//

	display_text :=
		box.text

	display_color :=
		box.text_color3

	if len(box.text) == 0 &&
	   len(box.placeholder_text) > 0 {
		display_text =
			box.placeholder_text

		display_color =
			box.placeholder_color3
	}

	//
	// Caret position
	//

	caret_width: f32 = 0

	if box.focused {
		caret_width =
			text_box_measure_prefix(
				box,
				box.cursor_byte,
			)
	}

	available_width :=
		max(
			rect.width -
			padding * 2,
			f32(0),
		)

	//
	// Horizontal scrolling target
	//

	if box.focused {
		desired :=
			box.scroll_target_x

		visible_caret :=
			caret_width -
			desired

		if visible_caret >
		   available_width {
			desired =
				caret_width -
				available_width
		} else if visible_caret < 0 {
			desired =
				caret_width
		}

		total_width :=
			text_box_measure_prefix(
				box,
				len(box.text),
			)

		max_scroll :=
			max(
				total_width -
				available_width,
				f32(0),
			)

		box.scroll_target_x =
			clamp(
				desired,
				f32(0),
				max_scroll,
			)
	} else {
		box.scroll_target_x = 0
	}

	//
	// Smooth scroll animation
	//

	scroll_lerp :=
		min(
			dt * 20,
			f32(1),
		)

	box.scroll_x +=
		(
			box.scroll_target_x -
			box.scroll_x
		) *
		scroll_lerp

	//
	// Text baseline
	//

	baseline :=
		rect.y +
		(
			rect.height -
			box.text_size
		) *
		0.5 +
		box.text_size

	guilib.save(surface)
	defer guilib.restore(surface)

	guilib.clipRect(
		surface,
		rect,
	)

	//
	// Selection highlight
	//

	selection_start,
	selection_finish,
	has_selection :=
		text_box_selection_bounds(
			box,
		)

	if has_selection &&
	   len(box.text) > 0 {
		start_width :=
			text_box_measure_prefix(
				box,
				selection_start,
			)

		end_width :=
			text_box_measure_prefix(
				box,
				selection_finish,
			)

		selection_x :=
			rect.x +
			padding +
			start_width -
			box.scroll_x

		selection_width :=
			max(
				end_width -
				start_width,
				f32(0),
			)

		guilib.drawRect(
			surface,
			guilib.Rect{
				x =
					selection_x,

				y =
					rect.y + 3,

				width =
					selection_width,

				height =
					max(
						rect.height - 6,
						f32(0),
					),

				color =
					box.selection_color3,

				bgTransparency =
					box.selection_transparency,
			},
		)
	}

	//
	// Text
	//

	if len(display_text) > 0 {
		text :=
			strings.clone_to_cstring(
				display_text,
			)

		defer delete(text)

		guilib.drawText(
			surface,
			text,
			guilib.TextParams{
				x =
					rect.x +
					padding -
					box.scroll_x,

				y =
					baseline,

				TextSize =
					box.text_size,

				color =
					display_color,

				transparency =
					box.text_transparency,

				font =
					"",
			},
		)
	}

	//
	// Animated blinking caret
	//

	if box.focused {
		caret_alpha: f32 = 1
		t := box.caret_timer

		if t < 0.50 {
			caret_alpha = 1
		} else if t < 0.65 {
			caret_alpha =
				1 -
				(
					t - 0.50
				) /
				0.15
		} else if t < 1.05 {
			caret_alpha = 0
		} else {
			caret_alpha =
				(
					t - 1.05
				) /
				0.15
		}

		caret_alpha =
			clamp(
				caret_alpha,
				f32(0),
				f32(1),
			)

		caret_x :=
			rect.x +
			padding +
			caret_width -
			box.scroll_x

		vertical_padding :=
			min(
				f32(4),
				rect.height * 0.2,
			)

		caret_transparency :=
			1 -
			(
				1 -
				box.text_transparency
			) *
			caret_alpha

		guilib.drawLine(
			surface,

			caret_x,
			rect.y +
				vertical_padding,

			caret_x,
			rect.y +
				rect.height -
				vertical_padding,

			1.5,

			box.caret_color3,

			caret_transparency,
		)
	}

	//
	// Animated focus underline
	//

	if box.focus_animation > 0.001 {
		focus_width :=
			rect.width *
			box.focus_animation

		focus_x :=
			rect.x +
			(
				rect.width -
				focus_width
			) *
			0.5

		guilib.drawRect(
			surface,
			guilib.Rect{
				x =
					focus_x,

				y =
					rect.y +
					rect.height -
					2,

				width =
					focus_width,

				height =
					2,

				color =
					box.focus_color3,

				bgTransparency =
					1 -
					box.focus_animation,
			},
		)
	}
}


TextBox_clone :: proc(
	source: ^Object,
	destination: ^Object,
) {
	src :=
		cast(^TextBox)source

	dst :=
		cast(^TextBox)destination

	text_box_replace_string(
		&dst.text,
		src.text,
	)

	text_box_replace_string(
		&dst.placeholder_text,
		src.placeholder_text,
	)

	dst.text_size =
		src.text_size

	dst.text_color3 =
		src.text_color3

	dst.placeholder_color3 =
		src.placeholder_color3

	dst.text_transparency =
		src.text_transparency

	dst.clear_text_on_focus =
		src.clear_text_on_focus

	dst.text_editable =
		src.text_editable

	dst.select_all_on_focus =
		src.select_all_on_focus

	dst.max_length =
		src.max_length

	dst.caret_color3 =
		src.caret_color3

	dst.selection_color3 =
		src.selection_color3

	dst.selection_transparency =
		src.selection_transparency

	dst.focus_color3 =
		src.focus_color3

	dst.focused = false

	dst.cursor_byte =
		len(dst.text)

	dst.selection_anchor =
		dst.cursor_byte

	dst.drag_selecting =
		false

	dst.focus_animation =
		0

	dst.caret_timer =
		0

	dst.scroll_x =
		0

	dst.scroll_target_x =
		0
}


TextBox_Handle_Event :: proc(
	registry: ^Registry,
	L: ^vm.State,
	event: sdl3.Event,
) {
	if registry == nil {
		return
	}

	descriptor :=
		Find_Class(
			registry,
			"TextBox",
		)

	if descriptor == nil {
		return
	}

	#partial switch event.type {

	//
	// Mouse down
	//

	case .MOUSE_BUTTON_DOWN:
		if event.button.button !=
		   sdl3.BUTTON_LEFT {
			return
		}

		clicked: ^TextBox
		best_z: i32
		found := false

		for object in descriptor.instances {
			if object == nil ||
			   object.destroyed {
				continue
			}

			box :=
				cast(^TextBox)object

			if !text_box_contains_point(
				box,
				event.button.x,
				event.button.y,
			) {
				continue
			}

			if !found ||
			   box.zindex >= best_z {
				clicked =
					box

				best_z =
					box.zindex

				found =
					true
			}
		}

		//
		// Clicked outside
		//

		if clicked == nil {
			if text_box_focused != nil {
				TextBox_blur(
					text_box_focused,
				)
			}

			return
		}

		was_focused :=
			clicked.focused

		if text_box_focused != nil &&
		   text_box_focused != clicked {
			TextBox_blur(
				text_box_focused,
			)
		}

		TextBox_focus(clicked)

		if !clicked.focused {
			return
		}

		//
		// Double click selects everything
		//

		if event.button.clicks >= 2 {
			text_box_select_all(
				clicked,
			)

			clicked.drag_selecting =
				false

			return
		}

		//
		// SelectAllOnFocus
		//

		if !was_focused &&
		   clicked.select_all_on_focus {
			clicked.drag_selecting =
				false

			return
		}

		cursor :=
			text_box_cursor_from_x(
				clicked,
				event.button.x,
			)

		modifiers :=
			sdl3.GetModState()

		shift :=
			.LSHIFT in modifiers ||
			.RSHIFT in modifiers

		if !shift {
			clicked.selection_anchor =
				cursor
		}

		clicked.cursor_byte =
			cursor

		clicked.drag_selecting =
			true

		text_box_restart_caret(
			clicked,
		)

	//
	// Mouse drag
	//

	case .MOUSE_MOTION:
		box :=
			text_box_focused

		if box == nil ||
		   !box.focused ||
		   !box.drag_selecting {
			return
		}

		box.cursor_byte =
			text_box_cursor_from_x(
				box,
				event.motion.x,
			)

		text_box_restart_caret(
			box,
		)

	//
	// Mouse released
	//

	case .MOUSE_BUTTON_UP:
		if event.button.button !=
		   sdl3.BUTTON_LEFT {
			return
		}

		if text_box_focused != nil {
			text_box_focused.drag_selecting =
				false
		}

	//
	// Unicode text input
	//

	case .TEXT_INPUT:
		box :=
			text_box_focused

		if box == nil ||
		   !box.focused ||
		   !box.text_editable ||
		   event.text.text == nil {
			return
		}

		text_box_insert(
			box,
			string(
				event.text.text,
			),
		)

	//
	// Keyboard commands
	//

	case .KEY_DOWN:
		box :=
			text_box_focused

		if box == nil ||
		   !box.focused {
			return
		}

		modifiers :=
			event.key.mod

		shift :=
			.LSHIFT in modifiers ||
			.RSHIFT in modifiers

		//
		// Ctrl on Windows/Linux,
		// Command on macOS.
		//

		shortcut :=
			.LCTRL in modifiers ||
			.RCTRL in modifiers ||
			.LGUI in modifiers ||
			.RGUI in modifiers

		//
		// Keyboard shortcuts
		//

		if shortcut {
			#partial switch event.key.scancode {

			case .A:
				text_box_select_all(
					box,
				)

				return

			case .C:
				text_box_copy_selection(
					box,
				)

				return

			case .X:
				if box.text_editable {
					text_box_cut_selection(
						box,
					)
				}

				return

			case .V:
				if box.text_editable {
					text_box_paste(
						box,
					)
				}

				return

			case:
			}
		}

		#partial switch event.key.scancode {

		//
		// Backspace
		//

		case .BACKSPACE:
			if !box.text_editable {
				return
			}

			if text_box_delete_selection(
				box,
			) {
				return
			}

			if box.cursor_byte > 0 {
				previous :=
					text_box_utf8_prev_boundary(
						box.text,
						box.cursor_byte,
					)

				text_box_erase(
					box,
					previous,
					box.cursor_byte,
				)
			}

		//
		// Delete
		//

		case .DELETE:
			if !box.text_editable {
				return
			}

			if text_box_delete_selection(
				box,
			) {
				return
			}

			if box.cursor_byte <
			   len(box.text) {
				next :=
					text_box_utf8_next_boundary(
						box.text,
						box.cursor_byte,
					)

				text_box_erase(
					box,
					box.cursor_byte,
					next,
				)
			}

		//
		// Left
		//

		case .LEFT:
			selection_start,
			selection_finish,
			selected :=
				text_box_selection_bounds(
					box,
				)

			_ = selection_finish

			if selected &&
			   !shift {
				box.cursor_byte =
					selection_start

				box.selection_anchor =
					selection_start
			} else {
				old_cursor :=
					box.cursor_byte

				if !shift {
					box.selection_anchor =
						old_cursor
				}

				box.cursor_byte =
					text_box_utf8_prev_boundary(
						box.text,
						old_cursor,
					)

				if !shift {
					box.selection_anchor =
						box.cursor_byte
				}
			}

			text_box_restart_caret(
				box,
			)

		//
		// Right
		//

		case .RIGHT:
			selection_start,
			selection_finish,
			selected :=
				text_box_selection_bounds(
					box,
				)

			_ = selection_start

			if selected &&
			   !shift {
				box.cursor_byte =
					selection_finish

				box.selection_anchor =
					selection_finish
			} else {
				old_cursor :=
					box.cursor_byte

				if !shift {
					box.selection_anchor =
						old_cursor
				}

				box.cursor_byte =
					text_box_utf8_next_boundary(
						box.text,
						old_cursor,
					)

				if !shift {
					box.selection_anchor =
						box.cursor_byte
				}
			}

			text_box_restart_caret(
				box,
			)

		//
		// Home
		//

		case .HOME:
			old_cursor :=
				box.cursor_byte

			if shift {
				if box.selection_anchor ==
				   box.cursor_byte {
					box.selection_anchor =
						old_cursor
				}

				box.cursor_byte = 0
			} else {
				box.cursor_byte = 0
				box.selection_anchor = 0
			}

			text_box_restart_caret(
				box,
			)

		//
		// End
		//

		case .END:
			old_cursor :=
				box.cursor_byte

			end :=
				len(box.text)

			if shift {
				if box.selection_anchor ==
				   box.cursor_byte {
					box.selection_anchor =
						old_cursor
				}

				box.cursor_byte =
					end
			} else {
				box.cursor_byte =
					end

				box.selection_anchor =
					end
			}

			text_box_restart_caret(
				box,
			)

		//
		// Enter
		//

		case .RETURN,
		     .KP_ENTER:
			TextBox_blur(
				box,
			)

		//
		// Escape
		//

		case .ESCAPE:
			TextBox_blur(
				box,
			)
		}
	}
}


Register_TextBox :: proc(
	registry: ^Registry,
) {
	Register_Class(
		registry,
		&TextBox_Class,

		TextBox_construct,
		TextBox_destroy,

		get =
			TextBox_get,

		set =
			TextBox_set,

		namecall =
			TextBox_namecall,

		clone =
			TextBox_clone,
	)
}
