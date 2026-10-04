package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import sdl3 "../platform"
import signals "../signals"
import vm "../vm"
import "core:math"

Adorn_Class := Class_Info {
	name   = "Adorn",
	parent = &Instance_Class,
}

PartAdornment_Class := Class_Info {
	name   = "PartAdornment",
	parent = &Adorn_Class,
}

Handles_Class := Class_Info {
	name   = "Handles",
	parent = &PartAdornment_Class,
}

ArcHandles_Class := Class_Info {
	name   = "ArcHandles",
	parent = &PartAdornment_Class,
}

Handles :: struct {
	using object:       Object,
	Adornee:            ^Object,
	Color3:             datatypes.Color3,
	Faces:              datatypes.Faces,
	Style:              enums.HandlesStyle,
	Visible:            bool,
	mouse_button1_down: ^signals.Signal,
	mouse_button1_up:   ^signals.Signal,
	mouse_drag:         ^signals.Signal,
	native_gizmo:       ^kineffi.KineFilamentGizmo,
	native_context:     ^kineffi.KineFilamentContext,
	// native_type remembers which gizmo type the live native gizmo was built
	// for, so changing Style can rebuild it: the native handle caches its mesh
	// and never learns the type changed on its own.
	native_type:        i32,
	hovered_axis:       i32,
	snap:               f64,
	selected_axis:      i32,
	dragging:           bool,
	previous_left:      bool,
	drag_start_x:       f32,
	drag_start_y:       f32,
	drag_last_delta:    f32,
	drag_last_delta2:   f32,
	// drag_pivot is the frame captured when a drag begins. Models rotate and
	// scale about it for the whole drag so a non-symmetric model cannot drag
	// its own handles around as its bounding box changes.
	drag_pivot:         datatypes.CFrame,
}

ArcHandles :: struct {
	using object:       Object,
	Adornee:            ^Object,
	Axes:               datatypes.Axes,
	Color3:             datatypes.Color3,
	Visible:            bool,
	mouse_button1_down: ^signals.Signal,
	mouse_button1_up:   ^signals.Signal,
	mouse_drag:         ^signals.Signal,
	native_gizmo:       ^kineffi.KineFilamentGizmo,
	native_context:     ^kineffi.KineFilamentContext,
	native_type:        i32,
	hovered_axis:       i32,
	selected_axis:      i32,
	snap:               f64,
	dragging:           bool,
	previous_left:      bool,
	drag_start_x:       f32,
	drag_start_y:       f32,
	drag_last_delta:    f32,
	drag_last_delta2:   f32,
	drag_pivot:         datatypes.CFrame,
}

handles_init :: proc() -> Handles {
	return Handles {
		object = Object_Init(&Handles_Class, "Handles"),
		Color3 = datatypes.Color3{1, 1, 1},
		Faces = datatypes.Faces_All,
		Style = .Resize,
		snap = 2,
		Visible = true,
	}
}

arc_handles_init :: proc() -> ArcHandles {
	return ArcHandles {
		object = Object_Init(&ArcHandles_Class, "ArcHandles"),
		Axes = datatypes.Axes_All,
		Color3 = datatypes.Color3{1, 1, 1},
		snap = 2,
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

handles_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	handles := new(Handles)
	handles^ = handles_init()
	return &handles.object
}

arc_handles_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	handles := new(ArcHandles)
	handles^ = arc_handles_init()
	return &handles.object
}

handles_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	handles := cast(^Handles)object
	handles_destroy_native(handles.native_gizmo, handles.native_context)
	handles_free_signal_pointers(
		&handles.mouse_button1_down,
		&handles.mouse_button1_up,
		&handles.mouse_drag,
	)
	Object_Destroy(object)
	free(handles)
}

handles_snap_delta :: proc(delta: f32, snap: f64) -> f32 {
	if snap <= 0 {
		return delta
	}

	step := f32(snap)
	return f32(math.round(f64(delta) / snap)) * step
}

handles_snap_increment :: proc(current_delta: f32, last_applied_delta: ^f32, snap: f64) -> f32 {
	if snap <= 0 {
		increment := current_delta - last_applied_delta^
		last_applied_delta^ = current_delta
		return increment
	}

	snapped := handles_snap_delta(current_delta, snap)
	increment := snapped - last_applied_delta^

	if increment != 0 {
		last_applied_delta^ = snapped
	}

	return increment
}

arc_handles_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	handles := cast(^ArcHandles)object
	handles_destroy_native(handles.native_gizmo, handles.native_context)
	handles_free_signal_pointers(
		&handles.mouse_button1_down,
		&handles.mouse_button1_up,
		&handles.mouse_drag,
	)
	Object_Destroy(object)
	free(handles)
}

handles_free_signal_pointers :: proc(
	mouse_button1_down, mouse_button1_up, mouse_drag: ^^signals.Signal,
) {
	if mouse_button1_down^ != nil {
		signals.Destroy(mouse_button1_down^)
		mouse_button1_down^ = nil
	}
	if mouse_button1_up^ != nil {
		signals.Destroy(mouse_button1_up^)
		mouse_button1_up^ = nil
	}
	if mouse_drag^ != nil {
		signals.Destroy(mouse_drag^)
		mouse_drag^ = nil
	}
}

handles_destroy_native :: proc(
	gizmo: ^kineffi.KineFilamentGizmo,
	ctx: ^kineffi.KineFilamentContext,
) {
	if gizmo != nil && ctx != nil {
		kineffi.Kine_Filament_DestroyGizmo(ctx, gizmo)
	}
}

handles_cframe_matrix :: proc(cf: datatypes.CFrame) -> [16]f32 {
	return [16]f32 {
		cf.r00,
		cf.r01,
		cf.r02,
		cf.x,
		cf.r10,
		cf.r11,
		cf.r12,
		cf.y,
		cf.r20,
		cf.r21,
		cf.r22,
		cf.z,
		0,
		0,
		0,
		1,
	}
}

// A handles selection is the thing a Handles or ArcHandles adorns: either a
// single BasePart or a Model. `pivot` is the world-space frame the gizmo sits
// on and every transform is measured from -- a Part's own CFrame, or a Model's
// bounding-box centre (Roblox's default WorldPivot).
handles_selection :: struct {
	part:  ^Part,
	model: ^Object,
	pivot: datatypes.CFrame,
}

handles_resolve_selection :: proc(adornee: ^Object) -> (handles_selection, bool) {
	if adornee == nil || adornee.destroyed {
		return {}, false
	}
	if Is_A(adornee, "Part") {
		part := cast(^Part)adornee
		return handles_selection{part = part, pivot = part.cframe}, true
	}
	if Is_A(adornee, "Model") {
		if pivot, ok := Handles_Model_Pivot(adornee); ok {
			return handles_selection{model = adornee, pivot = pivot}, true
		}
	}
	return {}, false
}

// A cached physics body mirrors a Part's transform, and Part's setter is what
// tells physics a mirrored property moved. Writing `cframe` fields directly
// from the gizmo leaves `position` -- the copy the physics service reads -- out
// of date, so every write goes through here.
handles_part_sync_position :: proc(part: ^Part) {
	if part != nil {
		part.position = datatypes.Vector3{part.cframe.x, part.cframe.y, part.cframe.z}
	}
}

// The world-space half extents of a Part's oriented box: the half size of the
// axis-aligned box that contains it once its rotation is applied.
handles_part_half_extents :: proc(part: ^Part) -> (x, y, z: f32) {
	hx := part.size.x * 0.5
	hy := part.size.y * 0.5
	hz := part.size.z * 0.5
	x = abs(part.cframe.r00) * hx + abs(part.cframe.r01) * hy + abs(part.cframe.r02) * hz
	y = abs(part.cframe.r10) * hx + abs(part.cframe.r11) * hy + abs(part.cframe.r12) * hz
	z = abs(part.cframe.r20) * hx + abs(part.cframe.r21) * hy + abs(part.cframe.r22) * hz
	return
}

handles_expand_bounds :: proc(
	min, max: ^datatypes.Vector3,
	found: ^bool,
	point: datatypes.Vector3,
) {
	if !found^ {
		min^ = point
		max^ = point
		found^ = true
		return
	}
	min^ = datatypes.Vec3_Min(min^, point)
	max^ = datatypes.Vec3_Max(max^, point)
}

handles_accumulate_bounds :: proc(
	object: ^Object,
	min, max: ^datatypes.Vector3,
	found: ^bool,
) {
	if object == nil || object.destroyed {
		return
	}
	if Is_A(object, "Part") {
		part := cast(^Part)object
		ex, ey, ez := handles_part_half_extents(part)
		handles_expand_bounds(min, max, found, datatypes.Vector3{
			part.cframe.x - ex,
			part.cframe.y - ey,
			part.cframe.z - ez,
		})
		handles_expand_bounds(min, max, found, datatypes.Vector3{
			part.cframe.x + ex,
			part.cframe.y + ey,
			part.cframe.z + ez,
		})
	}
	for child in object.children {
		handles_accumulate_bounds(child, min, max, found)
	}
}

// Handles_Model_Bounds returns the world-space axis-aligned box containing
// every BasePart under `model`. `found` is false when the subtree has no parts.
Handles_Model_Bounds :: proc(model: ^Object) -> (min, max: datatypes.Vector3, found: bool) {
	handles_accumulate_bounds(model, &min, &max, &found)
	return
}

// Handles_Model_Pivot is the frame a Model's handles are anchored to: the
// centre of its bounding box, rotation-free, matching Roblox's default
// WorldPivot for a model with no explicit pivot.
Handles_Model_Pivot :: proc(model: ^Object) -> (datatypes.CFrame, bool) {
	min, max, found := Handles_Model_Bounds(model)
	if !found {
		return {}, false
	}
	return datatypes.CFrame_New_Position(
		datatypes.Vec3_Multiply(datatypes.Vec3_Add(min, max), 0.5),
	), true
}

handles_translate_state :: struct {
	offset: datatypes.Vector3,
}

handles_translate_visit :: proc(part: ^Part, data: rawptr) {
	state := cast(^handles_translate_state)data
	part.cframe = datatypes.CFrame_Add_Vector3(part.cframe, state.offset)
	handles_part_sync_position(part)
}

handles_transform_state :: struct {
	transform: datatypes.CFrame,
}

handles_transform_visit :: proc(part: ^Part, data: rawptr) {
	state := cast(^handles_transform_state)data
	part.cframe = datatypes.CFrame_Mul_CFrame(state.transform, part.cframe)
	handles_part_sync_position(part)
}

handles_scale_state :: struct {
	pivot:   datatypes.Vector3,
	factors: datatypes.Vector3,
}

handles_scale_visit :: proc(part: ^Part, data: rawptr) {
	state := cast(^handles_scale_state)data
	part.size = datatypes.Vector3{
		max(0.05, part.size.x * state.factors.x),
		max(0.05, part.size.y * state.factors.y),
		max(0.05, part.size.z * state.factors.z),
	}
	offset := datatypes.Vec3_Subtract(
		datatypes.Vector3{part.cframe.x, part.cframe.y, part.cframe.z},
		state.pivot,
	)
	offset = datatypes.Vector3{
		offset.x * state.factors.x,
		offset.y * state.factors.y,
		offset.z * state.factors.z,
	}
	position := datatypes.Vec3_Add(state.pivot, offset)
	part.cframe.x = position.x
	part.cframe.y = position.y
	part.cframe.z = position.z
	handles_part_sync_position(part)
}

handles_for_each_model_part :: proc(
	object: ^Object,
	data: rawptr,
	visit: proc(part: ^Part, data: rawptr),
) {
	if object == nil || object.destroyed {
		return
	}
	if Is_A(object, "Part") {
		visit(cast(^Part)object, data)
	}
	for child in object.children {
		handles_for_each_model_part(child, data, visit)
	}
}

handles_model_translate :: proc(model: ^Object, offset: datatypes.Vector3) {
	state := handles_translate_state{offset = offset}
	handles_for_each_model_part(model, &state, handles_translate_visit)
}

handles_model_transform :: proc(model: ^Object, transform: datatypes.CFrame) {
	state := handles_transform_state{transform = transform}
	handles_for_each_model_part(model, &state, handles_transform_visit)
}

handles_model_scale :: proc(model: ^Object, pivot: datatypes.Vector3, factors: datatypes.Vector3) {
	state := handles_scale_state{pivot = pivot, factors = factors}
	handles_for_each_model_part(model, &state, handles_scale_visit)
}

handles_axis_component :: proc(axis: i32) -> int {
	switch axis {
	case kineffi.KINE_GIZMO_AXIS_X:
		return 0
	case kineffi.KINE_GIZMO_AXIS_Y:
		return 1
	case kineffi.KINE_GIZMO_AXIS_Z:
		return 2
	}
	return -1
}

handles_vector_component :: proc(v: datatypes.Vector3, component: int) -> f32 {
	switch component {
	case 0:
		return v.x
	case 1:
		return v.y
	case 2:
		return v.z
	}
	return 0
}

handles_vector_set_component :: proc(v: ^datatypes.Vector3, component: int, value: f32) {
	switch component {
	case 0:
		v.x = value
	case 1:
		v.y = value
	case 2:
		v.z = value
	}
}

// handles_model_scale_axis grows (or shrinks) the model along `axis` so its
// bounding-box extent changes by `delta`, keeping the supplied pivot fixed.
// Sizes and offsets from the pivot scale together, which is what makes the
// whole model grow rather than each part inflate independently.
handles_model_scale_axis :: proc(
	model: ^Object,
	pivot: datatypes.CFrame,
	axis: i32,
	delta: f32,
) {
	component := handles_axis_component(axis)
	if component < 0 {
		return
	}
	bounds_min, bounds_max, found := Handles_Model_Bounds(model)
	if !found {
		return
	}
	extent := handles_vector_component(datatypes.Vec3_Subtract(bounds_max, bounds_min), component)
	if extent <= 1e-4 {
		return
	}
	factor := max(0.05, extent + delta) / extent
	if factor <= 0 {
		return
	}
	factors := datatypes.Vector3{1, 1, 1}
	handles_vector_set_component(&factors, component, factor)
	handles_model_scale(model, datatypes.Vector3{pivot.x, pivot.y, pivot.z}, factors)
}

// Handles_Apply_Model_Axis applies one axis of a drag to every BasePart under
// `model`, about `pivot`. Movement translates the whole model, rotation revolves
// it around the pivot, and Resize scales it so its extent along `axis` grows by
// `delta`.
Handles_Apply_Model_Axis :: proc(
	model: ^Object,
	pivot: datatypes.CFrame,
	axis: i32,
	delta: f32,
	style: enums.HandlesStyle,
) {
	if model == nil || delta == 0 {
		return
	}
	local_axis := handles_axis_vector(axis)
	world_axis := datatypes.CFrame_VectorToWorldSpace(pivot, local_axis)
	switch style {
	case .Movement:
		handles_model_translate(model, datatypes.Vec3_Multiply(world_axis, delta))
	case .Rotation:
		rotation := datatypes.CFrame_FromAxisAngle(world_axis, delta)
		transform := datatypes.CFrame_Mul_CFrame(
			datatypes.CFrame_Mul_CFrame(pivot, rotation),
			datatypes.CFrame_Inverse(pivot),
		)
		handles_model_transform(model, transform)
	case .Resize:
		handles_model_scale_axis(model, pivot, axis, delta)
	}
}

// Handles_Apply_Model_Plane is the plane-handle twin of Handles_Apply_Model_Axis.
// Rotation has no in-plane drag, so it is a no-op there.
Handles_Apply_Model_Plane :: proc(
	model: ^Object,
	pivot: datatypes.CFrame,
	first_axis: i32,
	second_axis: i32,
	first: f32,
	second: f32,
	style: enums.HandlesStyle,
) {
	if model == nil || style == .Rotation {
		return
	}
	Handles_Apply_Model_Axis(model, pivot, first_axis, first, style)
	Handles_Apply_Model_Axis(model, pivot, second_axis, second, style)
}

handles_selection_apply_axis :: proc(
	selection: handles_selection,
	pivot: datatypes.CFrame,
	axis: i32,
	delta: f32,
	style: enums.HandlesStyle,
) {
	if selection.part != nil {
		handles_apply_axis_delta(selection.part, axis, delta, style)
		return
	}
	if selection.model != nil {
		Handles_Apply_Model_Axis(selection.model, pivot, axis, delta, style)
	}
}

handles_selection_apply_plane :: proc(
	selection: handles_selection,
	pivot: datatypes.CFrame,
	first_axis: i32,
	second_axis: i32,
	first: f32,
	second: f32,
	style: enums.HandlesStyle,
) {
	if selection.part != nil {
		handles_apply_plane_delta(selection.part, first_axis, second_axis, first, second, style)
		return
	}
	if selection.model != nil {
		Handles_Apply_Model_Plane(
			selection.model,
			pivot,
			first_axis,
			second_axis,
			first,
			second,
			style,
		)
	}
}

// handles_gizmo_type_for_style maps a Handles style onto the native gizmo that
// draws the matching handle set. ArcHandles is always Rotation.
handles_gizmo_type_for_style :: proc(style: enums.HandlesStyle) -> i32 {
	switch style {
	case .Movement:
		return kineffi.KINE_GIZMO_MOVE
	case .Rotation:
		return kineffi.KINE_GIZMO_ROTATE
	case .Resize:
		return kineffi.KINE_GIZMO_SCALE
	}
	return kineffi.KINE_GIZMO_SCALE
}

handles_ensure_native :: proc(
	ctx: ^kineffi.KineFilamentContext,
	gizmo: ^^kineffi.KineFilamentGizmo,
	native_context: ^^kineffi.KineFilamentContext,
	native_type: ^i32,
	gizmo_type: i32,
) {
	if ctx == nil {
		return
	}
	if native_context^ != ctx {
		handles_destroy_native(gizmo^, native_context^)
		gizmo^ = nil
		native_context^ = ctx
		native_type^ = 0
	}
	// The native gizmo bakes its mesh at creation, so a Style change has to
	// throw the old one away rather than mutate it in place.
	if gizmo^ != nil && native_type^ != gizmo_type {
		handles_destroy_native(gizmo^, native_context^)
		gizmo^ = nil
	}
	if gizmo^ == nil {
		gizmo^ = kineffi.Kine_Filament_CreateGizmo(ctx, gizmo_type)
		native_type^ = gizmo_type
	}
}

handles_plane :: proc(axis: i32) -> (first: i32, second: i32, normal: i32, is_plane: bool) {
	switch axis {
	case kineffi.KINE_GIZMO_AXIS_XY:
		return kineffi.KINE_GIZMO_AXIS_X,
			kineffi.KINE_GIZMO_AXIS_Y,
			kineffi.KINE_GIZMO_AXIS_Z,
			true
	case kineffi.KINE_GIZMO_AXIS_YZ:
		return kineffi.KINE_GIZMO_AXIS_Y,
			kineffi.KINE_GIZMO_AXIS_Z,
			kineffi.KINE_GIZMO_AXIS_X,
			true
	case kineffi.KINE_GIZMO_AXIS_XZ:
		return kineffi.KINE_GIZMO_AXIS_X,
			kineffi.KINE_GIZMO_AXIS_Z,
			kineffi.KINE_GIZMO_AXIS_Y,
			true
	}
	return 0, 0, 0, false
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
	report := axis
	if _, _, normal, is_plane := handles_plane(axis); is_plane {
		report = normal
	}
	value := i64(0)
	switch report {
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

handles_apply_axis_delta :: proc(part: ^Part, axis: i32, delta: f32, style: enums.HandlesStyle) {
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

handles_apply_plane_delta :: proc(
	part: ^Part,
	first_axis: i32,
	second_axis: i32,
	first: f32,
	second: f32,
	style: enums.HandlesStyle,
) {
	if part == nil || style == .Rotation {
		return
	}
	handles_apply_axis_delta(part, first_axis, first, style)
	handles_apply_axis_delta(part, second_axis, second, style)
}

handles_step_common :: proc(
	L: ^vm.State,
	renderer: ^Renderer_Object,
	adornee: ^Object,
	visible: bool,
	ctx: ^^kineffi.KineFilamentContext,
	gizmo: ^^kineffi.KineFilamentGizmo,
	native_type: ^i32,
	hovered_axis: ^i32,
	selected_axis: ^i32,
	dragging: ^bool,
	previous_left: ^bool,
	drag_start_x: ^f32,
	drag_start_y: ^f32,
	drag_last_delta: ^f32,
	drag_last_delta2: ^f32,
	drag_pivot: ^datatypes.CFrame,
	gizmo_type: i32,
	snap: ^f64,
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

	selection, has_selection := handles_resolve_selection(adornee)
	if !visible || !has_selection {
		handles_destroy_native(gizmo^, ctx^)
		gizmo^ = nil
		ctx^ = nil
		native_type^ = 0
		hovered_axis^ = kineffi.KINE_GIZMO_AXIS_NONE
		return
	}

	handles_ensure_native(renderer.Filament, gizmo, ctx, native_type, gizmo_type)
	if gizmo^ == nil {
		return
	}

	// A model drag is pinned to the pivot captured when the drag began, so a
	// non-symmetric model does not drag its own handles around as its bounding
	// box changes under rotation or scaling.
	active_pivot := selection.pivot
	if dragging^ && selection.model != nil {
		active_pivot = drag_pivot^
	}
	model := handles_cframe_matrix(active_pivot)
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
		drag_last_delta2^ = 0
		drag_pivot^ = selection.pivot
		handles_fire_axis(L, mouse_down, enum_registry, selected_axis^)
	}

	if dragging^ && left {
		first_axis, second_axis, _, is_plane := handles_plane(selected_axis^)
		if is_plane {
			first, second: f32
			if kineffi.Kine_Filament_GetGizmoPlaneDragDelta(
				   renderer.Filament,
				   gizmo^,
				   &model[0],
				   selected_axis^,
				   drag_start_x^,
				   drag_start_y^,
				   mouse_x,
				   mouse_y,
				   &first,
				   &second,
			   ) !=
			   0 {
				first_increment := handles_snap_increment(first, drag_last_delta, snap^)
				second_increment := handles_snap_increment(second, drag_last_delta2, snap^)
				drag_last_delta^ = first
				drag_last_delta2^ = second
				if apply_delta {
					handles_selection_apply_plane(
						selection,
						drag_pivot^,
						first_axis,
						second_axis,
						first_increment,
						second_increment,
						style,
					)
				}
				handles_fire_drag(L, mouse_drag, enum_registry, selected_axis^, first)
			}
		} else {
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
			increment := handles_snap_increment(delta, drag_last_delta, snap^)
			if apply_delta && increment != 0 {
				handles_selection_apply_axis(selection, drag_pivot^, selected_axis^, increment, style)
			}
			handles_fire_drag(L, mouse_drag, enum_registry, selected_axis^, delta)
		}
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
	case "Snap":
		vm.PushNumber(L, handles.snap)
	case "Color3":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, handles.Color3)
	case "Faces":
		if datatype_registry == nil {return false}
		datatypes.Push_Faces(L, datatype_registry, handles.Faces)
	case "Style":
		if enum_registry == nil {return false}
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
		case "MouseButton1Down":
			signals.Push(L, handles.mouse_button1_down)
		case "MouseButton1Up":
			signals.Push(L, handles.mouse_button1_up)
		case "MouseDrag":
			signals.Push(L, handles.mouse_drag)
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
		&handles.native_type,
		&handles.hovered_axis,
		&handles.selected_axis,
		&handles.dragging,
		&handles.previous_left,
		&handles.drag_start_x,
		&handles.drag_start_y,
		&handles.drag_last_delta,
		&handles.drag_last_delta2,
		&handles.drag_pivot,
		handles_gizmo_type_for_style(handles.Style),
		&handles.snap,
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
		&handles.native_type,
		&handles.hovered_axis,
		&handles.selected_axis,
		&handles.dragging,
		&handles.previous_left,
		&handles.drag_start_x,
		&handles.drag_start_y,
		&handles.drag_last_delta,
		&handles.drag_last_delta2,
		&handles.drag_pivot,
		kineffi.KINE_GIZMO_ROTATE,
		&handles.snap,
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
		if adornee == nil || (!Is_A(adornee, "Part") && !Is_A(adornee, "Model")) {
			_ = vm.RaiseError(L, "Adornee must be a BasePart, Model, or nil")
			return true
		}
		handles.Adornee = adornee
	case "Snap":
		handles.snap = vm.ArgNumber(L, value_index)
	case "Color3":
		if datatype_registry == nil {return false}
		handles.Color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Faces":
		if datatype_registry == nil {return false}
		handles.Faces = datatypes.Arg_Faces(L, value_index, datatype_registry)
	case "Style":
		if enum_registry == nil {return false}
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
		if datatype_registry == nil {return false}
		datatypes.Push_Axes(L, datatype_registry, handles.Axes)
	case "Color3":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, handles.Color3)
	case "Snap":
		vm.PushNumber(L, handles.snap)
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
		case "MouseButton1Down":
			signals.Push(L, handles.mouse_button1_down)
		case "MouseButton1Up":
			signals.Push(L, handles.mouse_button1_up)
		case "MouseDrag":
			signals.Push(L, handles.mouse_drag)
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
		if adornee == nil || (!Is_A(adornee, "Part") && !Is_A(adornee, "Model")) {
			_ = vm.RaiseError(L, "Adornee must be a BasePart, Model, or nil")
			return true
		}
		handles.Adornee = adornee
	case "Snap":
		handles.snap = vm.ArgNumber(L, value_index)
	case "Axes":
		if datatype_registry == nil {return false}
		handles.Axes = datatypes.Arg_Axes(L, value_index, datatype_registry)
	case "Color3":
		if datatype_registry == nil {return false}
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
		properties = []string {
			"Adornee",
			"Color3",
			"Faces",
			"Style",
			"Visible",
			"MouseButton1Down",
			"MouseButton1Up",
			"MouseDrag",
			"Snap",
		},
		events = []string{"MouseButton1Down", "MouseButton1Up", "MouseDrag"},
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
		properties = []string {
			"Adornee",
			"Axes",
			"Color3",
			"Visible",
			"MouseButton1Down",
			"MouseButton1Up",
			"MouseDrag",
			"Snap",
		},
	)
}
