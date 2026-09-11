package services

// wire:service global="TweenService"

import "core:math"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

TweenService_Class := classes.Class_Info{
	name   = "TweenService",
	parent = &Service_Class,
}

TweenService :: struct {
	using service: Service,
}

tween_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(TweenService)
	service.service = Service_Init(
		&TweenService_Class,
		"TweenService",
		data_model,
	)
	return &service.object
}

tween_bounce_out :: proc(t: f64) -> f64 {
	n1: f64 = 7.5625
	d1: f64 = 2.75

	if t < 1/d1 {
		return n1*t*t
	}

	if t < 2/d1 {
		x := t - 1.5/d1
		return n1*x*x + 0.75
	}

	if t < 2.5/d1 {
		x := t - 2.25/d1
		return n1*x*x + 0.9375
	}

	x := t - 2.625/d1
	return n1*x*x + 0.984375
}

tween_ease_in :: proc(alpha: f64, style: i64) -> f64 {
	t := clamp(alpha, 0.0, 1.0)

	switch style {
	case 0: // Linear
		return t

	case 1: // Sine
		return 1 - math.cos((t*math.PI)/2)

	case 2: // Back
		c1: f64 = 1.70158
		c3 := c1 + 1
		return c3*t*t*t - c1*t*t

	case 3: // Quad
		return t*t

	case 4: // Quart
		t2 := t*t
		return t2*t2

	case 5: // Quint
		t2 := t*t
		return t2*t2*t

	case 6: // Bounce
		return 1 - tween_bounce_out(1-t)

	case 7: // Elastic
		if t == 0 || t == 1 {
			return t
		}
		c4 := (2*math.PI)/3
		return -math.pow(2.0, 10*t-10) *
		       math.sin((t*10-10.75)*c4)

	case 8: // Exponential
		if t == 0 {
			return 0
		}
		return math.pow(2.0, 10*t-10)

	case 9: // Circular
		return 1 - math.sqrt(max(0.0, 1-t*t))

	case 10: // Cubic
		return t*t*t
	}

	return t
}

tween_get_value :: proc(
	alpha: f64,
	style: i64,
	direction: i64,
) -> f64 {
	t := clamp(alpha, 0.0, 1.0)

	switch direction {
	case 0: // In
		return tween_ease_in(t, style)

	case 1: // Out
		return 1 - tween_ease_in(1-t, style)

	case 2: // InOut
		if t < 0.5 {
			return tween_ease_in(t*2, style)/2
		}
		return 1 - tween_ease_in((1-t)*2, style)/2
	}

	return tween_ease_in(t, style)
}

tween_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "GetValue":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}

tween_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	switch method {
	case "GetValue":
		if enum_registry == nil {
			return 0, false
		}

		alpha := vm.ArgNumber(L, 2)

		style := enums.Arg_Item(
			L,
			3,
			enum_registry,
			"EasingStyle",
		)

		direction := enums.Arg_Item(
			L,
			4,
			enum_registry,
			"EasingDirection",
		)

		vm.PushNumber(
			L,
			tween_get_value(
				alpha,
				style.value,
				direction.value,
			),
		)

		return 1, true
	}

	return 0, false
}

tween_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	classes.Object_Destroy(object)
	free(cast(^TweenService)object)
}

Register_TweenService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&TweenService_Class,
		tween_service_construct,
		tween_service_destroy,
		creatable = false,
		get = tween_service_get,
		namecall = tween_service_namecall,
	)
}
