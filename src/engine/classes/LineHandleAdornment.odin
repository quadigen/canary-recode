package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

LineHandleAdornment_Class := Class_Info {
	name   = "LineHandleAdornment",
	parent = &ValueBase_Class,
}

LineHandleAdornment :: struct {
	using object: Object,
	adornee:      ^Object,
	color:        datatypes.Color3,
	length:       f32,
	thickness:    f32,
	cframe:       datatypes.CFrame,
}

LineHandleAdornment_Init :: proc() -> LineHandleAdornment {
	return LineHandleAdornment {
		object = Object_Init(&LineHandleAdornment_Class),
		color = datatypes.Color3{0, 1, 0},
		length = 1,
		thickness = 0.05,
		cframe = datatypes.CFrame_Identity,
	}
}

LineHandleAdornment_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(LineHandleAdornment)
	value^ = LineHandleAdornment_Init()
	value.name = "LineHandleAdornment"
	return &value.object
}

LineHandleAdornment_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^LineHandleAdornment)object)
}

LineHandleAdornment_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	adornment := cast(^LineHandleAdornment)object
	switch key {
	case "Adornee":
		Push_Object(L, adornment.adornee)
	case "Color3":
		datatypes.Push_Color3(L, datatype_registry, adornment.color)
	case "Length":
		vm.PushNumber(L, f64(adornment.length))
	case "Thickness":
		vm.PushNumber(L, f64(adornment.thickness))
	case "CFrame":
		datatypes.Push_CFrame(L, datatype_registry, adornment.cframe)
	case:
		return false
	}
	return true
}

LineHandleAdornment_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	adornment := cast(^LineHandleAdornment)object
	switch key {
	case "Adornee":
		adornment.adornee = object_from_argument(L, value_index)
	case "Color3":
		adornment.color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Length":
		adornment.length = f32(vm.ArgNumber(L, value_index))
	case "Thickness":
		adornment.thickness = f32(vm.ArgNumber(L, value_index))
	case "CFrame":
		adornment.cframe = datatypes.Arg_CFrame(L, value_index, datatype_registry)
	case:
		return false
	}
	return true
}

LineHandleAdornment_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^LineHandleAdornment)source
	dst := cast(^LineHandleAdornment)destination
	dst.adornee = src.adornee
	dst.color = src.color
	dst.length = src.length
	dst.thickness = src.thickness
	dst.cframe = src.cframe
}

LineHandleAdornment_step :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	adornment := cast(^LineHandleAdornment)object
	if ctx == nil || ctx.renderer == nil || ctx.renderer.Filament == nil {return}

	target := adornment.adornee
	if target == nil {target = adornment.parent}
	if target == nil || !Is_A(target, "Part") {return}
	part := cast(^Part)target

	world := datatypes.CFrame_Mul_CFrame(part.cframe, adornment.cframe)

	ax := world.x
	ay := world.y
	az := world.z
	bx := ax + world.r01 * adornment.length
	by := ay + world.r11 * adornment.length
	bz := az + world.r21 * adornment.length

	kineffi.Kine_Filament_DrawGizmoLine(
		ctx.renderer.Filament,
		ax,
		ay,
		az,
		bx,
		by,
		bz,
		adornment.color.R,
		adornment.color.G,
		adornment.color.B,
		adornment.thickness,
	)
}

Register_LineHandleAdornment :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&LineHandleAdornment_Class,
		LineHandleAdornment_construct,
		LineHandleAdornment_destroy,
		get = LineHandleAdornment_get,
		set = LineHandleAdornment_set,
		clone = LineHandleAdornment_clone,
		_step = LineHandleAdornment_step,
		_step_phase = .Render_3D,
		properties = []string{"Adornee", "Color3", "Length", "Thickness", "CFrame"},
	)
}
