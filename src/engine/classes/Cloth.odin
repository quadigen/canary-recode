package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:math"
import "core:math/linalg"
import "core:strings"

Cloth_Class := Class_Info {
	name   = "Cloth",
	parent = &Instance_Class,
}

CLOTH_SEGMENTS :: 10
CLOTH_STRIDE :: CLOTH_SEGMENTS + 1
CLOTH_VERTEX_COUNT :: CLOTH_STRIDE * CLOTH_STRIDE
CLOTH_PIN :: CLOTH_SEGMENTS / 2
CLOTH_MIN_SPAN :: f32(0.001)

Cloth_Pose_Source :: enum {
	Preview,
	Simulation,
	Replication,
}

Cloth_Particle :: struct {
	position, velocity: [3]f32,
}

Cloth :: struct {
	using object:            Object,
	touched:                 ^signals.Signal,
	attachment, attachment1: ^Object,
	size:                    datatypes.Vector2,
	color:                   datatypes.Color3,
	material_variant:        string,
	enabled, can_collide:    bool,
	mass, damping:           f32,
	force, impulse:          [3]f32,
	particles:               [CLOTH_VERTEX_COUNT]Cloth_Particle,
	initialized:             bool,
	pin_count:               int,
	width:                   f32,
	pose_source:             Cloth_Pose_Source,
	pose_anchors:            [2]datatypes.CFrame,
	revision, mesh_revision: u64,
	mesh:                    ^kineffi.KineFilamentMesh,
	mesh_context:            ^kineffi.KineFilamentContext,
}

cloth_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	cloth := new(Cloth)
	cloth.object = Object_Init(&Cloth_Class, "Cloth")
	cloth.size = {6, 4}
	cloth.color = {0.85, 0.85, 0.85}
	cloth.enabled = true
	cloth.can_collide = true
	cloth.mass = 1
	cloth.damping = 2
	return &cloth.object
}

cloth_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	cloth := cast(^Cloth)object
	if cloth.mesh != nil {
		kineffi.Kine_Filament_DestroyMesh(cloth.mesh_context, cloth.mesh)
	}
	delete(cloth.material_variant)
	signals.Destroy(cloth.touched)
	Object_Destroy(object)
	free(cloth)
}

Cloth_Forget_Attachment :: proc(attachment: ^Object) {
	descriptor := Find_Class(attachment.signal_registry, "Cloth")
	if descriptor == nil {return}
	for object in descriptor.instances {
		cloth := cast(^Cloth)object
		if cloth.attachment == attachment {
			cloth.attachment = nil
			cloth.initialized = false
			cloth.impulse = {}
		}
		if cloth.attachment1 == attachment {
			cloth.attachment1 = nil
			cloth.initialized = false
			cloth.impulse = {}
		}
	}
}

cloth_set_attachment :: proc(cloth: ^Cloth, value: ^Object, slot: int) {
	if slot == 0 {
		if cloth.attachment != value {
			cloth.attachment = value
			cloth.initialized = false
			cloth.impulse = {}
		}
		return
	}
	if cloth.attachment1 != value {
		cloth.attachment1 = value
		cloth.initialized = false
		cloth.impulse = {}
	}
}

Cloth_Pinned :: proc(pin_count, index: int) -> bool {
	if pin_count == 2 {return index == 0 || index == CLOTH_SEGMENTS}
	return index == CLOTH_PIN
}

cloth_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^Cloth)source, cast(^Cloth)destination
	dst.attachment, dst.attachment1 = src.attachment, src.attachment1
	dst.size, dst.color = src.size, src.color
	dst.material_variant = strings.clone(src.material_variant)
	dst.enabled, dst.can_collide = src.enabled, src.can_collide
	dst.mass, dst.damping, dst.force = src.mass, src.damping, src.force
}

Cloth_Anchors :: proc(
	cloth: ^Cloth,
	workspace: ^Object,
) -> (
	anchors: [2]datatypes.CFrame,
	count: int,
) {
	first, valid := cloth_anchor_frame(cloth.attachment, workspace)
	if !valid {return {}, 0}
	anchors[0] = first
	second := cloth.attachment1
	if second == nil {
		// Older curtains often only assigned one of the two points on their rail.
		// Leave the second point to the author if several siblings could fit.
		for sibling in cloth.attachment.parent.children {
			if sibling == nil ||
			   sibling == cloth.attachment ||
			   sibling.destroyed ||
			   !Is_A_Class(sibling, &Attachment_Class) {continue}
			if second != nil {return anchors, 1}
			second = sibling
		}
	}
	frame, second_valid := cloth_anchor_frame(second, workspace)
	if !second_valid {return anchors, 1}
	anchors[1] = frame
	return anchors, 2
}

cloth_anchor_frame :: proc(object, workspace: ^Object) -> (datatypes.CFrame, bool) {
	if object == nil || object.destroyed {return {}, false}
	attachment := cast(^Attachment)object
	parent := attachment.parent
	if !Is_A_Class(parent, &Part_Class) || !Is_Descendant_Of(parent, workspace) {return {}, false}
	part := cast(^Part)parent
	frame := datatypes.CFrame_Mul_CFrame(part.cframe, Attachment_Local_Frame(attachment))
	if !cloth_finite_vector(datatypes.CFrame_Position(frame)) ||
	   !cloth_finite_vector(datatypes.CFrame_RightVector(frame)) ||
	   !cloth_finite_vector(datatypes.CFrame_UpVector(frame)) {return {}, false}
	return frame, true
}

Cloth_Width :: proc(cloth: ^Cloth, span: [3]f32) -> f32 {
	distance := linalg.length(span)
	return distance if distance > CLOTH_MIN_SPAN else cloth.size.X
}

Cloth_Prepare_Surface :: proc(cloth: ^Cloth, workspace: ^Object) -> bool {
	if !cloth.enabled {return false}
	anchors, pin_count := Cloth_Anchors(cloth, workspace)
	if pin_count == 0 {
		cloth.initialized = false
		return false
	}
	if cloth.initialized && cloth.pose_source == .Replication {return true}
	if !cloth.initialized ||
	   cloth.pin_count != pin_count ||
	   (cloth.pose_source == .Preview && cloth.pose_anchors != anchors) {
		Cloth_Initialize(cloth, anchors, pin_count)
	}
	return true
}

Cloth_Initialize :: proc(cloth: ^Cloth, anchors: [2]datatypes.CFrame, pin_count: int) {
	anchor := anchors[0]
	start := [3]f32{anchor.x, anchor.y, anchor.z}
	right := datatypes.CFrame_RightVector(anchor)
	up := datatypes.CFrame_UpVector(anchor)
	width := [3]f32{right.x, right.y, right.z} * cloth.size.X
	span := width
	down := -[3]f32{up.x, up.y, up.z}
	cloth.width = cloth.size.X
	if pin_count == 2 {
		span = [3]f32{anchors[1].x, anchors[1].y, anchors[1].z} - start
		cloth.width = Cloth_Width(cloth, span)
		if linalg.dot(span, span) > CLOTH_MIN_SPAN * CLOTH_MIN_SPAN {
			axis := span / cloth.width
			gravity := [3]f32{0, -1, 0}
			down = gravity - axis * linalg.dot(gravity, axis)
			if linalg.dot(down, down) < 0.000001 {
				side := [3]f32{right.x, right.y, right.z}
				down = side - axis * linalg.dot(side, axis)
				if linalg.dot(down, down) < 0.000001 {
					down = linalg.cross(axis, [3]f32{0, 0, 1})
				}
			}
			down = linalg.normalize(down)
		} else {
			// Give coincident corners a folded surface for the solver to settle.
			span = width
			start -= span * 0.5
		}
	} else {
		start -= span * 0.5
	}
	for &particle, i in cloth.particles {
		x := f32(i % CLOTH_STRIDE) / CLOTH_SEGMENTS
		y := f32(i / CLOTH_STRIDE) / CLOTH_SEGMENTS * cloth.size.Y
		particle = Cloth_Particle {
			position = start + span * x + down * y,
		}
	}
	if pin_count == 2 {
		cloth.particles[0].position = {anchor.x, anchor.y, anchor.z}
		second := anchors[1]
		cloth.particles[CLOTH_SEGMENTS].position = {second.x, second.y, second.z}
	}
	cloth.initialized = true
	cloth.pin_count = pin_count
	cloth.pose_source = .Preview
	cloth.pose_anchors = anchors
	cloth.revision += 1
}

cloth_finite_vector :: proc(value: datatypes.Vector3) -> bool {
	return(
		!math.is_nan(value.x) &&
		!math.is_inf(value.x) &&
		!math.is_nan(value.y) &&
		!math.is_inf(value.y) &&
		!math.is_nan(value.z) &&
		!math.is_inf(value.z) \
	)
}

deformable_touched_get :: proc(L: ^vm.State, object: ^Object, signal: ^^signals.Signal) -> bool {
	if signal^ == nil &&
	   object.signal_registry != nil &&
	   object.signal_registry.signal_registry != nil {
		signal^ = signals.Create(object.signal_registry.signal_registry)
	}
	if signal^ == nil {return false}
	signals.Push(L, signal^)
	return true
}

cloth_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatypes_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	cloth := cast(^Cloth)object
	switch key {
	case "Touched":
		return deformable_touched_get(L, object, &cloth.touched)
	case "Attachment0":
		Push_Object(L, cloth.attachment)
	case "Attachment1":
		Push_Object(L, cloth.attachment1)
	case "Size":
		datatypes.Push_Vector2(L, datatypes_registry, cloth.size)
	case "Color":
		datatypes.Push_Color3(L, datatypes_registry, cloth.color)
	case "MaterialVariant":
		vm.PushString(L, cloth.material_variant)
	case "Enabled":
		vm.PushBoolean(L, cloth.enabled)
	case "CanCollide":
		vm.PushBoolean(L, cloth.can_collide)
	case "Mass":
		vm.PushNumber(L, f64(cloth.mass))
	case "Damping":
		vm.PushNumber(L, f64(cloth.damping))
	case "Force":
		datatypes.Push_Vector3(L, {cloth.force.x, cloth.force.y, cloth.force.z})
	case "ApplyImpulse":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

cloth_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatypes_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	cloth := cast(^Cloth)object
	switch key {
	case "Attachment0", "Attachment1":
		value := object_from_argument(L, index)
		if !vm.IsNil(L, index) && !Is_A_Class(value, &Attachment_Class) {
			_ = vm.RaiseError(L, "Attachment0 and Attachment1 must be an Attachment or nil")
			return true
		}
		cloth_set_attachment(cloth, value, key == "Attachment1" ? 1 : 0)
	case "Size":
		size := datatypes.Arg_Vector2(L, index, datatypes_registry)
		if !(size.X >= 0.1 && size.X <= 1024 && size.Y >= 0.1 && size.Y <= 1024) {
			_ = vm.RaiseError(L, "Cloth.Size dimensions must be between 0.1 and 1024 studs")
			return true
		}
		if size != cloth.size {
			cloth.size = size
			cloth.initialized = false
		}
	case "Color":
		cloth.color = datatypes.Arg_Color3(L, index, datatypes_registry)
	case "MaterialVariant":
		variant := strings.clone(vm.ArgString(L, index))
		delete(cloth.material_variant)
		cloth.material_variant = variant
	case "Enabled":
		cloth.enabled = vm.ArgBoolean(L, index)
		if !cloth.enabled {
			cloth.initialized = false
			cloth.impulse = {}
		}
	case "CanCollide":
		cloth.can_collide = vm.ArgBoolean(L, index)
	case "Mass", "Damping":
		value := f32(vm.ArgNumber(L, index))
		if math.is_nan(value) ||
		   math.is_inf(value) ||
		   (key == "Mass" && value < 0.001) ||
		   (key == "Damping" && value < 0) {
			_ = vm.RaiseError(
				L,
				"Cloth.Mass must be at least 0.001 and Damping must be nonnegative",
			)
			return true
		}
		if key == "Mass" {cloth.mass = value} else {cloth.damping = value}
	case "Force":
		force := datatypes.Arg_Vector3(L, index)
		if !cloth_finite_vector(force) {
			_ = vm.RaiseError(L, "Cloth.Force must be finite")
			return true
		}
		cloth.force = {force.x, force.y, force.z}
	case:
		return false
	}
	return true
}

cloth_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatypes_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "ApplyImpulse" {return 0, false}
	cloth := cast(^Cloth)object
	impulse := datatypes.Arg_Vector3(L, 2)
	total := cloth.impulse + [3]f32{impulse.x, impulse.y, impulse.z}
	if !cloth_finite_vector({total.x, total.y, total.z}) {
		return vm.RaiseError(L, "Cloth impulse must be finite"), true
	}
	if cloth.enabled && cloth.attachment != nil {cloth.impulse = total}
	return 0, true
}

Register_Cloth :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Cloth_Class,
		cloth_construct,
		cloth_destroy,
		get = cloth_get,
		set = cloth_set,
		namecall = cloth_namecall,
		clone = cloth_clone,
		properties = []string {
			"Attachment0",
			"Attachment1",
			"Size",
			"Color",
			"MaterialVariant",
			"Enabled",
			"CanCollide",
			"Mass",
			"Damping",
			"Force",
		},
		events = []string{"Touched"},
		methods = []string{"ApplyImpulse"},
	)
}
