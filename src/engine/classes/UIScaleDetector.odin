package classes

import datatypes "../datatypes"
import enums "../enum"
import sdl3 "../platform"
import signals "../signals"
import vm "../vm"
import "core:math"

UIScaleDetector_Class := Class_Info {
	name   = "UIScaleDetector",
	parent = &Instance_Class,
}

UIScaleDetector :: struct {
	using object:       Object,
	enabled:            bool,
	scale_style:        enums.UIScaleDetectorScaleStyle,
	response_style:     enums.UIScaleDetectorResponseStyle,
	edge_thickness:     f64,
	keep_aspect_ratio:  bool,
	scale_from_center:  bool,
	min_size:           datatypes.Vector2,
	max_size:           datatypes.Vector2,
	scale_start:        ^signals.Signal,
	scale_continue:     ^signals.Signal,
	scale_end:          ^signals.Signal,
	scaling:            bool,
	edge_left:          bool,
	edge_right:         bool,
	edge_top:           bool,
	edge_bottom:        bool,
	start_pointer:      datatypes.Vector2,
	start_abs_position: datatypes.Vector2,
	start_abs_size:     datatypes.Vector2,
	start_position:     datatypes.UDim2,
	start_size:         datatypes.UDim2,
	basis:              datatypes.Vector2,
	pivot:              datatypes.Vector2,
	start_distance:     f32,
	last_size:          datatypes.Vector2,
}

UIScaleDetector_Init :: proc() -> UIScaleDetector {
	return UIScaleDetector {
		object = Object_Init(&UIScaleDetector_Class),
		enabled = true,
		scale_style = .Edges,
		response_style = .Offset,
		edge_thickness = 6,
		keep_aspect_ratio = false,
		scale_from_center = false,
		min_size = datatypes.Vector2{10, 10},
		max_size = datatypes.Vector2{0, 0},
	}
}

UIScaleDetector_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	detector := new(UIScaleDetector)
	detector^ = UIScaleDetector_Init()
	detector.name = "UIScaleDetector"
	return &detector.object
}

UIScaleDetector_ensure_signals :: proc(d: ^UIScaleDetector) {
	if d == nil ||
	   d.object.signal_registry == nil ||
	   d.object.signal_registry.signal_registry == nil {
		return
	}

	registry := d.object.signal_registry.signal_registry

	if d.scale_start == nil {d.scale_start = signals.Create(registry)}
	if d.scale_continue == nil {d.scale_continue = signals.Create(registry)}
	if d.scale_end == nil {d.scale_end = signals.Create(registry)}
}

UIScaleDetector_free_signals :: proc(d: ^UIScaleDetector) {
	if d == nil {
		return
	}
	if d.scale_start != nil {
		signals.Destroy(d.scale_start)
		d.scale_start = nil
	}
	if d.scale_continue != nil {
		signals.Destroy(d.scale_continue)
		d.scale_continue = nil
	}
	if d.scale_end != nil {
		signals.Destroy(d.scale_end)
		d.scale_end = nil
	}
}

UIScaleDetector_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	detector := cast(^UIScaleDetector)object
	UIScaleDetector_free_signals(detector)
	Object_Destroy(object)
	free(detector)
}


ui_scale_detector_fire :: proc(
	L: ^vm.State,
	registry: ^Registry,
	signal: ^signals.Signal,
	value: datatypes.Vector2,
) {
	if L == nil || registry == nil || registry.datatypes == nil || signal == nil {
		return
	}

	datatypes.Push_Vector2(L, registry.datatypes, value)
	signals.Fire(L, signal, 1)
	vm.Pop(L)
}

ui_scale_detector_clamp_axis :: proc(value, lo, hi: f32) -> f32 {
	v := max(value, lo, 1)
	if hi > 0 {
		v = min(v, max(hi, lo))
	}
	return v
}


ui_scale_detector_zone :: proc(
	d: ^UIScaleDetector,
	gui: ^GuiObject,
	x, y: f32,
) -> (
	left, right, top, bottom: bool,
	ok: bool,
) {
	if d.scale_style == .Uniform {
		return false, false, false, false, true
	}

	local_x, local_y := GuiObject_screen_to_local(gui, x, y)

	pos := gui.absolute_position
	size := gui.absolute_size

	band_x := min(f32(d.edge_thickness), size.X * 0.5)
	band_y := min(f32(d.edge_thickness), size.Y * 0.5)

	left = local_x - pos.X <= band_x
	right = pos.X + size.X - local_x <= band_x
	top = local_y - pos.Y <= band_y
	bottom = pos.Y + size.Y - local_y <= band_y

	horizontal := left || right
	vertical := top || bottom

	switch d.scale_style {
	case .Edges:
		ok = horizontal || vertical
	case .Corners:
		ok = horizontal && vertical
	case .Uniform:
		ok = true
	}

	return
}

ui_scale_detector_begin :: proc(
	d: ^UIScaleDetector,
	gui: ^GuiObject,
	registry: ^Registry,
	L: ^vm.State,
	x, y: f32,
	left, right, top, bottom: bool,
) {
	basis_w, basis_h := ui_drag_detector_basis(gui)

	d.scaling = true
	d.edge_left, d.edge_right, d.edge_top, d.edge_bottom = left, right, top, bottom

	d.start_pointer = {x, y}
	d.start_abs_position = gui.absolute_position
	d.start_abs_size = gui.absolute_size
	d.start_position = gui.position
	d.start_size = gui.size
	d.basis = {basis_w, basis_h}
	d.last_size = gui.absolute_size

	d.pivot = {
		gui.absolute_position.X + gui.absolute_size.X * 0.5,
		gui.absolute_position.Y + gui.absolute_size.Y * 0.5,
	}

	dx := x - d.pivot.X
	dy := y - d.pivot.Y
	d.start_distance = max(math.sqrt(dx * dx + dy * dy), 1)

	UIScaleDetector_ensure_signals(d)
	ui_scale_detector_fire(L, registry, d.scale_start, {x, y})
}

ui_scale_detector_update :: proc(d: ^UIScaleDetector, gui: ^GuiObject, x, y: f32) {
	sw := d.start_abs_size.X
	sh := d.start_abs_size.Y

	uniform := d.scale_style == .Uniform
	from_center := d.scale_from_center || uniform

	w := sw
	h := sh

	if uniform {
		dx := x - d.pivot.X
		dy := y - d.pivot.Y
		factor := math.sqrt(dx * dx + dy * dy) / d.start_distance
		w = sw * factor
		h = sh * factor
	} else {
		dx := x - d.start_pointer.X
		dy := y - d.start_pointer.Y
		mult: f32 = from_center ? 2 : 1

		if d.edge_left {
			w = sw - dx * mult
		} else if d.edge_right {
			w = sw + dx * mult
		}

		if d.edge_top {
			h = sh - dy * mult
		} else if d.edge_bottom {
			h = sh + dy * mult
		}
	}

	min_w, max_w := d.min_size.X, d.max_size.X
	min_h, max_h := d.min_size.Y, d.max_size.Y

	if (d.keep_aspect_ratio || uniform) && sw > 0 && sh > 0 {
		ratio := sw / sh
		horizontal := d.edge_left || d.edge_right
		vertical := d.edge_top || d.edge_bottom

		drive_w: bool
		if uniform || horizontal == vertical {
			drive_w = abs(w / sw - 1) >= abs(h / sh - 1)
		} else {
			drive_w = horizontal
		}

		if drive_w {
			w = ui_scale_detector_clamp_axis(w, min_w, max_w)
			h = ui_scale_detector_clamp_axis(w / ratio, min_h, max_h)
			w = h * ratio
		} else {
			h = ui_scale_detector_clamp_axis(h, min_h, max_h)
			w = ui_scale_detector_clamp_axis(h * ratio, min_w, max_w)
			h = w / ratio
		}
	} else {
		w = ui_scale_detector_clamp_axis(w, min_w, max_w)
		h = ui_scale_detector_clamp_axis(h, min_h, max_h)
	}


	new_x := d.start_abs_position.X
	new_y := d.start_abs_position.Y

	if from_center {
		new_x += (sw - w) * 0.5
		new_y += (sh - h) * 0.5
	} else {
		if d.edge_left {new_x += sw - w}
		if d.edge_top {new_y += sh - h}
	}


	size := d.start_size

	switch d.response_style {
	case .Offset:
		size.X_Offset = w - size.X_Scale * d.basis.X
		size.Y_Offset = h - size.Y_Scale * d.basis.Y
	case .Scale:
		if d.basis.X > 0 {size.X_Scale = (w - size.X_Offset) / d.basis.X}
		if d.basis.Y > 0 {size.Y_Scale = (h - size.Y_Offset) / d.basis.Y}
	}


	shift_x := (new_x - d.start_abs_position.X) + gui.anchorpoint.X * (w - sw)
	shift_y := (new_y - d.start_abs_position.Y) + gui.anchorpoint.Y * (h - sh)

	pos := d.start_position

	switch d.response_style {
	case .Offset:
		pos.X_Offset += shift_x
		pos.Y_Offset += shift_y
	case .Scale:
		if d.basis.X > 0 {pos.X_Scale += shift_x / d.basis.X}
		if d.basis.Y > 0 {pos.Y_Scale += shift_y / d.basis.Y}
	}

	gui.size = size
	gui.position = pos
	d.last_size = {w, h}

	Gui_Layout_Mark_Dirty()
	surfacegui_mark_dirty_for(&gui.object)
}

ui_scale_detector_end :: proc(d: ^UIScaleDetector, registry: ^Registry, L: ^vm.State) {
	if !d.scaling {
		return
	}

	d.scaling = false
	UIScaleDetector_ensure_signals(d)
	ui_scale_detector_fire(L, registry, d.scale_end, d.last_size)
}


UIScaleDetector_Handle_Event :: proc(
	registry: ^Registry,
	L: ^vm.State,
	event: sdl3.Event,
) -> (
	claimed: bool,
) {
	if registry == nil || L == nil {
		return false
	}

	descriptor := Find_Class(registry, "UIScaleDetector")
	if descriptor == nil || len(descriptor.instances) == 0 {
		return false
	}

	#partial switch event.type {
	case .MOUSE_BUTTON_DOWN:
		if event.button.button != sdl3.BUTTON_LEFT {
			return false
		}

		result := GuiObject_hit_chain_ex(registry, f32(event.button.x), f32(event.button.y))
		defer delete(result.chain)


		for gui in result.chain {
			detector_object := Find_First_Child_Of_Class(&gui.object, "UIScaleDetector")
			if detector_object == nil || detector_object.destroyed {
				continue
			}

			d := cast(^UIScaleDetector)detector_object

			if !d.enabled || d.scaling {
				continue
			}

			left, right, top, bottom, ok := ui_scale_detector_zone(d, gui, result.x, result.y)
			if !ok {
				continue
			}

			ui_scale_detector_begin(
				d,
				gui,
				registry,
				L,
				result.x,
				result.y,
				left,
				right,
				top,
				bottom,
			)
			return true
		}

	case .MOUSE_MOTION:
		for object in descriptor.instances {
			if object == nil || object.destroyed {
				continue
			}

			d := cast(^UIScaleDetector)object

			if !d.scaling {
				continue
			}

			if d.object.parent == nil || !Is_A(d.object.parent, "GuiObject") {
				d.scaling = false
				continue
			}

			gui := cast(^GuiObject)d.object.parent

			x, y, _ := GuiObject_pointer_point(
				registry,
				gui,
				f32(event.motion.x),
				f32(event.motion.y),
			)

			ui_scale_detector_update(d, gui, x, y)

			UIScaleDetector_ensure_signals(d)
			ui_scale_detector_fire(L, registry, d.scale_continue, d.last_size)
		}

	case .MOUSE_BUTTON_UP:
		if event.button.button != sdl3.BUTTON_LEFT {
			return false
		}

		for object in descriptor.instances {
			if object == nil || object.destroyed {
				continue
			}

			d := cast(^UIScaleDetector)object

			if d.scaling {
				ui_scale_detector_end(d, registry, L)
			}
		}
	}

	return false
}


UIScaleDetector_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	d := cast(^UIScaleDetector)object

	switch key {
	case "Enabled":
		vm.PushBoolean(L, d.enabled)

	case "ScaleStyle":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"UIScaleDetectorScaleStyle",
			i64(d.scale_style),
		)

	case "ResponseStyle":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"UIScaleDetectorResponseStyle",
			i64(d.response_style),
		)

	case "EdgeThickness":
		vm.PushNumber(L, d.edge_thickness)

	case "KeepAspectRatio":
		vm.PushBoolean(L, d.keep_aspect_ratio)

	case "ScaleFromCenter":
		vm.PushBoolean(L, d.scale_from_center)

	case "MinSize":
		if datatype_registry == nil {return false}
		datatypes.Push_Vector2(L, datatype_registry, d.min_size)

	case "MaxSize":
		if datatype_registry == nil {return false}
		datatypes.Push_Vector2(L, datatype_registry, d.max_size)

	case "ScaleStart":
		UIScaleDetector_ensure_signals(d)
		signals.Push(L, d.scale_start)

	case "ScaleContinue":
		UIScaleDetector_ensure_signals(d)
		signals.Push(L, d.scale_continue)

	case "ScaleEnd":
		UIScaleDetector_ensure_signals(d)
		signals.Push(L, d.scale_end)

	case:
		return false
	}

	return true
}

UIScaleDetector_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	d := cast(^UIScaleDetector)object

	Gui_Layout_Mark_Dirty()

	switch key {
	case "Enabled":
		d.enabled = vm.ArgBoolean(L, value_index)
		if !d.enabled {
			d.scaling = false
		}

	case "ScaleStyle":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "UIScaleDetectorScaleStyle")
		if item == nil {return false}
		d.scale_style = enums.UIScaleDetectorScaleStyle(item.value)

	case "ResponseStyle":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "UIScaleDetectorResponseStyle")
		if item == nil {return false}
		d.response_style = enums.UIScaleDetectorResponseStyle(item.value)

	case "EdgeThickness":
		d.edge_thickness = max(f64(0), vm.ArgNumber(L, value_index))

	case "KeepAspectRatio":
		d.keep_aspect_ratio = vm.ArgBoolean(L, value_index)

	case "ScaleFromCenter":
		d.scale_from_center = vm.ArgBoolean(L, value_index)

	case "MinSize":
		if datatype_registry == nil {return false}
		d.min_size = datatypes.Arg_Vector2(L, value_index, datatype_registry)

	case "MaxSize":
		if datatype_registry == nil {return false}
		d.max_size = datatypes.Arg_Vector2(L, value_index, datatype_registry)

	case:
		return false
	}

	return true
}

UIScaleDetector_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UIScaleDetector)source
	dst := cast(^UIScaleDetector)destination

	dst.enabled = src.enabled
	dst.scale_style = src.scale_style
	dst.response_style = src.response_style
	dst.edge_thickness = src.edge_thickness
	dst.keep_aspect_ratio = src.keep_aspect_ratio
	dst.scale_from_center = src.scale_from_center
	dst.min_size = src.min_size
	dst.max_size = src.max_size

	dst.scaling = false
}

Register_UIScaleDetector :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UIScaleDetector_Class,
		UIScaleDetector_construct,
		UIScaleDetector_destroy,
		get = UIScaleDetector_get,
		set = UIScaleDetector_set,
		clone = UIScaleDetector_clone,
		properties = []string {
			"Enabled",
			"ScaleStyle",
			"ResponseStyle",
			"EdgeThickness",
			"KeepAspectRatio",
			"ScaleFromCenter",
			"MinSize",
			"MaxSize",
		},
		events = []string{"ScaleStart", "ScaleContinue", "ScaleEnd"},
	)
}
