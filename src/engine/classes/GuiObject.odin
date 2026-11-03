package classes

import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import sdl3 "../platform"
import signals "../signals"
import tracy "../util/odin-tracy"
import vm "../vm"
import "core:fmt"
import "core:math"

GuiObject_Class := Class_Info {
	name   = "GuiObject",
	parent = &Instance_Class,
}

GuiObject :: struct {
	using object:                Object,
	bg_transparency:             f64,
	bg_color:                    datatypes.Color3,
	active:                      bool,
	border_mode:                 enums.BorderMode,
	clips_descendants:           bool,
	gui_state:                   enums.GuiState,
	input_sink:                  bool,
	position:                    datatypes.UDim2,
	selectable:                  bool,
	size:                        datatypes.UDim2,
	automatic_size:              enums.AutomaticSize,
	visible:                     bool,
	zindex:                      i32,
	anchorpoint:                 datatypes.Vector2,
	rotation:                    f64,
	border_size_pixels:          i32,
	border_color3:               datatypes.Color3,
	absolute_position:           datatypes.Vector2,
	absolute_size:               datatypes.Vector2,
	input_began:                 ^signals.Signal,
	input_changed:               ^signals.Signal,
	input_ended:                 ^signals.Signal,
	mouse_enter:                 ^signals.Signal,
	mouse_leave:                 ^signals.Signal,
	mouse_moved:                 ^signals.Signal,
	mouse_wheel_forward:         ^signals.Signal,
	mouse_wheel_backward:        ^signals.Signal,
	mouse_inside:                bool,
	mouse_input_down:            [3]bool,
	layout_order:                i32,
	layout_override_active:      bool,
	layout_override_position:    datatypes.Vector2,
	layout_override_size_active: bool,
	layout_override_size:        datatypes.Vector2,
	content_size:                datatypes.Vector2,
	base_size:                   datatypes.Vector2,
	resolved_size:               datatypes.Vector2,
	previous_size:               datatypes.Vector2,
	content_offset:              datatypes.Vector2,
	resolved_size_valid:         bool,
	previous_size_valid:         bool,
	base_solved:                 bool,
	auto_solved:                 bool,
	hovered_gui:                 ^GuiObject,
	hovered_button:              ^GuiButton,
}

GuiObject_Init :: proc() -> GuiObject {
	Gui_Layout_Mark_Dirty()
	return GuiObject {
		object = Object_Init(&GuiObject_Class),
		position = datatypes.UDim2{0, 0, 0, 0},
		bg_color = datatypes.Color3{R = 1, G = 1, B = 1},
		size = datatypes.UDim2{0, 100, 0, 100},
		anchorpoint = datatypes.Vector2{0, 0},
		rotation = 0,
		automatic_size = .None,
		active = false,
		selectable = true,
		visible = true,
		zindex = 0,
		border_size_pixels = 0,
		input_sink = false,
		gui_state = enums.GuiState.Idle,
		bg_transparency = 0,
		absolute_position = datatypes.Vector2{0, 0},
		absolute_size = datatypes.Vector2{0, 0},
	}
}

GuiObject_ensure_signals :: proc(gui: ^GuiObject) {
	if gui == nil ||
	   gui.object.signal_registry == nil ||
	   gui.object.signal_registry.signal_registry == nil {
		return
	}

	registry := gui.object.signal_registry.signal_registry

	if gui.input_began == nil {
		gui.input_began = signals.Create(registry)
	}

	if gui.input_changed == nil {
		gui.input_changed = signals.Create(registry)
	}

	if gui.input_ended == nil {
		gui.input_ended = signals.Create(registry)
	}

	if gui.mouse_enter == nil {
		gui.mouse_enter = signals.Create(registry)
	}

	if gui.mouse_leave == nil {
		gui.mouse_leave = signals.Create(registry)
	}

	if gui.mouse_moved == nil {
		gui.mouse_moved = signals.Create(registry)
	}

	if gui.mouse_wheel_forward == nil {
		gui.mouse_wheel_forward = signals.Create(registry)
	}

	if gui.mouse_wheel_backward == nil {
		gui.mouse_wheel_backward = signals.Create(registry)
	}
}

GuiObject_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	gui_object := new(GuiObject)
	gui_object^ = GuiObject_Init()
	gui_object.name = "GuiObject"
	Gui_Layout_Mark_Dirty()
	return &gui_object.object
}

GuiObject_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Gui_Layout_Mark_Dirty()
	GuiObject_Free_Signals(cast(^GuiObject)object)
	Object_Destroy(object)
	free(cast(^GuiObject)object)
}

GuiObject_Free_Signals :: proc(gui: ^GuiObject) {
	if gui == nil {
		return
	}

	Gui_Layout_Mark_Dirty()

	if gui.input_began != nil {
		signals.Destroy(gui.input_began)
		gui.input_began = nil
	}
	if gui.input_changed != nil {
		signals.Destroy(gui.input_changed)
		gui.input_changed = nil
	}
	if gui.input_ended != nil {
		signals.Destroy(gui.input_ended)
		gui.input_ended = nil
	}
	if gui.mouse_enter != nil {
		signals.Destroy(gui.mouse_enter)
		gui.mouse_enter = nil
	}
	if gui.mouse_leave != nil {
		signals.Destroy(gui.mouse_leave)
		gui.mouse_leave = nil
	}
	if gui.mouse_moved != nil {
		signals.Destroy(gui.mouse_moved)
		gui.mouse_moved = nil
	}
	if gui.mouse_wheel_forward != nil {
		signals.Destroy(gui.mouse_wheel_forward)
		gui.mouse_wheel_forward = nil
	}
	if gui.mouse_wheel_backward != nil {
		signals.Destroy(gui.mouse_wheel_backward)
		gui.mouse_wheel_backward = nil
	}
}

GuiObject_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	gui := cast(^GuiObject)object

	switch key {
	case "Active":
		vm.PushBoolean(L, gui.active)

	case "LayoutOrder":
		vm.PushNumber(L, f64(gui.layout_order))

	case "BackgroundTransparency":
		vm.PushNumber(L, gui.bg_transparency)

	case "ClipsDescendants":
		vm.PushBoolean(L, gui.clips_descendants)

	case "InputSink":
		vm.PushBoolean(L, gui.input_sink)

	case "Selectable":
		vm.PushBoolean(L, gui.selectable)

	case "Visible":
		vm.PushBoolean(L, gui.visible)

	case "ZIndex":
		vm.PushNumber(L, f64(gui.zindex))

	case "BorderSizePixel":
		vm.PushNumber(L, f64(gui.border_size_pixels))

	case "BorderColor3":
		if datatype_registry == nil {
			return false
		}
		datatypes.Push_Color3(L, datatype_registry, gui.border_color3)

	case "BorderMode":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(L, enum_registry, "BorderMode", i64(gui.border_mode))

	case "GuiState":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(L, enum_registry, "GuiState", i64(gui.gui_state))

	case "BackgroundColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(L, datatype_registry, gui.bg_color)

	case "Position":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_UDim2(L, datatype_registry, gui.position)

	case "Size":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_UDim2(L, datatype_registry, gui.size)

	case "AutomaticSize":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(L, enum_registry, "AutomaticSize", i64(gui.automatic_size))

	case "AnchorPoint":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(L, datatype_registry, gui.anchorpoint)

	case "Rotation":
		vm.PushNumber(L, gui.rotation)

	case "AbsolutePosition":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(L, datatype_registry, gui.absolute_position)

	case "AbsoluteSize":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(L, datatype_registry, gui.absolute_size)

	case "InputBegan":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.input_began)

	case "InputChanged":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.input_changed)

	case "InputEnded":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.input_ended)

	case "MouseEnter":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.mouse_enter)

	case "MouseLeave":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.mouse_leave)

	case "MouseMoved":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.mouse_moved)

	case "MouseWheelForward":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.mouse_wheel_forward)

	case "MouseWheelBackward":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.mouse_wheel_backward)

	case:
		return false
	}

	return true
}

GuiObject_effectively_visible :: proc(gui: ^GuiObject) -> bool {
	if gui == nil || gui.destroyed || !gui.visible {
		return false
	}

	current := gui.object.parent

	for current != nil {
		if Is_A(current, "GuiObject") {
			parent_gui := cast(^GuiObject)current

			if !parent_gui.visible {
				return false
			}
		}

		if Is_A(current, "ScreenGui") {
			screen_gui := cast(^ScreenGui)current

			if !screen_gui.enabled {
				return false
			}
		}

		if Is_A(current, "SurfaceGui") {
			surface_gui := cast(^SurfaceGui)current

			if !surface_gui.enabled {
				return false
			}
		}

		current = current.parent
	}

	return true
}

GuiObject_get_absolute_transform :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) -> (
	x, y, width, height: f32,
) {
	if object == nil {
		return 0, 0, f32(ctx.viewport_width), f32(ctx.viewport_height)
	}
	if Is_A(object, "ScreenGui") {
		screen_gui := cast(^ScreenGui)object

		width = screen_gui.size.X
		height = screen_gui.size.Y

		if width <= 0 {
			width = f32(ctx.viewport_width)
		}

		if height <= 0 {
			height = f32(ctx.viewport_height)
		}

		return screen_gui.render_offset.X, screen_gui.render_offset.Y, width, height
	}

	if Is_A(object, "SurfaceGui") {
		surface_gui := cast(^SurfaceGui)object
		part := surfacegui_target_part(surface_gui)

		width, height = surfacegui_canvas_size(surface_gui, part)

		if width <= 0 {
			width = f32(ctx.viewport_width)
		}

		if height <= 0 {
			height = f32(ctx.viewport_height)
		}

		return 0, 0, width, height
	}

	if !Is_A(object, "GuiObject") {
		return GuiObject_get_absolute_transform(object.parent, ctx)
	}

	parent_x, parent_y, parent_width, parent_height := GuiObject_get_absolute_transform(
		object.parent,
		ctx,
	)

	gui := cast(^GuiObject)object

	if gui.layout_override_size_active {
		width = gui.layout_override_size.X
		height = gui.layout_override_size.Y
	} else if gui.resolved_size_valid {
		width = gui.resolved_size.X
		height = gui.resolved_size.Y
	} else {
		width = gui.size.X_Scale * parent_width + gui.size.X_Offset
		height = gui.size.Y_Scale * parent_height + gui.size.Y_Offset
	}

	if gui.layout_override_active {
		x = parent_x + gui.layout_override_position.X

		y = parent_y + gui.layout_override_position.Y
	} else {
		padding_x: f32 = 0
		padding_y: f32 = 0

		if object.parent != nil && Is_A(object.parent, "GuiObject") {
			parent_gui := cast(^GuiObject)object.parent

			padding_x = parent_gui.content_offset.X
			padding_y = parent_gui.content_offset.Y
		}

		x =
			parent_x +
			padding_x +
			gui.position.X_Scale * parent_width +
			gui.position.X_Offset -
			gui.anchorpoint.X * width

		y =
			parent_y +
			padding_y +
			gui.position.Y_Scale * parent_height +
			gui.position.Y_Offset -
			gui.anchorpoint.Y * height
	}

	if object.parent != nil && Is_A(object.parent, "ScrollingFrame") {
		scrolling := cast(^ScrollingFrame)object.parent
		x -= scrolling.canvas_position.X
		y -= scrolling.canvas_position.Y
	}

	return x, y, width, height
}

GuiObject_point_in_rect :: proc(
	x, y: f32,
	position: datatypes.Vector2,
	size: datatypes.Vector2,
) -> bool {
	return(
		x >= position.X &&
		y >= position.Y &&
		x <= position.X + size.X &&
		y <= position.Y + size.Y \
	)
}

GuiObject_accepts_pointer :: proc(gui: ^GuiObject) -> bool {
	if gui == nil {
		return false
	}

	return gui.input_sink || gui.active || Is_A(&gui.object, "TextBox")
}






GuiObject_paints :: proc(gui: ^GuiObject) -> bool {
	if gui == nil {
		return false
	}

	if gui.bg_transparency < 1 {
		return true
	}

	
	
	
	switch {
	case Is_A_Class(&gui.object, &ViewportFrame_Class):
		frame := cast(^ViewportFrame)gui
		return frame.current_camera != nil && frame.image_transparency < 1
	case Is_A(&gui.object, "ImageLabel"):
		label := cast(^ImageLabel)gui
		if label.stored_image != nil && label.image_transparency < 1 {return true}
	case Is_A(&gui.object, "ImageButton"):
		button := cast(^ImageButton)gui
		if button.stored_image != nil && button.image_transparency < 1 {return true}
	case Is_A(&gui.object, "TextLabel"):
		label := cast(^TextLabel)gui
		if label.text != "" && label.text_transparency < 1 {return true}
	case Is_A(&gui.object, "TextButton"):
		button := cast(^TextButton)gui
		if button.text != "" && button.text_transparency < 1 {return true}
	}

	return false
}

GuiObject_contains_point :: proc(gui: ^GuiObject, x, y: f32) -> bool {
	if !GuiObject_effectively_visible(gui) {
		return false
	}

	local_x, local_y := GuiObject_screen_to_local(gui, x, y)
	if !GuiObject_point_in_rect(local_x, local_y, gui.absolute_position, gui.absolute_size) {
		return false
	}

	current := gui.object.parent

	for current != nil {
		if Is_A(current, "GuiObject") {
			parent_gui := cast(^GuiObject)current

			if parent_gui.clips_descendants {
				parent_x, parent_y := GuiObject_screen_to_local(parent_gui, x, y)

				if !GuiObject_point_in_rect(
					parent_x,
					parent_y,
					parent_gui.absolute_position,
					parent_gui.absolute_size,
				) {
					return false
				}
			}
		}

		current = current.parent
	}

	return true
}

GuiObject_screen_to_local :: proc(gui: ^GuiObject, x, y: f32) -> (f32, f32) {
	px, py := x, y

	if gui == nil {
		return px, py
	}

	if gui.object.parent != nil && Is_A(gui.object.parent, "GuiObject") {
		px, py = GuiObject_screen_to_local(cast(^GuiObject)gui.object.parent, x, y)
	}

	if gui.rotation != 0 {
		center_x := gui.absolute_position.X + gui.absolute_size.X * 0.5
		center_y := gui.absolute_position.Y + gui.absolute_size.Y * 0.5
		radians := math.to_radians(f32(-gui.rotation))
		sine := math.sin(radians)
		cosine := math.cos(radians)
		dx := px - center_x
		dy := py - center_y

		px = center_x + dx * cosine - dy * sine
		py = center_y + dx * sine + dy * cosine
	}

	return px, py
}

gui_object_containing_screen :: proc(gui: ^GuiObject) -> ^ScreenGui {
	if gui == nil {
		return nil
	}

	current := gui.object.parent

	for current != nil {
		if Is_A(current, "ScreenGui") {
			return cast(^ScreenGui)current
		}

		current = current.parent
	}

	return nil
}

gui_object_containing_surface :: proc(gui: ^GuiObject) -> ^SurfaceGui {
	if gui == nil {
		return nil
	}

	current := gui.object.parent

	for current != nil {
		if Is_A(current, "SurfaceGui") {
			return cast(^SurfaceGui)current
		}

		current = current.parent
	}

	return nil
}

gui_object_is_overlay_pass :: proc(screen: ^ScreenGui) -> bool {
	if screen == nil {
		return false
	}

	if screen.render_on_top {
		return true
	}

	return screen.object.parent != nil && screen.object.parent.name == "StarterGui"
}

gui_object_visit_painted_subtree :: proc(
	object: ^Object,
	screen: ^ScreenGui,
	x, y: f32,
	seq: ^int,
	best: ^^GuiObject,
	best_seq: ^int,
	require_paint: bool,
) {
	if object == nil {
		return
	}

	for child in object.children {
		if child == nil || child.destroyed {
			continue
		}

		if Is_A(child, "GuiObject") &&
		   gui_object_containing_screen(cast(^GuiObject)child) == screen {
			gui := cast(^GuiObject)child

			if gui.visible &&
			   GuiObject_effectively_visible(gui) &&
			   GuiObject_accepts_pointer(gui) &&
			   (!require_paint || GuiObject_paints(gui)) &&
			   GuiObject_contains_point(gui, x, y) {
				seq^ += 1

				if seq^ > best_seq^ {
					best^ = gui
					best_seq^ = seq^
				}
			}
		}

		gui_object_visit_painted_subtree(child, screen, x, y, seq, best, best_seq, require_paint)
	}
}

gui_object_visit_surface_subtree :: proc(
	object: ^Object,
	surface: ^SurfaceGui,
	x, y: f32,
	seq: ^int,
	best: ^^GuiObject,
	best_seq: ^int,
	require_paint: bool,
) {
	if object == nil {
		return
	}

	for child in object.children {
		if child == nil || child.destroyed {
			continue
		}

		if Is_A(child, "GuiObject") &&
		   gui_object_containing_surface(cast(^GuiObject)child) == surface {
			gui := cast(^GuiObject)child

			if gui.visible &&
			   GuiObject_effectively_visible(gui) &&
			   GuiObject_accepts_pointer(gui) &&
			   (!require_paint || GuiObject_paints(gui)) &&
			   GuiObject_contains_point(gui, x, y) {
				seq^ += 1

				if seq^ > best_seq^ {
					best^ = gui
					best_seq^ = seq^
				}
			}
		}

		gui_object_visit_surface_subtree(child, surface, x, y, seq, best, best_seq, require_paint)
	}
}

GuiObject_find_topmost_in_surface :: proc(
	surface: ^SurfaceGui,
	x, y: f32,
	require_paint: bool = false,
) -> ^GuiObject {
	if surface == nil {
		return nil
	}

	seq := 0
	best: ^GuiObject
	best_seq := -1

	gui_object_visit_surface_subtree(
		&surface.object,
		surface,
		x,
		y,
		&seq,
		&best,
		&best_seq,
		require_paint,
	)

	return best
}





GuiObject_find_topmost :: proc(
	registry: ^Registry,
	x, y: f32,
	require_paint: bool = false,
	overlay_only: bool = false,
) -> ^GuiObject {
	if registry == nil {
		return nil
	}

	seq := 0
	best: ^GuiObject
	best_seq := -1

	screen_descriptor := Find_Class(registry, "ScreenGui")

	
	
	
	
	if screen_descriptor != nil && !overlay_only {
		for descriptor in registry.classes {
			for object in descriptor.instances {
				if object == nil || object.destroyed || !Is_A(object, "GuiObject") {
					continue
				}

				gui := cast(^GuiObject)object

				if gui_object_containing_screen(gui) != nil ||
				   gui_object_containing_surface(gui) != nil {
					continue
				}

				if gui.visible &&
				   GuiObject_effectively_visible(gui) &&
				   GuiObject_accepts_pointer(gui) &&
				   (!require_paint || GuiObject_paints(gui)) &&
				   GuiObject_contains_point(gui, x, y) {
					seq += 1

					if seq > best_seq {
						best = gui
						best_seq = seq
					}
				}
			}
		}
	}

	if screen_descriptor != nil {
		for object in screen_descriptor.instances {
			if object == nil || object.destroyed {
				continue
			}

			screen := cast(^ScreenGui)object

			if overlay_only || !screen.enabled || gui_object_is_overlay_pass(screen) {
				continue
			}

			gui_object_visit_painted_subtree(
				&screen.object,
				screen,
				x,
				y,
				&seq,
				&best,
				&best_seq,
				require_paint,
			)
		}

		for object in screen_descriptor.instances {
			if object == nil || object.destroyed {
				continue
			}

			screen := cast(^ScreenGui)object

			if !screen.enabled || !gui_object_is_overlay_pass(screen) {
				continue
			}

			gui_object_visit_painted_subtree(
				&screen.object,
				screen,
				x,
				y,
				&seq,
				&best,
				&best_seq,
				require_paint,
			)
		}
	}

	return best
}

GuiObject_Hit :: struct {
	target:  ^GuiObject,
	x:       f32,
	y:       f32,
	surface: ^SurfaceGui,
}

GuiObject_Hit_Chain :: struct {
	chain:   [dynamic]^GuiObject,
	x:       f32,
	y:       f32,
	surface: ^SurfaceGui,
}

GuiObject_hit_test :: proc(
	registry: ^Registry,
	x, y: f32,
	require_paint: bool = false,
	overlay_only: bool = false,
) -> GuiObject_Hit {
	target := GuiObject_find_topmost(registry, x, y, require_paint, overlay_only)
	if target != nil {
		return GuiObject_Hit{target = target, x = x, y = y}
	}

	surface, canvas_x, canvas_y, hit := surfacegui_hit_test(registry, x, y)
	if !hit {
		return {}
	}

	return GuiObject_Hit {
		target = GuiObject_find_topmost_in_surface(surface, canvas_x, canvas_y, require_paint),
		x = canvas_x,
		y = canvas_y,
		surface = surface,
	}
}

gui_object_hit_chain_from_hit :: proc(hit: GuiObject_Hit) -> GuiObject_Hit_Chain {
	result := GuiObject_Hit_Chain {
		x       = hit.x,
		y       = hit.y,
		surface = hit.surface,
	}

	if hit.target == nil {
		return result
	}

	append(&result.chain, hit.target)

	current := hit.target.object.parent

	for current != nil {
		if Is_A(current, "GuiObject") {
			append(&result.chain, cast(^GuiObject)current)
		}

		current = current.parent
	}

	return result
}

GuiObject_hit_chain_ex :: proc(
	registry: ^Registry,
	x, y: f32,
	require_paint: bool = false,
	overlay_only: bool = false,
) -> GuiObject_Hit_Chain {
	return gui_object_hit_chain_from_hit(
		GuiObject_hit_test(registry, x, y, require_paint, overlay_only),
	)
}

GuiObject_hit_chain :: proc(registry: ^Registry, x, y: f32) -> [dynamic]^GuiObject {
	result := GuiObject_hit_chain_ex(registry, x, y)
	return result.chain
}

GuiObject_pointer_point :: proc(
	registry: ^Registry,
	gui: ^GuiObject,
	screen_x, screen_y: f32,
) -> (
	x, y: f32,
	ok: bool,
) {
	surface := gui_object_containing_surface(gui)
	if surface == nil {
		return screen_x, screen_y, true
	}

	x, y, ok = surfacegui_hit_test_for(surface, screen_x, screen_y)
	if ok {
		surface.pointer_x = x
		surface.pointer_y = y
		surface.pointer_valid = true
		return
	}

	if surface.pointer_valid {
		return surface.pointer_x, surface.pointer_y, false
	}

	return screen_x, screen_y, false
}

GuiObject_surface_pointer_over :: proc(
	registry: ^Registry,
	x, y: f32,
	require_paint: bool = true,
) -> bool {
	surface, canvas_x, canvas_y, hit := surfacegui_hit_test(registry, x, y)
	if !hit {
		return false
	}

	return GuiObject_find_topmost_in_surface(surface, canvas_x, canvas_y, require_paint) != nil
}

GuiObject_in_hit_chain :: proc(registry: ^Registry, gui: ^GuiObject, x, y: f32) -> bool {
	if registry == nil || gui == nil {
		return false
	}

	chain := GuiObject_hit_chain(registry, x, y)
	defer delete(chain)

	for candidate in chain {
		if candidate == gui {
			return true
		}
	}

	return false
}

gui_object_mouse_type :: proc(button: u8) -> enums.UserInputType {
	switch button {
	case sdl3.BUTTON_LEFT:
		return .MouseButton1

	case sdl3.BUTTON_RIGHT:
		return .MouseButton2

	case sdl3.BUTTON_MIDDLE:
		return .MouseButton3
	}

	return .None
}

gui_object_mouse_index :: proc(button: u8) -> int {
	switch button {
	case sdl3.BUTTON_LEFT:
		return 0

	case sdl3.BUTTON_RIGHT:
		return 1

	case sdl3.BUTTON_MIDDLE:
		return 2
	}

	return -1
}

gui_object_fire_xy :: proc(L: ^vm.State, signal: ^signals.Signal, x, y: f32) {
	if L == nil || signal == nil {
		return
	}

	vm.PushNumber(L, f64(x))
	vm.PushNumber(L, f64(y))

	signals.Fire(L, signal, 2)

	vm.Pop(L, 2)
}

gui_object_fire_input :: proc(
	L: ^vm.State,
	registry: ^Registry,
	signal: ^signals.Signal,
	value: InputObject_Value,
) {
	if L == nil || registry == nil || signal == nil {
		return
	}

	input := Push_InputObject(L, registry, value)
	if input == nil {
		return
	}

	signals.Fire(L, signal, 1)

	vm.Pop(L)

	Destroy_Hierarchy(&input.object)
}

GuiObject_Handle_Event :: proc(registry: ^Registry, L: ^vm.State, event: sdl3.Event) {
	if registry == nil || L == nil {
		return
	}

	if !UIScaleDetector_Handle_Event(registry, L, event) {
		UIDragDetector_Handle_Event(registry, L, event)
	}
	UIDragDetector_Handle_Event(registry, L, event)

	#partial switch event.type {
	case .MOUSE_MOTION:
		result := GuiObject_hit_chain_ex(registry, f32(event.motion.x), f32(event.motion.y))
		defer delete(result.chain)

		chain := result.chain

		for descriptor in registry.classes {
			for object in descriptor.instances {
				if object == nil || object.destroyed || !Is_A(object, "GuiObject") {
					continue
				}

				gui := cast(^GuiObject)object

				inside := false

				for candidate in chain {
					if candidate == gui {
						inside = true
						break
					}
				}

				if inside != gui.mouse_inside {
					gui.mouse_inside = inside

					GuiObject_ensure_signals(gui)

					if inside {
						gui_object_fire_xy(L, gui.mouse_enter, result.x, result.y)
					} else {
						gui_object_fire_xy(L, gui.mouse_leave, result.x, result.y)
					}
				}
			}
		}

		for target in chain {
			if target.destroyed {
				continue
			}

			GuiObject_ensure_signals(target)

			gui_object_fire_xy(L, target.mouse_moved, result.x, result.y)

			if target.active {
				gui_object_fire_input(
					L,
					registry,
					target.input_changed,
					InputObject_Value {
						UserInputType = .MouseMovement,
						UserInputState = .Change,
						Position = {result.x, result.y, 0},
						Delta = {event.motion.xrel, event.motion.yrel, 0},
					},
				)
			}
		}

	case .MOUSE_BUTTON_DOWN:
		index := gui_object_mouse_index(event.button.button)

		if index < 0 {
			return
		}

		input_type := gui_object_mouse_type(event.button.button)

		hit := GuiObject_hit_test(registry, f32(event.button.x), f32(event.button.y))

		if hit.target == nil {
			return
		}

		gui := hit.target

		gui.mouse_input_down[index] = true

		GuiObject_ensure_signals(gui)

		gui_object_fire_input(
			L,
			registry,
			gui.input_began,
			InputObject_Value {
				UserInputType = input_type,
				UserInputState = .Begin,
				Position = {hit.x, hit.y, 0},
			},
		)

	case .MOUSE_BUTTON_UP:
		index := gui_object_mouse_index(event.button.button)

		if index < 0 {
			return
		}

		input_type := gui_object_mouse_type(event.button.button)

		for descriptor in registry.classes {
			for object in descriptor.instances {
				if object == nil || object.destroyed || !Is_A(object, "GuiObject") {
					continue
				}

				gui := cast(^GuiObject)object

				if !gui.mouse_input_down[index] {
					continue
				}

				gui.mouse_input_down[index] = false

				GuiObject_ensure_signals(gui)

				point_x, point_y, _ := GuiObject_pointer_point(
					registry,
					gui,
					f32(event.button.x),
					f32(event.button.y),
				)

				gui_object_fire_input(
					L,
					registry,
					gui.input_ended,
					InputObject_Value {
						UserInputType = input_type,
						UserInputState = .End,
						Position = {point_x, point_y, 0},
					},
				)
			}
		}

	case .MOUSE_WHEEL:
		hit := GuiObject_hit_test(registry, f32(event.wheel.mouse_x), f32(event.wheel.mouse_y))

		if hit.target == nil {
			return
		}

		gui := hit.target

		GuiObject_ensure_signals(gui)

		gui_object_fire_input(
			L,
			registry,
			gui.input_changed,
			InputObject_Value {
				UserInputType = .MouseWheel,
				UserInputState = .Change,
				Position = {hit.x, hit.y, event.wheel.y},
				Delta = {event.wheel.x, 0, event.wheel.y},
			},
		)

		wheel_y := f32(event.wheel.y)

		when ODIN_OS != .JS {
			if event.wheel.direction == .FLIPPED {
				wheel_y = -wheel_y
			}
		}

		if wheel_y > 0 {
			gui_object_fire_xy(L, gui.mouse_wheel_forward, hit.x, hit.y)
		} else if wheel_y < 0 {
			gui_object_fire_xy(L, gui.mouse_wheel_backward, hit.x, hit.y)
		}
	}
}

gui_parent_basis_size :: proc(gui: ^GuiObject, ctx: ^Class_Step_Context) -> (width, height: f32) {
	parent := gui.object.parent

	if parent == nil {
		return f32(ctx.viewport_width), f32(ctx.viewport_height)
	}

	if Is_A(parent, "GuiObject") {
		parent_gui := cast(^GuiObject)parent

		if parent_gui.previous_size_valid {
			return parent_gui.previous_size.X, parent_gui.previous_size.Y
		}

		return parent_gui.base_size.X, parent_gui.base_size.Y
	}

	_, _, width, height = GuiObject_get_absolute_transform(parent, ctx)

	if width <= 0 {
		width = f32(ctx.viewport_width)
	}

	if height <= 0 {
		height = f32(ctx.viewport_height)
	}

	return
}

gui_effective_size :: proc(
	gui: ^GuiObject,
	parent_width, parent_height: f32,
) -> (
	width, height: f32,
) {
	if gui == nil {
		return
	}

	if gui.layout_override_size_active {
		return gui.layout_override_size.X, gui.layout_override_size.Y
	}

	if gui.resolved_size_valid {
		return gui.resolved_size.X, gui.resolved_size.Y
	}

	if gui.base_solved {
		return gui.base_size.X, gui.base_size.Y
	}

	width = gui.size.X_Scale * parent_width + gui.size.X_Offset
	height = gui.size.Y_Scale * parent_height + gui.size.Y_Offset
	return
}

gui_automatic_size_limits :: proc(
	gui: ^GuiObject,
	registry: ^Registry,
	ctx: ^Class_Step_Context,
) -> (
	max_x, max_y: f32,
	clamp_x, clamp_y: bool,
) {
	parent := gui.object.parent

	if parent == nil {
		return f32(ctx.viewport_width), f32(ctx.viewport_height), true, true
	}

	if Is_A(parent, "GuiObject") {
		parent_gui := cast(^GuiObject)parent

		parent_width := parent_gui.resolved_size.X
		parent_height := parent_gui.resolved_size.Y

		if !parent_gui.resolved_size_valid {
			parent_width = parent_gui.base_size.X
			parent_height = parent_gui.base_size.Y
		}

		clamp_x = parent_gui.automatic_size != .X && parent_gui.automatic_size != .XY
		clamp_y = parent_gui.automatic_size != .Y && parent_gui.automatic_size != .XY

		left, right, top, bottom, _ := gui_resolve_uipadding(
			parent_gui,
			registry,
			parent_width,
			parent_height,
		)

		max_x = max(f32(0), parent_width - left - right)
		max_y = max(f32(0), parent_height - top - bottom)
		return
	}

	_, _, parent_width, parent_height := GuiObject_get_absolute_transform(parent, ctx)

	return max(f32(0), parent_width), max(f32(0), parent_height), true, true
}

gui_automatic_size_allows_y :: proc(gui: ^GuiObject) -> bool {
	switch {
	case Is_A(&gui.object, "TextLabel"):
		return (cast(^TextLabel)gui).text_wrapped
	case Is_A(&gui.object, "TextButton"):
		return (cast(^TextButton)gui).text_wrapped
	case Is_A(&gui.object, "TextBox"):
		return (cast(^TextBox)gui).wrap
	}

	return true
}


gui_resolve_uipadding :: proc(
	gui: ^GuiObject,
	registry: ^Registry,
	basis_width, basis_height: f32,
) -> (
	left, right, top, bottom: f32,
	found: bool,
) {
	if gui == nil {
		return
	}

	for child in gui.object.children {
		if child == nil || child.destroyed || !Is_A(child, "UIPadding") {
			continue
		}

		padding := cast(^UIPadding)child

		left = gui_resolve_udim(padding.padding_left, basis_width)
		right = gui_resolve_udim(padding.padding_right, basis_width)
		top = gui_resolve_udim(padding.padding_top, basis_height)
		bottom = gui_resolve_udim(padding.padding_bottom, basis_height)

		found = true

		return
	}

	return
}


GuiObject_Measure_Content :: proc(gui: ^GuiObject, registry: ^Registry) -> datatypes.Vector2 {
	if gui == nil {
		return datatypes.Vector2_Zero
	}

	basis_width := gui.resolved_size.X
	basis_height := gui.resolved_size.Y

	if !gui.resolved_size_valid {
		basis_width = gui.base_size.X
		basis_height = gui.base_size.Y
	}

	width: f32 = 0
	height: f32 = 0

	is_text := false
	text_content := datatypes.Vector2_Zero

	switch {
	case Is_A(&gui.object, "TextLabel"):
		text_content = TextLabel_Measure_Content(cast(^TextLabel)gui, basis_width)
		is_text = true
	case Is_A(&gui.object, "TextButton"):
		button := cast(^TextButton)gui
		label := TextButton_to_text_label(button)
		text_content = TextLabel_Measure_Content(&label, basis_width)
		is_text = true
	case Is_A(&gui.object, "TextBox"):
		text_content = TextBox_Measure_Content(cast(^TextBox)gui, basis_width)
		is_text = true
	}

	if is_text {
		width = text_content.X
		height = text_content.Y
	} else {
		layout_width: f32 = 0
		layout_height: f32 = 0
		has_layout := false

		min_x: f32 = 0
		min_y: f32 = 0
		max_x: f32 = 0
		max_y: f32 = 0

		for object in gui.object.children {
			if object == nil || object.destroyed {
				continue
			}

			if Is_A(object, "UIListLayout") {
				layout := cast(^UIListLayout)object
				if layout.enabled {
					layout_width = layout.absolute_content_size.X
					layout_height = layout.absolute_content_size.Y
					has_layout = true
				}
			} else if Is_A(object, "UIGridLayout") {
				layout := cast(^UIGridLayout)object
				if layout.enabled {
					layout_width = layout.absolute_content_size.X
					layout_height = layout.absolute_content_size.Y
					has_layout = true
				}
			} else if Is_A(object, "GuiObject") {
				child := cast(^GuiObject)object

				if !child.visible {
					continue
				}

				child_width, child_height := gui_effective_size(child, basis_width, basis_height)

				child_left: f32
				child_top: f32

				if child.layout_override_active {
					child_left = child.layout_override_position.X
					child_top = child.layout_override_position.Y
				} else {
					x_udim := datatypes.UDim{child.position.X_Scale, child.position.X_Offset}
					y_udim := datatypes.UDim{child.position.Y_Scale, child.position.Y_Offset}

					child_left =
						gui_resolve_udim(x_udim, basis_width) - child.anchorpoint.X * child_width
					child_top =
						gui_resolve_udim(y_udim, basis_height) - child.anchorpoint.Y * child_height
				}

				child_right := child_left + child_width
				child_bottom := child_top + child_height

				max_x = max(max_x, child_right)
				max_y = max(max_y, child_bottom)

				min_x = min(min_x, child_left)
				min_y = min(min_y, child_top)
			}
		}

		if has_layout {
			width = layout_width
			height = layout_height
		} else {
			width = max_x - min_x
			height = max_y - min_y
		}
	}

	left, right, top, bottom, found := gui_resolve_uipadding(
		gui,
		registry,
		basis_width,
		basis_height,
	)

	if found {
		width = max(width, 0) + left + right
		height = max(height, 0) + top + bottom
	}

	return datatypes.Vector2{width, height}
}

gui_layout_changed: bool
gui_layout_animated: bool




surfacegui_mark_dirty_for :: proc(object: ^Object) {
	current := object

	for current != nil {
		if Is_A(current, "SurfaceGui") {
			surface := cast(^SurfaceGui)current
			surface.render_dirty = true
			return
		}

		current = current.parent
	}
}


GUI_LAYOUT_SKIP_WHEN_CLEAN :: true

gui_layout_dirty: bool = true
gui_layout_last_width: i32
gui_layout_last_height: i32

gui_render_revision: u64

Gui_Layout_Mark_Dirty :: #force_inline proc "contextless" () {
	gui_layout_dirty = true
	gui_render_revision += 1
}

gui_layout_guis: [dynamic]^GuiObject
gui_layout_roots: [dynamic]^GuiObject
gui_layout_layouts: [dynamic]^Object


gui_measure_base :: proc(gui: ^GuiObject, registry: ^Registry, ctx: ^Class_Step_Context) {
	if gui == nil || gui.base_solved {
		return
	}

	gui.base_solved = true

	parent_width, parent_height := gui_parent_basis_size(gui, ctx)

	gui.base_size = {
		gui.size.X_Scale * parent_width + gui.size.X_Offset,
		gui.size.Y_Scale * parent_height + gui.size.Y_Offset,
	}

	for child in gui.object.children {
		if child == nil || child.destroyed || !Is_A(child, "GuiObject") {
			continue
		}

		gui_measure_base(cast(^GuiObject)child, registry, ctx)
	}
}


gui_measure_auto :: proc(gui: ^GuiObject, registry: ^Registry, ctx: ^Class_Step_Context) {
	if gui == nil || gui.auto_solved {
		return
	}

	gui.auto_solved = true

	for child in gui.object.children {
		if child == nil || child.destroyed || !Is_A(child, "GuiObject") {
			continue
		}

		gui_measure_auto(cast(^GuiObject)child, registry, ctx)
	}

	width := gui.base_size.X
	height := gui.base_size.Y

	automatic := gui.automatic_size

	
	
	
	needs_content := automatic != .None
	if !needs_content && Is_A(&gui.object, "ScrollingFrame") {
		needs_content = (cast(^ScrollingFrame)gui).automatic_canvas_size != .None
	}

	content: datatypes.Vector2
	if needs_content {
		content = GuiObject_Measure_Content(gui, registry)
	}

	if automatic != .None {
		max_x, max_y, clamp_x, clamp_y := gui_automatic_size_limits(gui, registry, ctx)

		if automatic == enums.AutomaticSize.X || automatic == enums.AutomaticSize.XY {
			width = max(width, content.X)

			if clamp_x {
				width = min(width, max_x)
			}
		}

		if automatic == enums.AutomaticSize.Y || automatic == enums.AutomaticSize.XY {
			if gui_automatic_size_allows_y(gui) {
				height = max(height, content.Y)

				if clamp_y {
					height = min(height, max_y)
				}
			}
		}
	}

	old := gui.resolved_size

	changed := abs(width - old.X) > 0.01 || abs(height - old.Y) > 0.01
	if needs_content &&
	   (abs(content.X - gui.content_size.X) > 0.01 || abs(content.Y - gui.content_size.Y) > 0.01) {
		changed = true
	}

	if changed {
		gui_layout_changed = true
	}

	if needs_content {
		gui.content_size = content
	}
	gui.resolved_size = {width, height}
	gui.resolved_size_valid = true

	left, _, top, _, _ := gui_resolve_uipadding(gui, registry, width, height)

	gui.content_offset = {left, top}
}

gui_layout_root :: proc(gui: ^GuiObject) -> bool {
	parent := gui.object.parent

	return parent == nil || !Is_A(parent, "GuiObject")
}


gui_compute_transform :: proc(
	gui: ^GuiObject,
	parent_x, parent_y, parent_w, parent_h: f32,
	padding_x, padding_y: f32,
	scroll_x, scroll_y: f32,
) -> (
	x, y, w, h: f32,
) {
	if gui.layout_override_size_active {
		w = gui.layout_override_size.X
		h = gui.layout_override_size.Y
	} else if gui.resolved_size_valid {
		w = gui.resolved_size.X
		h = gui.resolved_size.Y
	} else {
		w = gui.size.X_Scale * parent_w + gui.size.X_Offset
		h = gui.size.Y_Scale * parent_h + gui.size.Y_Offset
	}

	if gui.layout_override_active {
		x = parent_x + gui.layout_override_position.X
		y = parent_y + gui.layout_override_position.Y
	} else {
		x =
			parent_x +
			padding_x +
			gui.position.X_Scale * parent_w +
			gui.position.X_Offset -
			gui.anchorpoint.X * w

		y =
			parent_y +
			padding_y +
			gui.position.Y_Scale * parent_h +
			gui.position.Y_Offset -
			gui.anchorpoint.Y * h
	}

	x -= scroll_x
	y -= scroll_y

	return
}


gui_apply_transforms :: proc(parent: ^GuiObject, px, py, pw, ph: f32) {
	padding_x := parent.content_offset.X
	padding_y := parent.content_offset.Y

	scroll_x: f32 = 0
	scroll_y: f32 = 0

	if Is_A(&parent.object, "ScrollingFrame") {
		scrolling := cast(^ScrollingFrame)parent

		scroll_x = scrolling.canvas_position.X
		scroll_y = scrolling.canvas_position.Y
	}

	for child in parent.object.children {
		if child == nil || child.destroyed || !Is_A(child, "GuiObject") {
			continue
		}

		gui := cast(^GuiObject)child

		x, y, w, h := gui_compute_transform(
			gui,
			px,
			py,
			pw,
			ph,
			padding_x,
			padding_y,
			scroll_x,
			scroll_y,
		)

		gui.absolute_position = {x, y}
		gui.absolute_size = {w, h}

		gui_apply_transforms(gui, x, y, w, h)
	}
}

Update_GUI_Layout :: proc(registry: ^Registry, width, height: i32, delta_time: f32 = 0) {
	if registry == nil {
		return
	}


	when GUI_LAYOUT_SKIP_WHEN_CLEAN {
		if !gui_layout_dirty &&
		   width == gui_layout_last_width &&
		   height == gui_layout_last_height {
			return
		}
	}

	tracy.ZoneNC("Update_GUI_Layout", 0xE5C07B)

	L: ^vm.State

	if registry.vm_state != nil {
		L = registry.vm_state.L
	}

	ctx := Class_Step_Context {
		L               = L,
		delta_time      = delta_time,
		viewport_width  = width,
		viewport_height = height,
	}

	gui_layout_animated = false


	clear(&gui_layout_guis)
	clear(&gui_layout_roots)
	clear(&gui_layout_layouts)

	{
		tracy.ZoneNC("Layout Gather", 0x98C379)

		
		
		
		
		
		for descriptor in registry.classes {
			if descriptor == nil {
				continue
			}

			info := descriptor.info
			is_gui := Is_Class_A(info, &GuiObject_Class)
			is_layout :=
				Is_Class_A(info, &UIListLayout_Class) || Is_Class_A(info, &UIGridLayout_Class)

			if !is_gui && !is_layout {
				continue
			}

			for object in descriptor.instances {
				if object == nil || object.destroyed {
					continue
				}

				if is_gui {
					gui := cast(^GuiObject)object

					append(&gui_layout_guis, gui)

					if gui_layout_root(gui) {
						append(&gui_layout_roots, gui)
					}
				} else {
					append(&gui_layout_layouts, object)
				}
			}
		}
	}

	for _ in 0 ..< 8 {
		for gui in gui_layout_guis {
			gui.previous_size = gui.resolved_size
			gui.previous_size_valid = gui.resolved_size_valid

			gui.layout_override_active = false
			gui.layout_override_position = {}

			gui.layout_override_size_active = false
			gui.layout_override_size = {}

			gui.base_solved = false
			gui.auto_solved = false
			gui.resolved_size_valid = false
		}

		gui_layout_changed = false

		{
			tracy.ZoneNC("Layout Measure Base", 0x61AFEF)

			for gui in gui_layout_roots {
				gui_measure_base(gui, registry, &ctx)
			}
		}

		{
			tracy.ZoneNC("Layout Measure Auto", 0xC678DD)

			for gui in gui_layout_roots {
				gui_measure_auto(gui, registry, &ctx)
			}
		}

		{
			tracy.ZoneNC("Layout Apply Lists/Grids", 0xE06C75)


			for object in gui_layout_layouts {
				if object == nil || object.destroyed {
					continue
				}

				if Is_A_Class(object, &UIListLayout_Class) {
					UIListLayout_Apply(cast(^UIListLayout)object, registry, &ctx)
				} else if Is_A_Class(object, &UIGridLayout_Class) {
					UIGridLayout_Apply(cast(^UIGridLayout)object, registry, &ctx)
				}
			}
		}

		{
			tracy.ZoneNC("Layout Transforms", 0xD19A66)

			for root in gui_layout_roots {
				if root == nil || root.object.destroyed {
					continue
				}

				px, py, pw, ph := GuiObject_get_absolute_transform(root.object.parent, &ctx)

				x, y, w, h := gui_compute_transform(root, px, py, pw, ph, 0, 0, 0, 0)

				root.absolute_position = {x, y}
				root.absolute_size = {w, h}

				gui_apply_transforms(root, x, y, w, h)
			}
		}

		if !gui_layout_changed {
			break
		}
	}

	gui_layout_last_width = width
	gui_layout_last_height = height
	gui_layout_dirty = gui_layout_changed || gui_layout_animated
	if gui_layout_changed {
		gui_render_revision += 1
	}
}

GuiObject_get_rect :: proc(object: ^Object, ctx: ^Class_Step_Context) -> (guilib.Rect, bool) {
	gui := cast(^GuiObject)object

	if !gui.visible {
		return guilib.Rect{}, false
	}

	if ctx == nil || ctx.renderer == nil || ctx.renderer.SkiaSurface == nil {
		return guilib.Rect{}, false
	}

	x, y, width, height := GuiObject_get_absolute_transform(object, ctx)

	return guilib.Rect {
			x = x,
			y = y,
			width = width,
			height = height,
			color = gui.bg_color,
			bgTransparency = f32(gui.bg_transparency),
		},
		true
}

gui_resolve_udim :: proc(value: datatypes.UDim, basis: f32) -> f32 {
	return value.Scale * basis + value.Offset
}

gui_corner_radius :: proc(corner_object: ^Object, rect: guilib.Rect) -> f32 {
	if corner_object == nil {
		return 0
	}

	corner := cast(^UICorner)corner_object
	short_edge := min(rect.width, rect.height)
	radius := gui_resolve_udim(corner.corner_radius, short_edge)
	return clamp(radius, f32(0), short_edge * 0.5)
}

Gui_Corner_Shape :: enum u8 {
	None,
	Round,
	Squircle,
}

Gui_Shape :: struct {
	kind:     Gui_Corner_Shape,
	radius:   f32,
	tl:       f32,
	tr:       f32,
	br:       f32,
	bl:       f32,
	exponent: f32,
}



gui_corner_shape :: proc(object: ^Object, rect: guilib.Rect) -> Gui_Shape {
	short_edge := min(rect.width, rect.height)
	max_radius := short_edge * 0.5

	if squircle_object := Find_First_Child_Of_Class(object, "UISquircle"); squircle_object != nil {
		squircle := cast(^UISquircle)squircle_object
		base := clamp(gui_resolve_udim(squircle.radius, short_edge), f32(0), max_radius)

		tl := gui_resolve_udim(squircle.top_left_radius, short_edge)
		tr := gui_resolve_udim(squircle.top_right_radius, short_edge)
		br := gui_resolve_udim(squircle.bottom_right_radius, short_edge)
		bl := gui_resolve_udim(squircle.bottom_left_radius, short_edge)

		if tl <= 0 {tl = base}
		if tr <= 0 {tr = base}
		if br <= 0 {br = base}
		if bl <= 0 {bl = base}

		return Gui_Shape {
			kind = .Squircle,
			radius = base,
			tl = clamp(tl, f32(0), max_radius),
			tr = clamp(tr, f32(0), max_radius),
			br = clamp(br, f32(0), max_radius),
			bl = clamp(bl, f32(0), max_radius),
			exponent = max(f32(2), f32(squircle.exponent)),
		}
	}

	corner_object := Find_First_Child_Of_Class(object, "UICorner")
	radius := gui_corner_radius(corner_object, rect)
	if radius > 0 {
		return Gui_Shape {
			kind = .Round,
			radius = radius,
			tl = radius,
			tr = radius,
			br = radius,
			bl = radius,
			exponent = 2,
		}
	}

	return Gui_Shape{kind = .None, exponent = 2}
}

gui_render_children :: proc(
	gui: ^GuiObject,
	object: ^Object,
	ctx: ^Class_Step_Context,
	rect: guilib.Rect,
	shape: Gui_Shape,
) {
	if len(object.children) == 0 {return}
	scrolling_frame_virtualized := false
	if Is_A_Class(object, &ScrollingFrame_Class) {
		scrolling_frame_virtualized = (cast(^ScrollingFrame)object).virtualized_scrolling
	}

	if !gui.clips_descendants {
		if scrolling_frame_virtualized {
			ScreenGui_RenderChildren_Visible(object, ctx, rect)
		} else {
			ScreenGui_RenderChildren(object, ctx)
		}
		return
	}

	guilib.save(ctx.renderer.SkiaSurface)
	switch shape.kind {
	case .Squircle:
		guilib.clipSquircleCorners(
			ctx.renderer.SkiaSurface,
			rect,
			shape.tl,
			shape.tr,
			shape.br,
			shape.bl,
			shape.exponent,
		)
	case .Round:
		guilib.clipRoundedRect(ctx.renderer.SkiaSurface, rect, shape.radius)
	case .None:
		guilib.clipRect(ctx.renderer.SkiaSurface, rect)
	}
	if scrolling_frame_virtualized {
		ScreenGui_RenderChildren_Visible(object, ctx, rect)
	} else {
		ScreenGui_RenderChildren(object, ctx)
	}
	guilib.restore(ctx.renderer.SkiaSurface)
}

GuiObject_push_rotation :: proc(gui: ^GuiObject, ctx: ^Class_Step_Context) -> bool {
	if gui == nil || gui.rotation == 0 {
		return false
	}
	if ctx == nil || ctx.renderer == nil || ctx.renderer.SkiaSurface == nil {
		return false
	}

	x, y, width, height := GuiObject_get_absolute_transform(&gui.object, ctx)
	center_x := x + width * 0.5
	center_y := y + height * 0.5

	guilib.save(ctx.renderer.SkiaSurface)
	guilib.translate(ctx.renderer.SkiaSurface, center_x, center_y)
	guilib.rotate(ctx.renderer.SkiaSurface, f32(gui.rotation))
	guilib.translate(ctx.renderer.SkiaSurface, -center_x, -center_y)
	return true
}

GuiObject_pop_rotation :: proc(ctx: ^Class_Step_Context) {
	if ctx == nil || ctx.renderer == nil || ctx.renderer.SkiaSurface == nil {
		return
	}

	guilib.restore(ctx.renderer.SkiaSurface)
}

GuiObject_render :: proc(object: ^Object, ctx: ^Class_Step_Context, skip_shadow: bool = false) {
	gui := cast(^GuiObject)object

	rect, visible := GuiObject_get_rect(object, ctx)
	if !visible {
		return
	}

	gui.absolute_position = datatypes.Vector2{rect.x, rect.y}
	gui.absolute_size = datatypes.Vector2{rect.width, rect.height}

	shadow_object := Find_First_Child_Of_Class(object, "UIShadow")
	backdrop_object := Find_First_Child_Of_Class(object, "UIBackdrop")
	stroke_object := Find_First_Child_Of_Class(object, "UIStroke")
	magnifier_object := Find_First_Child_Of_Class(object, "UIMagnifier")
	motion_blur_object := Find_First_Child_Of_Class(object, "UIMotionBlur")

	shape := gui_corner_shape(object, rect)
	corner_radius := shape.radius

	if shadow_object != nil {
		shadow := cast(^UIShadow)shadow_object
		if shadow.enabled {
			short_edge := min(rect.width, rect.height)
			offset_x := shadow.offset.X_Scale * rect.width + shadow.offset.X_Offset
			offset_y := shadow.offset.Y_Scale * rect.height + shadow.offset.Y_Offset
			spread_x := shadow.spread.X_Scale * rect.width + shadow.spread.X_Offset
			spread_y := shadow.spread.Y_Scale * rect.height + shadow.spread.Y_Offset

			params := guilib.ShadowParams {
				offsetX   = offset_x,
				offsetY   = offset_y,
				blurSigma = max(f32(0), gui_resolve_udim(shadow.blur_radius, short_edge)),
				spread    = max(f32(0), (spread_x + spread_y) * 0.5),
				color     = shadow.color,
				alpha     = 1 - f32(shadow.transparency),
			}

			if shadow.showfortext != true && !skip_shadow {
				guilib.drawShadow(
					ctx.renderer.SkiaSurface,
					rect,
					corner_radius,
					f32(shadow.exponent),
					params,
				)
			}
		}
	}

	if backdrop_object != nil {
		backdrop := cast(^UIBackdrop)backdrop_object

		has_effect :=
			backdrop.blur_radius > 0 ||
			backdrop.brightness != 0 ||
			backdrop.contrast != 1 ||
			backdrop.saturation != 1 ||
			backdrop.hue_shift != 0 ||
			backdrop.morphology != 0 ||
			backdrop.displacement > 0 ||
			backdrop.pixelate > 0 ||
			backdrop.zoom != 1

		if backdrop.enabled && (has_effect || backdrop.tint_transparency < 0.999) {
			backdrop_rect := rect
			backdrop_rect.color = backdrop.tint_color
			backdrop_rect.bgTransparency = f32(backdrop.tint_transparency)

			offset_x := gui_resolve_udim(
				datatypes.UDim{Scale = backdrop.offset.X_Scale, Offset = backdrop.offset.X_Offset},
				rect.width,
			)

			offset_y := gui_resolve_udim(
				datatypes.UDim{Scale = backdrop.offset.Y_Scale, Offset = backdrop.offset.Y_Offset},
				rect.height,
			)

			if backdrop.parallax.X != 0 || backdrop.parallax.Y != 0 {
				viewport_center_x := f32(ctx.viewport_width) * 0.5
				viewport_center_y := f32(ctx.viewport_height) * 0.5
				element_center_x := rect.x + rect.width * 0.5
				element_center_y := rect.y + rect.height * 0.5

				offset_x += (viewport_center_x - element_center_x) * f32(backdrop.parallax.X)
				offset_y += (viewport_center_y - element_center_y) * f32(backdrop.parallax.Y)
			}

			params := guilib.BackdropParams {
				cornerRadiusX = corner_radius,
				cornerRadiusY = corner_radius,
				exponent      = f32(backdrop.exponent),
				offsetX       = offset_x,
				offsetY       = offset_y,
				blurSigma     = f32(backdrop.blur_radius),
				brightness    = f32(backdrop.brightness),
				contrast      = f32(backdrop.contrast),
				saturation    = f32(backdrop.saturation),
				hueShift      = f32(backdrop.hue_shift),
				morphology    = f32(backdrop.morphology),
				displacement  = f32(backdrop.displacement),
				pixelate      = f32(backdrop.pixelate),
				zoom          = f32(backdrop.zoom),
			}

			guilib.drawBackdrop(ctx.renderer.SkiaSurface, backdrop_rect, params)
		}
	}

	if gui.bg_transparency < 1 && !UIGradient_Draw_Background(gui, ctx, rect, shape) {
		switch shape.kind {
		case .Squircle:
			guilib.drawSquircleCorners(
				ctx.renderer.SkiaSurface,
				rect,
				shape.tl,
				shape.tr,
				shape.br,
				shape.bl,
				shape.exponent,
				0,
			)
		case .Round:
			guilib.drawRoundedRect(ctx.renderer.SkiaSurface, rect, shape.radius)
		case .None:
			guilib.drawRect(ctx.renderer.SkiaSurface, rect)
		}
	}

	if magnifier_object != nil {
		magnifier := cast(^UIMagnifier)magnifier_object

		if magnifier.enabled && magnifier.zoom > 1 && magnifier.transparency < 1 {
			magnifier_rect := rect
			magnifier_rect.color = datatypes.Color3 {
				R = 1,
				G = 1,
				B = 1,
			}
			magnifier_rect.bgTransparency = f32(magnifier.transparency)

			guilib.drawMagnifier(
				ctx.renderer.SkiaSurface,
				magnifier_rect,
				f32(magnifier.zoom),
				f32(magnifier.inset),
			)
		}
	}

	tracy.ZoneNC("GuiObject Render Children", 0x61AFEF)

	motion_blur_active := false

	if motion_blur_object != nil {
		motion_blur := cast(^UIMotionBlur)motion_blur_object

		if motion_blur.enabled {
			length := gui_resolve_udim(motion_blur.length, min(rect.width, rect.height))

			if length > 0 {
				guilib.beginMotionBlur(
					ctx.renderer.SkiaSurface,
					rect,
					f32(motion_blur.angle),
					length,
				)

				motion_blur_active = true
			}
		}
	}

	if Is_A_Class(object, &ViewportFrame_Class) {
		ViewportFrame_Draw_Image(cast(^ViewportFrame)object, ctx, rect)
	}
	gui_render_children(gui, object, ctx, rect, shape)

	if motion_blur_active {
		guilib.endMotionBlur(ctx.renderer.SkiaSurface)
	}

	if stroke_object != nil {
		stroke := cast(^UIStroke)stroke_object
		if stroke.enabled && stroke.thickness > 0 && stroke.transparency < 1 {
			stroke_rect := rect
			stroke_rect.color = stroke.color
			stroke_rect.bgTransparency = f32(stroke.transparency)

			switch shape.kind {
			case .Squircle:
				guilib.drawSquircleCorners(
					ctx.renderer.SkiaSurface,
					stroke_rect,
					shape.tl,
					shape.tr,
					shape.br,
					shape.bl,
					shape.exponent,
					f32(stroke.thickness),
				)
			case .Round:
				guilib.drawRoundedRectStroke(
					ctx.renderer.SkiaSurface,
					stroke_rect,
					corner_radius,
					f32(stroke.thickness),
				)
			case .None:
				guilib.drawRectStroke(ctx.renderer.SkiaSurface, stroke_rect, f32(stroke.thickness))
			}
		}
	}
}

GuiObject_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	gui_object := cast(^GuiObject)object


	Gui_Layout_Mark_Dirty()

	switch key {
	case "Active":
		gui_object.active = vm.ArgBoolean(L, value_index)
	case "LayoutOrder":
		gui_object.layout_order = i32(vm.ArgNumber(L, value_index))
	case "BackgroundTransparency":
		gui_object.bg_transparency = clamp(vm.ArgNumber(L, value_index), 0.0, 1.0)
	case "ClipsDescendants":
		gui_object.clips_descendants = vm.ArgBoolean(L, value_index)
	case "InputSink":
		gui_object.input_sink = vm.ArgBoolean(L, value_index)
	case "Selectable":
		gui_object.selectable = vm.ArgBoolean(L, value_index)
	case "Visible":
		gui_object.visible = vm.ArgBoolean(L, value_index)
	case "ZIndex":
		gui_object.zindex = i32(vm.ArgNumber(L, value_index))
	case "BorderSizePixel":
		gui_object.border_size_pixels = i32(vm.ArgNumber(L, value_index))
	case "BorderColor3":
		if datatype_registry == nil {
			return false
		}
		gui_object.border_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "BorderMode":
		if enum_registry == nil {return false}
		gui_object.border_mode = enums.BorderMode(
			enums.Arg_Item(L, value_index, enum_registry, "BorderMode").value,
		)
	case "GuiState":
		if enum_registry == nil {return false}
		gui_object.gui_state = enums.GuiState(
			enums.Arg_Item(L, value_index, enum_registry, "GuiState").value,
		)
	case "BackgroundColor3":
		if datatype_registry == nil {return false}
		gui_object.bg_color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Position":
		if datatype_registry == nil {return false}
		gui_object.position = datatypes.Arg_UDim2(L, value_index, datatype_registry)
	case "Size":
		if datatype_registry == nil {return false}
		gui_object.size = datatypes.Arg_UDim2(L, value_index, datatype_registry)
	case "AutomaticSize":
		if enum_registry == nil {return false}
		auto_item := enums.Arg_Item(L, value_index, enum_registry, "AutomaticSize")
		if auto_item == nil {return false}
		gui_object.automatic_size = enums.AutomaticSize(auto_item.value)
	case "AnchorPoint":
		if datatype_registry == nil {return false}
		gui_object.anchorpoint = datatypes.Arg_Vector2(L, value_index, datatype_registry)
	case "Rotation":
		gui_object.rotation = vm.ArgNumber(L, value_index)
	case "AbsolutePosition":
		_ = vm.RaiseError(L, "AbsolutePosition cannot be changed")
	case "AbsoluteSize":
		_ = vm.RaiseError(L, "AbsoluteSize cannot be changed")
	case:
		return false
	}

	return true
}

GuiObject_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^GuiObject)source
	dst := cast(^GuiObject)destination

	Gui_Layout_Mark_Dirty()

	dst.bg_transparency = src.bg_transparency
	dst.bg_color = src.bg_color
	dst.active = src.active
	dst.border_mode = src.border_mode
	dst.clips_descendants = src.clips_descendants
	dst.input_sink = src.input_sink
	dst.position = src.position
	dst.selectable = src.selectable
	dst.size = src.size
	dst.automatic_size = src.automatic_size
	dst.visible = src.visible
	dst.zindex = src.zindex
	dst.anchorpoint = src.anchorpoint
	dst.rotation = src.rotation
	dst.border_size_pixels = src.border_size_pixels
	dst.layout_order = src.layout_order

	dst.layout_override_active = false
	dst.layout_override_position = {}
	dst.layout_override_size_active = false
	dst.layout_override_size = {}
	dst.content_size = {}
	dst.base_size = {}
	dst.resolved_size = {}
	dst.previous_size = {}
	dst.content_offset = {}
	dst.resolved_size_valid = false
	dst.previous_size_valid = false
	dst.base_solved = false
	dst.auto_solved = false
	dst.mouse_inside = false
	dst.mouse_input_down = [3]bool{}
}

Register_GuiObject :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&GuiObject_Class,
		GuiObject_construct,
		GuiObject_destroy,
		get = GuiObject_get,
		set = GuiObject_set,
		clone = GuiObject_clone,
		properties = []string {
			"BorderColor3",
			"BorderSizePixel",
			"Selectable",
			"Active",
			"GuiState",
			"ClipsDescendants",
			"Position",
			"AbsolutePosition",
			"Size",
			"AutomaticSize",
			"BackgroundColor3",
			"BorderMode",
			"AnchorPoint",
			"Rotation",
			"ZIndex",
			"LayoutOrder",
			"InputSink",
			"AbsoluteSize",
			"Visible",
			"BackgroundTransparency",
		},
		events = []string {
			"InputBegan",
			"InputChanged",
			"InputEnded",
			"MouseEnter",
			"MouseLeave",
			"MouseMoved",
			"MouseWheelForward",
			"MouseWheelBackward",
		},
	)
}
