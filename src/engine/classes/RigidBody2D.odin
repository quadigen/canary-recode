package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

RigidBody2D_Class := Class_Info {
	name   = "RigidBody2D",
	parent = &Instance_Class,
}

RigidBody2D :: struct {
	using object: Object,
	pivot:        datatypes.CFrame,
	pivot_set:    bool,
}

RigidBody2D_Init :: proc() -> RigidBody2D {
	return RigidBody2D{object = Object_Init(&RigidBody2D_Class), pivot = datatypes.CFrame_Identity}
}

RigidBody2D_construct :: proc(renderer: ^Renderer_Object, data_RigidBody2D: rawptr) -> ^Object {
	corner := new(RigidBody2D)
	corner^ = RigidBody2D_Init()
	corner.name = "RigidBody2D"

	return &corner.object
}

RigidBody2D_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^RigidBody2D)object)
}

RigidBody2D_clone :: proc(source: ^Object, destination: ^Object) {
	src, dst := cast(^RigidBody2D)source, cast(^RigidBody2D)destination
	dst.pivot, dst.pivot_set = src.pivot, src.pivot_set
}

RigidBody2D_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "PivotTo", "GetPivot":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

rigidbody2d_context :: proc() -> Class_Step_Context {
	return Class_Step_Context {
		viewport_width = gui_layout_last_width,
		viewport_height = gui_layout_last_height,
	}
}
rigidbody2d_bounds :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
	lo, hi: ^[2]f32,
	found: ^bool,
) {
	for child in object.children {
		if child == nil || child.destroyed {continue}
		if Is_A_Class(child, &Part2D_Class) {
			center, size, _ := Part2D_Resolve_Transform(cast(^Part2D)child, ctx)
			a, b := center - size * 0.5, center + size * 0.5
			if !found^ {lo^, hi^, found^ = a, b, true}
			for i in 0 ..< 2 {lo^[i] = min(lo^[i], a[i]); hi^[i] = max(hi^[i], b[i])}
		}
		rigidbody2d_bounds(child, ctx, lo, hi, found)
	}
}
RigidBody2D_Get_Pivot :: proc(body: ^RigidBody2D, ctx: ^Class_Step_Context) -> datatypes.CFrame {
	if body.pivot_set {return body.pivot}
	lo, hi: [2]f32
	found := false
	rigidbody2d_bounds(&body.object, ctx, &lo, &hi, &found)
	center := (lo + hi) * 0.5
	return datatypes.CFrame_New_Position({f64(center[0]), f64(center[1]), 0})
}
rigidbody2d_transform :: proc(object: ^Object, delta: datatypes.CFrame, ctx: ^Class_Step_Context) {
	for child in object.children {
		if child == nil || child.destroyed {continue}
		if Is_A_Class(child, &Part2D_Class) {
			part := cast(^Part2D)child
			center, _, angle := Part2D_Resolve_Transform(part, ctx)
			target := datatypes.CFrame_Mul_Vector3(delta, {f64(center[0]), f64(center[1]), 0})
			_, _, rz := datatypes.CFrame_ToEulerAnglesXYZ(delta)
			Part2D_Move(
				part,
				[2]f32{f32(target.x), f32(target.y)} - center,
				angle + f32(rz * 180 / math.PI),
			)

			continue
		}
		if Is_A_Class(child, &RigidBody2D_Class) {
			sub := cast(^RigidBody2D)child
			if sub.pivot_set {sub.pivot = datatypes.CFrame_Mul_CFrame(delta, sub.pivot)}
		}
		rigidbody2d_transform(child, delta, ctx)
	}
}

RigidBody2D_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "PivotTo":
		if datatype_registry == nil {return 0, false}
		body := cast(^RigidBody2D)object
		ctx := rigidbody2d_context()
		target := datatypes.Arg_CFrame(L, 2, datatype_registry)
		rx, ry, rz := datatypes.CFrame_ToEulerAnglesXYZ(target)
		if abs(rx) > 0.0001 ||
		   abs(ry) > 0.0001 ||
		   abs(target.z) > 0.0001 ||
		   math.is_nan(target.x) ||
		   math.is_nan(target.y) ||
		   math.is_nan(rz) ||
		   math.is_inf(target.x) ||
		   math.is_inf(target.y) ||
		   math.is_inf(rz) {
			return vm.RaiseError(L, "RigidBody2D pivot must be a finite XY transform"), true
		}
		delta := datatypes.CFrame_Mul_CFrame(
			target,
			datatypes.CFrame_Inverse(RigidBody2D_Get_Pivot(body, &ctx)),
		)
		rigidbody2d_transform(object, delta, &ctx)
		body.pivot, body.pivot_set = target, true
		return 0, true
	case "GetPivot":
		if datatype_registry == nil {return 0, false}
		ctx := rigidbody2d_context()
		datatypes.Push_CFrame(
			L,
			datatype_registry,
			RigidBody2D_Get_Pivot(cast(^RigidBody2D)object, &ctx),
		)
		return 1, true
	}
	return 0, false
}

Register_RigidBody2D :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&RigidBody2D_Class,
		RigidBody2D_construct,
		RigidBody2D_destroy,
		clone = RigidBody2D_clone,
		get = RigidBody2D_get,
		namecall = RigidBody2D_namecall,
		methods = []string{"PivotTo", "GetPivot"},
	)
}
