package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"
import "core:math/linalg"

BallSocketConstraint_Class := Class_Info {
	name   = "BallSocketConstraint",
	parent = &Constraint_Class,
}

PrismaticConstraint_Class := Class_Info {
	name   = "PrismaticConstraint",
	parent = &Constraint_Class,
}

RodConstraint_Class := Class_Info {
	name   = "RodConstraint",
	parent = &Constraint_Class,
}

PlaneConstraint_Class := Class_Info {
	name   = "PlaneConstraint",
	parent = &Constraint_Class,
}

UniversalConstraint_Class := Class_Info {
	name   = "UniversalConstraint",
	parent = &Constraint_Class,
}

CylindricalConstraint_Class := Class_Info {
	name   = "CylindricalConstraint",
	parent = &Constraint_Class,
}

Attachment_Joint_Classes := [?]^Class_Info {
	&PlaneConstraint_Class,
	&UniversalConstraint_Class,
	&CylindricalConstraint_Class,
	&BallSocketConstraint_Class,
	&PrismaticConstraint_Class,
	&RodConstraint_Class,
}

Is_Attachment_Joint :: proc(class: ^Class_Info) -> bool {
	for candidate in Attachment_Joint_Classes {
		if class == candidate {return true}
	}
	return false
}

Attachment_Joint :: struct {
	using constraint:                      Constraint,
	limits_enabled:                        bool,
	upper_angle:                           f32,
	lower_limit:                           f32,
	upper_limit:                           f32,
	length:                                f32,
	system:                                kineffi.JPH_PhysicsSystemRef,
	joint:                                 kineffi.JPH_ConstraintRef,
	frames:                                [2]Constraint_Frame,
	position_offset:                       f32,
	angular_limits_enabled:                bool,
	lower_angle, upper_twist, restitution: f32,
	radius:                                f32,
}

attachment_joint_construct :: proc(class: ^Class_Info) -> ^Object {
	joint := new(Attachment_Joint)
	joint.constraint = Constraint_Init()
	joint.object.class = class
	joint.name = class.name
	joint.active = false
	joint.upper_angle = 45
	joint.lower_limit = -5
	joint.upper_limit = 5
	joint.length = 1
	joint.lower_angle = -45
	joint.upper_twist = 45
	joint.radius = 0.1
	return &joint.object
}

BallSocketConstraint_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return attachment_joint_construct(&BallSocketConstraint_Class)
}

PrismaticConstraint_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return attachment_joint_construct(&PrismaticConstraint_Class)
}

RodConstraint_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return attachment_joint_construct(&RodConstraint_Class)
}

Attachment_Joint_release :: proc(joint: ^Attachment_Joint) {
	if joint.joint != nil {
		kineffi.JPH_PhysicsSystem_RemoveConstraint(joint.system, joint.joint)
		kineffi.JPH_Constraint_Destroy(joint.joint)
		joint.joint = nil
	}
	joint.system = nil
	joint.active = false
}

attachment_joint_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	joint := cast(^Attachment_Joint)object
	Attachment_Joint_release(joint)
	Object_Destroy(object)
	free(joint)
}

attachment_joint_clone :: proc(source, destination: ^Object) {
	Constraint_clone(source, destination)
	src := cast(^Attachment_Joint)source
	dst := cast(^Attachment_Joint)destination
	dst.active = false
	dst.limits_enabled = src.limits_enabled
	dst.upper_angle = src.upper_angle
	dst.lower_limit = src.lower_limit
	dst.upper_limit = src.upper_limit
	dst.length = src.length
	dst.angular_limits_enabled = src.angular_limits_enabled
	dst.lower_angle = src.lower_angle
	dst.upper_twist = src.upper_twist
	dst.restitution = src.restitution
	dst.radius = src.radius
}

attachment_joint_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	joint := cast(^Attachment_Joint)object
	switch object.class {
	case &BallSocketConstraint_Class:
		switch key {
		case "LimitsEnabled":
			vm.PushBoolean(L, joint.limits_enabled)
		case "UpperAngle":
			vm.PushNumber(L, f64(joint.upper_angle))
		case:
			return Constraint_get(L, object, datatype_registry, enum_registry, key)
		}
	case &PrismaticConstraint_Class:
		switch key {
		case "LimitsEnabled":
			vm.PushBoolean(L, joint.limits_enabled)
		case "LowerLimit":
			vm.PushNumber(L, f64(joint.lower_limit))
		case "UpperLimit":
			vm.PushNumber(L, f64(joint.upper_limit))
		case "CurrentPosition":
			position: f32
			if joint.joint != nil {
				position =
					kineffi.JPH_SliderConstraint_GetCurrentPosition(joint.joint) +
					joint.position_offset
			}
			vm.PushNumber(L, f64(position))
		case:
			return Constraint_get(L, object, datatype_registry, enum_registry, key)
		}
	case &PlaneConstraint_Class:
		return Constraint_get(L, object, datatype_registry, enum_registry, key)
	case &UniversalConstraint_Class:
		switch key {
		case "LimitsEnabled":
			vm.PushBoolean(L, joint.limits_enabled)
		case "MaxAngle":
			vm.PushNumber(L, f64(joint.upper_angle))
		case "Radius":
			vm.PushNumber(L, f64(joint.radius))
		case "Restitution":
			vm.PushNumber(L, f64(joint.restitution))
		case:
			return Constraint_get(L, object, datatype_registry, enum_registry, key)
		}
	case &CylindricalConstraint_Class:
		switch key {
		case "LimitsEnabled":
			vm.PushBoolean(L, joint.limits_enabled)
		case "LowerLimit":
			vm.PushNumber(L, f64(joint.lower_limit))
		case "UpperLimit":
			vm.PushNumber(L, f64(joint.upper_limit))
		case "AngularLimitsEnabled":
			vm.PushBoolean(L, joint.angular_limits_enabled)
		case "LowerAngle":
			vm.PushNumber(L, f64(joint.lower_angle))
		case "UpperAngle":
			vm.PushNumber(L, f64(joint.upper_twist))
		case:
			return Constraint_get(L, object, datatype_registry, enum_registry, key)
		}
	case &RodConstraint_Class:
		if key != "Length" {
			return Constraint_get(L, object, datatype_registry, enum_registry, key)
		}
		vm.PushNumber(L, f64(joint.length))
	}
	return true
}

attachment_joint_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	joint := cast(^Attachment_Joint)object
	switch key {
	case "Active", "CurrentPosition":
		return false
	case "LimitsEnabled":
		if object.class == &RodConstraint_Class {return false}
		enabled := vm.ArgBoolean(L, value_index)
		if joint.limits_enabled != enabled {
			joint.limits_enabled = enabled
			Attachment_Joint_release(joint)
		}
	case "AngularLimitsEnabled":
		if object.class != &CylindricalConstraint_Class {return false}
		joint.angular_limits_enabled = vm.ArgBoolean(L, value_index)
		Attachment_Joint_release(joint)
	case "MaxAngle",
	     "LowerAngle",
	     "Radius",
	     "Restitution",
	     "UpperAngle",
	     "LowerLimit",
	     "UpperLimit",
	     "Length":
		property: ^f32
		lower, upper := -f64(math.F32_MAX), f64(math.F32_MAX)
		switch key {
		case "MaxAngle":
			if object.class != &UniversalConstraint_Class {return false}
			property = &joint.upper_angle
			lower, upper = 0, 180
		case "Radius", "Restitution":
			if object.class != &UniversalConstraint_Class {return false}
			property = &joint.radius if key == "Radius" else &joint.restitution
			lower = 0
			if key == "Restitution" {upper = 1}
		case "LowerAngle":
			if object.class != &CylindricalConstraint_Class {return false}
			property = &joint.lower_angle
			lower, upper = -180, 180
		case "UpperAngle":
			if object.class == &CylindricalConstraint_Class {
				property = &joint.upper_twist
				lower, upper = -180, 180
			} else {
				if object.class != &BallSocketConstraint_Class {return false}
				property = &joint.upper_angle
				lower, upper = 0, 180
			}
		case "LowerLimit":
			if object.class != &PrismaticConstraint_Class &&
			   object.class != &CylindricalConstraint_Class {return false}
			property = &joint.lower_limit
		case "UpperLimit":
			if object.class != &PrismaticConstraint_Class &&
			   object.class != &CylindricalConstraint_Class {return false}
			property = &joint.upper_limit
		case "Length":
			if object.class != &RodConstraint_Class {return false}
			property = &joint.length
			lower = 0
		}
		value := vm.ArgNumber(L, value_index)
		if !(value >= lower && value <= upper) {
			_ = vm.RaiseError(L, "constraint property is out of range")
			return true
		}
		if property^ != f32(value) {
			property^ = f32(value)
			Attachment_Joint_release(joint)
		}
	case "Attachment0", "Attachment1":
		value := object_from_argument(L, value_index)
		if !vm.IsNil(L, value_index) &&
		   (value == nil || value.destroyed || !Is_A_Class(value, &Attachment_Class)) {
			return false
		}
		slot := &joint.attachment0 if key == "Attachment0" else &joint.attachment1
		if slot^ != value {
			slot^ = value
			Attachment_Joint_release(joint)
		}
	case "Enabled":
		joint.enabled = vm.ArgBoolean(L, value_index)
		if !joint.enabled {Attachment_Joint_release(joint)}
	case:
		return false
	}
	return true
}

attachment_joint_point :: proc(
	joint: ^Attachment_Joint,
	system: kineffi.JPH_PhysicsSystemRef,
	ids: [2]kineffi.JPH_BodyID,
	points: [2]kineffi.JPH_RVec3,
	axes, normals: [2]kineffi.JPH_Vec3,
) -> kineffi.JPH_ConstraintRef {
	settings: kineffi.JPH_SixDOFConstraintSettings
	kineffi.JPH_SixDOFConstraintSettings_Init(&settings)
	settings.space = .WorldSpace
	settings.position1, settings.position2 = points[0], points[1]
	settings.axisX1, settings.axisX2 = axes[0], axes[1]
	settings.axisY1, settings.axisY2 = normals[0], normals[1]
	kineffi.JPH_SixDOFConstraintSettings_MakeFixedAxis(&settings, .TranslationX)
	kineffi.JPH_SixDOFConstraintSettings_MakeFixedAxis(&settings, .TranslationY)
	kineffi.JPH_SixDOFConstraintSettings_MakeFixedAxis(&settings, .TranslationZ)
	if joint.object.class == &BallSocketConstraint_Class && joint.limits_enabled {
		angle := linalg.to_radians(joint.upper_angle)
		kineffi.JPH_SixDOFConstraintSettings_SetLimitedAxis(&settings, .RotationY, -angle, angle)
		kineffi.JPH_SixDOFConstraintSettings_SetLimitedAxis(&settings, .RotationZ, -angle, angle)
	}
	return kineffi.JPH_SixDOFConstraint_CreateFromIDs(system, &settings, ids[0], ids[1])
}

attachment_joint_slider :: proc(
	joint: ^Attachment_Joint,
	system: kineffi.JPH_PhysicsSystemRef,
	ids: [2]kineffi.JPH_BodyID,
	points: [2]kineffi.JPH_RVec3,
	axes, normals: [2]kineffi.JPH_Vec3,
) -> kineffi.JPH_ConstraintRef {
	settings: kineffi.JPH_SliderConstraintSettings
	kineffi.JPH_SliderConstraintSettings_Init(&settings)
	settings.space = .WorldSpace
	settings.point1, settings.point2 = points[0], points[1]
	settings.sliderAxis1, settings.sliderAxis2 = axes[0], axes[1]
	settings.normalAxis1, settings.normalAxis2 = normals[0], normals[1]
	if joint.limits_enabled {
		lower := f64(min(joint.lower_limit, joint.upper_limit))
		upper := f64(max(joint.lower_limit, joint.upper_limit))

		offset := (lower + upper) * 0.5
		settings.point1.x += offset * f64(axes[0].x)
		settings.point1.y += offset * f64(axes[0].y)
		settings.point1.z += offset * f64(axes[0].z)
		joint.position_offset = f32(offset)
	}
	handle := kineffi.JPH_SliderConstraint_CreateFromIDs(system, &settings, ids[0], ids[1])
	if handle != nil && joint.limits_enabled {

		half_range := f32(abs(f64(joint.upper_limit) - f64(joint.lower_limit)) * 0.5)
		kineffi.JPH_SliderConstraint_SetLimits(handle, -half_range, half_range)
	}
	return handle
}

attachment_joint_step :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
) {
	joint := cast(^Attachment_Joint)object
	defer {
		if !joint.active {Attachment_Joint_release(joint)}
	}
	joint.active = false
	if !joint.enabled || system == nil {return}

	attachments := [2]^Object{joint.attachment0, joint.attachment1}
	frames: [2]Constraint_Frame
	points: [2]kineffi.JPH_RVec3
	ids: [2]kineffi.JPH_BodyID
	use_axes :=
		object.class == &PrismaticConstraint_Class ||
		object.class == &PlaneConstraint_Class ||
		object.class == &UniversalConstraint_Class ||
		object.class == &CylindricalConstraint_Class ||
		(object.class == &BallSocketConstraint_Class && joint.limits_enabled)
	for attachment, i in attachments {
		id, local, world, ok := resolve_attachment(attachment, system, body_ids)
		if !ok ||
		   math.is_nan(world.x) ||
		   math.is_inf(world.x) ||
		   math.is_nan(world.y) ||
		   math.is_inf(world.y) ||
		   math.is_nan(world.z) ||
		   math.is_inf(world.z) {return}
		ids[i], points[i] = id, world
		frames[i] = {
			body     = id,
			position = local,
			axis     = {1, 0, 0},
			normal   = {0, 1, 0},
		}
		if use_axes {
			frames[i], ok = constraint_frame(attachment, id, local)
			if !ok {return}
		}
	}
	if ids[0] == ids[1] {return}

	bi := kineffi.JPH_PhysicsSystem_GetBodyInterface(system)
	dynamic0 := kineffi.JPH_BodyInterface_GetMotionType(bi, ids[0]) == .Dynamic
	dynamic1 := kineffi.JPH_BodyInterface_GetMotionType(bi, ids[1]) == .Dynamic
	if !dynamic0 && !dynamic1 {return}
	if joint.joint != nil && joint.system == system && joint.frames == frames {
		joint.active = true
		return
	}

	Attachment_Joint_release(joint)
	axes: [2]kineffi.JPH_Vec3 = {{1, 0, 0}, {1, 0, 0}}
	normals: [2]kineffi.JPH_Vec3 = {{0, 1, 0}, {0, 1, 0}}
	if use_axes {
		for frame, i in frames {
			rotation: kineffi.JPH_Quat
			kineffi.JPH_BodyInterface_GetRotation(bi, frame.body, &rotation)
			axes[i] = constraint_world_vector(rotation, frame.axis)
			normals[i] = constraint_world_vector(rotation, frame.normal)
		}
	}

	handle: kineffi.JPH_ConstraintRef
	switch object.class {
	case &BallSocketConstraint_Class:
		handle = attachment_joint_point(joint, system, ids, points, axes, normals)
	case &PrismaticConstraint_Class:
		joint.position_offset = 0
		handle = attachment_joint_slider(joint, system, ids, points, axes, normals)
	case &PlaneConstraint_Class, &UniversalConstraint_Class, &CylindricalConstraint_Class:
		settings: kineffi.JPH_SixDOFConstraintSettings
		kineffi.JPH_SixDOFConstraintSettings_Init(&settings)
		settings.space = .WorldSpace
		settings.position1, settings.position2 = points[0], points[1]
		settings.axisX1, settings.axisX2 = axes[0], axes[1]
		settings.axisY1, settings.axisY2 = normals[0], normals[1]
		for axis in 0 ..< 6 {kineffi.JPH_SixDOFConstraintSettings_MakeFreeAxis(&settings, kineffi.JPH_SixDOFAxis(axis))}
		switch object.class {
		case &PlaneConstraint_Class:
			kineffi.JPH_SixDOFConstraintSettings_MakeFixedAxis(&settings, .TranslationX)
		case &UniversalConstraint_Class:
			for axis in 0 ..< 3 {kineffi.JPH_SixDOFConstraintSettings_MakeFixedAxis(&settings, kineffi.JPH_SixDOFAxis(axis))}
			kineffi.JPH_SixDOFConstraintSettings_MakeFixedAxis(&settings, .RotationZ)
			if joint.limits_enabled {
				angle := linalg.to_radians(joint.upper_angle)
				kineffi.JPH_SixDOFConstraintSettings_SetLimitedAxis(
					&settings,
					.RotationX,
					-angle,
					angle,
				)
				kineffi.JPH_SixDOFConstraintSettings_SetLimitedAxis(
					&settings,
					.RotationY,
					-angle,
					angle,
				)
			}
		case &CylindricalConstraint_Class:
			fixed_axes := [4]kineffi.JPH_SixDOFAxis {
				.TranslationY,
				.TranslationZ,
				.RotationY,
				.RotationZ,
			}
			for axis in fixed_axes {
				kineffi.JPH_SixDOFConstraintSettings_MakeFixedAxis(&settings, axis)
			}
			if joint.limits_enabled {
				kineffi.JPH_SixDOFConstraintSettings_SetLimitedAxis(
					&settings,
					.TranslationX,
					min(joint.lower_limit, 0),
					max(joint.upper_limit, 0),
				)
			}
			if joint.angular_limits_enabled {
				kineffi.JPH_SixDOFConstraintSettings_SetLimitedAxis(
					&settings,
					.RotationX,
					linalg.to_radians(min(joint.lower_angle, 0)),
					linalg.to_radians(max(joint.upper_twist, 0)),
				)
			}
		}
		handle = kineffi.JPH_SixDOFConstraint_CreateFromIDs(system, &settings, ids[0], ids[1])
	case &RodConstraint_Class:
		if joint.length == 0 {
			handle = attachment_joint_point(joint, system, ids, points, axes, normals)
		} else {
			settings: kineffi.JPH_DistanceConstraintSettings
			kineffi.JPH_DistanceConstraintSettings_Init(&settings)
			settings.space = .WorldSpace
			settings.point1, settings.point2 = points[0], points[1]
			settings.minDistance, settings.maxDistance = joint.length, joint.length
			handle = kineffi.JPH_DistanceConstraint_CreateFromIDs(
				system,
				&settings,
				ids[0],
				ids[1],
			)
		}
	}
	if handle == nil {return}

	kineffi.JPH_Constraint_AddRef(handle)
	kineffi.JPH_PhysicsSystem_AddConstraint(system, handle)
	joint.system = system
	joint.joint = handle
	joint.frames = frames
	joint.active = true
	if dynamic0 {kineffi.JPH_BodyInterface_ActivateBody(bi, ids[0])}
	if dynamic1 {kineffi.JPH_BodyInterface_ActivateBody(bi, ids[1])}
}

BallSocketConstraint_step :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
	delta_time: f32,
) {
	attachment_joint_step(object, system, body_ids)
}

Register_BallSocketConstraint :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&BallSocketConstraint_Class,
		BallSocketConstraint_construct,
		attachment_joint_destroy,
		get = attachment_joint_get,
		set = attachment_joint_set,
		clone = attachment_joint_clone,
		properties = []string{"LimitsEnabled", "UpperAngle"},
	)
}

PrismaticConstraint_step :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
	delta_time: f32,
) {
	attachment_joint_step(object, system, body_ids)
}

Register_PrismaticConstraint :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&PrismaticConstraint_Class,
		PrismaticConstraint_construct,
		attachment_joint_destroy,
		get = attachment_joint_get,
		set = attachment_joint_set,
		clone = attachment_joint_clone,
		properties = []string{"LimitsEnabled", "LowerLimit", "UpperLimit", "CurrentPosition"},
	)
}

RodConstraint_step :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
	delta_time: f32,
) {
	attachment_joint_step(object, system, body_ids)
}

Register_RodConstraint :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&RodConstraint_Class,
		RodConstraint_construct,
		attachment_joint_destroy,
		get = attachment_joint_get,
		set = attachment_joint_set,
		clone = attachment_joint_clone,
		properties = []string{"Length"},
	)
}

PlaneConstraint_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return attachment_joint_construct(&PlaneConstraint_Class)
}
PlaneConstraint_step :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
	delta_time: f32,
) {
	attachment_joint_step(object, system, body_ids)
}
Register_PlaneConstraint :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&PlaneConstraint_Class,
		PlaneConstraint_construct,
		attachment_joint_destroy,
		get = attachment_joint_get,
		set = attachment_joint_set,
		clone = attachment_joint_clone,
		properties = []string{},
	)
}

UniversalConstraint_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return attachment_joint_construct(&UniversalConstraint_Class)
}
UniversalConstraint_step :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
	delta_time: f32,
) {
	attachment_joint_step(object, system, body_ids)
}
Register_UniversalConstraint :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UniversalConstraint_Class,
		UniversalConstraint_construct,
		attachment_joint_destroy,
		get = attachment_joint_get,
		set = attachment_joint_set,
		clone = attachment_joint_clone,
		properties = []string{"LimitsEnabled", "MaxAngle", "Radius", "Restitution"},
	)
}

CylindricalConstraint_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	return attachment_joint_construct(&CylindricalConstraint_Class)
}
CylindricalConstraint_step :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
	delta_time: f32,
) {
	attachment_joint_step(object, system, body_ids)
}
Register_CylindricalConstraint :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&CylindricalConstraint_Class,
		CylindricalConstraint_construct,
		attachment_joint_destroy,
		get = attachment_joint_get,
		set = attachment_joint_set,
		clone = attachment_joint_clone,
		properties = []string {
			"LimitsEnabled",
			"LowerLimit",
			"UpperLimit",
			"AngularLimitsEnabled",
			"LowerAngle",
			"UpperAngle",
		},
	)
}
