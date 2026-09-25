package services

import "base:runtime"
import kineffi "../bindings"
import classes "../classes"
import signals "../signals"
import vm "../vm"

Pending_Contact :: struct {
	body1, body2: kineffi.JPH_BodyID,
}

pending_contacts: [dynamic]Pending_Contact

physics_on_contact_added :: proc "c" (body1: kineffi.JPH_BodyID, body2: kineffi.JPH_BodyID, manifold: ^kineffi.JPH_ContactManifoldData) {
	context = runtime.default_context()
	append(&pending_contacts, Pending_Contact{body1, body2})
}

part_touched :: proc(part, other: ^classes.Part, L: ^vm.State) {
	if part == nil || other == nil || L == nil || part.touched == nil {return}
	classes.Push_Object(L, &other.object)
	signals.Fire(L, part.touched, 1)
	vm.Pop(L)
}

Physics_Drain_Contacts :: proc(service: ^Physics) {
	if service == nil || service.contact_listener == nil {return}
	procs := kineffi.JPH_ContactListener_Procs{
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