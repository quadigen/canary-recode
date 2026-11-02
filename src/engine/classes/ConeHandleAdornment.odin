package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"


adornment_cone: ^kineffi.KineFilamentMesh

ConeHandleAdornment_Class := Class_Info {
	name   = "ConeHandleAdornment",
	parent = &ValueBase_Class,
}

ConeHandleAdornment :: struct {
	using object: Object,
	adornee:      ^Object,
	color:        datatypes.Color3,
	height:       f32,
	radius:       f32,
	cframe:       datatypes.CFrame,
}

ConeHandleAdornment_Init :: proc() -> ConeHandleAdornment {
	return ConeHandleAdornment {
		object = Object_Init(&ConeHandleAdornment_Class),
		color = datatypes.Color3{0, 1, 0},
		height = 1,
		radius = 0.5,
		cframe = datatypes.CFrame_Identity,
	}
}

ConeHandleAdornment_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(ConeHandleAdornment)
	value^ = ConeHandleAdornment_Init()
	value.name = "ConeHandleAdornment"
	return &value.object
}

ConeHandleAdornment_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^ConeHandleAdornment)object)
}

ConeHandleAdornment_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	adornment := cast(^ConeHandleAdornment)object
	switch key {
	case "Adornee":
		Push_Object(L, adornment.adornee)
	case "Color3":
		datatypes.Push_Color3(L, datatype_registry, adornment.color)
	case "Height":
		vm.PushNumber(L, f64(adornment.height))
	case "Radius":
		vm.PushNumber(L, f64(adornment.radius))
	case "CFrame":
		datatypes.Push_CFrame(L, datatype_registry, adornment.cframe)
	case:
		return false
	}
	return true
}

ConeHandleAdornment_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	adornment := cast(^ConeHandleAdornment)object
	switch key {
	case "Adornee":
		adornment.adornee = object_from_argument(L, value_index)
	case "Color3":
		adornment.color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Height":
		adornment.height = f32(vm.ArgNumber(L, value_index))
	case "Radius":
		adornment.radius = f32(vm.ArgNumber(L, value_index))
	case "CFrame":
		adornment.cframe = datatypes.Arg_CFrame(L, value_index, datatype_registry)
	case:
		return false
	}
	return true
}

ConeHandleAdornment_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^ConeHandleAdornment)source
	dst := cast(^ConeHandleAdornment)destination
	dst.adornee = src.adornee
	dst.color = src.color
	dst.height = src.height
	dst.radius = src.radius
	dst.cframe = src.cframe
}


cone_adornment_matrix :: proc(
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

ConeHandleAdornment_step :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	adornment := cast(^ConeHandleAdornment)object
	if ctx == nil || ctx.renderer == nil || ctx.renderer.Filament == nil {return}

	target := adornment.adornee
	if target == nil {target = adornment.parent}
	if target == nil || !Is_A(target, "Part") {return}
	part := cast(^Part)target

	if adornment_cone == nil {
		adornment_cone = kineffi.Kine_Filament_CreateMesh(
			ctx.renderer.Filament,
			kineffi.KINE_MESH_PYRAMID,
		)
	}

	xf := cone_adornment_matrix(part, adornment.cframe, adornment.height, adornment.radius)
	kineffi.Kine_Filament_DrawGizmoWireMesh(
		ctx.renderer.Filament,
		adornment_cone,
		&xf[0],
		adornment.color.R,
		adornment.color.G,
		adornment.color.B,
		0.03,
		30,
	)
}

Register_ConeHandleAdornment :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&ConeHandleAdornment_Class,
		ConeHandleAdornment_construct,
		ConeHandleAdornment_destroy,
		get = ConeHandleAdornment_get,
		set = ConeHandleAdornment_set,
		clone = ConeHandleAdornment_clone,
		_step = ConeHandleAdornment_step,
		_step_phase = .Render_3D,
		properties = []string{"Adornee", "Color3", "Height", "Radius", "CFrame"},
	)
}
