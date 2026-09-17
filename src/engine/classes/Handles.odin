package classes

import sdl3 "../platform"
import datatypes "../datatypes"
import enums "../enum"
import kineffi "../bindings"
import signals "../signals"
import vm "../vm"

Adorn_Class := Class_Info{
	name   = "Adorn",
	parent = &Instance_Class,
}

PartAdornment_Class := Class_Info{
	name   = "PartAdornment",
	parent = &Adorn_Class,
}

Handles_Class := Class_Info{
	name   = "Handles",
	parent = &PartAdornment_Class,
}

ArcHandles_Class := Class_Info{
	name   = "ArcHandles",
	parent = &PartAdornment_Class,
}

Handles :: struct {
	using object: Object,

	Adornee: ^Object,
	Color3:  datatypes.Color3,
	Faces:   datatypes.Faces,
	Style:   enums.HandlesStyle,
	Visible: bool,

	mouse_button1_down: ^signals.Signal,
	mouse_button1_up:   ^signals.Signal,
	mouse_drag:         ^signals.Signal,

	native_gizmo:   ^kineffi.KineFilamentGizmo,
	native_context: ^kineffi.KineFilamentContext,
	hovered_axis:  i32,
	selected_axis: i32,
	dragging:      bool,
	previous_left: bool,
	drag_start_x:  f32,
	drag_start_y:  f32,
	drag_last_delta: f32,
}

ArcHandles :: struct {
	using object: Object,

	Adornee: ^Object,
	Axes:    datatypes.Axes,
	Color3:  datatypes.Color3,
	Visible: bool,

	mouse_button1_down: ^signals.Signal,
	mouse_button1_up:   ^signals.Signal,
	mouse_drag:         ^signals.Signal,

	native_gizmo:   ^kineffi.KineFilamentGizmo,
	native_context: ^kineffi.KineFilamentContext,
	hovered_axis:  i32,
	selected_axis: i32,
	dragging:      bool,
	previous_left: bool,
	drag_start_x:  f32,
	drag_start_y:  f32,
	drag_last_delta: f32,
}

handles_init :: proc() -> Handles {
	return Handles{
		object = Object_Init(&Handles_Class, "Handles"),
		Color3 = datatypes.Color3{1, 1, 1},
		Faces  = datatypes.Faces_All,
		Style  = .Resize,
		Visible = true,
	}
}

arc_handles_init :: proc() -> ArcHandles {
	return ArcHandles{
		object = Object_Init(&ArcHandles_Class, "ArcHandles"),
		Axes   = datatypes.Axes_All,
		Color3 = datatypes.Color3{1, 1, 1},
		Visible = true,
	}
}

handles_ensure_signals :: proc(
	object: ^Object,
	mouse_button1_down: ^^signals.Signal,
	mouse_button1_up: ^^signals.Signal,
	mouse_drag: ^^signals.Signal,
) {
	if object == nil ||
	   object.signal_registry == nil ||
	   object.signal_registry.signal_registry == nil {
		return
	}

	registry := object.signal_registry.signal_registry
	if mouse_button1_down^ == nil {
		mouse_button1_down^ = signals.Create(registry)
	}
	if mouse_button1_up^ == nil {
		mouse_button1_up^ = signals.Create(registry)
	}
	if mouse_drag^ == nil {
		mouse_drag^ = signals.Create(registry)
	}
}

handles_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	handles := new(Handles)
	handles^ = handles_init()
	return &handles.object
}

arc_handles_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	handles := new(ArcHandles)
	handles^ = arc_handles_init()
	return &handles.object
}

handles_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	handles := cast(^Handles)object
	handles_destroy_native(handles.native_gizmo, handles.native_context)
	Object_Destroy(object)
	free(handles)
}

arc_handles_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	handles := cast(^ArcHandles)object
	handles_destroy_native(handles.native_gizmo, handles.native_context)
	Object_Destroy(object)
	free(handles)
}

handles_destroy_native :: proc(
	gizmo: ^kineffi.KineFilamentGizmo,
	ctx: ^kineffi.KineFilamentContext,
) {
	if gizmo != nil && ctx != nil {
		kineffi.Kine_Filament_DestroyGizmo(ctx, gizmo)
	}
}

handles_model_matrix :: proc(part: ^Part) -> [16]f32 {
	return [16]f32{
		part.cframe.r00, part.cframe.r01, part.cframe.r02, part.cframe.x,
		part.cframe.r10, part.cframe.r11, part.cframe.r12, part.cframe.y,
		part.cframe.r20, part.cframe.r21, part.cframe.r22, part.cframe.z,
		0, 0, 0, 1,
	}
}

handles_adornee_part :: proc(adornee: ^Object) -> ^Part {
	if adornee == nil || adornee.destroyed || !Is_A(adornee, "Part") {
		return nil
	}
	return cast(^Part)adornee
}

handles_ensure_native :: proc(
	ctx: ^kineffi.KineFilamentContext,
	gizmo: ^^kineffi.KineFilamentGizmo,
	native_context: ^^kineffi.KineFilamentContext,
	gizmo_type: i32,
) {
	if ctx == nil {
		return
	}
	if native_context^ != ctx {
		handles_destroy_native(gizmo^, native_context^)
		gizmo^ = nil
		native_context^ = ctx
	}
	if gizmo^ == nil {
		gizmo^ = kineffi.Kine_Filament_CreateGizmo(ctx, gizmo_type)
	}
}

handles_axis_vector :: proc(axis: i32) -> datatypes.Vector3 {
	switch axis {
	case kineffi.KINE_GIZMO_AXIS_X:
		return datatypes.Vector3_XAxis
	case kineffi.KINE_GIZMO_AXIS_Y:
		return datatypes.Vector3_YAxis
	case kineffi.KINE_GIZMO_AXIS_Z:
		return datatypes.Vector3_ZAxis
	}
	return datatypes.Vector3{}
}

handles_push_axis :: proc(L: ^vm.State, registry: ^enums.Registry, axis: i32) {
	value := i64(0)
	switch axis {
	case kineffi.KINE_GIZMO_AXIS_Y:
		value = 1
	case kineffi.KINE_GIZMO_AXIS_Z:
		value = 2
	}
	_ = enums.Push_Item_By_Value(L, registry, "Axis", value)
}

handles_fire_axis :: proc(
	L: ^vm.State,
	signal: ^signals.Signal,
	registry: ^enums.Registry,
	axis: i32,
) {
	if signal == nil || registry == nil {
		return
	}
	handles_push_axis(L, registry, axis)
	signals.Fire(L, signal, 1)
}

handles_fire_drag :: proc(
	L: ^vm.State,
	signal: ^signals.Signal,
	registry: ^enums.Registry,
	axis: i32,
	delta: f32,
) {
	if signal == nil || registry == nil {
		return
	}
	handles_push_axis(L, registry, axis)
	vm.PushNumber(L, f64(delta))
	signals.Fire(L, signal, 2)
}

handles_apply_delta :: proc(
	part: ^Part,
	axis: i32,
	delta: f32,
	style: enums.HandlesStyle,
) {
	if part == nil {
		return
	}

	local_axis := handles_axis_vector(axis)
	world_axis := datatypes.CFrame_VectorToWorldSpace(part.cframe, local_axis)

	switch style {
	case .Movement:
		part.cframe.x += world_axis.x * delta
		part.cframe.y += world_axis.y * delta
		part.cframe.z += world_axis.z * delta
		part.position.x = part.cframe.x
		part.position.y = part.cframe.y
		part.position.z = part.cframe.z
	case .Resize:
		keyboard := sdl3.GetKeyboardState(nil)
		centered := keyboard[sdl3.Scancode.LCTRL] || keyboard[sdl3.Scancode.RCTRL]
		if !centered {
			part.cframe.x += world_axis.x * delta * 0.5
			part.cframe.y += world_axis.y * delta * 0.5
			part.cframe.z += world_axis.z * delta * 0.5
			part.position.x = part.cframe.x
			part.position.y = part.cframe.y
			part.position.z = part.cframe.z
		}
		switch axis {
		case kineffi.KINE_GIZMO_AXIS_X:
			part.size.x = max(0.05, part.size.x + delta * (centered ? 2 : 1))
		case kineffi.KINE_GIZMO_AXIS_Y:
			part.size.y = max(0.05, part.size.y + delta * (centered ? 2 : 1))
		case kineffi.KINE_GIZMO_AXIS_Z:
			part.size.z = max(0.05, part.size.z + delta * (centered ? 2 : 1))
		}
	case .Rotation:
		rotation := datatypes.CFrame_FromAxisAngle(local_axis, delta)
		part.cframe = datatypes.CFrame_Mul_CFrame(part.cframe, rotation)
	}
}

handles_step_common :: proc(
	L: ^vm.State,
	renderer: ^Renderer_Object,
	adornee: ^Object,
	visible: bool,
	ctx: ^^kineffi.KineFilamentContext,
	gizmo: ^^kineffi.KineFilamentGizmo,
	hovered_axis: ^i32,
	selected_axis: ^i32,
	dragging: ^bool,
	previous_left: ^bool,
	drag_start_x: ^f32,
	drag_start_y: ^f32,
	drag_last_delta: ^f32,
	gizmo_type: i32,
	style: enums.HandlesStyle,
	mouse_down: ^signals.Signal,
	mouse_up: ^signals.Signal,
	mouse_drag: ^signals.Signal,
	enum_registry: ^enums.Registry,
	apply_delta: bool,
) {
	if renderer == nil || renderer.Filament == nil {
		return
	}

	part := handles_adornee_part(adornee)
	if !visible || part == nil {
		handles_destroy_native(gizmo^, ctx^)
		gizmo^ = nil
		ctx^ = nil
		hovered_axis^ = kineffi.KINE_GIZMO_AXIS_NONE
		return
	}

	handles_ensure_native(
		renderer.Filament,
		gizmo,
		ctx,
		gizmo_type,
	)
	if gizmo^ == nil {
		return
	}

	model := handles_model_matrix(part)
	mouse_x, mouse_y: f32
	buttons := sdl3.GetMouseState(&mouse_x, &mouse_y)
	left := .LEFT in buttons

	if !dragging^ {
		hovered_axis^ = kineffi.Kine_Filament_PickGizmo(
			renderer.Filament,
			gizmo^,
			&model[0],
			mouse_x,
			mouse_y,
		)
	}

	if left && !previous_left^ && hovered_axis^ != kineffi.KINE_GIZMO_AXIS_NONE {
		selected_axis^ = hovered_axis^
		dragging^ = true
		drag_start_x^ = mouse_x
		drag_start_y^ = mouse_y
		drag_last_delta^ = 0
		handles_fire_axis(L, mouse_down, enum_registry, selected_axis^)
	}

	if dragging^ && left {
		delta := kineffi.Kine_Filament_GetGizmoDragDelta(
			renderer.Filament,
			gizmo^,
			&model[0],
			selected_axis^,
			drag_start_x^,
			drag_start_y^,
			mouse_x,
			mouse_y,
		)
		increment := delta - drag_last_delta^
		drag_last_delta^ = delta
		if apply_delta {
			handles_apply_delta(part, selected_axis^, increment, style)
		}
		handles_fire_drag(L, mouse_drag, enum_registry, selected_axis^, delta)
	}

	if !left && previous_left^ && dragging^ {
		handles_fire_axis(L, mouse_up, enum_registry, selected_axis^)
		dragging^ = false
		selected_axis^ = kineffi.KINE_GIZMO_AXIS_NONE
	}

	previous_left^ = left
	kineffi.Kine_Filament_DrawGizmo(
		renderer.Filament,
		gizmo^,
		&model[0],
		hovered_axis^,
		selected_axis^,
	)
}

handles_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	handles := cast(^Handles)object

	switch key {
	case "Adornee":
		Push_Object(L, handles.Adornee)
	case "Color3":
		if datatype_registry == nil { return false }
		datatypes.Push_Color3(L, datatype_registry, handles.Color3)
	case "Faces":
		if datatype_registry == nil { return false }
		datatypes.Push_Faces(L, datatype_registry, handles.Faces)
	case "Style":
		if enum_registry == nil { return false }
		_ = enums.Push_Item_By_Value(L, enum_registry, "HandlesStyle", i64(handles.Style))
	case "Visible":
		vm.PushBoolean(L, handles.Visible)
	case "MouseButton1Down", "MouseButton1Up", "MouseDrag":
		handles_ensure_signals(
			&handles.object,
			&handles.mouse_button1_down,
			&handles.mouse_button1_up,
			&handles.mouse_drag,
		)
		switch key {
		case "MouseButton1Down": signals.Push(L, handles.mouse_button1_down)
		case "MouseButton1Up": signals.Push(L, handles.mouse_button1_up)
		case "MouseDrag": signals.Push(L, handles.mouse_drag)
		}
	case:
		return false
	}

	return true
}

handles_step :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	handles := cast(^Handles)object
	if handles == nil || ctx == nil {
		return
	}
	handles_ensure_signals(
		&handles.object,
		&handles.mouse_button1_down,
		&handles.mouse_button1_up,
		&handles.mouse_drag,
	)
	enum_registry: ^enums.Registry
	if handles.object.signal_registry != nil {
		enum_registry = handles.object.signal_registry.enums
	}
	handles_step_common(
		ctx.L,
		ctx.renderer,
		handles.Adornee,
		handles.Visible,
		&handles.native_context,
		&handles.native_gizmo,
		&handles.hovered_axis,
		&handles.selected_axis,
		&handles.dragging,
		&handles.previous_left,
		&handles.drag_start_x,
		&handles.drag_start_y,
		&handles.drag_last_delta,
		kineffi.KINE_GIZMO_SCALE,
		handles.Style,
		handles.mouse_button1_down,
		handles.mouse_button1_up,
		handles.mouse_drag,
		enum_registry,
		true,
	)
}

arc_handles_step :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	handles := cast(^ArcHandles)object
	if handles == nil || ctx == nil {
		return
	}
	handles_ensure_signals(
		&handles.object,
		&handles.mouse_button1_down,
		&handles.mouse_button1_up,
		&handles.mouse_drag,
	)
	enum_registry: ^enums.Registry
	if handles.object.signal_registry != nil {
		enum_registry = handles.object.signal_registry.enums
	}
	handles_step_common(
		ctx.L,
		ctx.renderer,
		handles.Adornee,
		handles.Visible,
		&handles.native_context,
		&handles.native_gizmo,
		&handles.hovered_axis,
		&handles.selected_axis,
		&handles.dragging,
		&handles.previous_left,
		&handles.drag_start_x,
		&handles.drag_start_y,
		&handles.drag_last_delta,
		kineffi.KINE_GIZMO_ROTATE,
		.Rotation,
		handles.mouse_button1_down,
		handles.mouse_button1_up,
		handles.mouse_drag,
		enum_registry,
		true,
	)
}

handles_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	handles := cast(^Handles)object

	switch key {
	case "Adornee":
		if vm.IsNil(L, value_index) {
			handles.Adornee = nil
			return true
		}
		adornee := object_from_argument(L, value_index)
		if adornee == nil || !Is_A(adornee, "Part") {
			_ = vm.RaiseError(L, "Adornee must be a BasePart or nil")
			return true
		}
		handles.Adornee = adornee
	case "Color3":
		if datatype_registry == nil { return false }
		handles.Color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Faces":
		if datatype_registry == nil { return false }
		handles.Faces = datatypes.Arg_Faces(L, value_index, datatype_registry)
	case "Style":
		if enum_registry == nil { return false }
		item := enums.Arg_Item(L, value_index, enum_registry, "HandlesStyle")
		handles.Style = enums.HandlesStyle(item.value)
	case "Visible":
		handles.Visible = vm.ArgBoolean(L, value_index)
	case:
		return false
	}

	return true
}

arc_handles_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	handles := cast(^ArcHandles)object

	switch key {
	case "Adornee":
		Push_Object(L, handles.Adornee)
	case "Axes":
		if datatype_registry == nil { return false }
		datatypes.Push_Axes(L, datatype_registry, handles.Axes)
	case "Color3":
		if datatype_registry == nil { return false }
		datatypes.Push_Color3(L, datatype_registry, handles.Color3)
	case "Visible":
		vm.PushBoolean(L, handles.Visible)
	case "MouseButton1Down", "MouseButton1Up", "MouseDrag":
		handles_ensure_signals(
			&handles.object,
			&handles.mouse_button1_down,
			&handles.mouse_button1_up,
			&handles.mouse_drag,
		)
		switch key {
		case "MouseButton1Down": signals.Push(L, handles.mouse_button1_down)
		case "MouseButton1Up": signals.Push(L, handles.mouse_button1_up)
		case "MouseDrag": signals.Push(L, handles.mouse_drag)
		}
	case:
		return false
	}

	return true
}

arc_handles_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	handles := cast(^ArcHandles)object

	switch key {
	case "Adornee":
		if vm.IsNil(L, value_index) {
			handles.Adornee = nil
			return true
		}
		adornee := object_from_argument(L, value_index)
		if adornee == nil || !Is_A(adornee, "Part") {
			_ = vm.RaiseError(L, "Adornee must be a BasePart or nil")
			return true
		}
		handles.Adornee = adornee
	case "Axes":
		if datatype_registry == nil { return false }
		handles.Axes = datatypes.Arg_Axes(L, value_index, datatype_registry)
	case "Color3":
		if datatype_registry == nil { return false }
		handles.Color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Visible":
		handles.Visible = vm.ArgBoolean(L, value_index)
	case:
		return false
	}

	return true
}

handles_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Handles)source
	dst := cast(^Handles)destination
	dst.Adornee = src.Adornee
	dst.Color3 = src.Color3
	dst.Faces = src.Faces
	dst.Style = src.Style
	dst.Visible = src.Visible
}

arc_handles_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^ArcHandles)source
	dst := cast(^ArcHandles)destination
	dst.Adornee = src.Adornee
	dst.Axes = src.Axes
	dst.Color3 = src.Color3
	dst.Visible = src.Visible
}

Register_Handles :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Handles_Class,
		handles_construct,
		handles_destroy,
		get = handles_get,
		set = handles_set,
		clone = handles_clone,
		_step = handles_step,
		_step_phase = .Render_3D,
		properties = []string{
			"Adornee",
			"Color3",
			"Faces",
			"Style",
			"Visible",
			"MouseButton1Down",
			"MouseButton1Up",
			"MouseDrag",
		},
	)
}

Register_ArcHandles :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&ArcHandles_Class,
		arc_handles_construct,
		arc_handles_destroy,
		get = arc_handles_get,
		set = arc_handles_set,
		clone = arc_handles_clone,
		_step = arc_handles_step,
		_step_phase = .Render_3D,
		properties = []string{
			"Adornee",
			"Axes",
			"Color3",
			"Visible",
			"MouseButton1Down",
			"MouseButton1Up",
			"MouseDrag",
		},
	)
}
