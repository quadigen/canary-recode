package services

import kineffi "../bindings"
import classes "../classes"

physics_weld_root :: proc(
	parents: ^map[kineffi.JPH_BodyID]kineffi.JPH_BodyID,
	id: kineffi.JPH_BodyID,
) -> kineffi.JPH_BodyID {
	current := id
	for {
		parent, found := parents^[current]
		if !found {return current}
		if next, found := parents^[parent]; found {
			parents^[current] = next
		}
		current = parent
	}
}


physics_sync_weld_groups :: proc(service: ^Physics, workspace: ^classes.Object) {
	if !service.weld_groups_dirty {return}
	service.weld_groups_dirty = false

	parents: map[kineffi.JPH_BodyID]kineffi.JPH_BodyID
	defer delete(parents)
	groups: map[kineffi.JPH_BodyID]kineffi.JPH_BodyID
	if descriptor := classes.Find_Class(service.signal_registry, "WeldConstraint");
	   descriptor != nil {
		for object in descriptor.instances {
			if object == nil ||
			   object.destroyed ||
			   !classes.Is_Descendant_Of(object, workspace) {continue}
			weld := cast(^classes.WeldConstraint)object
			if weld.jolt_constraint == nil || weld.jolt_system != service.system.handle {continue}
			a, b := weld.jolt_body0, weld.jolt_body1
			groups[a], groups[b] = a, b
			root_a, root_b := physics_weld_root(&parents, a), physics_weld_root(&parents, b)
			if root_a != root_b {parents[max(root_a, root_b)] = min(root_a, root_b)}
		}
	}

	interface := service.system.body_interface
	for id in service.weld_groups {
		if id not_in groups {
			kineffi.JPH_BodyInterface_SetWeldGroup(interface, id, kineffi.JPH_BODY_ID_INVALID)
		}
	}
	for id in groups {
		group := physics_weld_root(&parents, id)
		groups[id] = group
		if previous, found := service.weld_groups[id]; !found || previous != group {
			kineffi.JPH_BodyInterface_SetWeldGroup(interface, id, group)
		}
	}
	delete(service.weld_groups)
	service.weld_groups = groups
}

physics_sync_excluded_pairs :: proc(service: ^Physics, workspace: ^classes.Object) {
	if service.contact_listener == nil {return}
	pairs := service.scratch_excluded_pairs
	clear(&pairs)
	descriptor := classes.Find_Class(service.signal_registry, "NoCollisionConstraint")
	if descriptor != nil {
		for object in descriptor.instances {
			if object == nil || object.destroyed {continue}
			c := cast(^classes.NoCollisionConstraint)object
			c.active = false
			if !c.enabled || !classes.Is_Descendant_Of(object, workspace) {continue}
			a, b := c.part0, c.part1
			if a == nil || b == nil || a.destroyed || b.destroyed || a == b {continue}
			ai, bi := (cast(^classes.Part)a).part_index, (cast(^classes.Part)b).part_index
			if ai < 0 ||
			   bi < 0 ||
			   ai >= len(service.body_ids) ||
			   bi >= len(service.body_ids) {continue}
			id0, id1 := service.body_ids[ai], service.body_ids[bi]
			if id0 == kineffi.JPH_BODY_ID_INVALID ||
			   id1 == kineffi.JPH_BODY_ID_INVALID ||
			   id0 == id1 {continue}
			append(&pairs, id0, id1)
			c.active = true
		}
	}


	previous := service.applied_excluded_pairs
	changed := len(previous) != len(pairs)
	if !changed {
		for id, i in pairs {
			if id != previous[i] {changed = true; break}
		}
	}
	if changed {
		kineffi.JPH_ContactListener_SetExcludedPairs(
			service.contact_listener,
			service.system.body_interface,
			raw_data(pairs),
			u32(len(pairs) / 2),
		)
		service.applied_excluded_pairs = pairs
		service.scratch_excluded_pairs = previous
	} else {
		service.scratch_excluded_pairs = pairs
	}
}
