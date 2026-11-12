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

// Welded parts form a rigid assembly. Resolving contacts between its own
// shapes fights the fixed joints whenever authored pieces overlap.
physics_sync_weld_groups :: proc(service: ^Physics, workspace: ^classes.Object) {
	if !service.weld_groups_dirty {return}
	service.weld_groups_dirty = false

	parents: map[kineffi.JPH_BodyID]kineffi.JPH_BodyID
	defer delete(parents)
	groups: map[kineffi.JPH_BodyID]kineffi.JPH_BodyID
	if descriptor := classes.Find_Class(service.signal_registry, "WeldConstraint"); descriptor != nil {
		for object in descriptor.instances {
			if object == nil || object.destroyed || !classes.Is_Descendant_Of(object, workspace) {continue}
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
