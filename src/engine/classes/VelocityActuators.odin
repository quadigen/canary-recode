package classes

import j "../bindings"
import d "../datatypes"
import e "../enum"
import vm "../vm"
import "core:math"

LinearVelocity_Class := Class_Info {
	name   = "LinearVelocity",
	parent = &Constraint_Class,
}
LinearVelocity :: struct {
	using constraint:         Constraint,
	vector_velocity:          d.Vector3,
	line_direction:           d.Vector3,
	line_velocity:            f64,
	plane_velocity:           d.Vector2,
	primary_tangent_axis:     d.Vector3,
	secondary_tangent_axis:   d.Vector3,
	max_force:                f64,
	max_axes_force:           d.Vector3,
	max_planar_axes_force:    d.Vector2,
	force_limits_enabled:     bool,
	reaction_force_enabled:   bool,
	relative_to:              e.ActuatorRelativeTo,
	force_limit_mode:         e.ForceLimitMode,
	velocity_constraint_mode: e.VelocityConstraintMode,
}
LinearVelocity_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	a := new(LinearVelocity)
	a.constraint = Constraint_Init()
	a.object.class = &LinearVelocity_Class
	a.name = "LinearVelocity"
	a.active = false
	a.vector_velocity = {}
	a.line_direction = {1, 0, 0}
	a.line_velocity = 0
	a.plane_velocity = {}
	a.primary_tangent_axis = {1, 0, 0}
	a.secondary_tangent_axis = {0, 1, 0}
	a.max_force = 1000
	a.max_axes_force = {1000, 1000, 1000}
	a.max_planar_axes_force = {1000, 1000}
	a.force_limits_enabled = true
	a.reaction_force_enabled = false
	a.relative_to = .World
	a.force_limit_mode = .Magnitude
	a.velocity_constraint_mode = .Vector
	return &a.object
}
LinearVelocity_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^LinearVelocity)object)
}
LinearVelocity_clone :: proc(source, destination: ^Object) {
	Constraint_clone(source, destination)
	src, dst := cast(^LinearVelocity)source, cast(^LinearVelocity)destination
	dst.active = false
	dst.vector_velocity = src.vector_velocity
	dst.line_direction = src.line_direction
	dst.line_velocity = src.line_velocity
	dst.plane_velocity = src.plane_velocity
	dst.primary_tangent_axis = src.primary_tangent_axis
	dst.secondary_tangent_axis = src.secondary_tangent_axis
	dst.max_force = src.max_force
	dst.max_axes_force = src.max_axes_force
	dst.max_planar_axes_force = src.max_planar_axes_force
	dst.force_limits_enabled = src.force_limits_enabled
	dst.reaction_force_enabled = src.reaction_force_enabled
	dst.relative_to = src.relative_to
	dst.force_limit_mode = src.force_limit_mode
	dst.velocity_constraint_mode = src.velocity_constraint_mode
}
LinearVelocity_get :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^d.Registry,
	en: ^e.Registry,
	key: string,
) -> bool {
	a := cast(^LinearVelocity)object
	switch key {
	case "VectorVelocity":
		d.Push_Vector3(L, a.vector_velocity)
	case "LineDirection":
		d.Push_Vector3(L, a.line_direction)
	case "LineVelocity":
		vm.PushNumber(L, a.line_velocity)
	case "PlaneVelocity":
		d.Push_Vector2(L, dt, a.plane_velocity)
	case "PrimaryTangentAxis":
		d.Push_Vector3(L, a.primary_tangent_axis)
	case "SecondaryTangentAxis":
		d.Push_Vector3(L, a.secondary_tangent_axis)
	case "MaxForce":
		vm.PushNumber(L, a.max_force)
	case "MaxAxesForce":
		d.Push_Vector3(L, a.max_axes_force)
	case "MaxPlanarAxesForce":
		d.Push_Vector2(L, dt, a.max_planar_axes_force)
	case "ForceLimitsEnabled":
		vm.PushBoolean(L, a.force_limits_enabled)
	case "ReactionForceEnabled":
		vm.PushBoolean(L, a.reaction_force_enabled)
	case "RelativeTo":
		_ = e.Push_Item_By_Value(L, en, "ActuatorRelativeTo", i64(a.relative_to))
	case "ForceLimitMode":
		_ = e.Push_Item_By_Value(L, en, "ForceLimitMode", i64(a.force_limit_mode))
	case "VelocityConstraintMode":
		_ = e.Push_Item_By_Value(L, en, "VelocityConstraintMode", i64(a.velocity_constraint_mode))
	case:
		return Constraint_get(L, object, dt, en, key)
	}
	return true
}
LinearVelocity_set :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^d.Registry,
	en: ^e.Registry,
	key: string,
	index: int,
) -> bool {
	a := cast(^LinearVelocity)object
	switch key {
	case "Active":
		return false
	case "VectorVelocity":
		a.vector_velocity = d.Arg_Vector3(L, index)
	case "LineDirection":
		a.line_direction = d.Arg_Vector3(L, index)
	case "LineVelocity":
		a.line_velocity = vm.ArgNumber(L, index)
	case "PlaneVelocity":
		a.plane_velocity = d.Arg_Vector2(L, index, dt)
	case "PrimaryTangentAxis":
		a.primary_tangent_axis = d.Arg_Vector3(L, index)
	case "SecondaryTangentAxis":
		a.secondary_tangent_axis = d.Arg_Vector3(L, index)
	case "MaxForce":
		a.max_force = vm.ArgNumber(L, index)
	case "MaxAxesForce":
		a.max_axes_force = d.Arg_Vector3(L, index)
	case "MaxPlanarAxesForce":
		a.max_planar_axes_force = d.Arg_Vector2(L, index, dt)
	case "ForceLimitsEnabled":
		a.force_limits_enabled = vm.ArgBoolean(L, index)
	case "ReactionForceEnabled":
		a.reaction_force_enabled = vm.ArgBoolean(L, index)
	case "RelativeTo":
		a.relative_to = e.ActuatorRelativeTo(e.Arg_Item(L, index, en, "ActuatorRelativeTo").value)
	case "ForceLimitMode":
		a.force_limit_mode = e.ForceLimitMode(e.Arg_Item(L, index, en, "ForceLimitMode").value)
	case "VelocityConstraintMode":
		a.velocity_constraint_mode = e.VelocityConstraintMode(
			e.Arg_Item(L, index, en, "VelocityConstraintMode").value,
		)
	case:
		return Constraint_set(L, object, dt, en, key, index)
	}
	return true
}
Register_LinearVelocity :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&LinearVelocity_Class,
		LinearVelocity_construct,
		LinearVelocity_destroy,
		get = LinearVelocity_get,
		set = LinearVelocity_set,
		clone = LinearVelocity_clone,
		properties = []string {
			"VectorVelocity",
			"LineDirection",
			"LineVelocity",
			"PlaneVelocity",
			"PrimaryTangentAxis",
			"SecondaryTangentAxis",
			"MaxForce",
			"MaxAxesForce",
			"MaxPlanarAxesForce",
			"ForceLimitsEnabled",
			"ReactionForceEnabled",
			"RelativeTo",
			"ForceLimitMode",
			"VelocityConstraintMode",
		},
	)
}
AlignOrientation_Class := Class_Info {
	name   = "AlignOrientation",
	parent = &Constraint_Class,
}
AlignOrientation :: struct {
	using constraint:        Constraint,
	align_type:              e.AlignType,
	mode:                    e.OrientationAlignmentMode,
	target:                  d.CFrame,
	look_at_position:        d.Vector3,
	max_angular_velocity:    f64,
	max_torque:              f64,
	primary_axis:            d.Vector3,
	secondary_axis:          d.Vector3,
	primary_axis_only:       bool,
	reaction_torque_enabled: bool,
	responsiveness:          f64,
	rigidity_enabled:        bool,
}
AlignOrientation_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	a := new(AlignOrientation)
	a.constraint = Constraint_Init()
	a.object.class = &AlignOrientation_Class
	a.name = "AlignOrientation"
	a.active = false
	a.align_type = .AllAxes
	a.mode = .TwoAttachment
	a.target = d.CFrame_Identity
	a.look_at_position = {}
	a.max_angular_velocity = 100
	a.max_torque = 10000
	a.primary_axis = {1, 0, 0}
	a.secondary_axis = {0, 1, 0}
	a.primary_axis_only = false
	a.reaction_torque_enabled = false
	a.responsiveness = 10
	a.rigidity_enabled = false
	return &a.object
}
AlignOrientation_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^AlignOrientation)object)
}
AlignOrientation_clone :: proc(source, destination: ^Object) {
	Constraint_clone(source, destination)
	src, dst := cast(^AlignOrientation)source, cast(^AlignOrientation)destination
	dst.active = false
	dst.align_type = src.align_type
	dst.mode = src.mode
	dst.target = src.target
	dst.look_at_position = src.look_at_position
	dst.max_angular_velocity = src.max_angular_velocity
	dst.max_torque = src.max_torque
	dst.primary_axis = src.primary_axis
	dst.secondary_axis = src.secondary_axis
	dst.primary_axis_only = src.primary_axis_only
	dst.reaction_torque_enabled = src.reaction_torque_enabled
	dst.responsiveness = src.responsiveness
	dst.rigidity_enabled = src.rigidity_enabled
}
AlignOrientation_get :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^d.Registry,
	en: ^e.Registry,
	key: string,
) -> bool {
	a := cast(^AlignOrientation)object
	switch key {
	case "AlignType":
		_ = e.Push_Item_By_Value(L, en, "AlignType", i64(a.align_type))
	case "Mode":
		_ = e.Push_Item_By_Value(L, en, "OrientationAlignmentMode", i64(a.mode))
	case "CFrame":
		d.Push_CFrame(L, dt, a.target)
	case "LookAtPosition":
		d.Push_Vector3(L, a.look_at_position)
	case "MaxAngularVelocity":
		vm.PushNumber(L, a.max_angular_velocity)
	case "MaxTorque":
		vm.PushNumber(L, a.max_torque)
	case "PrimaryAxis":
		d.Push_Vector3(L, a.primary_axis)
	case "SecondaryAxis":
		d.Push_Vector3(L, a.secondary_axis)
	case "PrimaryAxisOnly":
		vm.PushBoolean(L, a.primary_axis_only)
	case "ReactionTorqueEnabled":
		vm.PushBoolean(L, a.reaction_torque_enabled)
	case "Responsiveness":
		vm.PushNumber(L, a.responsiveness)
	case "RigidityEnabled":
		vm.PushBoolean(L, a.rigidity_enabled)
	case:
		return Constraint_get(L, object, dt, en, key)
	}
	return true
}
AlignOrientation_set :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^d.Registry,
	en: ^e.Registry,
	key: string,
	index: int,
) -> bool {
	a := cast(^AlignOrientation)object
	switch key {
	case "Active":
		return false
	case "AlignType":
		a.align_type = e.AlignType(e.Arg_Item(L, index, en, "AlignType").value)
	case "Mode":
		a.mode = e.OrientationAlignmentMode(
			e.Arg_Item(L, index, en, "OrientationAlignmentMode").value,
		)
	case "CFrame":
		a.target = d.Arg_CFrame(L, index, dt)
	case "LookAtPosition":
		a.look_at_position = d.Arg_Vector3(L, index)
	case "MaxAngularVelocity":
		a.max_angular_velocity = vm.ArgNumber(L, index)
	case "MaxTorque":
		a.max_torque = vm.ArgNumber(L, index)
	case "PrimaryAxis":
		a.primary_axis = d.Arg_Vector3(L, index)
	case "SecondaryAxis":
		a.secondary_axis = d.Arg_Vector3(L, index)
	case "PrimaryAxisOnly":
		a.primary_axis_only = vm.ArgBoolean(L, index)
	case "ReactionTorqueEnabled":
		a.reaction_torque_enabled = vm.ArgBoolean(L, index)
	case "Responsiveness":
		a.responsiveness = vm.ArgNumber(L, index)
	case "RigidityEnabled":
		a.rigidity_enabled = vm.ArgBoolean(L, index)
	case:
		return Constraint_set(L, object, dt, en, key, index)
	}
	return true
}
Register_AlignOrientation :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&AlignOrientation_Class,
		AlignOrientation_construct,
		AlignOrientation_destroy,
		get = AlignOrientation_get,
		set = AlignOrientation_set,
		clone = AlignOrientation_clone,
		properties = []string {
			"AlignType",
			"Mode",
			"CFrame",
			"LookAtPosition",
			"MaxAngularVelocity",
			"MaxTorque",
			"PrimaryAxis",
			"SecondaryAxis",
			"PrimaryAxisOnly",
			"ReactionTorqueEnabled",
			"Responsiveness",
			"RigidityEnabled",
		},
	)
}

actuator_attachment_frame :: proc(
	attachment: ^Object,
	bi: j.JPH_BodyInterfaceRef,
	id: j.JPH_BodyID,
) -> d.CFrame {
	rot: j.JPH_Quat
	j.JPH_BodyInterface_GetRotation(bi, id, &rot)
	cf := d.CFrame_New_Quaternion(0, 0, 0, f64(rot.x), f64(rot.y), f64(rot.z), f64(rot.w))
	o := (cast(^Attachment)attachment).orientation
	local_frame := d.CFrame_FromOrientation(
		math.to_radians(o.x),
		math.to_radians(o.y),
		math.to_radians(o.z),
	)
	return d.CFrame_Mul_CFrame(cf, local_frame)
}

actuator_vec :: proc(v: j.JPH_Vec3) -> d.Vector3 {return {f64(v.x), f64(v.y), f64(v.z)}}
actuator_native :: proc(v: d.Vector3) -> j.JPH_Vec3 {return {f32(v.x), f32(v.y), f32(v.z)}}
actuator_clamp :: proc(v: d.Vector3, limit: f64) -> d.Vector3 {
	if math.is_nan(limit) || limit < 0 {return {}}
	n := d.Vec3_Magnitude(v)
	if !(n < 1e30) {return {}}
	if n > limit && n > 0 {return d.Vec3_Multiply(v, limit / n)}
	return v
}
LinearVelocity_step :: proc(
	object: ^Object,
	system: j.JPH_PhysicsSystemRef,
	body_ids: []j.JPH_BodyID,
	delta_time: f32,
) {
	a := cast(^LinearVelocity)object
	a.active = false
	if !a.enabled || system == nil || delta_time <= 0 {return}
	id, _, _, ok := resolve_attachment(a.attachment0, system, body_ids)
	if !ok {return}
	bi := j.JPH_PhysicsSystem_GetBodyInterface(system)
	if j.JPH_BodyInterface_GetMotionType(bi, id) != .Dynamic {return}
	other, _, _, has_other := resolve_attachment(a.attachment1, system, body_ids)
	frame := d.CFrame_Identity
	switch a.relative_to {
	case .Attachment0:
		frame = actuator_attachment_frame(a.attachment0, bi, id)
	case .Attachment1:
		if !has_other {return}
		frame = actuator_attachment_frame(a.attachment1, bi, other)
	case .World:
	}
	vel: j.JPH_Vec3
	j.JPH_BodyInterface_GetLinearVelocity(bi, id, &vel)
	current := actuator_vec(vel)
	local_frame := d.CFrame_VectorToObjectSpace(frame, current)
	if has_other && a.relative_to == .Attachment1 {
		v: j.JPH_Vec3
		j.JPH_BodyInterface_GetLinearVelocity(bi, other, &v)
		local_frame = d.Vec3_Subtract(
			local_frame,
			d.CFrame_VectorToObjectSpace(frame, actuator_vec(v)),
		)
	}
	velocity_error: d.Vector3
	switch a.velocity_constraint_mode {
	case .Vector:
		velocity_error = d.Vec3_Subtract(a.vector_velocity, local_frame)
	case .Line:
		if d.Vec3_Magnitude(a.line_direction) < 1e-6 {return}
		dir := d.Vec3_Unit(a.line_direction)
		velocity_error = d.Vec3_Multiply(dir, a.line_velocity - d.Vec3_Dot(local_frame, dir))
	case .Plane:
		if d.Vec3_Magnitude(a.primary_tangent_axis) < 1e-6 {return}
		x := d.Vec3_Unit(a.primary_tangent_axis)
		y := d.Vec3_Subtract(
			a.secondary_tangent_axis,
			d.Vec3_Multiply(x, d.Vec3_Dot(x, a.secondary_tangent_axis)),
		)
		if d.Vec3_Magnitude(y) < 1e-6 {return}
		y = d.Vec3_Unit(y)
		ex, ey :=
			f64(a.plane_velocity.X) -
			d.Vec3_Dot(local_frame, x),
			f64(a.plane_velocity.Y) -
			d.Vec3_Dot(local_frame, y)
		if a.force_limits_enabled && a.force_limit_mode == .PerAxis {

		}
		velocity_error = d.Vec3_Add(d.Vec3_Multiply(x, ex), d.Vec3_Multiply(y, ey))
	}
	reg := object.signal_registry
	mass := f64(1)
	if reg != nil &&
	   reg.part_body.get_mass !=
		   nil {mass = max(0.0001, reg.part_body.get_mass(reg.part_body_ctx, a.attachment0.parent))}
	force := d.Vec3_Multiply(velocity_error, mass / f64(delta_time))
	if a.force_limits_enabled {
		if a.force_limit_mode == .Magnitude || a.velocity_constraint_mode == .Line {
			force = actuator_clamp(force, max(0, a.max_force))
		} else if a.velocity_constraint_mode == .Plane {
			x := d.Vec3_Unit(a.primary_tangent_axis)
			y := d.Vec3_Unit(
				d.Vec3_Subtract(
					a.secondary_tangent_axis,
					d.Vec3_Multiply(x, d.Vec3_Dot(x, a.secondary_tangent_axis)),
				),
			)
			lx, ly :=
				f64(max(0, a.max_planar_axes_force.X)), f64(max(0, a.max_planar_axes_force.Y))
			force = d.Vec3_Add(
				d.Vec3_Multiply(x, clamp(d.Vec3_Dot(force, x), -lx, lx)),
				d.Vec3_Multiply(y, clamp(d.Vec3_Dot(force, y), -ly, ly)),
			)
		} else {
			l := a.max_axes_force
			force = {
				clamp(force.x, -abs(l.x), abs(l.x)),
				clamp(force.y, -abs(l.y), abs(l.y)),
				clamp(force.z, -abs(l.z), abs(l.z)),
			}
		}
	}
	force = actuator_clamp(d.CFrame_VectorToWorldSpace(frame, force), 1e20)
	native := actuator_native(force)
	j.JPH_BodyInterface_AddForce(bi, id, &native)
	j.JPH_BodyInterface_ActivateBody(bi, id)
	if has_other &&
	   a.reaction_force_enabled &&
	   j.JPH_BodyInterface_GetMotionType(bi, other) == .Dynamic {
		opposite := actuator_native(d.Vec3_Multiply(force, -1))
		j.JPH_BodyInterface_AddForce(bi, other, &opposite)
		j.JPH_BodyInterface_ActivateBody(bi, other)
	}
	a.active = true
}

AlignOrientation_step :: proc(
	object: ^Object,
	system: j.JPH_PhysicsSystemRef,
	body_ids: []j.JPH_BodyID,
	delta_time: f32,
) {
	a := cast(^AlignOrientation)object
	a.active = false
	if !a.enabled || system == nil || delta_time <= 0 {return}
	id, _, pos, ok := resolve_attachment(a.attachment0, system, body_ids)
	if !ok {return}
	bi := j.JPH_PhysicsSystem_GetBodyInterface(system)
	if j.JPH_BodyInterface_GetMotionType(bi, id) != .Dynamic {return}
	current := actuator_attachment_frame(a.attachment0, bi, id)
	target := a.target
	other, _, _, has_other := resolve_attachment(a.attachment1, system, body_ids)
	if a.mode == .TwoAttachment {
		if !has_other {return}
		target = actuator_attachment_frame(a.attachment1, bi, other)
	}


	x := d.CFrame_VectorToWorldSpace(current, {1, 0, 0})
	y := d.CFrame_VectorToWorldSpace(current, {0, 1, 0})
	z := d.CFrame_VectorToWorldSpace(current, {0, 0, 1})
	tx := d.CFrame_VectorToWorldSpace(target, {1, 0, 0})
	ty := d.CFrame_VectorToWorldSpace(target, {0, 1, 0})
	tz := d.CFrame_VectorToWorldSpace(target, {0, 0, 1})
	if a.align_type == .PrimaryAxisLookAt {
		toward := d.Vec3_Subtract(a.look_at_position, {pos.x, pos.y, pos.z})
		if d.Vec3_Magnitude(toward) < 1e-6 {return}
		tx = d.Vec3_Unit(toward)
	}
	err := d.Vec3_Cross(x, tx)
	if a.align_type == .AllAxes && !a.primary_axis_only {
		err = d.Vec3_Multiply(
			d.Vec3_Add(err, d.Vec3_Add(d.Vec3_Cross(y, ty), d.Vec3_Cross(z, tz))),
			0.5,
		)
	}
	if a.align_type == .PrimaryAxisPerpendicular ||
	   a.align_type ==
		   .Perpendicular {err = d.Vec3_Multiply(err, -d.Vec3_Dot(x, tx))} else if d.Vec3_Magnitude(err) < 1e-5 && d.Vec3_Dot(x, tx) < -0.99 {err = y}
	response := clamp(a.responsiveness, 1, 200)
	if a.rigidity_enabled {response = 100}
	desired := actuator_clamp(d.Vec3_Multiply(err, response), max(0, a.max_angular_velocity))
	av: j.JPH_Vec3
	j.JPH_BodyInterface_GetAngularVelocity(bi, id, &av)
	torque := actuator_clamp(
		d.Vec3_Multiply(d.Vec3_Subtract(desired, actuator_vec(av)), response),
		max(0, a.max_torque),
	)
	native := actuator_native(torque)
	j.JPH_BodyInterface_AddTorque(bi, id, &native)
	j.JPH_BodyInterface_ActivateBody(bi, id)
	if has_other &&
	   a.reaction_torque_enabled &&
	   j.JPH_BodyInterface_GetMotionType(bi, other) == .Dynamic {
		opposite := actuator_native(d.Vec3_Multiply(torque, -1))
		j.JPH_BodyInterface_AddTorque(bi, other, &opposite)
		j.JPH_BodyInterface_ActivateBody(bi, other)
	}
	a.active = true
}
