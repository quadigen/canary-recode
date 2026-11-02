package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:fmt"

adornment_cube: ^kineffi.KineFilamentMesh

BoxHandleAdornment_Class := Class_Info {
	name   = "BoxHandleAdornment",
	parent = &ValueBase_Class,
}

BoxHandleAdornment :: struct {
	using object: Object,
	adornee:      ^Object,
}

BoxHandleAdornment_Init :: proc() -> BoxHandleAdornment {
	return BoxHandleAdornment{object = Object_Init(&BoxHandleAdornment_Class)}
}

BoxHandleAdornment_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(BoxHandleAdornment)
	value^ = BoxHandleAdornment_Init()
	value.name = "BoxHandleAdornment"
	return &value.object
}

BoxHandleAdornment_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^BoxHandleAdornment)object)
}

BoxHandleAdornment_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	adornment := cast(^BoxHandleAdornment)object
	switch key {
	case "Adornee":
		Push_Object(L, adornment.adornee)
	case:
		return false
	}
	return true
}

BoxHandleAdornment_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	adornment := cast(^BoxHandleAdornment)object
	switch key {
	case "Adornee":
		adornment.adornee = object_from_argument(L, value_index)
	case:
		return false
	}
	return true
}

BoxHandleAdornment_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^BoxHandleAdornment)source
	dst := cast(^BoxHandleAdornment)destination

	dst.adornee = src.adornee
}

BoxHandleAdornment_step :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	adornment := cast(^BoxHandleAdornment)object

	target := adornment.adornee
	if target == nil {target = adornment.parent}
	if target == nil || !Is_A(target, "Part") {return}
	part := cast(^Part)target

	if adornment_cube == nil {
		adornment_cube = kineffi.Kine_Filament_CreateMesh(
			ctx.renderer.Filament,
			kineffi.KINE_MESH_CUBE,
		)
	}

	pad: f32 = 0.05
	xf := [16]f32 {
		part.size.x + pad,
		0,
		0,
		part.position.x,
		0,
		part.size.y + pad,
		0,
		part.position.y,
		0,
		0,
		part.size.z + pad,
		part.position.z,
		0,
		0,
		0,
		1,
	}

	kineffi.Kine_Filament_DrawGizmoWireMesh(
		ctx.renderer.Filament,
		adornment_cube,
		&xf[0],
		0,
		1,
		0,
		0.03,
		30,
	)
}

Register_BoxHandleAdornment :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&BoxHandleAdornment_Class,
		BoxHandleAdornment_construct,
		BoxHandleAdornment_destroy,
		get = BoxHandleAdornment_get,
		set = BoxHandleAdornment_set,
		clone = BoxHandleAdornment_clone,
		_step = BoxHandleAdornment_step,
		_step_phase = .Render_3D,
		properties = []string{"Adornee"},
	)
}
