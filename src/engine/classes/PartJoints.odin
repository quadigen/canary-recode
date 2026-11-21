package classes

import vm "../vm"

part_joint_world :: proc(object: ^Object) -> ^Object {
	for current := object; current != nil; current = current.parent {
		if Is_A(current, "Workspace") {return current}
	}
	return nil
}

part_joint_live :: proc(object, world: ^Object) -> bool {
	return object != nil && !object.destroyed && world != nil && part_joint_world(object) == world
}

part_joint_endpoint :: proc(attachment: ^Object) -> ^Object {
	if attachment == nil || attachment.destroyed {return nil}
	return attachment.parent
}

part_joint_namecall :: proc(L: ^vm.State, object: ^Object, method: string) -> (i32, bool) {
	registry := object.signal_registry
	if method == "GetJoints" || method == "GetNoCollisionConstraints" {
		vm.NewTable(L, 0)
		world := part_joint_world(object)
		if registry == nil || world == nil {return 1, true}
		index := 0
		for descriptor in registry.classes {
			if descriptor == nil {continue}
			is_no_collision := descriptor.info == &NoCollisionConstraint_Class
			if method == "GetNoCollisionConstraints" {
				if !is_no_collision {continue}
			} else if !Is_Class_A(descriptor.info, &Constraint_Class) {continue}
			for joint in descriptor.instances {
				if !part_joint_live(joint, world) ||
				   joint.lua_ref <= 0 ||
				   !Object_Is_Accessible(L, joint) {continue}
				a, b: ^Object
				if is_no_collision {
					c := cast(^NoCollisionConstraint)joint
					if !c.enabled {continue}
					a, b = c.part0, c.part1
				} else if joint.class == &WeldConstraint_Class {
					weld := cast(^WeldConstraint)joint
					if !weld.enabled {continue}
					a, b = weld.part0, weld.part1
				} else {
					c := cast(^Constraint)joint
					if !c.enabled {continue}
					a, b = part_joint_endpoint(c.attachment0), part_joint_endpoint(c.attachment1)
				}
				if a != object && b != object {continue}
				if a == b || !part_joint_live(a, world) || !part_joint_live(b, world) {continue}
				if !Is_A_Class(a, &Part_Class) || !Is_A_Class(b, &Part_Class) {continue}
				if !Object_Is_Accessible(L, a) || !Object_Is_Accessible(L, b) {continue}
				index += 1
				Push_Object(L, joint)
				vm.SetArrayValue(L, -2, index)
			}
		}
		return 1, true
	}

	grounded := method == "IsGrounded"
	if grounded && (cast(^Part)object).anchored {
		vm.PushBoolean(L, true)
		return 1, true
	}
	recursive := grounded || vm.ArgOptionalBoolean(L, 2, false)
	world := part_joint_world(object)
	if !grounded {vm.NewTable(L, 0)}
	if registry != nil && world != nil {
		if descriptor := Find_Class(registry, "WeldConstraint"); descriptor != nil {

			adjacency: map[^Object][dynamic]^Object
			defer {
				for _, neighbors in adjacency {delete(neighbors)}
				delete(adjacency)
			}
			for joint in descriptor.instances {
				if !part_joint_live(joint, world) || !Object_Is_Accessible(L, joint) {continue}
				weld := cast(^WeldConstraint)joint
				a, b := weld.part0, weld.part1
				if !weld.enabled ||
				   a == b ||
				   !part_joint_live(a, world) ||
				   !part_joint_live(b, world) {continue}
				if !Is_A_Class(a, &Part_Class) || !Is_A_Class(b, &Part_Class) {continue}
				if !Object_Is_Accessible(L, a) || !Object_Is_Accessible(L, b) {continue}
				first := adjacency[a]
				append(&first, b)
				adjacency[a] = first
				second := adjacency[b]
				append(&second, a)
				adjacency[b] = second
			}
			seen: map[^Object]bool
			defer delete(seen)
			queue: [dynamic]^Object
			defer delete(queue)
			seen[object] = true
			append(&queue, object)
			index := 0
			for head := 0; head < len(queue); head += 1 {
				for neighbor in adjacency[queue[head]] {
					if seen[neighbor] {continue}
					seen[neighbor] = true
					if grounded {
						if (cast(^Part)neighbor).anchored {
							vm.PushBoolean(L, true)
							return 1, true
						}
					} else if neighbor.lua_ref > 0 {
						index += 1
						Push_Object(L, neighbor)
						vm.SetArrayValue(L, -2, index)
					}
					if recursive {append(&queue, neighbor)}
				}
			}
		}
	}
	if grounded {vm.PushBoolean(L, false)}
	return 1, true
}
