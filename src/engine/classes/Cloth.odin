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
CLOTH_MAX_SEGMENTS :: 64
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
	using object:                          Object,
	touched:                               ^signals.Signal,
	attachment, attachment1:               ^Object,
	size:                                  datatypes.Vector2,
	color:                                 datatypes.Color3,
	material_variant:                      string,
	enabled, can_collide, self_collision:  bool,
	custom_pins:                           bool,
	cloth_type:                            enums.ClothType,
	segments_x, segments_y:                int,
	render_segments_x, render_segments_y:  int,
	solver_iterations, fold_count:         int,
	mass, damping:                         f32,
	fold_depth, gather_ratio:              f32,
	fold_stiffness, bend_stiffness:         f32,
	stretch_stiffness, shear_stiffness:     f32,
	force, impulse:                        [3]f32,
	config_revision:                       u64,

	grid:                                  [2]int,
	particles:                             []Cloth_Particle,
	rest, previous:                        [][3]f32,
	links:                                 [dynamic]Cloth_Link,
	pin_attachments:                       []^Object,
	pin_offsets, pin_targets, pin_starts:  [][3]f32,
	pin_weights, active_weights, pin_links: []f32,
	pinned:                                []bool,
	self_heads, self_next:                 []int,
	self_cells:                            [][3]int,
	self_positions:                        [][3]f32,
	sleep_frames:                          int,
	sleep_acceleration, sleep_wind:        [3]f32,

	simulation_origin:                     datatypes.Vector3,
	initialized:                           bool,
	pin_count:                             int,
	width:                                 f32,
	pose_source:                           Cloth_Pose_Source,
	pose_anchors:                          [2]datatypes.CFrame,
	rest_anchor:                           datatypes.CFrame,
	revision:                              u64,
	snapshot_start, snapshot_target:       [][3]f32,
	snapshot_tick:                         u32,
	snapshot_config:                       u64,
	snapshot_elapsed, snapshot_duration:   f32,
	snapshot_received:                     bool,

	render_grid:                           [2]int,
	topology_revision:                     u64,
	surface_vertices, decal_vertices:      [][8]f32,
	surface_normals:                       [][3]f32,
	surface_indices, surface_back_indices: []u32,
	surface_revision:                      u64,
	mesh_revision, mesh_topology_revision: u64,
	mesh:                                  ^kineffi.KineFilamentMesh,
	mesh_context:                          ^kineffi.KineFilamentContext,
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
	cloth.segments_x, cloth.segments_y = CLOTH_SEGMENTS, CLOTH_SEGMENTS
	cloth.solver_iterations = 8
	cloth.stretch_stiffness, cloth.shear_stiffness = 1, 1
	cloth.fold_stiffness, cloth.bend_stiffness = 0.6, 0.15
	Cloth_Ensure_Grid(cloth)
	return &cloth.object
}

cloth_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	cloth := cast(^Cloth)object
	if cloth.mesh != nil {
		kineffi.Kine_Filament_DestroyMesh(cloth.mesh_context, cloth.mesh)
	}
	cloth_free_grid(cloth)
	cloth_free_render_grid(cloth)
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
		changed := false
		for pin, i in cloth.pin_attachments {
			if pin != attachment {continue}
			cloth.pin_attachments[i] = nil
			cloth.pinned[i] = false
			cloth.active_weights[i] = 0
			changed = true
		}
		if cloth.attachment == attachment {
			cloth.attachment = nil
			changed = true
		}
		if cloth.attachment1 == attachment {
			cloth.attachment1 = nil
			changed = true
		}
		if changed {
			cloth.sleep_frames = 0
			cloth.config_revision += 1
		}
	}
}

cloth_set_attachment :: proc(cloth: ^Cloth, value: ^Object, slot: int) {
	reference := &cloth.attachment if slot == 0 else &cloth.attachment1
	if reference^ == value {return}
	reference^ = value
	if !cloth.custom_pins {
		cloth.initialized = false
		cloth.impulse = {}
	}
}

cloth_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^Cloth)source, cast(^Cloth)destination
	dst.attachment, dst.attachment1 = src.attachment, src.attachment1
	dst.custom_pins = src.custom_pins
	dst.segments_x, dst.segments_y = src.segments_x, src.segments_y
	dst.render_segments_x, dst.render_segments_y = src.render_segments_x, src.render_segments_y
	dst.cloth_type, dst.self_collision = src.cloth_type, src.self_collision
	dst.solver_iterations = src.solver_iterations
	dst.stretch_stiffness, dst.shear_stiffness = src.stretch_stiffness, src.shear_stiffness
	Cloth_Ensure_Grid(dst)
	copy(dst.pin_attachments, src.pin_attachments)
	copy(dst.pin_offsets, src.pin_offsets)
	copy(dst.pin_weights, src.pin_weights)
	dst.fold_count, dst.fold_depth = src.fold_count, src.fold_depth
	dst.gather_ratio, dst.fold_stiffness, dst.bend_stiffness = src.gather_ratio, src.fold_stiffness, src.bend_stiffness
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
	if cloth.custom_pins {
		if cloth.initialized {return cloth.pose_anchors, cloth.pin_count}
		if cloth.cloth_type == .Curtain {
			first, left := cloth_anchor_frame(cloth.pin_attachments[0], workspace)
			last, right := cloth_anchor_frame(cloth.pin_attachments[cloth.segments_x], workspace)
			if left && right {return {first, last}, 2}
		}
		for pin in cloth.pin_attachments {if frame, valid := cloth_anchor_frame(pin, workspace); valid {return {frame, {}}, 1}}
		return cloth.pose_anchors, 0
	}
	first, valid := cloth_anchor_frame(cloth.attachment, workspace)
	if !valid {
		if second, ok := cloth_anchor_frame(cloth.attachment1, workspace); ok {return {second, {}}, 1}
		return {datatypes.CFrame_Identity, {}}, 0
	}
	anchors[0] = first
	second := cloth.attachment1
	if second == nil && cloth.attachment != nil {
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
	if object == nil || object.destroyed || !Is_A_Class(object, &Attachment_Class) {return {}, false}
	attachment := cast(^Attachment)object
	if workspace == nil || !Is_Descendant_Of(object, workspace) {return {}, false}
	frame := Attachment_World_Frame(attachment)
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
	Cloth_Ensure_Grid(cloth)
	if cloth.initialized && cloth.pose_source == .Replication {return true}
	anchors, pin_count := Cloth_Anchors(cloth, workspace)
	if !cloth.initialized && pin_count == 0 && !cloth.custom_pins && cloth.cloth_type == .Flat {return false}
	if !cloth.initialized ||
	   (cloth.pose_source == .Preview && !cloth.custom_pins && cloth.pose_anchors != anchors) {
		Cloth_Initialize(cloth, anchors, pin_count, workspace)
	}
	if cloth.pose_source == .Preview {
		Cloth_Pin_Targets(cloth, workspace, anchors, pin_count)
		for &particle, i in cloth.particles {
			if cloth.active_weights[i] == 1 && particle.position != cloth.pin_targets[i] {
				particle.position = cloth.pin_targets[i]
				cloth.revision += 1
			}
		}
	}
	return true
}

Cloth_Initialize :: proc(cloth: ^Cloth, anchors: [2]datatypes.CFrame, pin_count: int, workspace: ^Object) {
	Cloth_Ensure_Grid(cloth)
	anchor := anchors[0]
	if pin_count == 0 {anchor = datatypes.CFrame_Identity}
	cloth.rest_anchor = anchor
	cloth.simulation_origin = {}
	if max(abs(anchor.x), abs(anchor.y), abs(anchor.z)) > 4096 {cloth.simulation_origin = {anchor.x, anchor.y, anchor.z}}
	start := Cloth_Local_Position(cloth, anchor)
	right := datatypes.CFrame_RightVector(anchor)
	up := datatypes.CFrame_UpVector(anchor)
	width := [3]f32{f32(right.x), f32(right.y), f32(right.z)} * cloth.size.X
	span := width
	down := -[3]f32{f32(up.x), f32(up.y), f32(up.z)}
	cloth.width = Cloth_Gathered_Width(cloth)
	span *= cloth.width / cloth.size.X
	if pin_count == 2 && cloth.cloth_type == .Flag {
		delta := Cloth_Local_Position(cloth, anchors[1]) - start
		if linalg.dot(delta, delta) > CLOTH_MIN_SPAN * CLOTH_MIN_SPAN {
			down = linalg.normalize(delta)
			projection := span - down * linalg.dot(span, down)
			if linalg.dot(projection, projection) < 0.000001 {
				projection = linalg.cross(down, [3]f32{0, 0, 1})
				if linalg.dot(projection, projection) < 0.000001 {projection = {1, 0, 0}}
			}
			span = linalg.normalize(projection) * cloth.width
		}
	} else if pin_count == 2 {
		span = Cloth_Local_Position(cloth, anchors[1]) - start
		cloth.width = Cloth_Width(cloth, span)
		if linalg.dot(span, span) > CLOTH_MIN_SPAN * CLOTH_MIN_SPAN {
			axis := span / cloth.width
			gravity := [3]f32{0, -1, 0}
			down = gravity - axis * linalg.dot(gravity, axis)
			if linalg.dot(down, down) < 0.000001 {
				side := [3]f32{f32(right.x), f32(right.y), f32(right.z)}
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
	} else if cloth.cloth_type == .Flat || cloth.cloth_type == .Custom {
		start -= span * 0.5
	}
	sag_direction := down
	if cloth.cloth_type == .Hammock {down = linalg.normalize(linalg.cross(span, sag_direction))}
	normal := linalg.normalize(linalg.cross(span, down))
	stride := cloth.segments_x + 1
	for &particle, i in cloth.particles {
		u := f32(i % stride) / f32(cloth.segments_x)
		v := f32(i / stride) / f32(cloth.segments_y)
		position := start + span * u + down * (v * cloth.size.Y) + sag_direction * Cloth_Sag(cloth, u)
		particle = {position + normal * Cloth_Fold_Offset(cloth, i % stride), {}}
	}
	if cloth.custom_pins {
		for pin, i in cloth.pin_attachments {
			frame, valid := cloth_anchor_frame(pin, workspace)
			if !valid {continue}
			offset := Cloth_Pin_Position(cloth, frame, i) - cloth.particles[i].position
			for &particle in cloth.particles {particle.position += offset}
			break
		}
	}
	for particle, i in cloth.particles {cloth.rest[i] = particle.position}
	Cloth_Build_Links(cloth)
	Cloth_Pin_Targets(cloth, workspace, anchors, pin_count)
	for &particle, i in cloth.particles {
		if cloth.pinned[i] {particle.position = cloth.pin_targets[i]}
	}
	cloth.sleep_frames = 0
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
	if slot, property, ok := Cloth_Pin_Property(key); ok && slot < len(cloth.particles) {
		switch property {
		case .Attachment: Push_Object(L, cloth.pin_attachments[slot])
		case .Offset:
			p := cloth.pin_offsets[slot]
			datatypes.Push_Vector3(L, {f64(p.x), f64(p.y), f64(p.z)})
		case .Weight: vm.PushNumber(L, f64(cloth.pin_weights[slot]))
		}
		return true
	}
	switch key {
	case "ClothType": _ = enums.Push_Item_By_Value(L, enum_registry, "ClothType", i64(cloth.cloth_type))
	case "SegmentsX": vm.PushNumber(L, f64(cloth.segments_x))
	case "SegmentsY": vm.PushNumber(L, f64(cloth.segments_y))
	case "RenderSegmentsX": vm.PushNumber(L, f64(cloth.render_segments_x))
	case "RenderSegmentsY": vm.PushNumber(L, f64(cloth.render_segments_y))
	case "SolverIterations": vm.PushNumber(L, f64(cloth.solver_iterations))
	case "SelfCollision": vm.PushBoolean(L, cloth.self_collision)
	case "StretchStiffness": vm.PushNumber(L, f64(cloth.stretch_stiffness))
	case "ShearStiffness": vm.PushNumber(L, f64(cloth.shear_stiffness))
	case "CustomPins": vm.PushBoolean(L, cloth.custom_pins)
	case "FoldCount": vm.PushNumber(L, f64(cloth.fold_count))
	case "FoldDepth": vm.PushNumber(L, f64(cloth.fold_depth))
	case "GatherRatio": vm.PushNumber(L, f64(cloth.gather_ratio))
	case "FoldStiffness": vm.PushNumber(L, f64(cloth.fold_stiffness))
	case "BendStiffness": vm.PushNumber(L, f64(cloth.bend_stiffness))
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
		datatypes.Push_Vector3(L, {f64(cloth.force.x), f64(cloth.force.y), f64(cloth.force.z)})
	case "ApplyImpulse", "PinVertex", "PinPoint", "PinRegion", "UnpinVertex", "UnpinPoint", "SetPinWeight", "GetPinWeight", "ResetSimulation", "ClearPins", "GetPins", "GetVertexCount", "GetVertexPosition":
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
	if slot, property, ok := Cloth_Pin_Property(key); ok && slot < len(cloth.particles) {
		switch property {
		case .Attachment:
			value := object_from_argument(L, index)
			if !vm.IsNil(L, index) && (!Is_A_Class(value, &Attachment_Class) || value.destroyed) {
				_ = vm.RaiseError(L, "Cloth pin must be an Attachment or nil")
				return true
			}
			cloth.pin_attachments[slot] = value
		case .Offset:
			p := datatypes.Arg_Vector3(L, index)
			if !cloth_finite_vector(p) || max(abs(p.x), abs(p.y), abs(p.z)) > 4096 {
				_ = vm.RaiseError(L, "Invalid cloth pin offset")
				return true
			}
			cloth.pin_offsets[slot] = {f32(p.x), f32(p.y), f32(p.z)}
		case .Weight:
			weight := vm.ArgNumber(L, index)
			if !(weight >= 0 && weight <= 1) {
				_ = vm.RaiseError(L, "Cloth pin weight must be between zero and one")
				return true
			}
			cloth.pin_weights[slot] = f32(weight)
		}
		cloth.sleep_frames = 0
		cloth.config_revision += 1
		return true
	}
	switch key {
	case "ClothType":
		item := enums.Arg_Item(L, index, enum_registry, "ClothType")
		if item != nil {Cloth_Set_Type(cloth, enums.ClothType(item.value))}
	case "SegmentsX", "SegmentsY", "RenderSegmentsX", "RenderSegmentsY", "SolverIterations":
		value := vm.ArgNumber(L, index)
		limit, minimum := f64(CLOTH_MAX_SEGMENTS), f64(1)
		switch key {
		case "RenderSegmentsX", "RenderSegmentsY": minimum = 0; limit *= 2
		case "SolverIterations": limit = 32
		}
		if !(value >= minimum && value <= limit && value == math.floor(value)) {
			_ = vm.RaiseError(L, "Cloth property is outside its supported integer range")
			return true
		}
		switch key {
		case "SegmentsX": cloth.segments_x = int(value)
		case "SegmentsY": cloth.segments_y = int(value)
		case "RenderSegmentsX": cloth.render_segments_x = int(value)
		case "RenderSegmentsY": cloth.render_segments_y = int(value)
		case "SolverIterations": cloth.solver_iterations = int(value)
		}
		Cloth_Ensure_Grid(cloth)
	case "SelfCollision": cloth.self_collision = vm.ArgBoolean(L, index)
	case "CustomPins":
		custom := vm.ArgBoolean(L, index)
		if cloth.custom_pins && !custom {cloth.initialized = false}
		cloth.custom_pins = custom
	case "FoldCount", "FoldDepth", "GatherRatio", "FoldStiffness", "BendStiffness", "StretchStiffness", "ShearStiffness":
		value := f32(vm.ArgNumber(L, index))
		if math.is_nan(value) || math.is_inf(value) || value < 0 ||
		   (key == "FoldCount" && (value > 32 || value != math.floor(value))) ||
		   (key == "FoldDepth" && value > 1024) ||
		   (key == "GatherRatio" && value > 1) ||
		   ((key == "FoldStiffness" || key == "BendStiffness" || key == "StretchStiffness" || key == "ShearStiffness") && value > 1) {
			_ = vm.RaiseError(L, "Invalid cloth fold configuration")
			return true
		}
		switch key {
		case "FoldCount": cloth.fold_count = int(value); cloth.initialized = false
		case "FoldDepth": cloth.fold_depth = value; cloth.initialized = false
		case "GatherRatio": cloth.gather_ratio = value; cloth.initialized = false
		case "FoldStiffness": cloth.fold_stiffness = value
		case "BendStiffness": cloth.bend_stiffness = value
		case "StretchStiffness": cloth.stretch_stiffness = value
		case "ShearStiffness": cloth.shear_stiffness = value
		}
	case "Attachment0", "Attachment1":
		value := object_from_argument(L, index)
		if !vm.IsNil(L, index) && (!Is_A_Class(value, &Attachment_Class) || value.destroyed) {
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
		if !cloth_finite_vector(force) || max(abs(force.x), abs(force.y), abs(force.z)) > f64(max(f32)) {
			_ = vm.RaiseError(L, "Cloth.Force must be finite")
			return true
		}
		cloth.force = {f32(force.x), f32(force.y), f32(force.z)}
	case:
		return false
	}
	cloth.sleep_frames = 0
	cloth.config_revision += 1
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
	cloth := cast(^Cloth)object
	if method != "ApplyImpulse" {return cloth_pin_namecall(L, cloth, datatypes_registry, method)}
	impulse := datatypes.Arg_Vector3(L, 2)
	total := cloth.impulse + [3]f32{f32(impulse.x), f32(impulse.y), f32(impulse.z)}
	if !cloth_finite_vector({f64(total.x), f64(total.y), f64(total.z)}) {
		return vm.RaiseError(L, "Cloth impulse must be finite"), true
	}
	if cloth.enabled {cloth.impulse = total}
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
			"ClothType", "SegmentsX", "SegmentsY", "RenderSegmentsX", "RenderSegmentsY",
			"SolverIterations", "SelfCollision", "StretchStiffness", "ShearStiffness",
			"CustomPins", "FoldCount", "FoldDepth", "GatherRatio", "FoldStiffness", "BendStiffness",
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
		methods = []string{"ApplyImpulse", "PinVertex", "PinPoint", "PinRegion", "UnpinVertex", "UnpinPoint", "SetPinWeight", "GetPinWeight", "ResetSimulation", "ClearPins", "GetPins", "GetVertexCount", "GetVertexPosition"},
	)
}


Cloth_Local_Position :: proc(cloth: ^Cloth, frame: datatypes.CFrame) -> [3]f32 {
	origin := cloth.simulation_origin
	return {f32(frame.x - origin.x), f32(frame.y - origin.y), f32(frame.z - origin.z)}
}

Cloth_World_Pin :: proc(cloth: ^Cloth) -> datatypes.Vector3 {
	p := cloth.particles[cloth.segments_x / 2].position
	o := cloth.simulation_origin
	return {o.x + f64(p.x), o.y + f64(p.y), o.z + f64(p.z)}
}
