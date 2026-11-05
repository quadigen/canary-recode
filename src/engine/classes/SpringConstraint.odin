package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"
import "core:math/linalg"

SpringConstraint_Class := Class_Info {
	name   = "SpringConstraint",
	parent = &Constraint_Class,
}

SPRING_MAX_COILS :: 8

Spring_Config :: struct {
	stand, visible, limits_enabled:      bool,
	color:                               datatypes.BrickColor,
	coils:                               f32,
	damping, stiffness, max_force:       f32,
	free_length, min_length, max_length: f32,
	radius, thickness:                   f32,
}

Spring_Frame :: struct {
	body:      kineffi.JPH_BodyID,
	offset:    kineffi.JPH_Vec3,
	right, up: [3]f32,
}

SpringConstraint :: struct {
	using constraint: Constraint,
	config:           Spring_Config,
	system:           kineffi.JPH_PhysicsSystemRef,
	joint:            kineffi.JPH_ConstraintRef,
	frames:           [2]Spring_Frame,
	stand_sign:       f32,
	applied_force:    [2][3]f32,
	applied_torque:   [2][3]f32,
}

SpringConstraint_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	spring := new(SpringConstraint)
	spring.constraint = Constraint_Init()
	spring.object.class = &SpringConstraint_Class
	spring.name = "SpringConstraint"
	spring.active = false
	spring.attachment0 = &spring.object
	spring.attachment1 = &spring.object
	spring.config = {
		color       = datatypes.BrickColor_Lemon_Metalic,
		coils       = 3,
		free_length = 1,
		max_length  = 5,
		max_force   = math.INF_F32,
		radius      = 0.4,
		thickness   = 0.1,
	}
	return &spring.object
}

SpringConstraint_release :: proc(spring: ^SpringConstraint) {
	if spring.joint != nil {
		kineffi.JPH_PhysicsSystem_RemoveConstraint(spring.system, spring.joint)
		kineffi.JPH_Constraint_Destroy(spring.joint)
		spring.joint = nil
	}
	spring.system = nil
	spring.active = false
	spring.applied_force = {}
	spring.applied_torque = {}
}

SpringConstraint_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	spring := cast(^SpringConstraint)object
	SpringConstraint_release(spring)
	Object_Destroy(object)
	free(spring)
}

spring_delta :: proc(a, b: kineffi.JPH_RVec3) -> [3]f32 {
	return {f32(b.x - a.x), f32(b.y - a.y), f32(b.z - a.z)}
}

spring_world_axis :: proc(rotation: kineffi.JPH_Quat, axis: [3]f32) -> [3]f32 {
	v := rotate_by_quat(rotation, {axis.x, axis.y, axis.z})
	return {v.x, v.y, v.z}
}

spring_create_joint :: proc(
	spring: ^SpringConstraint,
	system: kineffi.JPH_PhysicsSystemRef,
	frames: [2]Spring_Frame,
	points: [2]kineffi.JPH_RVec3,
	rotations: [2]kineffi.JPH_Quat,
) -> kineffi.JPH_ConstraintRef {
	config := spring.config
	min_length, max_length := f32(0), f32(math.F32_MAX)
	if config.limits_enabled {
		min_length = config.min_length
		max_length = max(config.max_length, min_length)
	}
	id0, id1 := frames[0].body, frames[1].body
	if !config.stand {
		settings: kineffi.JPH_DistanceConstraintSettings
		kineffi.JPH_DistanceConstraintSettings_Init(&settings)
		settings.point1, settings.point2 = points[0], points[1]
		settings.minDistance, settings.maxDistance = min_length, max_length
		return kineffi.JPH_DistanceConstraint_CreateFromIDs(system, &settings, id0, id1)
	}

	// A prismatic guide leaves one translation free and aligns both attachment frames.
	up0 := spring_world_axis(rotations[0], frames[0].up)
	up1 := spring_world_axis(rotations[1], frames[1].up)
	right0 := spring_world_axis(rotations[0], frames[0].right)
	right1 := spring_world_axis(rotations[1], frames[1].right)
	spring.stand_sign = linalg.dot(up0, spring_delta(points[0], points[1])) < 0 ? -1 : 1
	up0 *= spring.stand_sign
	up1 *= spring.stand_sign

	settings: kineffi.JPH_SixDOFConstraintSettings
	kineffi.JPH_SixDOFConstraintSettings_Init(&settings)
	settings.position1, settings.position2 = points[0], points[1]
	settings.axisX1, settings.axisX2 =
		{right0.x, right0.y, right0.z}, {right1.x, right1.y, right1.z}
	settings.axisY1, settings.axisY2 = {up0.x, up0.y, up0.z}, {up1.x, up1.y, up1.z}
	fixed_axes := [?]kineffi.JPH_SixDOFAxis {
		.TranslationX,
		.TranslationZ,
		.RotationX,
		.RotationY,
		.RotationZ,
	}
	for axis in fixed_axes {
		kineffi.JPH_SixDOFConstraintSettings_MakeFixedAxis(&settings, axis)
	}
	if min_length == max_length {
		// Jolt fixes an equal range at zero, so shift the guide origin to the stop.
		settings.position1.x += f64(up0.x) * f64(min_length)
		settings.position1.y += f64(up0.y) * f64(min_length)
		settings.position1.z += f64(up0.z) * f64(min_length)
		kineffi.JPH_SixDOFConstraintSettings_MakeFixedAxis(&settings, .TranslationY)
	} else {
		kineffi.JPH_SixDOFConstraintSettings_SetLimitedAxis(
			&settings,
			.TranslationY,
			min_length,
			max_length,
		)
	}
	return kineffi.JPH_SixDOFConstraint_CreateFromIDs(system, &settings, id0, id1)
}

spring_point_motion :: proc(
	bi: kineffi.JPH_BodyInterfaceRef,
	body: kineffi.JPH_BodyID,
	point: kineffi.JPH_RVec3,
) -> (
	velocity, offset: [3]f32,
) {
	center: kineffi.JPH_RVec3
	linear, angular: kineffi.JPH_Vec3
	kineffi.JPH_BodyInterface_GetCenterOfMassPosition(bi, body, &center)
	kineffi.JPH_BodyInterface_GetLinearVelocity(bi, body, &linear)
	kineffi.JPH_BodyInterface_GetAngularVelocity(bi, body, &angular)
	offset = spring_delta(center, point)
	velocity =
		[3]f32{linear.x, linear.y, linear.z} +
		linalg.cross([3]f32{angular.x, angular.y, angular.z}, offset)
	return
}

SpringConstraint_step :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
	delta_time: f32,
) {
	spring := cast(^SpringConstraint)object
	if !spring.enabled || system == nil {
		SpringConstraint_release(spring)
		return
	}
	id0, local0, world0, ok0 := resolve_attachment(spring.attachment0, system, body_ids)
	id1, local1, world1, ok1 := resolve_attachment(spring.attachment1, system, body_ids)
	separation := spring_delta(world0, world1)
	length := linalg.length(separation)
	if !ok0 || !ok1 || id0 == id1 || math.is_nan(length) || math.is_inf(length) {
		SpringConstraint_release(spring)
		return
	}
	bi := kineffi.JPH_PhysicsSystem_GetBodyInterface(system)
	is_dynamic := [2]bool {
		kineffi.JPH_BodyInterface_GetMotionType(bi, id0) == .Dynamic,
		kineffi.JPH_BodyInterface_GetMotionType(bi, id1) == .Dynamic,
	}
	if !is_dynamic[0] && !is_dynamic[1] {
		SpringConstraint_release(spring)
		return
	}

	frames := [2]Spring_Frame{{body = id0, offset = local0}, {body = id1, offset = local1}}
	points := [2]kineffi.JPH_RVec3{world0, world1}
	rotations: [2]kineffi.JPH_Quat
	config := spring.config
	if config.stand {
		attachments := [2]^Object{spring.attachment0, spring.attachment1}
		for &frame, i in frames {
			right, up, valid := constraint_attachment_axes(cast(^Attachment)attachments[i])
			if !valid || !(linalg.dot(up, up) > 0) || !(linalg.dot(right, right) > 0) {
				SpringConstraint_release(spring)
				return
			}
			frame.right, frame.up = right, up
			kineffi.JPH_BodyInterface_GetRotation(bi, frame.body, &rotations[i])
		}
	}

	if spring.system != system || spring.frames != frames {
		SpringConstraint_release(spring)
		if config.stand || config.limits_enabled {
			joint := spring_create_joint(spring, system, frames, points, rotations)
			if joint == nil {return}
			kineffi.JPH_Constraint_AddRef(joint)
			kineffi.JPH_PhysicsSystem_AddConstraint(system, joint)
			spring.joint = joint
			for frame, i in frames {
				if is_dynamic[i] {kineffi.JPH_BodyInterface_ActivateBody(bi, frame.body)}
			}
		}
		spring.system = system
		spring.frames = frames
		spring.active = true
	}

	spring.applied_force = {}
	spring.applied_torque = {}
	if delta_time <= 0 ||
	   config.max_force == 0 ||
	   (config.stiffness == 0 && config.damping == 0) {return}
	axis: [3]f32
	if config.stand {
		axis = spring.stand_sign * spring_world_axis(rotations[0], frames[0].up)
		length = linalg.dot(separation, axis)
	} else if length > 0 {
		axis = separation / length
	} else {
		// Give coincident anchors a direction in which to separate.
		axis = {0, 1, 0}
	}

	v0, offset0 := spring_point_motion(bi, id0, world0)
	v1, offset1 := spring_point_motion(bi, id1, world1)
	speed := linalg.dot(v1 - v0, axis)
	magnitude :=
		f64(config.stiffness) * (f64(length) - f64(config.free_length)) +
		f64(config.damping) * f64(speed)
	if math.is_nan(magnitude) || abs(magnitude) < 1e-5 {return}
	limit := f64(min(config.max_force, math.F32_MAX))
	force := f32(clamp(magnitude, -limit, limit)) * axis
	forces := [2][3]f32{force, -force}
	offsets := [2][3]f32{offset0, offset1}
	for value, i in forces {
		if !is_dynamic[i] {continue}
		native_force := kineffi.JPH_Vec3{value.x, value.y, value.z}
		kineffi.JPH_BodyInterface_AddForce2(bi, frames[i].body, &native_force, &points[i])
		spring.applied_force[i] = value
		spring.applied_torque[i] = linalg.cross(offsets[i], value)
	}
}

spring_attachment_point :: proc(object: ^Object) -> ([3]f32, bool) {
	if !Is_A_Class(object, &Attachment_Class) ||
	   object.destroyed ||
	   !Is_A_Class(object.parent, &Part_Class) {
		return {}, false
	}
	attachment := cast(^Attachment)object
	part := cast(^Part)object.parent
	p := datatypes.CFrame_PointToWorldSpace(part.cframe, attachment.position)
	return {p.x, p.y, p.z}, true
}

spring_attachments_in_workspace :: proc(spring: ^SpringConstraint) -> bool {
	workspace := spring.object.parent
	for workspace != nil && !Is_A(workspace, "Workspace") {workspace = workspace.parent}
	return(
		workspace != nil &&
		Is_Descendant_Of(spring.attachment0, workspace) &&
		Is_Descendant_Of(spring.attachment1, workspace) \
	)
}

SpringConstraint_render :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	spring := cast(^SpringConstraint)object
	config := spring.config
	if !config.visible ||
	   config.thickness <= 0 ||
	   ctx.renderer == nil ||
	   ctx.renderer.Filament == nil {return}

	if !spring_attachments_in_workspace(spring) {return}
	first, ok0 := spring_attachment_point(spring.attachment0)
	last, ok1 := spring_attachment_point(spring.attachment1)
	if !ok0 || !ok1 {return}
	delta := last - first
	length := linalg.length(delta)
	if !(length > 1e-5) || math.is_inf(length) {return}

	SEGMENTS_PER_COIL :: 12
	lines: [SPRING_MAX_COILS * SEGMENTS_PER_COIL + 2][2][3]f32
	count := 1
	lines[0] = {first, last}
	if config.coils > 0 && config.radius > 0 {
		axis := delta / length
		reference := abs(axis.y) < 0.9 ? [3]f32{0, 1, 0} : [3]f32{1, 0, 0}
		right := linalg.normalize(linalg.cross(axis, reference))
		up := linalg.cross(axis, right)
		segments := int(math.ceil(config.coils * SEGMENTS_PER_COIL))
		previous := first
		for i in 0 ..= segments {
			t := f32(i) / f32(segments)
			angle := t * config.coils * (2 * math.PI)
			next :=
				first +
				t * delta +
				config.radius * (math.cos(angle) * right + math.sin(angle) * up)
			lines[i] = {previous, next}
			previous = next
		}
		lines[segments + 1] = {previous, last}
		count = segments + 2
	}
	color := config.color.color
	kineffi.Kine_Filament_DrawGizmoLines(
		ctx.renderer.Filament,
		&lines[0][0][0],
		u32(count),
		color.R,
		color.G,
		color.B,
		config.thickness,
	)
}

spring_number_property :: proc(config: ^Spring_Config, key: string) -> ^f32 {
	switch key {
	case "Damping":
		return &config.damping
	case "FreeLength":
		return &config.free_length
	case "MaxForce":
		return &config.max_force
	case "MaxLength":
		return &config.max_length
	case "MinLength":
		return &config.min_length
	case "Radius":
		return &config.radius
	case "Stiffness":
		return &config.stiffness
	case "Thickness":
		return &config.thickness
	}
	return nil
}

SpringConstraint_get :: proc(
	L: ^vm.State,
	object: ^Object,
	registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	spring := cast(^SpringConstraint)object
	config := &spring.config
	if number := spring_number_property(config, key); number != nil {
		vm.PushNumber(L, f64(number^))
		return true
	}
	switch key {
	case "Active":
		vm.PushBoolean(L, spring.active && spring_attachments_in_workspace(spring))
	case "Stand":
		vm.PushBoolean(L, config.stand)
	case "Visible":
		vm.PushBoolean(L, config.visible)
	case "LimitsEnabled":
		vm.PushBoolean(L, config.limits_enabled)
	case "Coils":
		vm.PushNumber(L, f64(config.coils))
	case "Color":
		if registry == nil {return false}
		datatypes.Push_BrickColor(L, registry, config.color)
	case "CurrentLength":
		first, ok0 := spring_attachment_point(spring.attachment0)
		last, ok1 := spring_attachment_point(spring.attachment1)
		vm.PushNumber(L, f64(linalg.length(last - first)) if ok0 && ok1 else 0)
	case:
		return Constraint_get(L, object, registry, enum_registry, key)
	}
	return true
}

SpringConstraint_set :: proc(
	L: ^vm.State,
	object: ^Object,
	registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	spring := cast(^SpringConstraint)object
	config := &spring.config
	if number := spring_number_property(config, key); number != nil {
		value := vm.ArgNumber(L, index)
		if math.is_nan(value) {
			_ = vm.RaiseError(L, "SpringConstraint properties cannot be NaN")
			return true
		}
		limit := f64(math.INF_F32) if key == "MaxForce" else f64(math.F32_MAX)
		next := f32(clamp(value, 0, limit))
		if next != number^ && (key == "MinLength" || key == "MaxLength") {
			SpringConstraint_release(spring)
		}
		number^ = next
		return true
	}
	switch key {
	case "Stand", "LimitsEnabled":
		flag := &config.stand if key == "Stand" else &config.limits_enabled
		value := vm.ArgBoolean(L, index)
		if flag^ != value {SpringConstraint_release(spring)}
		flag^ = value
	case "Visible":
		config.visible = vm.ArgBoolean(L, index)
	case "Color":
		if registry == nil {return false}
		config.color = datatypes.Arg_BrickColor(L, index, registry)
	case "Coils":
		value := vm.ArgNumber(L, index)
		if math.is_nan(value) {return false}
		config.coils = f32(clamp(value, 0, SPRING_MAX_COILS))
	case "Active", "CurrentLength":
		return false
	case "Attachment0", "Attachment1":
		value := object_from_argument(L, index)
		if !vm.IsNil(L, index) && !Is_A_Class(value, &Attachment_Class) {return false}
		slot := &spring.attachment0 if key == "Attachment0" else &spring.attachment1
		if slot^ != value {SpringConstraint_release(spring)}
		slot^ = value
	case "Enabled":
		spring.enabled = vm.ArgBoolean(L, index)
		if !spring.enabled {SpringConstraint_release(spring)}
	case:
		return false
	}
	return true
}

SpringConstraint_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "GetDebugAppliedForce" && method != "GetDebugAppliedTorque" {return 0, false}
	spring := cast(^SpringConstraint)object
	index := vm.ArgNumber(L, 2)
	value: [3]f32
	if index == 0 || index == 1 {
		values :=
			&spring.applied_force if method == "GetDebugAppliedForce" else &spring.applied_torque
		value = values[i32(index)]
	}
	datatypes.Push_Vector3(L, {value.x, value.y, value.z})
	return 1, true
}

SpringConstraint_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^SpringConstraint)source, cast(^SpringConstraint)destination
	dst.config = src.config
	dst.active = false
}

Register_SpringConstraint :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&SpringConstraint_Class,
		SpringConstraint_construct,
		SpringConstraint_destroy,
		get = SpringConstraint_get,
		set = SpringConstraint_set,
		clone = SpringConstraint_clone,
		namecall = SpringConstraint_namecall,
		_step = SpringConstraint_render,
		_step_phase = .Render_3D,
		properties = []string {
			"Coils",
			"Color",
			"CurrentLength",
			"Damping",
			"FreeLength",
			"LimitsEnabled",
			"MaxForce",
			"MaxLength",
			"MinLength",
			"Radius",
			"Stand",
			"Stiffness",
			"Thickness",
			"Visible",
		},
		methods = []string{"GetDebugAppliedForce", "GetDebugAppliedTorque"},
	)
}
