package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

Part2D_Class := Class_Info {
	name   = "Part2D",
	parent = &WorldObject2D_Class,
}

Part2D :: struct {
	using gui_object:        GuiObject,
	anchored:                bool,
	can_collide:             bool,
	is_ball:                 bool,
	density:                 f32,
	friction:                f32,
	elasticity:              f32,
	velocity:                [2]f32,
	angular_velocity:        f32,
	angular_dirty:           bool,
	pending_impulse:         [2]f32,
	pending_angular_impulse: f32,
	velocity_dirty:          bool,
	shape_dirty:             bool,
	physics_owner:           rawptr,
	physics_release:         proc(owner: rawptr, part: ^Part2D),
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


Part2D_Move :: proc(part: ^Part2D, displacement: [2]f32, rotation_deg: f32) {
	if displacement == ([2]f32{}) && part.rotation == f64(rotation_deg) {return}
	part.position.X_Offset += displacement[0]
	part.position.Y_Offset += displacement[1]
	part.absolute_position.X += displacement[0]
	part.absolute_position.Y += displacement[1]
	part.rotation = f64(rotation_deg)
	part.rotation_cache_valid = false
	gui_mark_layout_for(&part.object, false)
}

Part2D_Set_Transform :: proc(part: ^Part2D, center: [2]f32, rotation_deg: f32) {
	old, _, _ := Part2D_Get_Transform(part)
	Part2D_Move(part, center - old, rotation_deg)
}

Part2D_Resolve_Transform :: proc(
	part: ^Part2D,
	ctx: ^Class_Step_Context,
) -> (
	center, size: [2]f32,
	angle: f32,
) {
	x, y, w, h := GuiObject_get_absolute_transform(&part.object, ctx)
	return {x + w * 0.5, y + h * 0.5}, {w, h}, f32(part.rotation)
}

part2d_finite :: proc(value: f32) -> bool {
	return !math.is_nan(value) && !math.is_inf(value)
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
	case "ApplyImpulse", "ApplyAngularImpulse":
		vm.PushUserdataMethod(L, key)
		return true
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
	case "Velocity":
		if datatype_registry == nil {return false}
		datatypes.Push_Vector2(L, datatype_registry, {part.velocity[0], part.velocity[1]})
		return true
	case "AngularVelocity":
		vm.PushNumber(L, f64(part.angular_velocity))
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
		value := f32(vm.ArgNumber(L, value_index))
		if !part2d_finite(value) {_ = vm.RaiseError(L, "Density must be finite"); return true}
		part.density = max(value, 0)
		part.shape_dirty = true
		return true
	case "Friction":
		value := f32(vm.ArgNumber(L, value_index))
		if !part2d_finite(value) {_ = vm.RaiseError(L, "Friction must be finite"); return true}
		part.friction = max(value, 0)
		part.shape_dirty = true
		return true
	case "Elasticity":
		value := f32(vm.ArgNumber(L, value_index))
		if !part2d_finite(value) {_ = vm.RaiseError(L, "Elasticity must be finite"); return true}
		part.elasticity = clamp(value, 0, 1)
		part.shape_dirty = true
		return true
	case "Velocity":
		if datatype_registry == nil {return false}
		value := datatypes.Arg_Vector2(L, value_index, datatype_registry)
		if !part2d_finite(value.X) || !part2d_finite(value.Y) {
			_ = vm.RaiseError(L, "Velocity must be finite")
			return true
		}
		part.velocity = {value.X, value.Y}
		part.velocity_dirty = true
		return true
	case "AngularVelocity":
		value := f32(vm.ArgNumber(L, value_index))
		if !part2d_finite(
			value,
		) {_ = vm.RaiseError(L, "AngularVelocity must be finite"); return true}
		part.angular_velocity = value
		part.angular_dirty = true
		return true
	case "VelocityX":
		value := f32(vm.ArgNumber(L, value_index))
		if !part2d_finite(value) {_ = vm.RaiseError(L, "VelocityX must be finite"); return true}
		part.velocity[0] = value
		part.velocity_dirty = true
		return true
	case "VelocityY":
		value := f32(vm.ArgNumber(L, value_index))
		if !part2d_finite(value) {_ = vm.RaiseError(L, "VelocityY must be finite"); return true}
		part.velocity[1] = value
		part.velocity_dirty = true
		return true
	}
	handled := GuiObject_set(L, object, datatype_registry, enum_registry, key, value_index)
	if handled && (key == "Size" || key == "AutomaticSize") {
		part.resolved_size_valid = false
		part.shape_dirty = true
	}
	return handled
}

Part2D_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	part := cast(^Part2D)object
	switch method {
	case "ApplyImpulse":
		if dr == nil {return 0, false}
		impulse := datatypes.Arg_Vector2(L, 2, dr)
		total := part.pending_impulse + [2]f32{impulse.X, impulse.Y}
		if !part2d_finite(total[0]) ||
		   !part2d_finite(total[1]) {return vm.RaiseError(L, "Impulse must be finite"), true}
		if !part.anchored {part.pending_impulse = total}
	case "ApplyAngularImpulse":
		total := part.pending_angular_impulse + f32(vm.ArgNumber(L, 2))
		if !part2d_finite(total) {return vm.RaiseError(L, "Angular impulse must be finite"), true}
		if !part.anchored {part.pending_angular_impulse = total}
	case:
		return 0, false
	}
	return 0, true
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
	dst.velocity = src.velocity
	dst.angular_velocity = src.angular_velocity
	dst.velocity_dirty = true
	dst.angular_dirty = true
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
		namecall = Part2D_namecall,
		methods = []string{"ApplyImpulse", "ApplyAngularImpulse"},
		properties = []string {
			"Anchored",
			"CanCollide",
			"IsBall",
			"Density",
			"Friction",
			"Elasticity",
			"Velocity",
			"AngularVelocity",
			"VelocityX",
			"VelocityY",
		},
		clone = Part2D_clone,
	)
}
