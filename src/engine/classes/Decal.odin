package classes

import "core:c"
import "core:strings"

import image "vendor:stb/image"

import datatypes "../datatypes"
import enums "../enum"
import kineffi "../bindings"
import vm "../vm"

Decal_Class := Class_Info{
	name   = "Decal",
	parent = &Instance_Class,
}

Decal :: struct {
	using object: Object,

	texture:      string,
	color:        datatypes.Color3,
	transparency: f32,
	face:         enums.NormalId,

	studs_per_tile_u: f32,
	studs_per_tile_v: f32,
	offset_studs_u:  f32,
	offset_studs_v:  f32,

	z_offset: f32,

	enabled:         bool,
	culling:         bool,
	cast_shadows:    bool,
	receive_shadows: bool,

	native_texture: ^kineffi.KineFilamentTex,
	native_decal:   i32,

	texture_dirty: bool,
	color_dirty:   bool,
}

Decal_Init :: proc() -> Decal {
	return Decal{
		object = Object_Init(&Decal_Class),

		texture = strings.clone(""),

		color = datatypes.Color3{
			R = 1,
			G = 1,
			B = 1,
		},

		transparency = 0,
		face         = .Front,

		studs_per_tile_u = 1,
		studs_per_tile_v = 1,
		offset_studs_u   = 0,
		offset_studs_v   = 0,

		z_offset = 0.002,

		enabled         = true,
		culling         = false,
		cast_shadows    = false,
		receive_shadows = true,

		native_texture = nil,
		native_decal   = -1,

		texture_dirty = true,
		color_dirty   = true,
	}
}

Decal_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	decal := new(Decal)
	decal^ = Decal_Init()
	decal.name = "Decal"

	return &decal.object
}

decal_destroy_renderable :: proc(
	decal: ^Decal,
	renderer: ^Renderer_Object,
) {
	if decal == nil {
		return
	}

	if decal.native_decal >= 0 &&
	   renderer != nil &&
	   renderer.Filament != nil {
		kineffi.Kine_Filament_RemoveDecal(
			renderer.Filament,
			decal.native_decal,
		)
	}

	decal.native_decal = -1
}

decal_destroy_texture :: proc(
	decal: ^Decal,
	renderer: ^Renderer_Object,
) {
	if decal == nil || decal.native_texture == nil {
		return
	}

	if renderer != nil && renderer.Filament != nil {
		_ = kineffi.Kine_Filament_DestroyTex(
			renderer.Filament,
			decal.native_texture,
		)
	}

	decal.native_texture = nil
}

decal_reload_texture :: proc(
	decal: ^Decal,
	renderer: ^Renderer_Object,
) -> bool {
	if decal == nil ||
	   renderer == nil ||
	   renderer.Filament == nil {
		return false
	}

	decal_destroy_renderable(decal, renderer)
	decal_destroy_texture(decal, renderer)

	decal.texture_dirty = false

	if len(decal.texture) == 0 {
		return false
	}

	when ODIN_OS == .JS {
		return false
	} else {
		path := strings.clone_to_cstring(decal.texture)
		defer delete(path)

		width, height, channels: c.int

		pixels := image.load(
			path,
			&width,
			&height,
			&channels,
			4,
		)

		if pixels == nil {
			return false
		}

		defer image.image_free(pixels)

		if width <= 0 || height <= 0 {
			return false
		}

		decal.native_texture =
			kineffi.Kine_Filament_CreateTexFromPixels(
				renderer.Filament,
				i32(width),
				i32(height),
				i32(width) * 4,
				pixels,
			)

		return decal.native_texture != nil
	}
}

decal_in_workspace :: proc(object: ^Object) -> bool {
	current := object

	for current != nil {
		if Is_A(current, "Workspace") {
			return true
		}

		current = current.parent
	}

	return false
}

decal_parent_part :: proc(decal: ^Decal) -> ^Part {
	if decal == nil ||
	   decal.parent == nil ||
	   decal.parent.destroyed ||
	   !Is_A(decal.parent, "Part") {
		return nil
	}

	if !decal_in_workspace(decal.parent) {
		return nil
	}

	return cast(^Part)decal.parent
}

decal_vec_neg :: proc(v: datatypes.Vector3) -> datatypes.Vector3 {
	return datatypes.Vector3{
		-v.x,
		-v.y,
		-v.z,
	}
}

decal_vec_mul :: proc(
	v: datatypes.Vector3,
	s: f32,
) -> datatypes.Vector3 {
	return datatypes.Vector3{
		v.x * s,
		v.y * s,
		v.z * s,
	}
}

decal_vec_add :: proc(
	a, b: datatypes.Vector3,
) -> datatypes.Vector3 {
	return datatypes.Vector3{
		a.x + b.x,
		a.y + b.y,
		a.z + b.z,
	}
}

Decal_Face_Info :: struct {
	center:     datatypes.Vector3,
	horizontal: datatypes.Vector3,
	normal:     datatypes.Vector3,
	vertical:   datatypes.Vector3,
	width:      f32,
	height:     f32,
}

decal_face_info :: proc(
	decal: ^Decal,
	part: ^Part,
) -> Decal_Face_Info {
	position := datatypes.CFrame_Position(part.cframe)

	right := datatypes.CFrame_RightVector(part.cframe)
	up    := datatypes.CFrame_UpVector(part.cframe)
	look  := datatypes.CFrame_LookVector(part.cframe)
	back  := decal_vec_neg(look)

	info := Decal_Face_Info{}

	switch decal.face {
	case .Front:
		info.normal     = look
		info.horizontal = right
		info.vertical   = up
		info.width      = part.size.x
		info.height     = part.size.y

		info.center = decal_vec_add(
			position,
			decal_vec_mul(
				look,
				part.size.z * 0.5 + decal.z_offset,
			),
		)

	case .Back:
		info.normal     = back
		info.horizontal = decal_vec_neg(right)
		info.vertical   = up
		info.width      = part.size.x
		info.height     = part.size.y

		info.center = decal_vec_add(
			position,
			decal_vec_mul(
				back,
				part.size.z * 0.5 + decal.z_offset,
			),
		)

	case .Right:
		info.normal     = right
		info.horizontal = back
		info.vertical   = up
		info.width      = part.size.z
		info.height     = part.size.y

		info.center = decal_vec_add(
			position,
			decal_vec_mul(
				right,
				part.size.x * 0.5 + decal.z_offset,
			),
		)

	case .Left:
		info.normal     = decal_vec_neg(right)
		info.horizontal = look
		info.vertical   = up
		info.width      = part.size.z
		info.height     = part.size.y

		info.center = decal_vec_add(
			position,
			decal_vec_mul(
				info.normal,
				part.size.x * 0.5 + decal.z_offset,
			),
		)

	case .Top:
		info.normal     = up
		info.horizontal = right
		info.vertical   = back
		info.width      = part.size.x
		info.height     = part.size.z

		info.center = decal_vec_add(
			position,
			decal_vec_mul(
				up,
				part.size.y * 0.5 + decal.z_offset,
			),
		)

	case .Bottom:
		info.normal     = decal_vec_neg(up)
		info.horizontal = right
		info.vertical   = look
		info.width      = part.size.x
		info.height     = part.size.z

		info.center = decal_vec_add(
			position,
			decal_vec_mul(
				info.normal,
				part.size.y * 0.5 + decal.z_offset,
			),
		)
	}

	return info
}

decal_transform :: proc(
	info: Decal_Face_Info,
) -> [16]f32 {
	// Native decal geometry is a unit quad in the XZ plane:
	//
	// X = horizontal
	// Y = surface normal
	// Z = vertical
	//
	// Scale X/Z to the selected Part face dimensions.
	return [16]f32{
		info.horizontal.x * info.width,
		info.normal.x,
		info.vertical.x * info.height,
		info.center.x,

		info.horizontal.y * info.width,
		info.normal.y,
		info.vertical.y * info.height,
		info.center.y,

		info.horizontal.z * info.width,
		info.normal.z,
		info.vertical.z * info.height,
		info.center.z,

		0, 0, 0, 1,
	}
}

decal_ensure_native :: proc(
	decal: ^Decal,
	renderer: ^Renderer_Object,
	info: Decal_Face_Info,
) -> bool {
	if decal.native_decal >= 0 {
		return true
	}

	if decal.native_texture == nil {
		return false
	}

	decal.native_decal =
		kineffi.Kine_Filament_CreateDecal(
			renderer.Filament,

			info.width,
			info.height,

			decal.native_texture,

			decal.offset_studs_u,
			decal.offset_studs_v,

			decal.studs_per_tile_u,
			decal.studs_per_tile_v,

			decal.culling,
			decal.cast_shadows,
			decal.receive_shadows,
		)

	if decal.native_decal < 0 {
		return false
	}

	decal.color_dirty = true

	return true
}

Decal_Step :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) {
	decal := cast(^Decal)object

	if decal == nil ||
	   ctx == nil ||
	   ctx.renderer == nil ||
	   ctx.renderer.Filament == nil {
		return
	}

	renderer := ctx.renderer

	if decal.texture_dirty {
		_ = decal_reload_texture(
			decal,
			renderer,
		)
	}

	if !decal.enabled ||
	   decal.native_texture == nil {
		decal_destroy_renderable(
			decal,
			renderer,
		)

		return
	}

	part := decal_parent_part(decal)

	if part == nil {
		decal_destroy_renderable(
			decal,
			renderer,
		)

		return
	}

	info := decal_face_info(
		decal,
		part,
	)

	if info.width <= 0 || info.height <= 0 {
		decal_destroy_renderable(
			decal,
			renderer,
		)

		return
	}

	if !decal_ensure_native(
		decal,
		renderer,
		info,
	) {
		return
	}

	transform := decal_transform(info)

	_ = kineffi.Kine_Filament_SetDecalTransform(
		renderer.Filament,
		decal.native_decal,
		&transform[0],
	)

	_ = kineffi.Kine_Filament_SetDecalTiling(
		renderer.Filament,
		decal.native_decal,

		info.width,
		info.height,

		decal.offset_studs_u,
		decal.offset_studs_v,

		decal.studs_per_tile_u,
		decal.studs_per_tile_v,
	)

	_ = kineffi.Kine_Filament_EditDecal(
		renderer.Filament,
		decal.native_decal,

		info.width,
		info.height,

		decal.culling,
		decal.cast_shadows,
		decal.receive_shadows,
	)

	if decal.color_dirty {
		_ = kineffi.Kine_Filament_SetDecalColor(
			renderer.Filament,
			decal.native_decal,

			decal.color.R,
			decal.color.G,
			decal.color.B,

			1.0 - decal.transparency,
		)

		decal.color_dirty = false
	}
}

Decal_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	decal := cast(^Decal)object

	decal_destroy_renderable(
		decal,
		renderer,
	)

	decal_destroy_texture(
		decal,
		renderer,
	)

	delete(decal.texture)

	Object_Destroy(object)
	free(decal)
}

Decal_clone :: proc(
	source: ^Object,
	destination: ^Object,
) {
	src := cast(^Decal)source
	dst := cast(^Decal)destination

	delete(dst.texture)

	dst.texture = strings.clone(
		src.texture,
	)

	dst.color        = src.color
	dst.transparency = src.transparency
	dst.face         = src.face

	dst.studs_per_tile_u = src.studs_per_tile_u
	dst.studs_per_tile_v = src.studs_per_tile_v
	dst.offset_studs_u   = src.offset_studs_u
	dst.offset_studs_v   = src.offset_studs_v

	dst.z_offset = src.z_offset

	dst.enabled         = src.enabled
	dst.culling         = src.culling
	dst.cast_shadows    = src.cast_shadows
	dst.receive_shadows = src.receive_shadows

	dst.native_texture = nil
	dst.native_decal   = -1

	dst.texture_dirty = true
	dst.color_dirty   = true
}

Decal_Get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	decal := cast(^Decal)object

	switch key {
	case "Texture":
		vm.PushString(
			L,
			decal.texture,
		)

	case "Color3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(
			L,
			datatype_registry,
			decal.color,
		)

	case "Transparency":
		vm.PushNumber(
			L,
			f64(decal.transparency),
		)

	case "Face":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"NormalId",
			i64(decal.face),
		)

	case "StudsPerTileU":
		vm.PushNumber(
			L,
			f64(decal.studs_per_tile_u),
		)

	case "StudsPerTileV":
		vm.PushNumber(
			L,
			f64(decal.studs_per_tile_v),
		)

	case "OffsetStudsU":
		vm.PushNumber(
			L,
			f64(decal.offset_studs_u),
		)

	case "OffsetStudsV":
		vm.PushNumber(
			L,
			f64(decal.offset_studs_v),
		)

	case "ZOffset":
		vm.PushNumber(
			L,
			f64(decal.z_offset),
		)

	case "Enabled":
		vm.PushBoolean(
			L,
			decal.enabled,
		)

	case "Culling":
		vm.PushBoolean(
			L,
			decal.culling,
		)

	case "CastShadows":
		vm.PushBoolean(
			L,
			decal.cast_shadows,
		)

	case "ReceiveShadows":
		vm.PushBoolean(
			L,
			decal.receive_shadows,
		)

	case:
		return false
	}

	return true
}

Decal_Set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	decal := cast(^Decal)object

	switch key {
	case "Texture":
		delete(decal.texture)

		decal.texture = strings.clone(
			vm.ArgString(
				L,
				value_index,
			),
		)

		decal.texture_dirty = true

	case "Color3":
		if datatype_registry == nil {
			return false
		}

		decal.color = datatypes.Arg_Color3(
			L,
			value_index,
			datatype_registry,
		)

		decal.color_dirty = true

	case "Transparency":
		decal.transparency = clamp(
			f32(vm.ArgNumber(
				L,
				value_index,
			)),
			0,
			1,
		)

		decal.color_dirty = true

	case "Face":
		if enum_registry == nil {
			return false
		}

		item := enums.Arg_Item(
			L,
			value_index,
			enum_registry,
			"NormalId",
		)

		decal.face = enums.NormalId(
			item.value,
		)

	case "StudsPerTileU":
		decal.studs_per_tile_u = max(
			f32(vm.ArgNumber(
				L,
				value_index,
			)),
			0.001,
		)

	case "StudsPerTileV":
		decal.studs_per_tile_v = max(
			f32(vm.ArgNumber(
				L,
				value_index,
			)),
			0.001,
		)

	case "OffsetStudsU":
		decal.offset_studs_u = f32(
			vm.ArgNumber(
				L,
				value_index,
			),
		)

	case "OffsetStudsV":
		decal.offset_studs_v = f32(
			vm.ArgNumber(
				L,
				value_index,
			),
		)

	case "ZOffset":
		decal.z_offset = f32(
			vm.ArgNumber(
				L,
				value_index,
			),
		)

	case "Enabled":
		decal.enabled = vm.ArgBoolean(
			L,
			value_index,
		)

	case "Culling":
		decal.culling = vm.ArgBoolean(
			L,
			value_index,
		)

	case "CastShadows":
		decal.cast_shadows = vm.ArgBoolean(
			L,
			value_index,
		)

	case "ReceiveShadows":
		decal.receive_shadows = vm.ArgBoolean(
			L,
			value_index,
		)

	case:
		return false
	}

	return true
}

Register_Decal :: proc(
	registry: ^Registry,
) {
	Register_Class(
		registry,
		&Decal_Class,

		Decal_construct,
		Decal_destroy,

		get = Decal_Get,
		set = Decal_Set,
		properties = []string{
			"Texture",
			"Color3",
			"Transparency",
			"Face",
			"StudsPerTileU",
			"StudsPerTileV",
			"OffsetStudsU",
			"OffsetStudsV",
			"ZOffset",
			"Enabled",
			"Culling",
			"CastShadows",
			"ReceiveShadows",
		},

		clone = Decal_clone,

		_step = Decal_Step,
		_step_phase = .Render_3D,
	)
}
