package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

CylinderHandleAdornment_Class := Class_Info {
	name   = "CylinderHandleAdornment",
	parent = &ValueBase_Class,
}

CylinderHandleAdornment :: struct {
	using object: Object,
	adornee:      ^Object,
	color:        datatypes.Color3,
	height:       f32,
	radius:       f32,
	inner_radius: f32,
	cframe:       datatypes.CFrame,
}

CylinderHandleAdornment_Init :: proc() -> CylinderHandleAdornment {
	return CylinderHandleAdornment {
		object = Object_Init(&CylinderHandleAdornment_Class),
		color = datatypes.Color3{0, 1, 0},
		height = 1,
		radius = 1,
		inner_radius = 0,
		cframe = datatypes.CFrame_Identity,
	}
}

CylinderHandleAdornment_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	value := new(CylinderHandleAdornment)
	value^ = CylinderHandleAdornment_Init()
	value.name = "CylinderHandleAdornment"
	return &value.object
}

CylinderHandleAdornment_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^CylinderHandleAdornment)object)
}

CylinderHandleAdornment_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	adornment := cast(^CylinderHandleAdornment)object
	switch key {
	case "Adornee":
		Push_Object(L, adornment.adornee)
	case "Color3":
		datatypes.Push_Color3(L, datatype_registry, adornment.color)
	case "Height":
		vm.PushNumber(L, f64(adornment.height))
	case "Radius":
		vm.PushNumber(L, f64(adornment.radius))
	case "InnerRadius":
		vm.PushNumber(L, f64(adornment.inner_radius))
	case "CFrame":
		datatypes.Push_CFrame(L, datatype_registry, adornment.cframe)
	case:
		return false
	}
	return true
}

CylinderHandleAdornment_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	adornment := cast(^CylinderHandleAdornment)object
	switch key {
	case "Adornee":
		adornment.adornee = object_from_argument(L, value_index)
	case "Color3":
		adornment.color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Height":
		adornment.height = f32(vm.ArgNumber(L, value_index))
	case "Radius":
		adornment.radius = f32(vm.ArgNumber(L, value_index))
	case "InnerRadius":
		adornment.inner_radius = f32(vm.ArgNumber(L, value_index))
	case "CFrame":
		adornment.cframe = datatypes.Arg_CFrame(L, value_index, datatype_registry)
	case:
		return false
	}
	return true
}

CylinderHandleAdornment_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^CylinderHandleAdornment)source
	dst := cast(^CylinderHandleAdornment)destination
	dst.adornee = src.adornee
	dst.color = src.color
	dst.height = src.height
	dst.radius = src.radius
	dst.inner_radius = src.inner_radius
	dst.cframe = src.cframe
}


cylinder_adornment_matrix :: proc(
	part: ^Part,
	local_cf: datatypes.CFrame,
	height, radius: f32,
) -> [16]f32 {

	world := datatypes.CFrame_Mul_CFrame(part.cframe, local_cf)


	d := radius * 2
	return [16]f32 {
		world.r00 * d,
		world.r01 * height,
		world.r02 * d,
		world.x,
		world.r10 * d,
		world.r11 * height,
		world.r12 * d,
		world.y,
		world.r20 * d,
		world.r21 * height,
		world.r22 * d,
		world.z,
		0,
		0,
		0,
		1,
	}
}

CylinderHandleAdornment_step :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	adornment := cast(^CylinderHandleAdornment)object
	if ctx == nil || ctx.renderer == nil || ctx.renderer.Filament == nil {return}

	target := adornment.adornee
	if target == nil {target = adornment.parent}
	if target == nil || !Is_A(target, "Part") {return}
	part := cast(^Part)target

	xf := cylinder_adornment_matrix(part, adornment.cframe, adornment.height, adornment.radius)
	kineffi.Kine_Filament_DrawGizmoCylinder(
		ctx.renderer.Filament,
		&xf[0],
		adornment.color.R,
		adornment.color.G,
		adornment.color.B,
		true,
		0.03,
		24,
	)


	if adornment.inner_radius > 0 && adornment.inner_radius < adornment.radius {
		ixf := cylinder_adornment_matrix(
			part,
			adornment.cframe,
			adornment.height,
			adornment.inner_radius,
		)
		kineffi.Kine_Filament_DrawGizmoCylinder(
			ctx.renderer.Filament,
			&ixf[0],
			adornment.color.R,
			adornment.color.G,
			adornment.color.B,
			true,
			0.03,
			24,
		)
	}
}

Register_CylinderHandleAdornment :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&CylinderHandleAdornment_Class,
		CylinderHandleAdornment_construct,
		CylinderHandleAdornment_destroy,
		get = CylinderHandleAdornment_get,
		set = CylinderHandleAdornment_set,
		clone = CylinderHandleAdornment_clone,
		_step = CylinderHandleAdornment_step,
		_step_phase = .Render_3D,
		properties = []string{"Adornee", "Color3", "Height", "Radius", "InnerRadius", "CFrame"},
	)
}
