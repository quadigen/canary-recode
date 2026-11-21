package classes

import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"
import "core:math"

BillboardGui_Class := Class_Info {
	name   = "BillboardGui",
	parent = &LayerCollector_Class,
}

BillboardGui :: struct {
	using object:                                                                                               Object,
	adornee,
	player_to_hide_from:                                                                               ^Object,
	enabled,
	active,
	always_on_top,
	clips_descendants:                                                          bool,
	size:                                                                                                       datatypes.UDim2,
	size_offset:                                                                                                datatypes.Vector2,
	studs_offset,
	studs_offset_world,
	extents_offset,
	extents_offset_world:                                     datatypes.Vector3,
	brightness,
	light_influence,
	max_distance,
	distance_lower,
	distance_upper,
	distance_step,
	current_distance: f64,
}
BillboardGui_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	g := new(BillboardGui)
	g.object = Object_Init(&BillboardGui_Class, "BillboardGui")
	g.enabled, g.active, g.clips_descendants = true, true, true
	g.brightness = 1
	g.max_distance = math.F32_MAX
	g.distance_upper = math.F32_MAX
	g.size = {0, 0, 0, 0}
	g.size.X_Offset, g.size.Y_Offset = 200, 50
	return &g.object
}
BillboardGui_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^BillboardGui)object)
}
BillboardGui_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^BillboardGui)source, cast(^BillboardGui)destination
	dst.adornee, dst.player_to_hide_from = src.adornee, src.player_to_hide_from
	dst.enabled, dst.active, dst.always_on_top, dst.clips_descendants =
		src.enabled, src.active, src.always_on_top, src.clips_descendants
	dst.size, dst.size_offset = src.size, src.size_offset
	dst.studs_offset, dst.studs_offset_world, dst.extents_offset, dst.extents_offset_world =
		src.studs_offset, src.studs_offset_world, src.extents_offset, src.extents_offset_world
	dst.brightness, dst.light_influence, dst.max_distance =
		src.brightness, src.light_influence, src.max_distance
	dst.distance_lower, dst.distance_upper, dst.distance_step =
		src.distance_lower, src.distance_upper, src.distance_step
}
billboard_target :: proc(g: ^BillboardGui) -> (^Part, datatypes.Vector3, bool) {
	target := g.adornee
	if target == nil {target = g.parent}
	if target == nil || target.destroyed {return nil, {}, false}
	offset: datatypes.Vector3
	if Is_A_Class(target, &Attachment_Class) {
		offset = (cast(^Attachment)target).position
		target = target.parent
	}
	if target == nil ||
	   target.destroyed ||
	   !Is_A_Class(target, &Part_Class) {return nil, {}, false}
	for ancestor := target.parent; ancestor != nil; ancestor = ancestor.parent {
		if Is_A(ancestor, "Workspace") {
			part := cast(^Part)target
			return part, datatypes.CFrame_PointToWorldSpace(part.cframe, offset), true
		}
	}
	return nil, {}, false
}

BillboardGui_Project :: proc(
	g: ^BillboardGui,
	ctx: ^Class_Step_Context,
) -> (
	f32,
	f32,
	f32,
	f32,
	bool,
) {
	if !g.enabled {return 0, 0, 0, 0, false}
	ren := ctx.renderer
	if ren == nil && g.signal_registry != nil {ren = g.signal_registry.renderer}
	if ren == nil || ren.ActiveCamera == nil {return 0, 0, 0, 0, false}
	camera := cast(^Camera)ren.ActiveCamera
	part, point, ok := billboard_target(g)
	if !ok {return 0, 0, 0, 0, false}
	frame := camera.CFrame
	extent := datatypes.Vec3_Multiply(part.size, 0.5)
	point = datatypes.Vec3_Add(point, g.studs_offset_world)
	point = datatypes.Vec3_Add(point, datatypes.CFrame_VectorToWorldSpace(frame, g.studs_offset))
	point = datatypes.Vec3_Add(
		point,
		{
			extent.x * g.extents_offset_world.x,
			extent.y * g.extents_offset_world.y,
			extent.z * g.extents_offset_world.z,
		},
	)
	point = datatypes.Vec3_Add(
		point,
		datatypes.CFrame_VectorToWorldSpace(
			frame,
			{
				extent.x * g.extents_offset.x,
				extent.y * g.extents_offset.y,
				extent.z * g.extents_offset.z,
			},
		),
	)
	delta := datatypes.Vec3_Subtract(point, datatypes.CFrame_Position(frame))
	distance := datatypes.Vec3_Magnitude(delta)
	g.current_distance = distance
	depth := datatypes.Vec3_Dot(delta, datatypes.CFrame_LookVector(frame))
	if depth <= 0.01 || distance > g.max_distance {return 0, 0, 0, 0, false}
	w, h := f64(ctx.viewport_width), f64(ctx.viewport_height)
	if w <= 0 || h <= 0 {return 0, 0, 0, 0, false}
	tangent := math.tan(math.to_radians(f64(camera.field_of_view)) * 0.5)
	if tangent <= 0 {return 0, 0, 0, 0, false}
	pixels_per_stud := h / (2 * depth * tangent)
	sizing_distance := max(depth, max(0.01, g.distance_lower))
	if g.distance_upper > 0 {sizing_distance = min(sizing_distance, g.distance_upper)}
	sizing_scale := h / (2 * sizing_distance * tangent)
	width := f64(g.size.X_Scale) * sizing_scale + f64(g.size.X_Offset)
	height := f64(g.size.Y_Scale) * sizing_scale + f64(g.size.Y_Offset)
	x :=
		w * 0.5 +
		datatypes.Vec3_Dot(delta, datatypes.CFrame_RightVector(frame)) * pixels_per_stud -
		width * 0.5 +
		f64(g.size_offset.X) * width
	y :=
		h * 0.5 -
		datatypes.Vec3_Dot(delta, datatypes.CFrame_UpVector(frame)) * pixels_per_stud -
		height * 0.5 -
		f64(g.size_offset.Y) * height
	return f32(x),
		f32(y),
		f32(max(0, width)),
		f32(max(0, height)),
		width > 0 && height > 0 && x + width >= 0 && y + height >= 0 && x < w && y < h
}

BillboardGui_render :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	g := cast(^BillboardGui)object
	if !ctx.gui_overlay || ctx.renderer == nil || ctx.renderer.SkiaSurface == nil {return}
	x, y, w, h, visible := BillboardGui_Project(g, ctx)
	if !visible {return}
	if !g.always_on_top &&
	   g.signal_registry != nil &&
	   g.signal_registry.billboard_occluded != nil {
		camera := cast(^Camera)ctx.renderer.ActiveCamera
		part, point, ok := billboard_target(g)
		if ok && camera != nil {

			frame := camera.CFrame
			extent := datatypes.Vec3_Multiply(part.size, 0.5)
			point = datatypes.Vec3_Add(point, g.studs_offset_world)
			point = datatypes.Vec3_Add(
				point,
				datatypes.CFrame_VectorToWorldSpace(frame, g.studs_offset),
			)
			point = datatypes.Vec3_Add(
				point,
				{
					extent.x * g.extents_offset_world.x,
					extent.y * g.extents_offset_world.y,
					extent.z * g.extents_offset_world.z,
				},
			)
			point = datatypes.Vec3_Add(
				point,
				datatypes.CFrame_VectorToWorldSpace(
					frame,
					{
						extent.x * g.extents_offset.x,
						extent.y * g.extents_offset.y,
						extent.z * g.extents_offset.z,
					},
				),
			)
			if g.signal_registry.billboard_occluded(
				g.signal_registry.part_body_ctx,
				&part.object,
				datatypes.CFrame_Position(frame),
				point,
			) {return}
		}
	}
	previous := ctx.gui_transform
	previous_cache := ctx.cache_gui
	ctx.gui_transform = {object, x, y, w, h}
	ctx.cache_gui = false
	ctx.gui_dynamic = true
	defer {ctx.gui_transform = previous; ctx.cache_gui = previous_cache}
	if g.clips_descendants {
		guilib.save(ctx.renderer.SkiaSurface)
		guilib.clipRect(ctx.renderer.SkiaSurface, {x = x, y = y, width = w, height = h})
	}
	defer if g.clips_descendants {guilib.restore(ctx.renderer.SkiaSurface)}
	ScreenGui_RenderChildren(object, ctx)
}
BillboardGui_get :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	g := cast(^BillboardGui)object
	switch key {
	case "Adornee":
		Push_Object(L, g.adornee)
	case "PlayerToHideFrom":
		Push_Object(L, g.player_to_hide_from)
	case "Enabled":
		vm.PushBoolean(L, g.enabled)
	case "Active":
		vm.PushBoolean(L, g.active)
	case "AlwaysOnTop", "RenderOnTop":
		vm.PushBoolean(L, g.always_on_top)
	case "ClipsDescendants":
		vm.PushBoolean(L, g.clips_descendants)
	case "Size":
		datatypes.Push_UDim2(L, d, g.size)
	case "SizeOffset":
		datatypes.Push_Vector2(L, d, g.size_offset)
	case "StudsOffset":
		datatypes.Push_Vector3(L, g.studs_offset)
	case "StudsOffsetWorldSpace":
		datatypes.Push_Vector3(L, g.studs_offset_world)
	case "ExtentsOffset":
		datatypes.Push_Vector3(L, g.extents_offset)
	case "ExtentsOffsetWorldSpace":
		datatypes.Push_Vector3(L, g.extents_offset_world)
	case "Brightness":
		vm.PushNumber(L, g.brightness)
	case "LightInfluence":
		vm.PushNumber(L, g.light_influence)
	case "MaxDistance":
		vm.PushNumber(L, g.max_distance)
	case "DistanceLowerLimit":
		vm.PushNumber(L, g.distance_lower)
	case "DistanceUpperLimit":
		vm.PushNumber(L, g.distance_upper)
	case "DistanceStep":
		vm.PushNumber(L, g.distance_step)
	case "CurrentDistance":
		vm.PushNumber(L, g.current_distance)
	case:
		return false
	}
	return true
}
BillboardGui_set :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	g := cast(^BillboardGui)object
	switch key {
	case "Adornee", "PlayerToHideFrom":
		value := Object_From_Argument(L, index)
		if !vm.IsNil(L, index) && value == nil {return false}
		if key == "Adornee" {g.adornee = value} else {g.player_to_hide_from = value}
	case "Enabled":
		g.enabled = vm.ArgBoolean(L, index)
	case "Active":
		g.active = vm.ArgBoolean(L, index)
	case "AlwaysOnTop", "RenderOnTop":
		g.always_on_top = vm.ArgBoolean(L, index)
	case "ClipsDescendants":
		g.clips_descendants = vm.ArgBoolean(L, index)
	case "Size":
		g.size = datatypes.Arg_UDim2(L, index, d)
	case "SizeOffset":
		g.size_offset = datatypes.Arg_Vector2(L, index, d)
	case "StudsOffset":
		g.studs_offset = datatypes.Arg_Vector3(L, index)
	case "StudsOffsetWorldSpace":
		g.studs_offset_world = datatypes.Arg_Vector3(L, index)
	case "ExtentsOffset":
		g.extents_offset = datatypes.Arg_Vector3(L, index)
	case "ExtentsOffsetWorldSpace":
		g.extents_offset_world = datatypes.Arg_Vector3(L, index)
	case "Brightness":
		g.brightness = vm.ArgNumber(L, index)
	case "LightInfluence":
		g.light_influence = vm.ArgNumber(L, index)
	case "MaxDistance":
		g.max_distance = vm.ArgNumber(L, index)
	case "DistanceLowerLimit":
		g.distance_lower = vm.ArgNumber(L, index)
	case "DistanceUpperLimit":
		g.distance_upper = vm.ArgNumber(L, index)
	case "DistanceStep":
		g.distance_step = vm.ArgNumber(L, index)
	case:
		return false
	}
	Gui_Layout_Mark_Dirty()
	return true
}
Register_BillboardGui :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&BillboardGui_Class,
		BillboardGui_construct,
		BillboardGui_destroy,
		get = BillboardGui_get,
		set = BillboardGui_set,
		clone = BillboardGui_clone,
		_step = BillboardGui_render,
		properties = []string {
			"Adornee",
			"PlayerToHideFrom",
			"Enabled",
			"Active",
			"AlwaysOnTop",
			"RenderOnTop",
			"ClipsDescendants",
			"Size",
			"SizeOffset",
			"StudsOffset",
			"StudsOffsetWorldSpace",
			"ExtentsOffset",
			"ExtentsOffsetWorldSpace",
			"Brightness",
			"LightInfluence",
			"MaxDistance",
			"DistanceLowerLimit",
			"DistanceUpperLimit",
			"DistanceStep",
			"CurrentDistance",
		},
	)
}
