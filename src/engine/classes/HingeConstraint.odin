package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"
import "core:math/linalg"

HingeConstraint_Class := Class_Info {
	name   = "HingeConstraint",
	parent = &Constraint_Class,
}

Hinge_Config :: struct {
	visible:                bool,
	color:                  datatypes.BrickColor,
	actuator_type:          enums.ActuatorType,
	angular_responsiveness: f32,
	angular_speed:          f32,
	angular_velocity:       f32,
	limits_enabled:         bool,
	lower_angle:            f32,
	motor_max_acceleration: f32,
	motor_max_torque:       f32,
	radius:                 f32,
	restitution:            f32,
	servo_max_torque:       f32,
	softlock:               bool,
	target_angle:           f32,
	upper_angle:            f32,
}

Hinge_Frame :: struct {
	body:         kineffi.JPH_BodyID,
	position:     kineffi.JPH_Vec3,
	axis, normal: [3]f32,
}

HingeConstraint :: struct {
	using constraint: Constraint,
	config:           Hinge_Config,
	system:           kineffi.JPH_PhysicsSystemRef,
	joint:            kineffi.JPH_ConstraintRef,
	frames:           [2]Hinge_Frame,
	angle_offset:     f32,
	previous_speed:   f32,
}

HingeConstraint_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	hinge := new(HingeConstraint)
	hinge.constraint = Constraint_Init()
	hinge.object.class = &HingeConstraint_Class
	hinge.name = "HingeConstraint"
	hinge.active = false
	hinge.attachment0 = &hinge.object
	hinge.attachment1 = &hinge.object
	hinge.config = {
		color                  = datatypes.BrickColor_Green,
		angular_responsiveness = 45,
		lower_angle            = -45,
		upper_angle            = 45,
		motor_max_acceleration = 500000,
		radius                 = 0.15,
	}
	return &hinge.object
}

HingeConstraint_release :: proc(hinge: ^HingeConstraint) {
	if hinge.joint != nil {
		kineffi.JPH_PhysicsSystem_RemoveConstraint(hinge.system, hinge.joint)
		kineffi.JPH_Constraint_Destroy(hinge.joint)
		hinge.joint = nil
	}
	hinge.system = nil
	hinge.active = false
	hinge.previous_speed = 0
}

HingeConstraint_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	hinge := cast(^HingeConstraint)object
	HingeConstraint_release(hinge)
	Object_Destroy(object)
	free(hinge)
}

hinge_attachment_axes :: proc(attachment: ^Attachment) -> (axis, normal: [3]f32, valid: bool) {
	axis = {attachment.axis.x, attachment.axis.y, attachment.axis.z}
	normal = {
		attachment.secondary_axis.x,
		attachment.secondary_axis.y,
		attachment.secondary_axis.z,
	}
	axis_length := linalg.length(axis)
	if !(axis_length > 0) || math.is_inf(axis_length) {return {}, {}, false}
	axis /= axis_length
	normal -= linalg.dot(normal, axis) * axis
	normal_length := linalg.length(normal)
	if normal_length < 1e-6 {
		// Attachment axes can be edited independently in this engine.
		reference := abs(axis.z) < 0.9 ? [3]f32{0, 0, 1} : [3]f32{0, 1, 0}
		normal = reference - linalg.dot(reference, axis) * axis
		normal_length = linalg.length(normal)
	}
	if !(normal_length > 0) || math.is_inf(normal_length) {return {}, {}, false}
	normal /= normal_length

	o := attachment.orientation
	q := linalg.quaternion_from_euler_angles(
		f32(linalg.to_radians(o.y)),
		f32(linalg.to_radians(o.x)),
		f32(linalg.to_radians(o.z)),
		.YXZ,
	)
	rotation := kineffi.JPH_Quat{q.x, q.y, q.z, q.w}
	a := rotate_by_quat(rotation, {axis.x, axis.y, axis.z})
	n := rotate_by_quat(rotation, {normal.x, normal.y, normal.z})
	return {a.x, a.y, a.z}, {n.x, n.y, n.z}, true
}

hinge_frame :: proc(
	object: ^Object,
	body: kineffi.JPH_BodyID,
	position: kineffi.JPH_Vec3,
) -> (
	Hinge_Frame,
	bool,
) {
	axis, normal, valid := hinge_attachment_axes(cast(^Attachment)object)
	return Hinge_Frame{body, position, axis, normal}, valid
}

hinge_world_vector :: proc(rotation: kineffi.JPH_Quat, v: [3]f32) -> kineffi.JPH_Vec3 {
	return rotate_by_quat(rotation, {v.x, v.y, v.z})
}

hinge_angle_limits :: proc(config: Hinge_Config) -> (lower, upper: f32) {
	if !config.limits_enabled {return -math.PI, math.PI}
	return linalg.to_radians(
		min(config.lower_angle, config.upper_angle),
	), linalg.to_radians(max(config.lower_angle, config.upper_angle))
}

hinge_gizmo_frame :: proc(
	object, workspace: ^Object,
) -> (
	pivot, axis, normal: [3]f32,
	valid: bool,
) {
	if object == nil ||
	   object.destroyed ||
	   !Is_Descendant_Of(object, workspace) ||
	   !Is_A_Class(object.parent, &Part_Class) {return}

	attachment := cast(^Attachment)object
	local_axis, local_normal, ok := hinge_attachment_axes(attachment)
	if !ok {return}
	cframe := (cast(^Part)object.parent).cframe
	p := datatypes.CFrame_PointToWorldSpace(cframe, attachment.position)
	a := datatypes.CFrame_VectorToWorldSpace(cframe, {local_axis.x, local_axis.y, local_axis.z})
	n := datatypes.CFrame_VectorToWorldSpace(
		cframe,
		{local_normal.x, local_normal.y, local_normal.z},
	)
	return {p.x, p.y, p.z}, {a.x, a.y, a.z}, {n.x, n.y, n.z}, true
}

HingeConstraint_render :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	hinge := cast(^HingeConstraint)object
	config := hinge.config
	if !config.visible ||
	   config.radius <= 0 ||
	   ctx.renderer == nil ||
	   ctx.renderer.Filament == nil {
		return
	}

	workspace := object.parent
	for workspace != nil && !Is_A(workspace, "Workspace") {
		workspace = workspace.parent
	}
	if workspace == nil {return}
	pivot, axis, normal, ok0 := hinge_gizmo_frame(hinge.attachment0, workspace)
	other_pivot, _, other_normal, ok1 := hinge_gizmo_frame(hinge.attachment1, workspace)
	if !ok0 || !ok1 {return}

	radius := config.radius
	tangent := linalg.cross(axis, normal)
	lower, upper := hinge_angle_limits(config)
	ARC_SEGMENTS :: 32
	lines: [ARC_SEGMENTS + 5][2][3]f32
	lines[0] = {pivot - radius * axis, pivot + radius * axis}
	lines[1] = {other_pivot, other_pivot + radius * other_normal}
	count := 2
	if linalg.length(other_pivot - pivot) > 1e-5 {
		lines[count] = {pivot, other_pivot}
		count += 1
	}

	start := pivot + radius * (math.cos(lower) * normal + math.sin(lower) * tangent)
	previous := start
	if upper > lower {
		for i in 1 ..= ARC_SEGMENTS {
			angle := lower + (upper - lower) * f32(i) / ARC_SEGMENTS
			point := pivot + radius * (math.cos(angle) * normal + math.sin(angle) * tangent)
			lines[count] = {previous, point}
			count += 1
			previous = point
		}
	}
	if config.limits_enabled {
		lines[count] = {pivot, start}
		count += 1
		if upper > lower {
			lines[count] = {pivot, previous}
			count += 1
		}
	}

	color := config.color.color
	kineffi.Kine_Filament_DrawGizmoLines(
		ctx.renderer.Filament,
		&lines[0][0][0],
		u32(count),
		color.R,
		color.G,
		color.B,
		min(radius * 0.08, 0.05),
	)
}

hinge_angle :: proc(hinge: ^HingeConstraint) -> f32 {
	if hinge.joint == nil {return 0}
	angle := kineffi.JPH_HingeConstraint_GetCurrentAngle(hinge.joint) + hinge.angle_offset
	return angle - 2 * math.PI * math.floor((angle + math.PI) / (2 * math.PI))
}

HingeConstraint_step :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
	delta_time: f32,
) {
	hinge := cast(^HingeConstraint)object
	if !hinge.enabled || system == nil {
		HingeConstraint_release(hinge)
		return
	}

	id0, local0, world0, ok0 := resolve_attachment(hinge.attachment0, system, body_ids)
	id1, local1, world1, ok1 := resolve_attachment(hinge.attachment1, system, body_ids)
	if !ok0 || !ok1 || id0 == id1 {
		HingeConstraint_release(hinge)
		return
	}

	bi := kineffi.JPH_PhysicsSystem_GetBodyInterface(system)
	dynamic0 := kineffi.JPH_BodyInterface_GetMotionType(bi, id0) == .Dynamic
	dynamic1 := kineffi.JPH_BodyInterface_GetMotionType(bi, id1) == .Dynamic
	if !dynamic0 && !dynamic1 {
		HingeConstraint_release(hinge)
		return
	}
	frame0, valid0 := hinge_frame(hinge.attachment0, id0, local0)
	frame1, valid1 := hinge_frame(hinge.attachment1, id1, local1)
	if !valid0 || !valid1 {
		HingeConstraint_release(hinge)
		return
	}

	config := hinge.config
	lower, upper := hinge_angle_limits(config)
	offset := (lower + upper) * 0.5
	// Jolt requires the allowed interval to straddle its zero angle.
	half_range := max((upper - lower) * 0.5, 1e-5)
	rot0: kineffi.JPH_Quat
	kineffi.JPH_BodyInterface_GetRotation(bi, id0, &rot0)
	world_axis := hinge_world_vector(rot0, frame0.axis)

	frames := [2]Hinge_Frame{frame0, frame1}
	if hinge.joint == nil ||
	   hinge.system != system ||
	   hinge.frames != frames ||
	   hinge.angle_offset != offset {
		HingeConstraint_release(hinge)
		rot1: kineffi.JPH_Quat
		kineffi.JPH_BodyInterface_GetRotation(bi, id1, &rot1)
		normal1 :=
			math.cos(offset) * frame1.normal -
			math.sin(offset) * linalg.cross(frame1.axis, frame1.normal)

		settings: kineffi.JPH_HingeConstraintSettings
		kineffi.JPH_HingeConstraintSettings_Init(&settings)
		settings.space = .WorldSpace
		settings.point1 = world0
		settings.point2 = world1
		settings.hingeAxis1 = world_axis
		settings.hingeAxis2 = hinge_world_vector(rot1, frame1.axis)
		settings.normalAxis1 = hinge_world_vector(rot0, frame0.normal)
		settings.normalAxis2 = hinge_world_vector(rot1, normal1)
		hinge.joint = kineffi.JPH_HingeConstraint_CreateFromIDs(system, &settings, id0, id1)
		if hinge.joint == nil {return}

		if dynamic0 && dynamic1 {
			// Contact loads propagate through several joints in a steering assembly.
			settings.base.numVelocityStepsOverride = 24
			settings.base.numPositionStepsOverride = 12
			kineffi.JPH_Constraint_ApplyBaseSettings(hinge.joint, &settings.base)
		}
		kineffi.JPH_Constraint_AddRef(hinge.joint)
		kineffi.JPH_PhysicsSystem_AddConstraint(system, hinge.joint)
		hinge.system = system
		hinge.frames = frames
		hinge.angle_offset = offset
		hinge.active = true
		kineffi.JPH_BodyInterface_ActivateBody(bi, id0)
		kineffi.JPH_BodyInterface_ActivateBody(bi, id1)
	}

	if kineffi.JPH_HingeConstraint_GetLimitsMax(hinge.joint) != half_range {
		kineffi.JPH_HingeConstraint_SetLimits(hinge.joint, -half_range, half_range)
		kineffi.JPH_BodyInterface_ActivateBody(bi, id0)
		kineffi.JPH_BodyInterface_ActivateBody(bi, id1)
	}

	omega0, omega1: kineffi.JPH_Vec3
	kineffi.JPH_BodyInterface_GetAngularVelocity(bi, id0, &omega0)
	kineffi.JPH_BodyInterface_GetAngularVelocity(bi, id1, &omega1)
	speed :=
		(omega1.x - omega0.x) * world_axis.x +
		(omega1.y - omega0.y) * world_axis.y +
		(omega1.z - omega0.z) * world_axis.z
	angle := kineffi.JPH_HingeConstraint_GetCurrentAngle(hinge.joint) + offset
	target_speed, torque: f32
	switch config.actuator_type {
	case .None:
	case .Motor:
		max_change := config.motor_max_acceleration * delta_time
		target_speed = speed + clamp(config.angular_velocity - speed, -max_change, max_change)
		torque = config.motor_max_torque
	case .Servo:
		target := clamp(linalg.to_radians(config.target_angle), lower, upper)
		error := target - angle
		if !config.limits_enabled {
			error -= 2 * math.PI * math.floor((error + math.PI) / (2 * math.PI))
		}
		target_speed = clamp(
			error * min(config.angular_responsiveness, 1 / max(delta_time, 1e-6)),
			-config.angular_speed,
			config.angular_speed,
		)
		torque = config.servo_max_torque
		if config.softlock && abs(error) < 1e-4 {
			target_speed = 0
		}
	}

	// Jolt stops motion at the limit. Use the incoming speed from the preceding
	// step to give the hinge a rebound when it reaches an angular stop.
	at_stop :=
		(angle >= upper - 1e-4 && hinge.previous_speed > 0) ||
		(angle <= lower + 1e-4 && hinge.previous_speed < 0)
	if config.limits_enabled &&
	   config.restitution > 0 &&
	   at_stop &&
	   abs(speed) < abs(hinge.previous_speed) {
		target_speed = -hinge.previous_speed * config.restitution
		torque = math.F32_MAX
	}
	hinge.previous_speed = speed

	if torque > 0 {
		motor := kineffi.JPH_MotorSettings {
			minTorqueLimit = -torque,
			maxTorqueLimit = torque,
		}
		kineffi.JPH_HingeConstraint_SetMotorSettings(hinge.joint, &motor)
		kineffi.JPH_HingeConstraint_SetTargetAngularVelocity(hinge.joint, target_speed)
		kineffi.JPH_HingeConstraint_SetMotorState(hinge.joint, .Velocity)
		if abs(target_speed) > 1e-5 || abs(speed) > 1e-5 {
			kineffi.JPH_BodyInterface_ActivateBody(bi, id0)
			kineffi.JPH_BodyInterface_ActivateBody(bi, id1)
		}
	} else {
		kineffi.JPH_HingeConstraint_SetMotorState(hinge.joint, .Off)
	}
}

HingeConstraint_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	hinge := cast(^HingeConstraint)object
	switch key {
	case "Visible":
		vm.PushBoolean(L, hinge.config.visible)
	case "Color":
		if datatype_registry == nil {return false}
		datatypes.Push_BrickColor(L, datatype_registry, hinge.config.color)
	case "ActuatorType":
		return(
			enum_registry != nil &&
			enums.Push_Item_By_Value(
				L,
				enum_registry,
				"ActuatorType",
				i64(hinge.config.actuator_type),
			) \
		)
	case "CurrentAngle":
		vm.PushNumber(L, f64(linalg.to_degrees(hinge_angle(hinge))))
	case "AngularResponsiveness":
		vm.PushNumber(L, f64(hinge.config.angular_responsiveness))
	case "AngularSpeed":
		vm.PushNumber(L, f64(hinge.config.angular_speed))
	case "AngularVelocity":
		vm.PushNumber(L, f64(hinge.config.angular_velocity))
	case "LimitsEnabled":
		vm.PushBoolean(L, hinge.config.limits_enabled)
	case "LowerAngle":
		vm.PushNumber(L, f64(hinge.config.lower_angle))
	case "MotorMaxAcceleration":
		vm.PushNumber(L, f64(hinge.config.motor_max_acceleration))
	case "MotorMaxTorque":
		vm.PushNumber(L, f64(hinge.config.motor_max_torque))
	case "Radius":
		vm.PushNumber(L, f64(hinge.config.radius))
	case "Restitution":
		vm.PushNumber(L, f64(hinge.config.restitution))
	case "ServoMaxTorque":
		vm.PushNumber(L, f64(hinge.config.servo_max_torque))
	case "SoftlockServoUponReachingTarget":
		vm.PushBoolean(L, hinge.config.softlock)
	case "TargetAngle":
		vm.PushNumber(L, f64(hinge.config.target_angle))
	case "UpperAngle":
		vm.PushNumber(L, f64(hinge.config.upper_angle))
	case:
		return Constraint_get(L, object, datatype_registry, enum_registry, key)
	}
	return true
}

hinge_number :: proc(L: ^vm.State, index: int) -> f32 {
	value := vm.ArgNumber(L, index)
	if math.is_nan(value) {
		_ = vm.RaiseError(L, "HingeConstraint properties cannot be NaN")
		return 0
	}
	return f32(clamp(value, -f64(math.F32_MAX), f64(math.F32_MAX)))
}

HingeConstraint_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	hinge := cast(^HingeConstraint)object
	switch key {
	case "Visible":
		hinge.config.visible = vm.ArgBoolean(L, value_index)
	case "Color":
		if datatype_registry == nil {return false}
		hinge.config.color = datatypes.Arg_BrickColor(L, value_index, datatype_registry)
	case "ActuatorType":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "ActuatorType")
		hinge.config.actuator_type = enums.ActuatorType(item.value)
	case "Active", "CurrentAngle":
		return false
	case "Attachment0", "Attachment1", "Enabled":
		if !Constraint_set(
			L,
			object,
			datatype_registry,
			enum_registry,
			key,
			value_index,
		) {return false}
		HingeConstraint_release(hinge)
	case "AngularResponsiveness":
		value := hinge_number(L, value_index)
		hinge.config.angular_responsiveness = max(value, 0)
	case "AngularSpeed":
		value := hinge_number(L, value_index)
		hinge.config.angular_speed = max(value, 0)
	case "AngularVelocity":
		value := hinge_number(L, value_index)
		hinge.config.angular_velocity = value
	case "LimitsEnabled":
		hinge.config.limits_enabled = vm.ArgBoolean(L, value_index)
	case "LowerAngle":
		value := hinge_number(L, value_index)
		hinge.config.lower_angle = clamp(value, -180, 180)
	case "MotorMaxAcceleration":
		value := hinge_number(L, value_index)
		hinge.config.motor_max_acceleration = max(value, 0)
	case "MotorMaxTorque":
		value := hinge_number(L, value_index)
		hinge.config.motor_max_torque = max(value, 0)
	case "Radius":
		value := hinge_number(L, value_index)
		hinge.config.radius = max(value, 0)
	case "Restitution":
		value := hinge_number(L, value_index)
		hinge.config.restitution = clamp(value, 0, 1)
	case "ServoMaxTorque":
		value := hinge_number(L, value_index)
		hinge.config.servo_max_torque = max(value, 0)
	case "SoftlockServoUponReachingTarget":
		hinge.config.softlock = vm.ArgBoolean(L, value_index)
	case "TargetAngle":
		value := hinge_number(L, value_index)
		hinge.config.target_angle = clamp(value, -180, 180)
	case "UpperAngle":
		value := hinge_number(L, value_index)
		hinge.config.upper_angle = clamp(value, -180, 180)
	case:
		return Constraint_set(L, object, datatype_registry, enum_registry, key, value_index)
	}
	return true
}

HingeConstraint_clone :: proc(source, destination: ^Object) {
	Constraint_clone(source, destination)
	src := cast(^HingeConstraint)source
	dst := cast(^HingeConstraint)destination
	dst.active = false
	dst.config = src.config
}

Register_HingeConstraint :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&HingeConstraint_Class,
		HingeConstraint_construct,
		HingeConstraint_destroy,
		get = HingeConstraint_get,
		set = HingeConstraint_set,
		clone = HingeConstraint_clone,
		_step = HingeConstraint_render,
		_step_phase = .Render_3D,
		properties = []string {
			"Visible",
			"Color",
			"ActuatorType",
			"AngularResponsiveness",
			"AngularSpeed",
			"AngularVelocity",
			"CurrentAngle",
			"LimitsEnabled",
			"LowerAngle",
			"MotorMaxAcceleration",
			"MotorMaxTorque",
			"Radius",
			"Restitution",
			"ServoMaxTorque",
			"SoftlockServoUponReachingTarget",
			"TargetAngle",
			"UpperAngle",
		},
	)
}
