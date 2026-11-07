package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Part2D_Class := Class_Info {
	name   = "Part2D",
	parent = &GuiObject_Class,
}

Part2D :: struct {
	using gui_object: GuiObject,
	anchored:         bool,
	can_collide:      bool,
	is_ball:          bool,
	density:          f32,
	friction:         f32,
	elasticity:       f32,
	velocity:         [2]f32, // pixels / second
	velocity_dirty:   bool, // script wrote velocity -> push to Box2D next step
	shape_dirty:      bool, // shape/material changed -> rebuild fixture next step
	physics_owner:    rawptr,
	physics_release:  proc(owner: rawptr, part: ^Part2D),
}

Part2D_Init :: proc() -> Part2D {
	gui := GuiObject_Init()
	gui.object.class = &Part2D_Class

	return Part2D {
		gui_object = gui,
		anchored = true,
		can_collide = true,
		density = 1.0,
		friction = 0.3,
		elasticity = 0.0,
	}
}

Part2D_Get_Transform :: proc(part: ^Part2D) -> (center: [2]f32, size: [2]f32, rotation_deg: f32) {
	size = {f32(part.absolute_size.X), f32(part.absolute_size.Y)}
	center = {
		f32(part.absolute_position.X) + size[0] * 0.5,
		f32(part.absolute_position.Y) + size[1] * 0.5,
	}
	rotation_deg = f32(part.rotation)
	return
}

Part2D_Set_Transform :: proc(part: ^Part2D, center: [2]f32, rotation_deg: f32) {
	size := [2]f32{f32(part.absolute_size.X), f32(part.absolute_size.Y)}
	top_left := center - size * 0.5
	part.absolute_position.X = top_left[0]
	part.absolute_position.Y = top_left[1]
	part.rotation = f64(rotation_deg)
}

Part2D_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	part := new(Part2D)
	part^ = Part2D_Init()
	part.name = "Part2D"

	return &part.object
}

Part2D_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	part := cast(^Part2D)object
	if part.physics_release != nil && part.physics_owner != nil {
		part.physics_release(part.physics_owner, part)
	}
	GuiObject_Free_Signals(cast(^GuiObject)object)
	Object_Destroy(object)
	free(part)
}

Part2D_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	part := cast(^Part2D)object
	switch key {
	case "Anchored":
		vm.PushBoolean(L, part.anchored)
		return true
	case "CanCollide":
		vm.PushBoolean(L, part.can_collide)
		return true
	case "IsBall":
		vm.PushBoolean(L, part.is_ball)
		return true
	case "Density":
		vm.PushNumber(L, f64(part.density))
		return true
	case "Friction":
		vm.PushNumber(L, f64(part.friction))
		return true
	case "Elasticity":
		vm.PushNumber(L, f64(part.elasticity))
		return true
	case "VelocityX":
		vm.PushNumber(L, f64(part.velocity[0]))
		return true
	case "VelocityY":
		vm.PushNumber(L, f64(part.velocity[1]))
		return true
	}
	return GuiObject_get(L, object, datatype_registry, enum_registry, key)
}

Part2D_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	part := cast(^Part2D)object
	switch key {
	case "Anchored":
		part.anchored = vm.ArgBoolean(L, value_index)
		return true
	case "CanCollide":
		part.can_collide = vm.ArgBoolean(L, value_index)
		part.shape_dirty = true
		return true
	case "IsBall":
		part.is_ball = vm.ArgBoolean(L, value_index)
		part.shape_dirty = true
		return true
	case "Density":
		part.density = max(f32(vm.ArgNumber(L, value_index)), 0)
		part.shape_dirty = true
		return true
	case "Friction":
		part.friction = max(f32(vm.ArgNumber(L, value_index)), 0)
		part.shape_dirty = true
		return true
	case "Elasticity":
		part.elasticity = clamp(f32(vm.ArgNumber(L, value_index)), 0, 1)
		part.shape_dirty = true
		return true
	case "VelocityX":
		part.velocity[0] = f32(vm.ArgNumber(L, value_index))
		part.velocity_dirty = true
		return true
	case "VelocityY":
		part.velocity[1] = f32(vm.ArgNumber(L, value_index))
		part.velocity_dirty = true
		return true
	}
	return GuiObject_set(L, object, datatype_registry, enum_registry, key, value_index)
}

Part2D_render :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	GuiObject_render(object, ctx)
}

Part2D_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Part2D)source
	dst := cast(^Part2D)destination
	dst.anchored = src.anchored
	dst.can_collide = src.can_collide
	dst.is_ball = src.is_ball
	dst.density = src.density
	dst.friction = src.friction
	dst.elasticity = src.elasticity
	dst.shape_dirty = true
}

Register_Part2D :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Part2D_Class,
		Part2D_construct,
		Part2D_destroy,
		get = Part2D_get,
		set = Part2D_set,
		properties = []string {
			"Anchored",
			"CanCollide",
			"IsBall",
			"Density",
			"Friction",
			"Elasticity",
			"VelocityX",
			"VelocityY",
		},
		clone = Part2D_clone,
	)
}
