package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import signals "../signals"
import tracy "../util/odin-tracy"
import vm "../vm"

Pending_Contact :: struct {
	body1, body2: kineffi.JPH_BodyID,
}

pending_contacts: [dynamic]Pending_Contact

physics_on_contact_added :: proc "c" (
	body1: kineffi.JPH_BodyID,
	body2: kineffi.JPH_BodyID,
	manifold: ^kineffi.JPH_ContactManifoldData,
) {
	context = tracy.DefaultContext()
	append(&pending_contacts, Pending_Contact{body1, body2})
}

part_touched :: proc(part, other: ^classes.Part, L: ^vm.State) {
	if part == nil ||
	   other == nil ||
	   L == nil ||
	   part.touched == nil ||
	   part.destroyed ||
	   other.destroyed ||
	   !part.can_touch ||
	   !other.can_touch {return}
	classes.Push_Object(L, &other.object)
	signals.Fire(L, part.touched, 1)
	vm.Pop(L)
}

Physics_Drain_Contacts :: proc(service: ^Physics) {
	if service == nil || service.contact_listener == nil {return}
	procs := kineffi.JPH_ContactListener_Procs {
		OnContactAdded = physics_on_contact_added,
	}
	for {
		handled := kineffi.JPH_ContactListener_PollEvents(service.contact_listener, &procs, 64)
		if handled < 64 {break}
	}
	if len(pending_contacts) == 0 {return}
	L: ^vm.State
	if service.data_model != nil &&
	   service.data_model.registry != nil &&
	   service.data_model.registry.vm_state != nil &&
	   service.data_model.registry.vm_state.L != nil {
		L = service.data_model.registry.vm_state.L
	}
	if L == nil {
		clear(&pending_contacts)
		return
	}
	queue := pending_contacts
	pending_contacts = nil
	for pair in queue {
		a := physics_part_for_body(service, pair.body1)
		b := physics_part_for_body(service, pair.body2)
		if a == nil || b == nil || a == b {continue}
		part_touched(a, b, L)
		part_touched(b, a, L)
	}
	delete(queue)
}

Deformable_Contact_Key :: [2]datatypes.UniqueId
Deformable_Contact :: struct {
	object: ^classes.Object,
	root:   ^classes.Part,
}

physics_has_deformables :: proc(service: ^Physics) -> bool {
	for name in ([]string{"Cloth", "SoftBody"}) {
		if descriptor := classes.Find_Class(service.signal_registry, name);
		   descriptor != nil && len(descriptor.instances) > 0 {return true}
	}
	return false
}

physics_collect_character_capsules :: proc(service: ^Physics, workspace: ^classes.Object) {
	clear(&service.character_capsules)
	if !physics_has_deformables(service) {return}
	controllers := classes.Find_Class(service.signal_registry, "CollisionController")
	if controllers == nil {return}
	for instance in controllers.instances {
		if instance == nil || instance.destroyed ||
		   !classes.Is_A_Class(instance.parent, &classes.CharacterController_Class) ||
		   !classes.Is_Descendant_Of(instance, workspace) {continue}
		controller := cast(^classes.CollisionController)instance
		if !controller.body_created {continue}
		root := classes.CharacterController_Root(cast(^classes.CharacterController)instance.parent)
		if root != nil && !root.destroyed {service.character_capsules[controller.body_id] = root}
	}
}

physics_report_deformable_contact :: proc(service: ^Physics, object: ^classes.Object, body_id: kineffi.JPH_BodyID) {
	root := service.character_capsules[body_id]
	if root == nil && object.class == &classes.Cloth_Class {root = physics_part_for_body(service, body_id)}
	if root == nil || root.destroyed || !root.can_touch {return}
	key := Deformable_Contact_Key{object.unique_id, root.unique_id}
	service.deformable_contacts[key] = {object, root}
}

physics_fire_deformable_touched :: proc(L: ^vm.State, object: ^classes.Object, root: ^classes.Part) {
	if L == nil || object.destroyed || root.destroyed || !root.can_touch {return}
	signal: ^signals.Signal
	if object.class == &classes.Cloth_Class {
		signal = (cast(^classes.Cloth)object).touched
	} else {
		signal = (cast(^classes.SoftBody)object).touched
	}
	if signal != nil {
		classes.Push_Object(L, &root.object)
		signals.Fire(L, signal, 1)
		vm.Pop(L)
	}
	if root.touched != nil && !root.destroyed && !object.destroyed && root.can_touch {
		classes.Push_Object(L, object)
		signals.Fire(L, root.touched, 1)
		vm.Pop(L)
	}
}

physics_drain_deformable_contacts :: proc(service: ^Physics) {
	for key, contact in service.deformable_contacts {
		if key in service.previous_deformable_contacts {continue}
		physics_fire_deformable_touched(service.signal_registry.vm_state.L, contact.object, contact.root)
	}
	service.previous_deformable_contacts, service.deformable_contacts =
		service.deformable_contacts, service.previous_deformable_contacts
	clear(&service.deformable_contacts)
}
