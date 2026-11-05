package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import "core:math"

handles_valid_adornee :: proc(object: ^Object, allow_attachment := false) -> bool {
	return(
		object != nil &&
		!object.destroyed &&
		(Is_A_Class(object, &Part_Class) ||
				Is_A_Class(object, &Model_Class) ||
				Is_A_Class(object, &SoftBody_Class) ||
				(allow_attachment && Is_A_Class(object, &Attachment_Class))) \
	)
}

handles_forget_softbody :: proc(object: ^Object) {
	handles_forget_adornee(object)
	if descriptor := Find_Class(object.signal_registry, "ArcHandles"); descriptor != nil {
		for instance in descriptor.instances {
			handles := cast(^ArcHandles)instance
			if handles.Adornee == object {
				handles.Adornee = nil
				handles.dragging = false
			}
		}
	}
}

Handles_Apply_SoftBody_Axis :: proc(
	body: ^SoftBody,
	axis: i32,
	delta: f32,
	style: enums.HandlesStyle,
	centered := false,
) {
	if body == nil ||
	   body.destroyed ||
	   delta == 0 ||
	   math.is_nan(delta) ||
	   math.is_inf(delta) {return}
	component := handles_axis_component(axis)
	if component < 0 {return}
	frame := SoftBody_Current_CFrame(body)
	local_axis := handles_axis_vector(axis)
	switch style {
	case .Movement:
		offset := datatypes.Vec3_Multiply(local_axis, delta)
		frame = datatypes.CFrame_Mul_CFrame(frame, datatypes.CFrame_New_Position(offset))
	case .Rotation:
		rotation := datatypes.CFrame_FromAxisAngle(local_axis, delta)
		frame = datatypes.CFrame_Mul_CFrame(frame, rotation)
	case .Resize:
		if !handles_resize_softbody(body, component, delta, centered, &frame) {return}
	}
	body.cframe = frame
	body.pose_dirty = true
}

handles_softbody_bounds :: proc(positions: []kineffi.JPH_Vec3) -> (low, high: datatypes.Vector3) {
	first := positions[0]
	low, high = {first.x, first.y, first.z}, {first.x, first.y, first.z}
	for position in positions[1:] {
		point := datatypes.Vector3{position.x, position.y, position.z}
		low = datatypes.Vec3_Min(low, point)
		high = datatypes.Vec3_Max(high, point)
	}
	return
}

handles_resize_softbody :: proc(
	body: ^SoftBody,
	component: int,
	delta: f32,
	centered: bool,
	frame: ^datatypes.CFrame,
) -> bool {
	if len(body.rest_positions) == 0 {return false}
	low, high := handles_softbody_bounds(body.rest_positions[:])
	pending_scale := datatypes.Vec3_Divide_Vector(body.scale, body.geometry_scale)
	low, high =
		datatypes.Vec3_Multiply_Vector(low, pending_scale),
		datatypes.Vec3_Multiply_Vector(high, pending_scale)
	extent := handles_vector_component(datatypes.Vec3_Subtract(high, low), component)
	if extent <= 1e-4 {return false}
	old_scale := handles_vector_component(body.scale, component)
	new_scale := clamp(
		old_scale * max(0.05, extent + delta * (centered ? 2 : 1)) / extent,
		0.001,
		1000,
	)
	if old_scale == new_scale {return false}

	live_low, live_high := low, high
	if body.system != nil && !body.mesh_dirty {
		live_low, live_high = handles_softbody_bounds(body.positions)
	}
	rest_center := datatypes.Vec3_Multiply(datatypes.Vec3_Add(low, high), 0.5)
	ratio := new_scale / old_scale
	handles_vector_set_component(
		&rest_center,
		component,
		handles_vector_component(rest_center, component) * ratio,
	)
	live_center := datatypes.Vec3_Multiply(datatypes.Vec3_Add(live_low, live_high), 0.5)
	shift := datatypes.Vec3_Subtract(live_center, rest_center)
	if !centered {
		live_extent := handles_vector_component(
			datatypes.Vec3_Subtract(live_high, live_low),
			component,
		)
		anchor_shift := (extent * ratio - live_extent) * 0.5
		handles_vector_set_component(
			&shift,
			component,
			handles_vector_component(shift, component) + anchor_shift,
		)
	}
	frame^ = datatypes.CFrame_Mul_CFrame(frame^, datatypes.CFrame_New_Position(shift))
	handles_vector_set_component(&body.scale, component, new_scale)
	body.mesh_dirty = true
	return true
}
