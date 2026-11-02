package classes

import "core:math"

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import sdl3 "../platform"
import tracy "../util/odin-tracy"
import vm "../vm"

SURFACE_GUI_MAX_TEXTURE_DIMENSION :: 4096

SurfaceGui_Class := Class_Info {
	name   = "SurfaceGui",
	parent = &Instance_Class,
}

SurfaceGui :: struct {
	using object:                Object,
	active:                      bool,
	always_on_top:               bool,
	brightness:                  f32,
	canvas_size:                 datatypes.Vector2,
	clips_descendants:           bool,
	face:                        enums.NormalId,
	light_influence:             f32,
	max_distance:                f32,
	pixels_per_stud:             f32,
	shape:                       enums.SurfaceGuiShape,
	sizing_mode:                 enums.SurfaceGuiSizingMode,
	rendered_revision:           u64,
	z_offset:                    f32,
	enabled:                     bool,
	tool_punch_through_distance: f32,
	adornee:                     ^Object,
	native_texture:              ^kineffi.KineFilamentTex,
	native_decal:                i32,
	texture_width:               i32,
	texture_height:              i32,
	surface:                     ^kineffi.KineSkiaSurface,
	surface_width:               i32,
	surface_height:              i32,
	pointer_x:                   f32,
	pointer_y:                   f32,
	pointer_valid:               bool,
	render_dirty:                bool,
}

SurfaceGui_Init :: proc() -> SurfaceGui {
	return SurfaceGui {
		object = Object_Init(&SurfaceGui_Class),
		active = true,
		always_on_top = false,
		brightness = 1,
		canvas_size = datatypes.Vector2{X = 800, Y = 600},
		clips_descendants = true,
		face = .Front,
		light_influence = 0,
		max_distance = 1000,
		pixels_per_stud = 100,
		shape = .Flat,
		sizing_mode = .PixelsPerStud,
		z_offset = 0,
		enabled = true,
		tool_punch_through_distance = 0,
		adornee = nil,
		native_texture = nil,
		native_decal = -1,
		texture_width = 0,
		texture_height = 0,
		surface = nil,
		surface_width = 0,
		surface_height = 0,
		pointer_x = 0,
		pointer_y = 0,
		pointer_valid = false,
		render_dirty = true,
	}
}

SurfaceGui_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	gui := new(SurfaceGui)
	gui^ = SurfaceGui_Init()
	gui.name = "SurfaceGui"
	return &gui.object
}

surfacegui_destroy_renderable :: proc(gui: ^SurfaceGui, renderer: ^Renderer_Object) {
	if gui == nil {
		return
	}

	if gui.native_decal >= 0 && renderer != nil && renderer.Filament != nil {
		_ = kineffi.Kine_Filament_RemoveDecal(renderer.Filament, gui.native_decal)
	}

	gui.native_decal = -1
}

surfacegui_destroy_texture :: proc(gui: ^SurfaceGui, renderer: ^Renderer_Object) {
	if gui == nil || gui.native_texture == nil {
		return
	}

	if renderer != nil && renderer.Filament != nil {
		_ = kineffi.Kine_Filament_DestroyTex(renderer.Filament, gui.native_texture)
	}

	gui.native_texture = nil
	gui.texture_width = 0
	gui.texture_height = 0
}

surfacegui_destroy_surface :: proc(gui: ^SurfaceGui) {
	if gui == nil || gui.surface == nil {
		return
	}

	kineffi.Kine_Skia_Surface_Destroy(gui.surface)
	gui.surface = nil
	gui.surface_width = 0
	gui.surface_height = 0
}

SurfaceGui_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	gui := cast(^SurfaceGui)object

	surfacegui_destroy_renderable(gui, renderer)
	surfacegui_destroy_texture(gui, renderer)
	surfacegui_destroy_surface(gui)

	Object_Destroy(object)
	free(gui)
}

surfacegui_target_part :: proc(gui: ^SurfaceGui) -> ^Part {
	if gui == nil {
		return nil
	}

	if gui.adornee != nil && !gui.adornee.destroyed && Is_A(gui.adornee, "Part") {
		return cast(^Part)gui.adornee
	}

	parent := gui.parent
	if parent == nil || parent.destroyed || !Is_A(parent, "Part") {
		return nil
	}

	return cast(^Part)parent
}

surfacegui_canvas_size :: proc(gui: ^SurfaceGui, part: ^Part) -> (width, height: f32) {
	if gui == nil {
		return
	}

	switch gui.sizing_mode {
	case .FixedSize:
		return gui.canvas_size.X, gui.canvas_size.Y

	case .PixelsPerStud:
		if part == nil {
			return
		}

		info := part_face_info(part, gui.face, 0)
		return info.width * gui.pixels_per_stud, info.height * gui.pixels_per_stud

	case:
		return gui.canvas_size.X, gui.canvas_size.Y
	}
}

SurfaceGui_Texture_Size :: struct {
	width:  i32,
	height: i32,
	scale:  f32,
}

surfacegui_texture_size :: proc(canvas_width, canvas_height: f32) -> SurfaceGui_Texture_Size {
	if canvas_width <= 0 || canvas_height <= 0 {
		return {}
	}

	max_dimension := f32(SURFACE_GUI_MAX_TEXTURE_DIMENSION)
	scale := f32(1)

	if canvas_width > max_dimension {
		scale = min(scale, max_dimension / canvas_width)
	}

	if canvas_height > max_dimension {
		scale = min(scale, max_dimension / canvas_height)
	}

	return SurfaceGui_Texture_Size {
		width = max(1, i32(math.round(canvas_width * scale))),
		height = max(1, i32(math.round(canvas_height * scale))),
		scale = scale,
	}
}

surfacegui_render_surface :: proc(
	gui: ^SurfaceGui,
	ctx: ^Class_Step_Context,
	size: SurfaceGui_Texture_Size,
	canvas_width, canvas_height: f32,
) -> bool {
	if gui.surface == nil || gui.surface_width != size.width || gui.surface_height != size.height {
		surfacegui_destroy_surface(gui)

		gui.surface = kineffi.Kine_Skia_Surface_Create(size.width, size.height)
		if gui.surface == nil {
			return false
		}

		gui.surface_width = size.width
		gui.surface_height = size.height
	}

	kineffi.Kine_Skia_Surface_Clear(gui.surface, 0, 0, 0, 0)

	previous_surface := ctx.renderer.SkiaSurface
	previous_width := ctx.viewport_width
	previous_height := ctx.viewport_height

	ctx.renderer.SkiaSurface = gui.surface
	ctx.viewport_width = i32(canvas_width)
	ctx.viewport_height = i32(canvas_height)

	guilib.save(gui.surface)

	if size.scale != 1 {
		guilib.scale(gui.surface, size.scale, size.scale)
	}

	if gui.clips_descendants {
		guilib.clipRect(gui.surface, guilib.Rect{width = canvas_width, height = canvas_height})
	}

	ScreenGui_RenderChildren(&gui.object, ctx)

	guilib.restore(gui.surface)
	kineffi.Kine_Skia_Surface_Flush(gui.surface)

	ctx.renderer.SkiaSurface = previous_surface
	ctx.viewport_width = previous_width
	ctx.viewport_height = previous_height

	return true
}

surfacegui_unpremultiply :: proc(surface: ^kineffi.KineSkiaSurface) {
	tracy.ZoneNC("SurfaceGui Unpremultiply", 0xE5C07B)

	pixels := kineffi.Kine_Skia_Surface_GetPixels(surface)
	row_bytes := kineffi.Kine_Skia_Surface_GetRowBytes(surface)
	width := kineffi.Kine_Skia_Surface_GetWidth(surface)
	height := kineffi.Kine_Skia_Surface_GetHeight(surface)

	if pixels == nil || row_bytes == 0 || width <= 0 || height <= 0 {
		return
	}

	data := cast([^]u8)pixels

	for y in 0 ..< int(height) {
		row := y * int(row_bytes)

		for x in 0 ..< int(width) {
			index := row + x * 4
			alpha := int(data[index + 3])

			if alpha == 0 || alpha == 255 {
				continue
			}

			data[index + 0] = u8(min(255, int(data[index + 0]) * 255 / alpha))
			data[index + 1] = u8(min(255, int(data[index + 1]) * 255 / alpha))
			data[index + 2] = u8(min(255, int(data[index + 2]) * 255 / alpha))
		}
	}
}

surfacegui_upload_texture :: proc(gui: ^SurfaceGui, renderer: ^Renderer_Object) -> bool {
	if gui == nil || gui.surface == nil || renderer == nil || renderer.Filament == nil {
		return false
	}

	tracy.ZoneNC("SurfaceGui Upload", 0x56B6C2)

	surfacegui_unpremultiply(gui.surface)

	width := kineffi.Kine_Skia_Surface_GetWidth(gui.surface)
	height := kineffi.Kine_Skia_Surface_GetHeight(gui.surface)
	row_bytes := kineffi.Kine_Skia_Surface_GetRowBytes(gui.surface)
	pixels := kineffi.Kine_Skia_Surface_GetPixels(gui.surface)

	if width <= 0 || height <= 0 || row_bytes == 0 || pixels == nil {
		return false
	}

	if gui.native_texture != nil && gui.texture_width == width && gui.texture_height == height {
		if kineffi.Kine_Filament_UpdateTexFromPixels(
			   renderer.Filament,
			   gui.native_texture,
			   width,
			   height,
			   i32(row_bytes),
			   pixels,
		   ) !=
		   0 {
			return true
		}

		surfacegui_destroy_renderable(gui, renderer)
		surfacegui_destroy_texture(gui, renderer)
	}

	gui.native_texture = kineffi.Kine_Filament_CreateTexFromPixels(
		renderer.Filament,
		width,
		height,
		i32(row_bytes),
		pixels,
	)

	if gui.native_texture == nil {
		return false
	}

	gui.texture_width = width
	gui.texture_height = height
	return true
}

surfacegui_ensure_native :: proc(
	gui: ^SurfaceGui,
	renderer: ^Renderer_Object,
	info: Decal_Face_Info,
) -> bool {
	if gui.native_decal >= 0 {
		return true
	}

	if gui.native_texture == nil {
		return false
	}

	gui.native_decal = kineffi.Kine_Filament_CreateDecal(
		renderer.Filament,
		info.width,
		info.height,
		gui.native_texture,
		0,
		0,
		info.width,
		info.height,
		false,
		false,
		true,
	)

	return gui.native_decal >= 0
}

surfacegui_visible_distance :: proc(
	gui: ^SurfaceGui,
	ctx: ^Class_Step_Context,
	center: datatypes.Vector3,
) -> bool {
	if gui.max_distance <= 0 || ctx.renderer.ActiveCamera == nil {
		return true
	}

	camera_object := cast(^Object)ctx.renderer.ActiveCamera
	if !Is_A(camera_object, "Camera") {
		return true
	}

	camera := cast(^Camera)camera_object
	camera_position := datatypes.CFrame_Position(camera.CFrame)

	dx := camera_position.x - center.x
	dy := camera_position.y - center.y
	dz := camera_position.z - center.z
	distance_squared := dx * dx + dy * dy + dz * dz

	return distance_squared <= gui.max_distance * gui.max_distance
}

surfacegui_camera :: proc(renderer: ^Renderer_Object) -> ^Camera {
	if renderer == nil || renderer.ActiveCamera == nil {
		return nil
	}

	camera_object := cast(^Object)renderer.ActiveCamera
	if camera_object == nil || camera_object.destroyed || !Is_A(camera_object, "Camera") {
		return nil
	}

	return cast(^Camera)camera_object
}

surfacegui_screen_ray :: proc(
	renderer: ^Renderer_Object,
	screen_x, screen_y: f32,
) -> (
	origin, direction: datatypes.Vector3,
	ok: bool,
) {
	if renderer == nil || !renderer.HasViewportRect {
		return
	}

	rect := renderer.ViewportRect
	width := f32(rect[2])
	height := f32(rect[3])
	if width <= 0 || height <= 0 {
		return
	}

	camera := surfacegui_camera(renderer)
	if camera == nil {
		return
	}

	ui_scale := sdl3.UI_Scale > 0 ? sdl3.UI_Scale : f32(1)
	mouse_scale_x := renderer.MouseScale[0] > 0 ? renderer.MouseScale[0] : f32(1)
	mouse_scale_y := renderer.MouseScale[1] > 0 ? renderer.MouseScale[1] : f32(1)

	local_x := screen_x * mouse_scale_x * ui_scale + sdl3.UI_Safe_Left - f32(rect[0])
	local_y := screen_y * mouse_scale_y * ui_scale + sdl3.UI_Safe_Top - f32(rect[1])

	if local_x < 0 || local_x > width || local_y < 0 || local_y > height {
		return
	}

	normalized_x := (local_x / width) * 2 - 1
	normalized_y := 1 - (local_y / height) * 2
	tangent := f32(math.tan(math.to_radians(f64(CAMERA_FIELD_OF_VIEW_DEGREES)) * 0.5))
	aspect := width / height
	view := datatypes.Vector3{normalized_x * aspect * tangent, normalized_y * tangent, -1}

	origin = datatypes.CFrame_Position(camera.CFrame)
	direction = datatypes.Vec3_Unit(datatypes.CFrame_VectorToWorldSpace(camera.CFrame, view))
	ok = true
	return
}

surfacegui_ray_face :: proc(
	gui: ^SurfaceGui,
	part: ^Part,
	origin, direction: datatypes.Vector3,
) -> (
	canvas_x, canvas_y: f32,
	distance: f32,
	ok: bool,
) {
	info := part_face_info(part, gui.face, 0)
	denominator := datatypes.Vec3_Dot(direction, info.normal)
	if abs(denominator) < 0.000001 {
		return
	}

	distance =
		datatypes.Vec3_Dot(datatypes.Vec3_Subtract(info.center, origin), info.normal) / denominator

	if distance <= 0 {
		return
	}

	point := datatypes.Vec3_Add(origin, datatypes.Vec3_Multiply(direction, distance))
	delta := datatypes.Vec3_Subtract(point, info.center)
	u := datatypes.Vec3_Dot(delta, info.horizontal) / info.width + 0.5
	v := 0.5 - datatypes.Vec3_Dot(delta, info.vertical) / info.height

	if u < 0 || u > 1 || v < 0 || v > 1 {
		return
	}

	canvas_width, canvas_height := surfacegui_canvas_size(gui, part)
	if canvas_width <= 0 || canvas_height <= 0 {
		return
	}

	canvas_x = u * canvas_width
	canvas_y = v * canvas_height
	ok = true
	return
}

surfacegui_hit_test :: proc(
	registry: ^Registry,
	screen_x, screen_y: f32,
) -> (
	gui: ^SurfaceGui,
	canvas_x, canvas_y: f32,
	ok: bool,
) {
	if registry == nil || registry.renderer == nil {
		return
	}

	origin, direction, has_ray := surfacegui_screen_ray(registry.renderer, screen_x, screen_y)
	if !has_ray {
		return
	}

	camera := surfacegui_camera(registry.renderer)
	if camera == nil {
		return
	}

	camera_position := datatypes.CFrame_Position(camera.CFrame)
	best_distance := f32(1e30)

	descriptor := Find_Class(registry, "SurfaceGui")
	if descriptor == nil {
		return
	}

	for object in descriptor.instances {
		if object == nil || object.destroyed {
			continue
		}

		surface := cast(^SurfaceGui)object
		if !surface.enabled || !surface.active {
			continue
		}

		part := surfacegui_target_part(surface)
		if part == nil || !decal_in_workspace(&part.object) {
			continue
		}

		hit_x, hit_y, distance, hit := surfacegui_ray_face(surface, part, origin, direction)
		if !hit || distance >= best_distance {
			continue
		}

		if surface.max_distance > 0 {
			info := part_face_info(part, surface.face, 0)
			delta := datatypes.Vec3_Subtract(camera_position, info.center)
			if datatypes.Vec3_Dot(delta, delta) > surface.max_distance * surface.max_distance {
				continue
			}
		}

		best_distance = distance
		gui = surface
		canvas_x = hit_x
		canvas_y = hit_y
		ok = true
	}

	if ok {
		gui.pointer_x = canvas_x
		gui.pointer_y = canvas_y
		gui.pointer_valid = true
	}

	return
}

surfacegui_hit_test_for :: proc(
	gui: ^SurfaceGui,
	screen_x, screen_y: f32,
) -> (
	canvas_x, canvas_y: f32,
	ok: bool,
) {
	if gui == nil || !gui.enabled || !gui.active {
		return
	}

	part := surfacegui_target_part(gui)
	if part == nil || !decal_in_workspace(&part.object) {
		return
	}

	registry := gui.object.signal_registry
	if registry == nil || registry.renderer == nil {
		return
	}

	renderer := registry.renderer

	origin, direction, has_ray := surfacegui_screen_ray(renderer, screen_x, screen_y)
	if !has_ray {
		return
	}

	canvas_x, canvas_y, _, ok = surfacegui_ray_face(gui, part, origin, direction)
	return
}

surfacegui_needs_animation :: proc(object: ^Object) -> bool {
	if object == nil {
		return false
	}

	for child in object.children {
		if child == nil || child.destroyed {
			continue
		}

		if Is_A(child, "TextBox") {
			box := cast(^TextBox)child
			if box.focused || box.focus_animation > 0.001 {
				return true
			}
		}

		if Is_A(child, "ScrollingFrame") {
			frame := cast(^ScrollingFrame)child
			if frame.scrollbar_alpha > 0.001 ||
			   frame.target_position.X != frame.canvas_position.X ||
			   frame.target_position.Y != frame.canvas_position.Y ||
			   frame.dragging_vertical ||
			   frame.dragging_horizontal ||
			   frame.dragging_content {
				return true
			}
		}

		if surfacegui_needs_animation(child) {
			return true
		}
	}

	return false
}

SurfaceGui_Step :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	gui := cast(^SurfaceGui)object

	if gui == nil || ctx == nil || ctx.renderer == nil || ctx.renderer.Filament == nil {
		return
	}

	renderer := ctx.renderer

	if !gui.enabled {
		surfacegui_destroy_renderable(gui, renderer)
		return
	}

	part := surfacegui_target_part(gui)
	if part == nil || !decal_in_workspace(&part.object) {
		surfacegui_destroy_renderable(gui, renderer)
		return
	}

	info := part_face_info(part, gui.face, 0)

	if info.width <= 0 || info.height <= 0 {
		surfacegui_destroy_renderable(gui, renderer)
		return
	}

	if !surfacegui_visible_distance(gui, ctx, info.center) {
		surfacegui_destroy_renderable(gui, renderer)
		return
	}

	canvas_width, canvas_height := surfacegui_canvas_size(gui, part)
	if canvas_width <= 0 || canvas_height <= 0 {
		surfacegui_destroy_renderable(gui, renderer)
		return
	}

	size := surfacegui_texture_size(canvas_width, canvas_height)
	if size.width <= 0 || size.height <= 0 {
		surfacegui_destroy_renderable(gui, renderer)
		return
	}

	revision := gui_render_revision
	needs_render :=
		gui.render_dirty ||
		gui.rendered_revision != revision ||
		gui.surface == nil ||
		gui.native_texture == nil ||
		size.width != gui.surface_width ||
		size.height != gui.surface_height ||
		surfacegui_needs_animation(&gui.object)

	if needs_render {
		if size.width != gui.surface_width || size.height != gui.surface_height {
			surfacegui_destroy_renderable(gui, renderer)
		}

		if !surfacegui_render_surface(gui, ctx, size, canvas_width, canvas_height) {
			surfacegui_destroy_renderable(gui, renderer)
			return
		}

		if !surfacegui_upload_texture(gui, renderer) {
			surfacegui_destroy_renderable(gui, renderer)
			return
		}

		gui.rendered_revision = revision
		gui.render_dirty = false
	}

	render_info := info
	render_info.center = decal_vec_add(
		info.center,
		decal_vec_mul(info.normal, 0.002 + gui.z_offset * 0.001),
	)

	if !surfacegui_ensure_native(gui, renderer, render_info) {
		return
	}

	transform := decal_transform(render_info)

	_ = kineffi.Kine_Filament_SetDecalTransform(renderer.Filament, gui.native_decal, &transform[0])

	_ = kineffi.Kine_Filament_SetDecalTiling(
		renderer.Filament,
		gui.native_decal,
		render_info.width,
		render_info.height,
		0,
		0,
		render_info.width,
		render_info.height,
	)

	_ = kineffi.Kine_Filament_EditDecal(
		renderer.Filament,
		gui.native_decal,
		render_info.width,
		render_info.height,
		false,
		false,
		true,
	)

	brightness := gui.brightness
	if gui.always_on_top || gui.light_influence >= 1 {
		brightness = 1
	}

	_ = kineffi.Kine_Filament_SetDecalColor(
		renderer.Filament,
		gui.native_decal,
		brightness,
		brightness,
		brightness,
		1,
	)
}

SurfaceGui_Get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	gui := cast(^SurfaceGui)object

	switch key {
	case "Active":
		vm.PushBoolean(L, gui.active)

	case "AlwaysOnTop":
		vm.PushBoolean(L, gui.always_on_top)

	case "Brightness":
		vm.PushNumber(L, f64(gui.brightness))

	case "CanvasSize":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(L, datatype_registry, gui.canvas_size)

	case "ClipsDescendants":
		vm.PushBoolean(L, gui.clips_descendants)

	case "Face":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(L, enum_registry, "NormalId", i64(gui.face))

	case "LightInfluence":
		vm.PushNumber(L, f64(gui.light_influence))

	case "MaxDistance":
		vm.PushNumber(L, f64(gui.max_distance))

	case "PixelsPerStud":
		vm.PushNumber(L, f64(gui.pixels_per_stud))

	case "Shape":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(L, enum_registry, "SurfaceGuiShape", i64(gui.shape))

	case "SizingMode":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"SurfaceGuiSizingMode",
			i64(gui.sizing_mode),
		)

	case "ZOffset":
		vm.PushNumber(L, f64(gui.z_offset))

	case "Enabled":
		vm.PushBoolean(L, gui.enabled)

	case "Adornee":
		Push_Object(L, gui.adornee)

	case "ToolPunchThroughDistance":
		vm.PushNumber(L, f64(gui.tool_punch_through_distance))

	case:
		return false
	}

	return true
}

SurfaceGui_Set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	gui := cast(^SurfaceGui)object

	switch key {
	case "Active":
		gui.active = vm.ArgBoolean(L, value_index)

	case "AlwaysOnTop":
		gui.always_on_top = vm.ArgBoolean(L, value_index)

	case "Brightness":
		gui.brightness = clamp(f32(vm.ArgNumber(L, value_index)), 0, 1000)

	case "CanvasSize":
		if datatype_registry == nil {
			return false
		}

		gui.canvas_size = datatypes.Arg_Vector2(L, value_index, datatype_registry)

	case "ClipsDescendants":
		gui.clips_descendants = vm.ArgBoolean(L, value_index)

	case "Face":
		if enum_registry == nil {
			return false
		}

		item := enums.Arg_Item(L, value_index, enum_registry, "NormalId")

		gui.face = enums.NormalId(item.value)

	case "LightInfluence":
		gui.light_influence = clamp(f32(vm.ArgNumber(L, value_index)), 0, 1)

	case "MaxDistance":
		gui.max_distance = max(f32(vm.ArgNumber(L, value_index)), 0)

	case "PixelsPerStud":
		gui.pixels_per_stud = max(f32(vm.ArgNumber(L, value_index)), 0.001)

	case "Shape":
		if enum_registry == nil {
			return false
		}

		item := enums.Arg_Item(L, value_index, enum_registry, "SurfaceGuiShape")

		gui.shape = enums.SurfaceGuiShape(item.value)

	case "SizingMode":
		if enum_registry == nil {
			return false
		}

		item := enums.Arg_Item(L, value_index, enum_registry, "SurfaceGuiSizingMode")

		gui.sizing_mode = enums.SurfaceGuiSizingMode(item.value)

	case "ZOffset":
		gui.z_offset = f32(vm.ArgNumber(L, value_index))

	case "Enabled":
		gui.enabled = vm.ArgBoolean(L, value_index)

	case "Adornee":
		if vm.IsNil(L, value_index) {
			gui.adornee = nil
			return true
		}

		adornee := object_from_argument(L, value_index)
		if adornee == nil || !Is_A(adornee, "BasePart") {
			_ = vm.RaiseError(L, "Adornee must be a BasePart or nil")
			return true
		}

		gui.adornee = adornee

	case "ToolPunchThroughDistance":
		gui.tool_punch_through_distance = max(f32(vm.ArgNumber(L, value_index)), 0)

	case:
		return false
	}

	return true
}

SurfaceGui_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^SurfaceGui)source
	dst := cast(^SurfaceGui)destination

	dst.active = src.active
	dst.always_on_top = src.always_on_top
	dst.brightness = src.brightness
	dst.canvas_size = src.canvas_size
	dst.clips_descendants = src.clips_descendants
	dst.face = src.face
	dst.light_influence = src.light_influence
	dst.max_distance = src.max_distance
	dst.pixels_per_stud = src.pixels_per_stud
	dst.shape = src.shape
	dst.sizing_mode = src.sizing_mode
	dst.z_offset = src.z_offset
	dst.enabled = src.enabled
	dst.tool_punch_through_distance = src.tool_punch_through_distance
	dst.adornee = src.adornee

	dst.native_texture = nil
	dst.native_decal = -1
	dst.texture_width = 0
	dst.texture_height = 0

	dst.surface = nil
	dst.surface_width = 0
	dst.surface_height = 0

	dst.pointer_x = 0
	dst.pointer_y = 0
	dst.pointer_valid = false

	dst.rendered_revision = 0
	dst.render_dirty = true
}

Register_SurfaceGui :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&SurfaceGui_Class,
		SurfaceGui_construct,
		SurfaceGui_destroy,
		get = SurfaceGui_Get,
		set = SurfaceGui_Set,
		properties = []string {
			"Active",
			"AlwaysOnTop",
			"Brightness",
			"CanvasSize",
			"ClipsDescendants",
			"Face",
			"LightInfluence",
			"MaxDistance",
			"PixelsPerStud",
			"Shape",
			"SizingMode",
			"ZOffset",
			"Enabled",
			"Adornee",
			"ToolPunchThroughDistance",
		},
		clone = SurfaceGui_clone,
		_step = SurfaceGui_Step,
		_step_phase = .Render_3D,
	)
}
