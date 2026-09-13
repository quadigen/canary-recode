package classes

import "core:math"

import datatypes "../datatypes"
import enums "../enum"
import kineffi "../bindings"
import vm "../vm"

Light_Class := Class_Info{
	name   = "Light",
	parent = &Instance_Class,
}

PointLight_Class := Class_Info{
	name   = "PointLight",
	parent = &Light_Class,
}

SpotLight_Class := Class_Info{
	name   = "SpotLight",
	parent = &Light_Class,
}

SurfaceLight_Class := Class_Info{
	name   = "SurfaceLight",
	parent = &Light_Class,
}


LIGHT_TYPE_POINT        :: i32(0)
LIGHT_TYPE_SPOT         :: i32(1)
LIGHT_TYPE_FOCUSED_SPOT :: i32(2)

LIGHT_INTENSITY_SCALE :: f32(1000.0)
DEG_TO_RAD            :: f32(math.PI / 180.0)


Light :: struct {
	using object: Object,

	brightness: f32,
	color:      datatypes.Color3,
	enabled:    bool,
	shadows:    bool,

	native_id:      i32,
	native_context: ^kineffi.KineFilamentContext,
}


PointLight :: struct {
	using light: Light,

	range: f32,
}


SpotLight :: struct {
	using light: Light,

	angle: f32,
	face:  enums.NormalId,
	range: f32,
}


SurfaceLight :: struct {
	using light: Light,

	angle: f32,
	face:  enums.NormalId,
	range: f32,
}

Light_Init :: proc(
	class: ^Class_Info,
	name: string,
) -> Light {
	return Light{
		object = Object_Init(class, name),

		brightness = 1,
		color = datatypes.Color3{
			R = 1,
			G = 1,
			B = 1,
		},
		enabled = true,
		shadows = false,

		native_id = -1,
	}
}


PointLight_Init :: proc() -> PointLight {
	return PointLight{
		light = Light_Init(
			&PointLight_Class,
			"PointLight",
		),

		range = 8,
	}
}


SpotLight_Init :: proc() -> SpotLight {
	return SpotLight{
		light = Light_Init(
			&SpotLight_Class,
			"SpotLight",
		),

		angle = 90,
		face = .Front,
		range = 16,
	}
}


SurfaceLight_Init :: proc() -> SurfaceLight {
	return SurfaceLight{
		light = Light_Init(
			&SurfaceLight_Class,
			"SurfaceLight",
		),

		angle = 90,
		face = .Front,
		range = 16,
	}
}

light_remove_native :: proc(
	light: ^Light,
	renderer: ^Renderer_Object,
) {
	if light == nil || light.native_id < 0 {
		return
	}
	if renderer != nil &&
	   renderer.Filament != nil &&
	   renderer.Filament == light.native_context {
		kineffi.Kine_Filament_RemoveLight(
			renderer.Filament,
			light.native_id,
		)
	}

	light.native_id = -1
	light.native_context = nil
}


light_prepare_context :: proc(
	light: ^Light,
	ctx: ^Class_Step_Context,
) -> ^kineffi.KineFilamentContext {
	if light == nil ||
	   ctx == nil ||
	   ctx.renderer == nil ||
	   ctx.renderer.Filament == nil {
		return nil
	}

	filament := ctx.renderer.Filament

	if light.native_context != filament {
		light.native_id = -1
		light.native_context = filament
	}

	return filament
}


light_is_in_workspace :: proc(object: ^Object) -> bool {
	current := object

	for current != nil {
		if Is_A(current, "Workspace") {
			return true
		}

		current = current.parent
	}

	return false
}


light_parent_part :: proc(light: ^Light) -> ^Part {
	if light == nil ||
	   light.parent == nil ||
	   !Is_A(light.parent, "Part") {
		return nil
	}

	if !light_is_in_workspace(light.parent) {
		return nil
	}

	return cast(^Part)light.parent
}


part_position :: proc(part: ^Part) -> datatypes.Vector3 {
	return datatypes.Vector3{
		part.cframe.x,
		part.cframe.y,
		part.cframe.z,
	}
}


face_local_direction :: proc(
	face: enums.NormalId,
) -> datatypes.Vector3 {
	switch face {
	case .Right:
		return datatypes.Vector3{1, 0, 0}

	case .Top:
		return datatypes.Vector3{0, 1, 0}

	case .Back:
		return datatypes.Vector3{0, 0, 1}

	case .Left:
		return datatypes.Vector3{-1, 0, 0}

	case .Bottom:
		return datatypes.Vector3{0, -1, 0}

	case .Front:
		return datatypes.Vector3{0, 0, -1}
	}

	return datatypes.Vector3{0, 0, -1}
}


face_world_direction :: proc(
	part: ^Part,
	face: enums.NormalId,
) -> datatypes.Vector3 {
	return datatypes.CFrame_VectorToWorldSpace(
		part.cframe,
		face_local_direction(face),
	)
}


surface_local_position :: proc(
	part: ^Part,
	face: enums.NormalId,
) -> datatypes.Vector3 {
	switch face {
	case .Right:
		return datatypes.Vector3{
			part.size.x * 0.5,
			0,
			0,
		}

	case .Top:
		return datatypes.Vector3{
			0,
			part.size.y * 0.5,
			0,
		}

	case .Back:
		return datatypes.Vector3{
			0,
			0,
			part.size.z * 0.5,
		}

	case .Left:
		return datatypes.Vector3{
			-part.size.x * 0.5,
			0,
			0,
		}

	case .Bottom:
		return datatypes.Vector3{
			0,
			-part.size.y * 0.5,
			0,
		}

	case .Front:
		return datatypes.Vector3{
			0,
			0,
			-part.size.z * 0.5,
		}
	}

	return datatypes.Vector3{}
}


surface_world_position :: proc(
	part: ^Part,
	face: enums.NormalId,
) -> datatypes.Vector3 {
	return datatypes.CFrame_PointToWorldSpace(
		part.cframe,
		surface_local_position(part, face),
	)
}


light_intensity :: proc(light: ^Light) -> f32 {
	return max(
		0,
		light.brightness * LIGHT_INTENSITY_SCALE,
	)
}


light_cone :: proc(angle_degrees: f32) -> (
	inner_radians: f32,
	outer_radians: f32,
) {
	angle := clamp(angle_degrees, 0, 180)

	outer_radians =
		(angle * 0.5) *
		DEG_TO_RAD

	inner_radians = outer_radians * 0.8

	outer_radians = max(
		outer_radians,
		0.00873,
	)

	inner_radians = max(
		inner_radians,
		0.00873,
	)

	inner_radians = min(
		inner_radians,
		outer_radians,
	)

	return
}

sync_point_light :: proc(
	light: ^PointLight,
	ctx: ^Class_Step_Context,
) {
	filament := light_prepare_context(
		&light.light,
		ctx,
	)

	if filament == nil {
		return
	}

	part := light_parent_part(&light.light)

	if part == nil || !light.enabled {
		light_remove_native(
			&light.light,
			ctx.renderer,
		)
		return
	}

	position := part_position(part)

	if light.native_id < 0 {
		light.native_id =
			kineffi.Kine_Filament_CreateLightEx(
				filament,
				LIGHT_TYPE_POINT,

				position.x,
				position.y,
				position.z,

				0,
				-1,
				0,

				light.color.R,
				light.color.G,
				light.color.B,

				light_intensity(&light.light),
				max(light.range, 0.001),

				0.35,
				0.785398163,

				false,
				true,
			)

		if light.native_id < 0 {
			return
		}
	}

	kineffi.Kine_Filament_SetPositionLight(
		filament,
		light.native_id,
		position.x,
		position.y,
		position.z,
	)

	kineffi.Kine_Filament_SetColorLight(
		filament,
		light.native_id,
		light.color.R,
		light.color.G,
		light.color.B,
	)

	kineffi.Kine_Filament_SetIntensityLight(
		filament,
		light.native_id,
		light_intensity(&light.light),
	)

	kineffi.Kine_Filament_SetFalloffLight(
		filament,
		light.native_id,
		max(light.range, 0.001),
	)

	kineffi.Kine_Filament_SetEnabledLight(
		filament,
		light.native_id,
		true,
	)
}


sync_spot_light :: proc(
	light: ^SpotLight,
	ctx: ^Class_Step_Context,
) {
	filament := light_prepare_context(
		&light.light,
		ctx,
	)

	if filament == nil {
		return
	}

	part := light_parent_part(&light.light)

	if part == nil || !light.enabled {
		light_remove_native(
			&light.light,
			ctx.renderer,
		)
		return
	}

	position := part_position(part)

	direction := face_world_direction(
		part,
		light.face,
	)

	inner, outer := light_cone(
		light.angle,
	)

	if light.native_id < 0 {
		light.native_id =
			kineffi.Kine_Filament_CreateLightEx(
				filament,
				LIGHT_TYPE_SPOT,

				position.x,
				position.y,
				position.z,

				direction.x,
				direction.y,
				direction.z,

				light.color.R,
				light.color.G,
				light.color.B,

				light_intensity(&light.light),
				max(light.range, 0.001),

				inner,
				outer,

				light.shadows,
				true,
			)

		if light.native_id < 0 {
			return
		}
	}

	kineffi.Kine_Filament_SetPositionLight(
		filament,
		light.native_id,
		position.x,
		position.y,
		position.z,
	)

	kineffi.Kine_Filament_SetDirectionLight(
		filament,
		light.native_id,
		direction.x,
		direction.y,
		direction.z,
	)

	kineffi.Kine_Filament_SetColorLight(
		filament,
		light.native_id,
		light.color.R,
		light.color.G,
		light.color.B,
	)

	kineffi.Kine_Filament_SetIntensityLight(
		filament,
		light.native_id,
		light_intensity(&light.light),
	)

	kineffi.Kine_Filament_SetFalloffLight(
		filament,
		light.native_id,
		max(light.range, 0.001),
	)

	kineffi.Kine_Filament_SetConeLight(
		filament,
		light.native_id,
		inner,
		outer,
	)

	kineffi.Kine_Filament_SetShadowLight(
		filament,
		light.native_id,
		light.shadows,
	)

	kineffi.Kine_Filament_SetEnabledLight(
		filament,
		light.native_id,
		true,
	)
}


sync_surface_light :: proc(
	light: ^SurfaceLight,
	ctx: ^Class_Step_Context,
) {
	filament := light_prepare_context(
		&light.light,
		ctx,
	)

	if filament == nil {
		return
	}

	part := light_parent_part(&light.light)

	if part == nil || !light.enabled {
		light_remove_native(
			&light.light,
			ctx.renderer,
		)
		return
	}

	position := surface_world_position(
		part,
		light.face,
	)

	direction := face_world_direction(
		part,
		light.face,
	)

	inner, outer := light_cone(
		light.angle,
	)

	if light.native_id < 0 {
		light.native_id =
			kineffi.Kine_Filament_CreateLightEx(
				filament,
				LIGHT_TYPE_FOCUSED_SPOT,

				position.x,
				position.y,
				position.z,

				direction.x,
				direction.y,
				direction.z,

				light.color.R,
				light.color.G,
				light.color.B,

				light_intensity(&light.light),
				max(light.range, 0.001),

				inner,
				outer,

				light.shadows,
				true,
			)

		if light.native_id < 0 {
			return
		}
	}

	kineffi.Kine_Filament_SetPositionLight(
		filament,
		light.native_id,
		position.x,
		position.y,
		position.z,
	)

	kineffi.Kine_Filament_SetDirectionLight(
		filament,
		light.native_id,
		direction.x,
		direction.y,
		direction.z,
	)

	kineffi.Kine_Filament_SetColorLight(
		filament,
		light.native_id,
		light.color.R,
		light.color.G,
		light.color.B,
	)

	kineffi.Kine_Filament_SetIntensityLight(
		filament,
		light.native_id,
		light_intensity(&light.light),
	)

	kineffi.Kine_Filament_SetFalloffLight(
		filament,
		light.native_id,
		max(light.range, 0.001),
	)

	kineffi.Kine_Filament_SetConeLight(
		filament,
		light.native_id,
		inner,
		outer,
	)

	kineffi.Kine_Filament_SetShadowLight(
		filament,
		light.native_id,
		light.shadows,
	)
}

light_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	light := cast(^Light)object

	switch key {
	case "Brightness":
		vm.PushNumber(
			L,
			f64(light.brightness),
		)

	case "Color":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(
			L,
			datatype_registry,
			light.color,
		)

	case "Enabled":
		vm.PushBoolean(
			L,
			light.enabled,
		)

	case "Shadows":
		vm.PushBoolean(
			L,
			light.shadows,
		)

	case:
		return false
	}

	return true
}


light_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	light := cast(^Light)object

	switch key {
	case "Brightness":
		light.brightness = max(
			0,
			f32(vm.ArgNumber(
				L,
				value_index,
			)),
		)

	case "Color":
		if datatype_registry == nil {
			return false
		}

		light.color =
			datatypes.Arg_Color3(
				L,
				value_index,
				datatype_registry,
			)

	case "Enabled":
		light.enabled =
			vm.ArgBoolean(
				L,
				value_index,
			)

	case "Shadows":
		light.shadows =
			vm.ArgBoolean(
				L,
				value_index,
			)

	case:
		return false
	}

	return true
}

point_light_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	light := new(PointLight)
	light^ = PointLight_Init()

	return &light.object
}


point_light_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	light := cast(^PointLight)object

	light_remove_native(
		&light.light,
		renderer,
	)

	Object_Destroy(object)
	free(light)
}


point_light_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	light := cast(^PointLight)object

	switch key {
	case "Range":
		vm.PushNumber(
			L,
			f64(light.range),
		)

	case:
		return light_get(
			L,
			object,
			datatype_registry,
			enum_registry,
			key,
		)
	}

	return true
}


point_light_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	light := cast(^PointLight)object

	switch key {
	case "Range":
		light.range = max(
			0,
			f32(vm.ArgNumber(
				L,
				value_index,
			)),
		)

	case:
		return light_set(
			L,
			object,
			datatype_registry,
			enum_registry,
			key,
			value_index,
		)
	}

	return true
}


point_light_step :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) {
	sync_point_light(
		cast(^PointLight)object,
		ctx,
	)
}


point_light_clone :: proc(
	source: ^Object,
	destination: ^Object,
) {
	src := cast(^PointLight)source
	dst := cast(^PointLight)destination

	dst.range = src.range
}

spot_light_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	light := new(SpotLight)
	light^ = SpotLight_Init()

	return &light.object
}


spot_light_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	light := cast(^SpotLight)object

	light_remove_native(
		&light.light,
		renderer,
	)

	Object_Destroy(object)
	free(light)
}


spot_light_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	light := cast(^SpotLight)object

	switch key {
	case "Angle":
		vm.PushNumber(
			L,
			f64(light.angle),
		)

	case "Face":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"NormalId",
			i64(light.face),
		)

	case "Range":
		vm.PushNumber(
			L,
			f64(light.range),
		)

	case:
		return light_get(
			L,
			object,
			datatype_registry,
			enum_registry,
			key,
		)
	}

	return true
}


spot_light_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	light := cast(^SpotLight)object

	switch key {
	case "Angle":
		light.angle = clamp(
			f32(vm.ArgNumber(
				L,
				value_index,
			)),
			0,
			180,
		)

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

		light.face =
			enums.NormalId(item.value)

	case "Range":
		light.range = max(
			0,
			f32(vm.ArgNumber(
				L,
				value_index,
			)),
		)

	case:
		return light_set(
			L,
			object,
			datatype_registry,
			enum_registry,
			key,
			value_index,
		)
	}

	return true
}


spot_light_step :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) {
	sync_spot_light(
		cast(^SpotLight)object,
		ctx,
	)
}


spot_light_clone :: proc(
	source: ^Object,
	destination: ^Object,
) {
	src := cast(^SpotLight)source
	dst := cast(^SpotLight)destination

	dst.angle = src.angle
	dst.face = src.face
	dst.range = src.range
}
surface_light_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	light := new(SurfaceLight)
	light^ = SurfaceLight_Init()

	return &light.object
}


surface_light_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	light := cast(^SurfaceLight)object

	light_remove_native(
		&light.light,
		renderer,
	)

	Object_Destroy(object)
	free(light)
}


surface_light_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	light := cast(^SurfaceLight)object

	switch key {
	case "Angle":
		vm.PushNumber(
			L,
			f64(light.angle),
		)

	case "Face":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"NormalId",
			i64(light.face),
		)

	case "Range":
		vm.PushNumber(
			L,
			f64(light.range),
		)

	case:
		return light_get(
			L,
			object,
			datatype_registry,
			enum_registry,
			key,
		)
	}

	return true
}


surface_light_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	light := cast(^SurfaceLight)object

	switch key {
	case "Angle":
		light.angle = clamp(
			f32(vm.ArgNumber(
				L,
				value_index,
			)),
			0,
			180,
		)

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

		light.face =
			enums.NormalId(item.value)

	case "Range":
		light.range = max(
			0,
			f32(vm.ArgNumber(
				L,
				value_index,
			)),
		)

	case:
		return light_set(
			L,
			object,
			datatype_registry,
			enum_registry,
			key,
			value_index,
		)
	}

	return true
}


surface_light_step :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) {
	sync_surface_light(
		cast(^SurfaceLight)object,
		ctx,
	)
}


surface_light_clone :: proc(
	source: ^Object,
	destination: ^Object,
) {
	src := cast(^SurfaceLight)source
	dst := cast(^SurfaceLight)destination

	dst.angle = src.angle
	dst.face = src.face
	dst.range = src.range
}

light_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	light := new(Light)
	light^ = Light_Init(
		&Light_Class,
		"Light",
	)

	return &light.object
}


light_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	light := cast(^Light)object

	light_remove_native(
		light,
		renderer,
	)

	Object_Destroy(object)
	free(light)
}


light_clone :: proc(
	source: ^Object,
	destination: ^Object,
) {
	src := cast(^Light)source
	dst := cast(^Light)destination

	dst.brightness = src.brightness
	dst.color = src.color
	dst.enabled = src.enabled
	dst.shadows = src.shadows

	dst.native_id = -1
	dst.native_context = nil
}

Register_Light :: proc(
	registry: ^Registry,
) {
	Register_Class(
		registry,
		&Light_Class,
		light_construct,
		light_destroy,

		creatable = false,

		get = light_get,
		set = light_set,
		clone = light_clone,
	)
}


Register_PointLight :: proc(
	registry: ^Registry,
) {
	Register_Class(
		registry,
		&PointLight_Class,
		point_light_construct,
		point_light_destroy,

		get = point_light_get,
		set = point_light_set,

		_step = point_light_step,
		_step_phase = .Render_3D,

		clone = point_light_clone,
	)
}


Register_SpotLight :: proc(
	registry: ^Registry,
) {
	Register_Class(
		registry,
		&SpotLight_Class,
		spot_light_construct,
		spot_light_destroy,

		get = spot_light_get,
		set = spot_light_set,

		_step = spot_light_step,
		_step_phase = .Render_3D,

		clone = spot_light_clone,
	)
}


Register_SurfaceLight :: proc(
	registry: ^Registry,
) {
	Register_Class(
		registry,
		&SurfaceLight_Class,
		surface_light_construct,
		surface_light_destroy,

		get = surface_light_get,
		set = surface_light_set,

		_step = surface_light_step,
		_step_phase = .Render_3D,

		clone = surface_light_clone,
	)
}