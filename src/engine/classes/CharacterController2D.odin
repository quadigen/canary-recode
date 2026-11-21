package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"


CharacterController2D_Class := Class_Info {
	name   = "CharacterController2D",
	parent = &Part2D_Class,
}
CharacterController2D :: struct {
	using part:                    Part2D,
	up_direction:                  datatypes.Vector2,
	floor_max_angle:               f32,
	max_slides:                    i32,
	on_floor, on_wall, on_ceiling: bool,
	last_motion:                   datatypes.Vector2,
	move_and_slide:                proc(
		owner: rawptr,
		character: ^CharacterController2D,
		dt: f32,
	) -> bool,
}
CharacterController2D_construct :: proc(r: ^Renderer_Object, dm: rawptr) -> ^Object {
	p := new(CharacterController2D)
	p.part = Part2D_Init()
	p.object.class = &CharacterController2D_Class
	p.name = "CharacterController2D"
	p.anchored = false
	p.up_direction = {0, -1}
	p.floor_max_angle = 45
	p.max_slides = 4
	return &p.object
}
CharacterController2D_destroy :: proc(o: ^Object, r: ^Renderer_Object) {
	p := cast(^CharacterController2D)o
	if p.physics_release != nil &&
	   p.physics_owner != nil {p.physics_release(p.physics_owner, &p.part)}
	GuiObject_Free_Signals(&p.gui_object)
	Object_Destroy(o)
	free(p)
}
CharacterController2D_get :: proc(
	L: ^vm.State,
	o: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
) -> bool {
	p := cast(^CharacterController2D)o
	switch key {
	case "Grounded":
		vm.PushBoolean(L, p.on_floor)
	case "Move":
		vm.PushUserdataMethod(L, key)
	case:
		return Part2D_get(L, o, dr, er, key)
	}
	return true
}
CharacterController2D_namecall :: proc(
	L: ^vm.State,
	o: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	p := cast(^CharacterController2D)o
	switch method {
	case "Move":
		dt := f32(vm.ArgOptionalNumber(L, 2, 1.0 / 60.0))
		if !part2d_finite(dt) ||
		   dt < 0 {return vm.RaiseError(L, "Move delta must be finite and nonnegative"), true}
		p.on_floor, p.on_wall, p.on_ceiling = false, false, false
		p.last_motion = {}
		hit := false
		if !p.anchored && p.physics_owner != nil && p.move_and_slide != nil {
			hit = p.move_and_slide(p.physics_owner, p, min(dt, 0.25))
		}
		vm.PushBoolean(L, hit)
		return 1, true
	case "ApplyImpulse", "ApplyAngularImpulse":
		return vm.RaiseError(L, "CharacterController2D uses Velocity and Move"), true
	case:
		return Part2D_namecall(L, o, dr, er, method)
	}
}
Register_CharacterController2D :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&CharacterController2D_Class,
		CharacterController2D_construct,
		CharacterController2D_destroy,
		get = CharacterController2D_get,
		set = Part2D_set,
		namecall = CharacterController2D_namecall,
		properties = []string{"Grounded"},
		methods = []string{"Move"},
	)
}
