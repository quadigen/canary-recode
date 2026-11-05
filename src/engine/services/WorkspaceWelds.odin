package services

import "core:slice"

import kineffi "../bindings"
import classes "../classes"
import enums "../enum"
import vm "../vm"

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
			1.0e-4,
			planar_only = true,
		)
		for id in hits {
			other := physics_part_for_body(physics, id)
			if other == nil {continue}
			append(&pairs, Workspace_Weld_Pair{part, &other.object})
		}
	}
	for pair in pairs {
		if pair.selected.destroyed ||
		   pair.outsider.destroyed ||
		   !workspace_contains_physics_object(workspace, pair.selected) ||
		   !workspace_contains_physics_object(workspace, pair.outsider) {
			continue
		}
		if workspace_has_weld(workspace, descriptor.instances[:], pair) {continue}
		object, ok := classes.Push_New(registry, &vm.VM{L = L}, "WeldConstraint")
		if !ok {break}
		weld := cast(^classes.WeldConstraint)object
		weld.part0 = pair.selected
		weld.part1 = pair.outsider
		classes.Set_Parent(object, pair.selected)
		vm.Pop(L)
	}
	return 0
}
