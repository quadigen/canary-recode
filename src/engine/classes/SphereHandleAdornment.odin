package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

SphereHandleAdornment_Class := Class_Info {
	name   = "SphereHandleAdornment",
	parent = &ValueBase_Class,
}

SphereHandleAdornment :: struct {
	using object: Object,
	adornee:      ^Object,
	color:        datatypes.Color3,
	radius:       f32,
}

SphereHandleAdornment_Init :: proc() -> SphereHandleAdornment {
	return SphereHandleAdornment {
		object = Object_Init(&SphereHandleAdornment_Class),
		color = datatypes.Color3{0, 1, 0},
		radius = 1,
	}
}

SphereHandleAdornment_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	value := new(SphereHandleAdornment)
	value^ = SphereHandleAdornment_Init()
	value.name = "SphereHandleAdornment"
	return &value.object
}

SphereHandleAdornment_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^SphereHandleAdornment)object)
}

SphereHandleAdornment_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	adornment := cast(^SphereHandleAdornment)object
	switch key {
	case "Adornee":
		Push_Object(L, adornment.adornee)
	case "Color3":
		datatypes.Push_Color3(L, datatype_registry, adornment.color)
	case "Radius":
		vm.PushNumber(L, f64(adornment.radius))
	case:
		return false
	}
	return true
}

SphereHandleAdornment_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	adornment := cast(^SphereHandleAdornment)object
	switch key {
	case "Adornee":
		adornment.adornee = object_from_argument(L, value_index)
	case "Color3":
		adornment.color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Radius":
		adornment.radius = f32(vm.ArgNumber(L, value_index))
	case:
		return false
	}
	return true
}

SphereHandleAdornment_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^SphereHandleAdornment)source
	dst := cast(^SphereHandleAdornment)destination
	dst.adornee = src.adornee
	dst.color = src.color
	dst.radius = src.radius
}

SphereHandleAdornment_step :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	adornment := cast(^SphereHandleAdornment)object
	if ctx == nil || ctx.renderer == nil || ctx.renderer.Filament == nil {return}

	target := adornment.adornee
	if target == nil {target = adornment.parent}
	if target == nil || !Is_A(target, "Part") {return}
	part := cast(^Part)target

	kineffi.Kine_Filament_DrawGizmoSphere(
		ctx.renderer.Filament,
		part.position.x,
		part.position.y,
		part.position.z,
		adornment.radius,
		adornment.color.R,
		adornment.color.G,
		adornment.color.B,
		true,
		0.03,
		24,
	)
}

Register_SphereHandleAdornment :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&SphereHandleAdornment_Class,
		SphereHandleAdornment_construct,
		SphereHandleAdornment_destroy,
		get = SphereHandleAdornment_get,
		set = SphereHandleAdornment_set,
		clone = SphereHandleAdornment_clone,
		_step = SphereHandleAdornment_step,
		_step_phase = .Render_3D,
		properties = []string{"Adornee", "Color3", "Radius"},
	)
}
