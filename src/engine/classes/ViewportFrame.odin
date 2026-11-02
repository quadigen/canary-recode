package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import materials "../material"
import sdl3 "../platform"
import vm "../vm"
import "core:math"

ViewportFrame_Class := Class_Info {
	name   = "ViewportFrame",
	parent = &GuiObject_Class,
}
ViewportFrame_MeshPart_Provider: proc(
	part: ^MeshPart,
	ctx: ^kineffi.KineFilamentContext,
) -> ^kineffi.KineFilamentMesh

ViewportFrame :: struct {
	using gui_object:         GuiObject,
	current_camera:           ^Camera,
	ambient:                  datatypes.Color3,
	light_color:              datatypes.Color3,
	light_direction:          datatypes.Vector3,
	image_color:              datatypes.Color3,
	image_transparency:       f32,
	resolution_scale:         f32,
	update_rate:              f32,
	shadows, post_processing: bool,
	elapsed:                  f32,
	native:                   ^kineffi.KineFilamentViewport,
	items:                    [dynamic]kineffi.KineFilamentDrawItem,
}

ViewportFrame_Init :: proc() -> ViewportFrame {
	gui := GuiObject_Init()
	gui.object.class = &ViewportFrame_Class
	gui.clips_descendants = true
	gui.input_sink = true
	return ViewportFrame {
		gui_object = gui,
		ambient = {0.5, 0.5, 0.5},
		light_color = {1, 1, 1},
		light_direction = {-1, -1, -1},
		image_color = {1, 1, 1},
		resolution_scale = 1,
		update_rate = 60,
		shadows = true,
		post_processing = true,
	}
}
viewport_frame_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	frame := new(ViewportFrame)
	frame^ = ViewportFrame_Init()
	frame.name = "ViewportFrame"
	return &frame.object
}
viewport_frame_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	frame := cast(^ViewportFrame)object
	if frame.native != nil {kineffi.Kine_Filament_Viewport_Destroy(frame.native)}
	delete(frame.items)
	GuiObject_Free_Signals(&frame.gui_object)
	Object_Destroy(object)
	free(frame)
}
viewport_frame_get :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	frame := cast(^ViewportFrame)object
	switch key {
	case "CurrentCamera":
		Push_Object(L, cast(^Object)frame.current_camera)
	case "Ambient":
		datatypes.Push_Color3(L, types, frame.ambient)
	case "LightColor":
		datatypes.Push_Color3(L, types, frame.light_color)
	case "LightDirection":
		datatypes.Push_Vector3(L, frame.light_direction)
	case "ImageColor3":
		datatypes.Push_Color3(L, types, frame.image_color)
	case "ImageTransparency":
		vm.PushNumber(L, f64(frame.image_transparency))
	case "ResolutionScale":
		vm.PushNumber(L, f64(frame.resolution_scale))
	case "UpdateRate":
		vm.PushNumber(L, f64(frame.update_rate))
	case "Shadows":
		vm.PushBoolean(L, frame.shadows)
	case "PostProcessing":
		vm.PushBoolean(L, frame.post_processing)
	case:
		return GuiObject_get(L, object, types, enums, key)
	}
	return true
}
viewport_frame_set :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	frame := cast(^ViewportFrame)object
	switch key {
	case "CurrentCamera":
		camera := object_from_argument(L, index)
		if !vm.IsNil(L, index) && (camera == nil || !Is_A_Class(camera, &Camera_Class)) {
			_ = vm.RaiseError(L, "ViewportFrame.CurrentCamera must be a Camera or nil")
			return true
		}
		frame.current_camera = cast(^Camera)camera
		frame.elapsed = 1
	case "Ambient":
		frame.ambient = datatypes.Arg_Color3(L, index, types)
	case "LightColor":
		frame.light_color = datatypes.Arg_Color3(L, index, types)
	case "LightDirection":
		frame.light_direction = datatypes.Arg_Vector3(L, index)
	case "ImageColor3":
		frame.image_color = datatypes.Arg_Color3(L, index, types)
	case "ImageTransparency":
		frame.image_transparency = clamp(f32(vm.ArgNumber(L, index)), 0, 1)
	case "ResolutionScale":
		frame.resolution_scale = clamp(f32(vm.ArgNumber(L, index)), 0.25, 2)
	case "UpdateRate":
		frame.update_rate = clamp(f32(vm.ArgNumber(L, index)), 0, 240)
	case "Shadows":
		frame.shadows = vm.ArgBoolean(L, index)
	case "PostProcessing":
		frame.post_processing = vm.ArgBoolean(L, index)
	case:
		return GuiObject_set(L, object, types, enums, key, index)
	}
	return true
}
viewport_frame_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^ViewportFrame)source, cast(^ViewportFrame)destination
	dst.current_camera = src.current_camera
	dst.ambient =
		src.ambient; dst.light_color = src.light_color; dst.light_direction = src.light_direction
	dst.image_color = src.image_color; dst.image_transparency = src.image_transparency
	dst.resolution_scale = src.resolution_scale; dst.update_rate = src.update_rate
	dst.shadows = src.shadows; dst.post_processing = src.post_processing
}

viewport_frame_find_clone :: proc(src, dst, target: ^Object) -> ^Object {
	if src == target {return dst}
	next := 0
	for child in src.children {
		if child == nil || !child.archivable {continue}
		if next >= len(dst.children) {break}
		if result := viewport_frame_find_clone(child, dst.children[next], target);
		   result != nil {return result}
		next += 1
	}
	return nil
}
ViewportFrame_Remap_Cloned_Camera :: proc(source, destination: ^Object) {
	target := (cast(^ViewportFrame)source).current_camera
	if target == nil {return}
	if copy := viewport_frame_find_clone(source, destination, &target.object); copy != nil {
		(cast(^ViewportFrame)destination).current_camera = cast(^Camera)copy
	}
}
ViewportFrame_Camera_Destroyed :: proc(camera: ^Camera) {
	registry := camera.signal_registry
	if registry == nil {return}
	descriptor := Find_Class(registry, "ViewportFrame")
	if descriptor == nil {return}
	for object in descriptor.instances {
		if object == nil || object.destroyed {continue}
		frame := cast(^ViewportFrame)object
		if frame.current_camera == camera {frame.current_camera = nil}
	}
}
viewport_frame_hash :: proc(hash: u64, value: u64) -> u64 {return (hash ~ value) * 1099511628211}
viewport_frame_collect :: proc(
	frame: ^ViewportFrame,
	root: ^Object,
	ctx: ^kineffi.KineFilamentContext,
	hash: ^u64,
) {
	for child in root.children {
		if child == nil || child.destroyed || Is_A_Class(child, &ViewportFrame_Class) {continue}
		if Is_A_Class(child, &Part_Class) {
			part := cast(^Part)child
			if part.transparency < 1 {
				mesh: ^kineffi.KineFilamentMesh
				if part.material == .Water {
					mesh = kineffi.Kine_Filament_Viewport_Primitive(
						ctx,
						kineffi.KINE_MESH_WATER_GRID,
					)
				} else if Is_A_Class(child, &MeshPart_Class) &&
				   ViewportFrame_MeshPart_Provider != nil {
					mesh = ViewportFrame_MeshPart_Provider(cast(^MeshPart)child, ctx)
				}
				if mesh == nil {
					bytes, ok := highlight_shape_glb(part.shape)
					if ok {
						mesh = kineffi.Kine_Filament_Viewport_Mesh(
							ctx,
							u64(part.shape) + 1,
							raw_data(bytes),
							uintptr(len(bytes)),
							"glb",
						)
						kineffi.Kine_Filament_SetUseImportedMaterials(ctx, mesh, false)
					}
				}
				if mesh != nil {
					cf, size := part.cframe, part.size
					scale: f32 = part.material == .Water ? 1 : 0.5
					item := kineffi.KineFilamentDrawItem {
						mesh         = mesh,
						transform    = {
							cf.r00 * size.x * scale,
							cf.r01 * size.y * scale,
							cf.r02 * size.z * scale,
							cf.x,
							cf.r10 * size.x * scale,
							cf.r11 * size.y * scale,
							cf.r12 * size.z * scale,
							cf.y,
							cf.r20 * size.x * scale,
							cf.r21 * size.y * scale,
							cf.r22 * size.z * scale,
							cf.z,
							0,
							0,
							0,
							1,
						},
						r            = part.color.R,
						g            = part.color.G,
						b            = part.color.B,
						transmission = f32(1 - part.transparency),
					}
					entry, params := materials.Lookup(part.material)
					shader, shader_revision := MaterialVariant_Resolve(
						child.signal_registry,
						part.material_variant,
						ctx,
					)
					item.shader = shader
					hash^ = viewport_frame_hash(hash^, u64(uintptr(shader)))
					hash^ = viewport_frame_hash(hash^, shader_revision)
					item.materialKind = params.kind
					item.param1 =
						params.param1; item.param2 = params.param2; item.param3 = params.param3
					item.tex = entry.texture
					if params.kind ==
					   kineffi.KINE_MAT_GLASS {item.transmission = f32(part.transparency)}
					if params.kind ==
					   kineffi.KINE_MAT_WATER {item.transmission = params.transmission}
					mesh_texture := kineffi.Kine_Filament_GetMeshTexture(mesh)
					if mesh_texture != nil &&
					   params.kind ==
						   kineffi.KINE_MAT_DEFAULT {item.tex = mesh_texture; item.param3 = 1}
					if item.tex != nil &&
					   mesh_texture == nil &&
					   params.kind ==
						   kineffi.KINE_MAT_DEFAULT {item.param3 = max(f32(1), max(size.x, max(size.y, size.z)) / 4)}
					hash^ = viewport_frame_hash(hash^, u64(uintptr(item.tex)))
					hash^ = viewport_frame_hash(hash^, u64(item.materialKind))
					for value in ([3]f32{item.param1, item.param2, item.param3}) {hash^ = viewport_frame_hash(hash^, u64(transmute(u32)value))}
					item.flags = u32(kineffi.KINE_FILAMENT_DRAW_RECEIVE_SHADOWS)
					if part.castshadow {item.flags |= u32(kineffi.KINE_FILAMENT_DRAW_CAST_SHADOWS)}
					hash^ = viewport_frame_hash(hash^, u64(item.flags))
					hash^ = viewport_frame_hash(hash^, u64(uintptr(mesh)))
					for value in item.transform {hash^ = viewport_frame_hash(hash^, u64(transmute(u32)value))}
					for value in ([4]f32{item.r, item.g, item.b, item.transmission}) {hash^ = viewport_frame_hash(hash^, u64(transmute(u32)value))}
					append(&frame.items, item)
				}
			}
		}
		viewport_frame_collect(frame, child, ctx, hash)
	}
}


viewport_frame_effects :: proc(root: ^Object, s: ^kineffi.KineViewportSettings) {
	for child in root.children {
		if child == nil || child.destroyed {continue}
		switch Get_Class_Name(child) {
		case "BloomEffect":
			e := cast(^BloomEffect)child; s.effectMask |= 1
			s.bloom = {
				e.enabled ? 1 : 0,
				f32(e.intensity),
				f32(e.size),
				e.threshold > 0 ? 1 : 0,
				e.lens_flare ? 1 : 0,
			}
		case "BlurEffect":
			e := cast(^BlurEffect)child; s.effectMask |= 1
			s.bloom = {e.enabled ? 1 : 0, f32(e.size / 100), f32(max(8, e.size)), 0, 0}
		case "SSAOEffect":
			e := cast(^SSAOEffect)child; s.effectMask |= 2
			s.ao = {
				e.enabled ? 1 : 0,
				f32(e.radius),
				f32(e.power),
				f32(e.intensity),
				f32(e.quality),
				f32(e.ao_type),
				0,
			}
		case "DepthOfFieldEffect":
			e := cast(^DepthOfFieldEffect)child; s.effectMask |= 4
			s.dof = DepthOfFieldEffect_Render_Options(e)
		case "ColorCorrectionEffect":
			e := cast(^ColorCorrectionEffect)child; s.effectMask |= 8
			s.color = {
				e.enabled ? 1 : 0,
				f32(e.brightness),
				f32(1 + e.contrast),
				f32(1 + e.saturation),
				e.tint_color.R,
				e.tint_color.G,
				e.tint_color.B,
			}
		case "VignetteEffect":
			e := cast(^VignetteEffect)child; s.effectMask |= 16
			s.vignette = {
				e.enabled ? 1 : 0,
				f32(e.midpoint),
				f32(e.roundness),
				f32(e.feather),
				e.color.R,
				e.color.G,
				e.color.B,
				f32(1 - e.transparency),
			}
		case "ScreenSpaceReflectionsEffect":
			e := cast(^ScreenSpaceReflectionsEffect)child; s.effectMask |= 32
			s.reflections = {
				e.enabled ? 1 : 0,
				f32(e.thickness),
				f32(e.bias),
				f32(e.max_distance),
				f32(e.stride),
			}
		case "AntiAliasingEffect":
			e := cast(^AntiAliasingEffect)child; s.effectMask |= 64
			s.antialiasing = {
				e.fxaa || e.taa ? 1 : 0,
				e.msaa ? 1 : 0,
				f32(e.sample_count),
				e.enabled ? 1 : 0,
			}
		case "DitheringEffect":
			e := cast(^DitheringEffect)child; s.effectMask |= 128; s.dithering = e.enabled ? 1 : 0
		case "RenderQualityEffect":
			e := cast(^RenderQualityEffect)child; s.effectMask |= 256
			s.quality = e.enabled ? i32(e.quality) : 2
		}
	}
}


ViewportFrame_Is_Visible :: proc(frame: ^ViewportFrame, width, height: f32) -> bool {
	if !GuiObject_effectively_visible(&frame.gui_object) ||
	   frame.current_camera == nil ||
	   frame.image_transparency >= 1 {return false}
	position, size := frame.absolute_position, frame.absolute_size
	if size.X <= 0 ||
	   size.Y <= 0 ||
	   position.X + size.X <= 0 ||
	   position.Y + size.Y <= 0 ||
	   position.X >= width ||
	   position.Y >= height {return false}
	left, top, right, bottom :=
		max(position.X, 0),
		max(position.Y, 0),
		min(position.X + size.X, width),
		min(position.Y + size.Y, height)
	has_screen := false
	for parent := frame.object.parent; parent != nil; parent = parent.parent {
		if Is_A(parent, "ScreenGui") {has_screen = true}
		if Is_A(parent, "GuiObject") {
			gui := cast(^GuiObject)parent
			if gui.clips_descendants || Is_A(parent, "ScrollingFrame") {
				p, s := gui.absolute_position, gui.absolute_size
				left = max(
					left,
					p.X,
				); top = max(top, p.Y); right = min(right, p.X + s.X); bottom = min(bottom, p.Y + s.Y)
			}
		}
	}
	return has_screen && right > left && bottom > top
}
ViewportFrame_Prepare_All :: proc(registry: ^Registry, width, height: i32, dt: f32) {
	if registry == nil || registry.renderer == nil || registry.renderer.Filament == nil {return}
	ctx := registry.renderer.Filament
	materials.init(registry.renderer)
	kineffi.Kine_Filament_Viewport_Begin(ctx)
	descriptor := Find_Class(registry, "ViewportFrame")
	if descriptor == nil {return}
	for object in descriptor.instances {
		if object == nil || object.destroyed {continue}
		frame := cast(^ViewportFrame)object
		frame.elapsed += dt
		if !ViewportFrame_Is_Visible(frame, f32(width), f32(height)) {


			if frame.native !=
			   nil {kineffi.Kine_Filament_Viewport_Destroy(frame.native); frame.native = nil}
			continue
		}

		if frame.native != nil && !kineffi.Kine_Filament_Viewport_IsValid(frame.native, ctx) {
			kineffi.Kine_Filament_Viewport_Destroy(frame.native); frame.native = nil
		}
		if frame.native == nil {frame.native = kineffi.Kine_Filament_Viewport_Create(ctx)}
		if frame.native == nil {continue}
		camera := frame.current_camera
		if frame.update_rate > 0 && frame.elapsed < 1 / frame.update_rate {
			kineffi.Kine_Filament_Viewport_Touch(frame.native)
			continue
		}
		frame.elapsed = 0
		_ = resize(&frame.items, 0)
		hash := u64(14695981039346656037)
		viewport_frame_collect(frame, object, ctx, &hash)
		size := frame.absolute_size
		density := max(f32(1), sdl3.UI_Scale) * frame.resolution_scale
		factor := min(f32(1), 1024 / max(size.X * density, size.Y * density))
		settings := kineffi.KineViewportSettings {
			camera         = {
				camera.CFrame.r00,
				camera.CFrame.r01,
				camera.CFrame.r02,
				camera.CFrame.x,
				camera.CFrame.r10,
				camera.CFrame.r11,
				camera.CFrame.r12,
				camera.CFrame.y,
				camera.CFrame.r20,
				camera.CFrame.r21,
				camera.CFrame.r22,
				camera.CFrame.z,
				0,
				0,
				0,
				1,
			},
			ambient        = {frame.ambient.R, frame.ambient.G, frame.ambient.B},
			lightColor     = {frame.light_color.R, frame.light_color.G, frame.light_color.B},
			lightDirection = {
				frame.light_direction.x,
				frame.light_direction.y,
				frame.light_direction.z,
			},
			fieldOfView    = camera.field_of_view,
			shadows        = frame.shadows ? 1 : 0,
			postProcessing = frame.post_processing ? 1 : 0,
			width          = i32(max(f32(1), math.ceil(size.X * density * factor))),
			height         = i32(max(f32(1), math.ceil(size.Y * density * factor))),
		}
		viewport_frame_effects(object, &settings)
		viewport_frame_effects(&camera.object, &settings)
		camera.viewport_width = f32(settings.width); camera.viewport_height = f32(settings.height)
		_ = kineffi.Kine_Filament_Viewport_Update(
			frame.native,
			&settings,
			raw_data(frame.items),
			u32(len(frame.items)),
			hash,
		)
	}
}

ViewportFrame_Draw_Image :: proc(
	frame: ^ViewportFrame,
	ctx: ^Class_Step_Context,
	rect: guilib.Rect,
) {
	if frame.native == nil || frame.current_camera == nil || frame.image_transparency >= 1 {return}
	guilib.save(ctx.renderer.SkiaSurface)
	corner := Find_Child(&frame.object, "UICorner")
	if corner !=
	   nil {guilib.clipRoundedRect(ctx.renderer.SkiaSurface, rect, gui_corner_radius(corner, rect))} else {guilib.clipRect(ctx.renderer.SkiaSurface, rect)}
	color := frame.image_color
	kineffi.Kine_Filament_Viewport_Draw(
		frame.native,
		ctx.renderer.SkiaSurface,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		color.R,
		color.G,
		color.B,
		1 - frame.image_transparency,
	)
	guilib.restore(ctx.renderer.SkiaSurface)
}
Register_ViewportFrame :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&ViewportFrame_Class,
		viewport_frame_construct,
		viewport_frame_destroy,
		get = viewport_frame_get,
		set = viewport_frame_set,
		clone = viewport_frame_clone,
		properties = []string {
			"CurrentCamera",
			"Ambient",
			"LightColor",
			"LightDirection",
			"ImageColor3",
			"ImageTransparency",
			"ResolutionScale",
			"UpdateRate",
			"Shadows",
			"PostProcessing",
		},
	)
}
