package classes

// Highlight draws a translucent fill over a part or model plus an inverted-hull
// outline around it. Roblox keeps no InstanceAdornment parent here: Adornee is
// just a reference the Highlight reads each frame, so an unset Adornee resolves
// to the Highlight's own Parent at draw time rather than at assignment time.

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

Highlight_Class := Class_Info{
	name   = "Highlight",
	parent = &Instance_Class,
}

Highlight :: struct {
	using object:          Object,
	adornee:              ^Object,
	depth_mode:           enums.HighlightDepthMode,
	enabled:              bool,
	fill_color:           datatypes.Color3,
	fill_transparency:    f64,
	outline_color:        datatypes.Color3,
	outline_transparency: f64,

	// Shape meshes are built lazily and cached per PartType, so a Highlight over
	// a Model uploads each distinct shape once instead of once per part. The
	// context is tracked separately because a Filament teardown invalidates the
	// buffers without touching this object.
	meshes:       [11]^kineffi.KineFilamentMesh,
	mesh_context: ^kineffi.KineFilamentContext,
}

highlight_shape_glb :: proc(shape: enums.PartType) -> (data: string, ok: bool) {
	switch shape {
	case .Ball:
		return #load("../assets/shapes/Ball.glb"), true
	case .Block:
		return #load("../assets/shapes/Block.glb"), true
	case .Cylinder:
		return #load("../assets/shapes/Cylinder.glb"), true
	case .Wedge:
		return #load("../assets/shapes/Wedge.glb"), true
	case .CornerWedge:
		return #load("../assets/shapes/Corner Wedge.glb"), true
	case .Cone:
		return #load("../assets/shapes/Cone.glb"), true
	case .Pyramid:
		return #load("../assets/shapes/Pyramid.glb"), true
	case .Truss:
		return #load("../assets/shapes/Truss.glb"), true
	case .Torus:
		return #load("../assets/shapes/Torus.glb"), true
	case .TriangleWedge:
		return #load("../assets/shapes/Triangle Wedge.glb"), true
	case .Capsule:
		return #load("../assets/shapes/Capsule.glb"), true
	}
	return "", false
}

highlight_destroy_meshes :: proc(highlight: ^Highlight) {
	if highlight.mesh_context != nil {
		for mesh in highlight.meshes {
			if mesh != nil {
				_ = kineffi.Kine_Filament_DestroyMesh(highlight.mesh_context, mesh)
			}
		}
	}
	highlight.meshes = {}
	highlight.mesh_context = nil
}

highlight_shape_mesh :: proc(
	highlight: ^Highlight,
	ctx: ^kineffi.KineFilamentContext,
	shape: enums.PartType,
) -> ^kineffi.KineFilamentMesh {
	if ctx == nil {
		return nil
	}

	slot := i32(shape)
	if slot < 0 || slot >= len(highlight.meshes) {
		return nil
	}

	if highlight.mesh_context != ctx {
		// The old context's GPU buffers went away with the engine they belonged
		// to, so only this object still holds pointers to them.
		highlight.meshes = {}
		highlight.mesh_context = ctx
	}

	if highlight.meshes[slot] != nil {
		return highlight.meshes[slot]
	}

	data, ok := highlight_shape_glb(shape)
	if !ok {
		highlight.meshes[slot] =
			kineffi.Kine_Filament_CreateMesh(ctx, kineffi.KINE_MESH_CUBE)
		return highlight.meshes[slot]
	}

	highlight.meshes[slot] = kineffi.Kine_Filament_CreateMeshFromMemory(
		ctx,
		raw_data(data),
		uintptr(len(data)),
		"glb",
	)
	return highlight.meshes[slot]
}

Highlight_Init :: proc() -> Highlight {
	return Highlight{
		object = Object_Init(&Highlight_Class, "Highlight"),
		// Roblox authors a new Highlight visibly on: enabled, with a red fill at
		// half transparency and an opaque white outline.
		depth_mode = .AlwaysOnTop,
		enabled = true,
		fill_color = datatypes.Color3 {
			R = 255.0 / 255.0,
			G = 100.0 / 255.0,
			B =  50.0 / 255.0,
		},
		fill_transparency    = 0.5,
		outline_color        = datatypes.Color3{1, 1, 1},
		outline_transparency = 0,
	}
}

highlight_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	highlight := new(Highlight)
	highlight^ = Highlight_Init()
	return &highlight.object
}

highlight_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	highlight := cast(^Highlight)object
	highlight_destroy_meshes(highlight)
	Object_Destroy(object)
	free(highlight)
}

highlight_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Highlight)source
	dst := cast(^Highlight)destination
	if src == nil || dst == nil {
		return
	}
	dst.adornee = src.adornee
	dst.depth_mode = src.depth_mode
	dst.enabled = src.enabled
	dst.fill_color = src.fill_color
	dst.fill_transparency = src.fill_transparency
	dst.outline_color = src.outline_color
	dst.outline_transparency = src.outline_transparency
}

highlight_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	highlight := cast(^Highlight)object

	switch key {
	case "Adornee":
		Push_Object(L, highlight.adornee)
	case "DepthMode":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"HighlightDepthMode",
			i64(highlight.depth_mode),
		)
	case "Enabled":
		vm.PushBoolean(L, highlight.enabled)
	case "FillColor":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, highlight.fill_color)
	case "FillTransparency":
		vm.PushNumber(L, highlight.fill_transparency)
	case "OutlineColor":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, highlight.outline_color)
	case "OutlineTransparency":
		vm.PushNumber(L, highlight.outline_transparency)
	case:
		return false
	}

	return true
}

highlight_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	highlight := cast(^Highlight)object

	switch key {
	case "Adornee":
		if vm.IsNil(L, value_index) {
			highlight.adornee = nil
			return true
		}
		adornee := object_from_argument(L, value_index)
		if adornee == nil {
			_ = vm.RaiseError(L, "Adornee must be an Instance or nil")
			return true
		}
		highlight.adornee = adornee
	case "DepthMode":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "HighlightDepthMode")
		highlight.depth_mode = enums.HighlightDepthMode(item.value)
	case "Enabled":
		highlight.enabled = vm.ArgBoolean(L, value_index)
	case "FillColor":
		if datatype_registry == nil {return false}
		highlight.fill_color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "FillTransparency":
		highlight.fill_transparency = vm.ArgNumber(L, value_index)
	case "OutlineColor":
		if datatype_registry == nil {return false}
		highlight.outline_color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "OutlineTransparency":
		highlight.outline_transparency = vm.ArgNumber(L, value_index)
	case:
		return false
	}

	return true
}

// Roblox keeps the outline the same pixel width no matter how far away the part
// is, so the world-space thickness has to grow with the camera distance.
//
// Four pixels is what makes the outline read as an outline. Roblox's own
// selection highlight is noticeably heavier than a one-pixel hairline, and at
// two pixels this ring was legible only on parts close to the camera.
HIGHLIGHT_OUTLINE_PIXELS :: f32(4.0)

// Must match the vertical field of view main.odin hands Filament in
// set_viewport_rect, since world_per_pixel is derived from it.
HIGHLIGHT_FIELD_OF_VIEW_DEGREES :: f32(60.0)

// Distance assumed when there is no active camera to measure against, and a
// floor that keeps the shell from collapsing into the part it outlines.
HIGHLIGHT_FALLBACK_DISTANCE :: f32(40.0)
HIGHLIGHT_MIN_THICKNESS :: f32(0.02)

highlight_world_per_pixel :: proc(distance: f32, viewport_height: i32) -> f32 {
	if viewport_height <= 0 {
		return 0
	}
	half_fov := math.tan(f64(HIGHLIGHT_FIELD_OF_VIEW_DEGREES) * 0.5 * math.PI / 180.0)
	return 2.0 * distance * f32(half_fov) / f32(viewport_height)
}

// The fill overlays the part's own surface, so it needs a small push toward the
// viewer to avoid z-fighting with it. It scales with distance for the same
// reason the outline thickness does.
highlight_depth_bias :: proc(world_per_pixel: f32) -> f32 {
	bias := world_per_pixel * 0.5
	if bias < 1.0 / 4096.0 {
		bias = 1.0 / 4096.0
	}
	return bias
}

highlight_camera_position :: proc(
	ctx: ^Class_Step_Context,
) -> (position: datatypes.Vector3, ok: bool) {
	if ctx == nil ||
	   ctx.renderer == nil ||
	   ctx.renderer.ActiveCamera == nil {
		return datatypes.Vector3{}, false
	}
	camera := cast(^Camera)ctx.renderer.ActiveCamera
	if camera == nil {
		return datatypes.Vector3{}, false
	}
	return datatypes.CFrame_Position(camera.CFrame), true
}

highlight_part_mesh :: proc(
	highlight: ^Highlight,
	part: ^Part,
	ctx: ^kineffi.KineFilamentContext,
) -> ^kineffi.KineFilamentMesh {
	if Is_A(&part.object, "MeshPart") {
		// Reuse the MeshPart's own upload when it is live in this context. That
		// is what keeps an EditableMesh-backed part highlighted as its current
		// geometry rather than its block-shaped fallback.
		mesh_part := cast(^MeshPart)part
		if mesh_part.native_mesh != nil && mesh_part.native_context == ctx {
			return mesh_part.native_mesh
		}
	}
	return highlight_shape_mesh(highlight, ctx, part.shape)
}

highlight_transform :: proc(part: ^Part) -> [16]f32 {
	cframe := part.cframe
	// The shape GLBs are authored two units wide, so half the part size is the
	// scale that reproduces the part's real dimensions.
	render_size :=
		datatypes.Vector3{part.size.x * 0.5, part.size.y * 0.5, part.size.z * 0.5}

	return [16]f32{
		cframe.r00 * render_size.x,
		cframe.r01 * render_size.y,
		cframe.r02 * render_size.z,
		cframe.x,
		cframe.r10 * render_size.x,
		cframe.r11 * render_size.y,
		cframe.r12 * render_size.z,
		cframe.y,
		cframe.r20 * render_size.x,
		cframe.r21 * render_size.y,
		cframe.r22 * render_size.z,
		cframe.z,
		0,
		0,
		0,
		1,
	}
}

// Queues one part's outline and fill. Called for the part itself as well as
// for each descendant, because a Part used as an Adornee is not in its own
// children list.
highlight_append_part_items :: proc(
	highlight: ^Highlight,
	part: ^Part,
	mesh: ^kineffi.KineFilamentMesh,
	ctx: ^Class_Step_Context,
	camera_position: datatypes.Vector3,
	have_camera: bool,
	items: ^[dynamic]kineffi.KineFilamentDrawItem,
) {
	delta := datatypes.Vector3{
		x = part.cframe.x - camera_position.x,
		y = part.cframe.y - camera_position.y,
		z = part.cframe.z - camera_position.z,
	}
	distance := datatypes.Vec3_Magnitude(delta)
	if !have_camera {
		// No camera means no distance to scale from, and most parts sit tens of
		// studs out. Guessing low here made the outline vanish entirely, so fall
		// back to a distance that produces a readable ring at a typical framing.
		distance = HIGHLIGHT_FALLBACK_DISTANCE
	}

	world_per_pixel := highlight_world_per_pixel(distance, ctx.viewport_height)

	thickness := world_per_pixel * HIGHLIGHT_OUTLINE_PIXELS
	if thickness <= 0 {
		// Guard against a degenerate viewport. Below this the shell expands too
		// little to survive depth quantization and the outline disappears.
		thickness = HIGHLIGHT_MIN_THICKNESS
	}

	transform := highlight_transform(part)

	// Neither draw sets KINE_FILAMENT_DRAW_CULLING. The outline expands vertices
	// past the source mesh bounds, so bounds derived from the mesh alone would
	// let Filament cull a visible highlight.
	if highlight.outline_transparency < 1.0 {
		outline_kind := i32(kineffi.KINE_MAT_HIGHLIGHT_OUTLINE)
		if highlight.depth_mode == .AlwaysOnTop {
			outline_kind = kineffi.KINE_MAT_HIGHLIGHT_OUTLINE_TOP
		}
		append(
			items,
			kineffi.KineFilamentDrawItem{
				mesh = mesh,
				transform = transform,
				r = highlight.outline_color.R,
				g = highlight.outline_color.G,
				b = highlight.outline_color.B,
				param1 = thickness,
				transmission = f32(1.0 - highlight.outline_transparency),
				materialKind = outline_kind,
			},
		)
	}

	if highlight.fill_transparency < 1.0 {
		fill_kind := i32(kineffi.KINE_MAT_HIGHLIGHT_FILL)
		if highlight.depth_mode == .AlwaysOnTop {
			fill_kind = kineffi.KINE_MAT_HIGHLIGHT_FILL_TOP
		}
		append(
			items,
			kineffi.KineFilamentDrawItem{
				mesh = mesh,
				transform = transform,
				r = highlight.fill_color.R,
				g = highlight.fill_color.G,
				b = highlight.fill_color.B,
				param1 = highlight_depth_bias(world_per_pixel),
				transmission = f32(1.0 - highlight.fill_transparency),
				materialKind = fill_kind,
			},
		)
	}
}

highlight_append_part :: proc(
	highlight: ^Highlight,
	root: ^Object,
	ctx: ^Class_Step_Context,
	camera_position: datatypes.Vector3,
	have_camera: bool,
	items: ^[dynamic]kineffi.KineFilamentDrawItem,
) {
	// Both layers fully transparent means the Highlight draws nothing, so the
	// whole subtree is skipped rather than walked looking for invisible geometry.
	if highlight.fill_transparency >= 1.0 && highlight.outline_transparency >= 1.0 {
		return
	}

	if Is_A(root, "Part") {
		part := cast(^Part)root
		mesh := highlight_part_mesh(highlight, part, ctx.renderer.Filament)
		if mesh != nil {
			highlight_append_part_items(
				highlight,
				part,
				mesh,
				ctx,
				camera_position,
				have_camera,
				items,
			)
		}
	}

	for child in root.children {
		if child == nil || child.destroyed {
			continue
		}
		highlight_append_part(highlight, child, ctx, camera_position, have_camera, items)
	}
}

// Roblox draws a Highlight in 3D space, so it participates in the Render_3D
// phase alongside Workspace. Each Highlight submits its own draw list rather
// than sharing Workspace's: Workspace only walks the DataModel's own parts and
// would never see a Highlight's Adornee.
highlight_step :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	highlight := cast(^Highlight)object
	if highlight == nil ||
	   ctx == nil ||
	   ctx.renderer == nil ||
	   ctx.renderer.Filament == nil {
		return
	}
	if !highlight.enabled {
		return
	}
	if highlight.fill_transparency >= 1.0 && highlight.outline_transparency >= 1.0 {
		return
	}

	adornee := highlight.adornee
	if adornee == nil {
		adornee = highlight.object.parent
	}
	if adornee == nil || adornee.destroyed {
		return
	}

	camera_position, have_camera := highlight_camera_position(ctx)

	// The walk covers the adornee itself, so a Part Adornee highlights just that
	// part while a Model Adornee highlights its part descendants.
	items: [dynamic]kineffi.KineFilamentDrawItem
	highlight_append_part(highlight, adornee, ctx, camera_position, have_camera, &items)
	if len(items) > 0 {
		_ = kineffi.Kine_Filament_DrawMeshList(
			ctx.renderer.Filament,
			raw_data(items),
			u32(len(items)),
		)
	}
	delete(items)
}

Register_Highlight :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Highlight_Class,
		highlight_construct,
		highlight_destroy,
		get = highlight_get,
		set = highlight_set,
		clone = highlight_clone,
		_step = highlight_step,
		_step_phase = .Render_3D,
		properties = []string{
			"Adornee",
			"DepthMode",
			"Enabled",
			"FillColor",
			"FillTransparency",
			"OutlineColor",
			"OutlineTransparency",
		},
	)
}
