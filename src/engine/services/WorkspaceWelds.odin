package services

import "core:slice"

import kineffi "../bindings"
import classes "../classes"
import enums "../enum"
import vm "../vm"

WORKSPACE_WELD_SURFACE_TOLERANCE :: 0.01

Workspace_Weld_Pair :: struct {
	selected, outsider: ^classes.Object,
}

workspace_weld_is_live :: proc(object, workspace: ^classes.Object) -> bool {
	return object != nil && !object.destroyed && classes.Is_Descendant_Of(object, workspace)
}

workspace_has_weld :: proc(
	workspace: ^classes.Object,
	instances: []^classes.Object,
	pair: Workspace_Weld_Pair,
) -> bool {
	for object in instances {
		if !workspace_weld_is_live(object, workspace) {continue}
		weld := cast(^classes.WeldConstraint)object
		if (weld.part0 == pair.selected && weld.part1 == pair.outsider) ||
		   (weld.part1 == pair.selected && weld.part0 == pair.outsider) {
			return true
		}
	}
	return false
}

workspace_weld_root :: proc(
	parents: ^map[^classes.Object]^classes.Object,
	part: ^classes.Object,
) -> ^classes.Object {
	root := part
	for parent := parents^[root]; parent != nil; parent = parents^[root] {
		if grandparent := parents^[parent]; grandparent != nil {parents^[root] = grandparent}
		root = parent
	}
	return root
}

workspace_collect_weld_components :: proc(
	workspace: ^classes.Object,
	instances: []^classes.Object,
	parents: ^map[^classes.Object]^classes.Object,
) {
	for object in instances {
		if !workspace_weld_is_live(object, workspace) {continue}
		weld := cast(^classes.WeldConstraint)object
		if !weld.enabled ||
		   !workspace_weld_is_live(weld.part0, workspace) ||
		   !workspace_weld_is_live(weld.part1, workspace) {continue}
		a := workspace_weld_root(parents, weld.part0)
		b := workspace_weld_root(parents, weld.part1)
		if a != b {parents^[a] = b}
	}
}

workspace_collect_movable_joints :: proc(
	workspace: ^classes.Object,
	registry: ^classes.Registry,
) -> [dynamic]Workspace_Weld_Pair {
	pairs: [dynamic]Workspace_Weld_Pair
	for descriptor in registry.classes {
		if descriptor == nil ||
		   (descriptor.info != &classes.HingeConstraint_Class &&
		    !classes.Is_Attachment_Joint(descriptor.info)) {continue}
		for object in descriptor.instances {
			if !workspace_weld_is_live(object, workspace) {continue}
			joint := cast(^classes.Constraint)object
			if !joint.enabled ||
			   !workspace_weld_is_live(joint.attachment0, workspace) ||
			   !workspace_weld_is_live(joint.attachment1, workspace) {continue}
			a, b := joint.attachment0.parent, joint.attachment1.parent
			if !workspace_weld_is_live(a, workspace) || !workspace_weld_is_live(b, workspace) {continue}
			append(&pairs, Workspace_Weld_Pair{a, b})
		}
	}
	return pairs
}

workspace_weld_locks_joint :: proc(
	parents: ^map[^classes.Object]^classes.Object,
	joints: []Workspace_Weld_Pair,
	a, b: ^classes.Object,
) -> bool {
	if a == b {return false}
	for joint in joints {
		first := workspace_weld_root(parents, joint.selected)
		second := workspace_weld_root(parents, joint.outsider)
		if (a == first && b == second) || (a == second && b == first) {return true}
	}
	return false
}

workspace_remove_outsider_welds :: proc(
	L: ^vm.State,
	workspace: ^classes.Object,
	instances: []^classes.Object,
	selected: map[^classes.Object]bool,
) {
	snapshot := slice.clone(instances)
	defer delete(snapshot)
	for object in snapshot {
		if !workspace_weld_is_live(object, workspace) {continue}
		weld := cast(^classes.WeldConstraint)object
		a, b := weld.part0, weld.part1
		if a == nil ||
		   b == nil ||
		   a.destroyed ||
		   b.destroyed ||
		   selected[a] == selected[b] ||
		   !classes.Object_Is_Accessible(L, object) ||
		   !classes.Object_Is_Accessible(L, a) ||
		   !classes.Object_Is_Accessible(L, b) {
			continue
		}
		classes.WeldConstraint_release(weld)
		classes.Destroy_Hierarchy(object)
	}
}

workspace_update_outsider_welds :: proc(
	L: ^vm.State,
	workspace: ^classes.Object,
	physics: ^Physics,
	enum_registry: ^enums.Registry,
	join: bool,
) -> i32 {
	if !vm.IsTable(L, 2) {return vm.RaiseError(L, "expected an array of BaseParts")}
	mode := enums.JointCreationMode.All
	if join && !vm.IsNoneOrNil(L, 3) {
		mode = enums.JointCreationMode(
			enums.Arg_Item(L, 3, enum_registry, "JointCreationMode").value,
		)
	}

	selected := make(map[^classes.Object]bool)
	for i in 1 ..= vm.RawLen(L, 2) {
		vm.RawGetIndex(L, 2, i)
		part := classes.Object_From_Argument(L, -1)
		vm.Pop(L)
		if part == nil || part.destroyed || !classes.Is_A_Class(part, &classes.Part_Class) {
			delete(selected)
			return vm.RaiseError(L, "expected an array of BaseParts")
		}
		if workspace_contains_physics_object(workspace, part) {selected[part] = true}
	}
	defer delete(selected)
	if len(selected) == 0 || (join && mode == .None) {return 0}

	registry := workspace.signal_registry
	descriptor := classes.Find_Class(registry, "WeldConstraint")
	if descriptor == nil {return 0}
	if !join {
		workspace_remove_outsider_welds(L, workspace, descriptor.instances[:], selected)
		return 0
	}
	if physics == nil || !physics.initialized {return 0}

	Physics_Synchronize(physics, workspace)
	candidates: [dynamic]kineffi.JPH_BodyID
	defer delete(candidates)
	for body in physics.bodies {
		if !selected[body.object] &&
		   workspace_contains_physics_object(workspace, body.object) &&
		   classes.Object_Is_Accessible(L, body.object) {
			append(&candidates, body.body_id)
		}
	}
	results := make([]kineffi.JPH_BodyID, len(candidates))
	defer delete(results)
	pairs: [dynamic]Workspace_Weld_Pair
	defer delete(pairs)
	for part in selected {
		// A small separation allowance includes flush contacts.
		hits := physics_overlap_part(
			physics,
			cast(^classes.Part)part,
			candidates[:],
			results,
			WORKSPACE_WELD_SURFACE_TOLERANCE,
			planar_only = true,
		)
		for id in hits {
			other := physics_part_for_body(physics, id)
			if other == nil {continue}
			append(&pairs, Workspace_Weld_Pair{part, &other.object})
		}
	}
	joints := workspace_collect_movable_joints(workspace, registry)
	defer delete(joints)
	parents: map[^classes.Object]^classes.Object
	defer delete(parents)
	if len(joints) != 0 {
		workspace_collect_weld_components(workspace, descriptor.instances[:], &parents)
	}
	for pair in pairs {
		if pair.selected.destroyed ||
		   pair.outsider.destroyed ||
		   !workspace_contains_physics_object(workspace, pair.selected) ||
		   !workspace_contains_physics_object(workspace, pair.outsider) {
			continue
		}
		if workspace_has_weld(workspace, descriptor.instances[:], pair) {continue}
		a, b: ^classes.Object
		if len(joints) != 0 {
			a = workspace_weld_root(&parents, pair.selected)
			b = workspace_weld_root(&parents, pair.outsider)
			if workspace_weld_locks_joint(&parents, joints[:], a, b) {continue}
		}
		object, ok := classes.Push_New(registry, &vm.VM{L = L}, "WeldConstraint")
		if !ok {break}
		weld := cast(^classes.WeldConstraint)object
		weld.part0 = pair.selected
		weld.part1 = pair.outsider
		classes.Set_Parent(object, pair.selected)
		if a != b {parents[a] = b}
		vm.Pop(L)
	}
	return 0
}
