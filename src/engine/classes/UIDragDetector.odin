package classes

import datatypes "../datatypes"
import enums "../enum"
import sdl3 "../platform"
import signals "../signals"
import vm "../vm"
import "core:math"

UIDragDetector_Class := Class_Info {
	name   = "UIDragDetector",
	parent = &Instance_Class,
}

UIDragDetector :: struct {
	using object:         Object,
	enabled:              bool,
	drag_style:           enums.UIDragDetectorDragStyle,
	response_style:       enums.UIDragDetectorResponseStyle,
	drag_axis:            datatypes.Vector2,
	min_drag_translation: datatypes.UDim2,
	max_drag_translation: datatypes.UDim2,
	min_drag_angle:       f64,
	max_drag_angle:       f64,
	drag_start:           ^signals.Signal,
	drag_continue:        ^signals.Signal,
	drag_end:             ^signals.Signal,
	dragging:             bool,
	start_pointer:        datatypes.Vector2,
	start_position:       datatypes.UDim2,
	start_rotation:       f64,
	basis:                datatypes.Vector2,
	pivot:                datatypes.Vector2,
	last_angle:           f32,
	total_angle:          f32,
}

UIDragDetector_Init :: proc() -> UIDragDetector {
	return UIDragDetector {
		object = Object_Init(&UIDragDetector_Class),
		enabled = true,
		drag_style = .TranslatePlane,
		response_style = .Offset,
		drag_axis = datatypes.Vector2{1, 0},
		min_drag_angle = 0,
		max_drag_angle = 0,
	}
}

UIDragDetector_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	detector := new(UIDragDetector)
	detector^ = UIDragDetector_Init()
	detector.name = "UIDragDetector"
	return &detector.object
}

UIDragDetector_ensure_signals :: proc(d: ^UIDragDetector) {
	if d == nil ||
	   d.object.signal_registry == nil ||
	   d.object.signal_registry.signal_registry == nil {
		return
	}

	registry := d.object.signal_registry.signal_registry

	if d.drag_start == nil {d.drag_start = signals.Create(registry)}
	if d.drag_continue == nil {d.drag_continue = signals.Create(registry)}
	if d.drag_end == nil {d.drag_end = signals.Create(registry)}
}

UIDragDetector_free_signals :: proc(d: ^UIDragDetector) {
	if d == nil {
		return
	}
	if d.drag_start != nil {
		signals.Destroy(d.drag_start)
		d.drag_start = nil
	}
	if d.drag_continue != nil {
		signals.Destroy(d.drag_continue)
		d.drag_continue = nil
	}
	if d.drag_end != nil {
		signals.Destroy(d.drag_end)
		d.drag_end = nil
	}
}

UIDragDetector_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	detector := cast(^UIDragDetector)object
	UIDragDetector_free_signals(detector)
	Object_Destroy(object)
	free(detector)
}


ui_drag_detector_basis :: proc(gui: ^GuiObject) -> (w, h: f32) {
	parent := gui.object.parent

	if parent != nil {
		if Is_A(parent, "GuiObject") {
			parent_gui := cast(^GuiObject)parent
			w = parent_gui.absolute_size.X
			h = parent_gui.absolute_size.Y
		} else if Is_A(parent, "ScreenGui") {
			screen := cast(^ScreenGui)parent
			w = screen.size.X
			h = screen.size.Y
		} else if Is_A(parent, "SurfaceGui") {
			surface := cast(^SurfaceGui)parent
			part := surfacegui_target_part(surface)
			w, h = surfacegui_canvas_size(surface, part)
		}
	}

	if w <= 0 {w = f32(gui_layout_last_width)}
	if h <= 0 {h = f32(gui_layout_last_height)}

	return
}

ui_drag_detector_translation_constrained :: proc(d: ^UIDragDetector) -> bool {
	return(
		d.min_drag_translation != (datatypes.UDim2{}) ||
		d.max_drag_translation != (datatypes.UDim2{}) \
	)
}

ui_drag_detector_wrap_angle :: proc(degrees: f32) -> f32 {
	a := degrees
	for a > 180 {a -= 360}
	for a <= -180 {a += 360}
	return a
}

ui_drag_detector_fire :: proc(
	L: ^vm.State,
	registry: ^Registry,
	signal: ^signals.Signal,
	position: datatypes.Vector2,
) {
	if L == nil || registry == nil || registry.datatypes == nil || signal == nil {
		return
	}

	datatypes.Push_Vector2(L, registry.datatypes, position)
	signals.Fire(L, signal, 1)
	vm.Pop(L)
}

ui_drag_detector_begin :: proc(
	d: ^UIDragDetector,
	gui: ^GuiObject,
	registry: ^Registry,
	L: ^vm.State,
	x, y: f32,
) {
	basis_w, basis_h := ui_drag_detector_basis(gui)

	d.dragging = true
	d.start_pointer = {x, y}
	d.start_position = gui.position
	d.start_rotation = gui.rotation
	d.basis = {basis_w, basis_h}

	d.pivot = {
		gui.absolute_position.X + gui.absolute_size.X * 0.5,
		gui.absolute_position.Y + gui.absolute_size.Y * 0.5,
	}
	d.last_angle = math.to_degrees(math.atan2(y - d.pivot.Y, x - d.pivot.X))
	d.total_angle = 0

	UIDragDetector_ensure_signals(d)
	ui_drag_detector_fire(L, registry, d.drag_start, {x, y})
}

ui_drag_detector_update :: proc(d: ^UIDragDetector, gui: ^GuiObject, x, y: f32) {
	switch d.drag_style {
	case .Scriptable:
		return

	case .Rotate:
		current := math.to_degrees(math.atan2(y - d.pivot.Y, x - d.pivot.X))
		d.total_angle += ui_drag_detector_wrap_angle(current - d.last_angle)
		d.last_angle = current

		total := d.total_angle
		if d.min_drag_angle != d.max_drag_angle {
			lo := f32(min(d.min_drag_angle, d.max_drag_angle))
			hi := f32(max(d.min_drag_angle, d.max_drag_angle))
			total = clamp(total, lo, hi)
		}

		gui.rotation = d.start_rotation + f64(total)

	case .TranslatePlane, .TranslateLine:
		dx := x - d.start_pointer.X
		dy := y - d.start_pointer.Y

		if d.drag_style == .TranslateLine {
			ax := d.drag_axis.X
			ay := d.drag_axis.Y
			length := math.sqrt(ax * ax + ay * ay)

			if length < 1e-5 {
				ax, ay = 1, 0
			} else {
				ax /= length
				ay /= length
			}

			projected := dx * ax + dy * ay
			dx = projected * ax
			dy = projected * ay
		}

		if ui_drag_detector_translation_constrained(d) {
			min_x := gui_resolve_udim(
				{d.min_drag_translation.X_Scale, d.min_drag_translation.X_Offset},
				d.basis.X,
			)
			max_x := gui_resolve_udim(
				{d.max_drag_translation.X_Scale, d.max_drag_translation.X_Offset},
				d.basis.X,
			)
			min_y := gui_resolve_udim(
				{d.min_drag_translation.Y_Scale, d.min_drag_translation.Y_Offset},
				d.basis.Y,
			)
			max_y := gui_resolve_udim(
				{d.max_drag_translation.Y_Scale, d.max_drag_translation.Y_Offset},
				d.basis.Y,
			)

			dx = clamp(dx, min(min_x, max_x), max(min_x, max_x))
			dy = clamp(dy, min(min_y, max_y), max(min_y, max_y))
		}

		pos := d.start_position

		#partial switch d.response_style {
		case .Offset:
			pos.X_Offset += dx
			pos.Y_Offset += dy
		case .Scale:
			if d.basis.X > 0 {pos.X_Scale += dx / d.basis.X}
			if d.basis.Y > 0 {pos.Y_Scale += dy / d.basis.Y}
		}

		gui.position = pos
	}

	Gui_Layout_Mark_Dirty()
	surfacegui_mark_dirty_for(&gui.object)
}

ui_drag_detector_end :: proc(
	d: ^UIDragDetector,
	registry: ^Registry,
	L: ^vm.State,
	position: datatypes.Vector2,
) {
	if !d.dragging {
		return
	}

	d.dragging = false
	UIDragDetector_ensure_signals(d)
	ui_drag_detector_fire(L, registry, d.drag_end, position)
}


UIDragDetector_Handle_Event :: proc(registry: ^Registry, L: ^vm.State, event: sdl3.Event) {
	if registry == nil || L == nil {
		return
	}

	descriptor := Find_Class(registry, "UIDragDetector")
	if descriptor == nil || len(descriptor.instances) == 0 {
		return
	}

	#partial switch event.type {
	case .MOUSE_BUTTON_DOWN:
		if event.button.button != sdl3.BUTTON_LEFT {
			return
		}

		result := GuiObject_hit_chain_ex(registry, f32(event.button.x), f32(event.button.y))
		defer delete(result.chain)

		if len(result.chain) == 0 {
			return
		}

		for object in descriptor.instances {
			if object == nil || object.destroyed {
				continue
			}

			d := cast(^UIDragDetector)object

			if !d.enabled || d.dragging {
				continue
			}

			if d.object.parent == nil || !Is_A(d.object.parent, "GuiObject") {
				continue
			}

			gui := cast(^GuiObject)d.object.parent

			in_chain := false
			for candidate in result.chain {
				if candidate == gui {
					in_chain = true
					break
				}
			}

			if in_chain {
				ui_drag_detector_begin(d, gui, registry, L, result.x, result.y)
			}
		}

	case .MOUSE_MOTION:
		for object in descriptor.instances {
			if object == nil || object.destroyed {
				continue
			}

			d := cast(^UIDragDetector)object

			if !d.dragging {
				continue
			}

			if d.object.parent == nil || !Is_A(d.object.parent, "GuiObject") {
				d.dragging = false
				continue
			}

			gui := cast(^GuiObject)d.object.parent

			x, y, _ := GuiObject_pointer_point(
				registry,
				gui,
				f32(event.motion.x),
				f32(event.motion.y),
			)

			ui_drag_detector_update(d, gui, x, y)

			UIDragDetector_ensure_signals(d)
			ui_drag_detector_fire(L, registry, d.drag_continue, {x, y})
		}

	case .MOUSE_BUTTON_UP:
		if event.button.button != sdl3.BUTTON_LEFT {
			return
		}

		for object in descriptor.instances {
			if object == nil || object.destroyed {
				continue
			}

			d := cast(^UIDragDetector)object

			if !d.dragging {
				continue
			}

			x, y := f32(event.button.x), f32(event.button.y)

			if d.object.parent != nil && Is_A(d.object.parent, "GuiObject") {
				x, y, _ = GuiObject_pointer_point(registry, cast(^GuiObject)d.object.parent, x, y)
			}

			ui_drag_detector_end(d, registry, L, {x, y})
		}
	}
}


UIDragDetector_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	d := cast(^UIDragDetector)object

	switch key {
	case "Enabled":
		vm.PushBoolean(L, d.enabled)

	case "DragStyle":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"UIDragDetectorDragStyle",
			i64(d.drag_style),
		)

	case "ResponseStyle":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"UIDragDetectorResponseStyle",
			i64(d.response_style),
		)

	case "DragAxis":
		if datatype_registry == nil {return false}
		datatypes.Push_Vector2(L, datatype_registry, d.drag_axis)

	case "MinDragTranslation":
		if datatype_registry == nil {return false}
		datatypes.Push_UDim2(L, datatype_registry, d.min_drag_translation)

	case "MaxDragTranslation":
		if datatype_registry == nil {return false}
		datatypes.Push_UDim2(L, datatype_registry, d.max_drag_translation)

	case "MinDragAngle":
		vm.PushNumber(L, d.min_drag_angle)

	case "MaxDragAngle":
		vm.PushNumber(L, d.max_drag_angle)

	case "DragStart":
		UIDragDetector_ensure_signals(d)
		signals.Push(L, d.drag_start)

	case "DragContinue":
		UIDragDetector_ensure_signals(d)
		signals.Push(L, d.drag_continue)

	case "DragEnd":
		UIDragDetector_ensure_signals(d)
		signals.Push(L, d.drag_end)

	case:
		return false
	}

	return true
}

UIDragDetector_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	d := cast(^UIDragDetector)object

	switch key {
	case "Enabled":
		d.enabled = vm.ArgBoolean(L, value_index)
		if !d.enabled {
			d.dragging = false
		}

	case "DragStyle":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "UIDragDetectorDragStyle")
		if item == nil {return false}
		d.drag_style = enums.UIDragDetectorDragStyle(item.value)

	case "ResponseStyle":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "UIDragDetectorResponseStyle")
		if item == nil {return false}
		d.response_style = enums.UIDragDetectorResponseStyle(item.value)

	case "DragAxis":
		if datatype_registry == nil {return false}
		d.drag_axis = datatypes.Arg_Vector2(L, value_index, datatype_registry)

	case "MinDragTranslation":
		if datatype_registry == nil {return false}
		d.min_drag_translation = datatypes.Arg_UDim2(L, value_index, datatype_registry)

	case "MaxDragTranslation":
		if datatype_registry == nil {return false}
		d.max_drag_translation = datatypes.Arg_UDim2(L, value_index, datatype_registry)

	case "MinDragAngle":
		d.min_drag_angle = vm.ArgNumber(L, value_index)

	case "MaxDragAngle":
		d.max_drag_angle = vm.ArgNumber(L, value_index)

	case:
		return false
	}

	return true
}

UIDragDetector_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UIDragDetector)source
	dst := cast(^UIDragDetector)destination

	dst.enabled = src.enabled
	dst.drag_style = src.drag_style
	dst.response_style = src.response_style
	dst.drag_axis = src.drag_axis
	dst.min_drag_translation = src.min_drag_translation
	dst.max_drag_translation = src.max_drag_translation
	dst.min_drag_angle = src.min_drag_angle
	dst.max_drag_angle = src.max_drag_angle

	dst.dragging = false
}

Register_UIDragDetector :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UIDragDetector_Class,
		UIDragDetector_construct,
		UIDragDetector_destroy,
		get = UIDragDetector_get,
		set = UIDragDetector_set,
		clone = UIDragDetector_clone,
		properties = []string {
			"Enabled",
			"DragStyle",
			"ResponseStyle",
			"DragAxis",
			"MinDragTranslation",
			"MaxDragTranslation",
			"MinDragAngle",
			"MaxDragAngle",
		},
		events = []string{"DragStart", "DragContinue", "DragEnd"},
	)
}
