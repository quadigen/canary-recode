package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"
import "core:strings"

Cloth_Class := Class_Info {
	name   = "Cloth",
	parent = &Instance_Class,
}

CLOTH_SEGMENTS :: 10
CLOTH_STRIDE :: CLOTH_SEGMENTS + 1
CLOTH_VERTEX_COUNT :: CLOTH_STRIDE * CLOTH_STRIDE
CLOTH_PIN :: CLOTH_SEGMENTS / 2

Cloth_Particle :: struct {
	position, velocity: [3]f32,
}

Cloth :: struct {
	using object:            Object,
	attachment, attachment1: ^Object,
	size:                    datatypes.Vector2,
	color:                   datatypes.Color3,
	material_variant:        string,
	enabled, can_collide:    bool,
	mass, damping:           f32,
	force, impulse:          [3]f32,
	particles:               [CLOTH_VERTEX_COUNT]Cloth_Particle,
	initialized:             bool,
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

Cloth_Pin_Count :: proc(cloth: ^Cloth) -> int {
	if cloth.attachment1 != nil && !cloth.attachment1.destroyed {return 2}
	return 1
}

Cloth_Pin_Index :: proc(cloth: ^Cloth, slot: int) -> int {
	if cloth.attachment1 != nil && !cloth.attachment1.destroyed {
		return slot == 0 ? 0 : CLOTH_SEGMENTS
	}
	return CLOTH_PIN
}

Cloth_Pinned :: proc(cloth: ^Cloth, index: int) -> bool {
	if cloth.attachment1 != nil && !cloth.attachment1.destroyed {
		return index == 0 || index == CLOTH_SEGMENTS
	}
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

Cloth_Anchor :: proc(cloth: ^Cloth, workspace: ^Object) -> (datatypes.CFrame, bool) {
	return Cloth_Anchor_At(cloth, workspace, 0)
}

// The top center is pinned, or both top corners when Attachment1 is present.
Cloth_Anchor_At :: proc(
	cloth: ^Cloth,
	workspace: ^Object,
	slot: int,
) -> (datatypes.CFrame, bool) {
	attachment_object := slot == 0 ? cloth.attachment : cloth.attachment1
	if attachment_object == nil || attachment_object.destroyed {return {}, false}
	attachment := cast(^Attachment)attachment_object
	parent := attachment.parent
	if !Is_A_Class(parent, &Part_Class) || !Is_Descendant_Of(parent, workspace) {return {}, false}
	part := cast(^Part)parent
	rotation := datatypes.CFrame_FromOrientation(
		math.to_radians(attachment.orientation.x),
		math.to_radians(attachment.orientation.y),
		math.to_radians(attachment.orientation.z),
	)
	local := datatypes.CFrame_Add_Vector3(rotation, attachment.position)
	frame := datatypes.CFrame_Mul_CFrame(part.cframe, local)
	if !cloth_finite_vector(datatypes.CFrame_Position(frame)) ||
	   !cloth_finite_vector(datatypes.CFrame_RightVector(frame)) ||
	   !cloth_finite_vector(datatypes.CFrame_UpVector(frame)) {return {}, false}
	return frame, true
}

Cloth_Initialize :: proc(cloth: ^Cloth, anchor: datatypes.CFrame) {
	for &particle, i in cloth.particles {
		x := (f32(i % CLOTH_STRIDE) / CLOTH_SEGMENTS - 0.5) * cloth.size.X
		y := -f32(i / CLOTH_STRIDE) / CLOTH_SEGMENTS * cloth.size.Y
		point := datatypes.CFrame_PointToWorldSpace(anchor, {x, y, 0})
		particle = Cloth_Particle {
			position = {point.x, point.y, point.z},
		}
	}
	cloth.initialized = true
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

cloth_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatypes_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	cloth := cast(^Cloth)object
	switch key {
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
		methods = []string{"ApplyImpulse"},
	)
}
