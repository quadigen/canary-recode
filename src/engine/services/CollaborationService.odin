#+build !js
// wire:service
package services

import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

CollaborationService_Class := classes.Class_Info{
	name = "CollaborationService",
	parent = &Service_Class,
}

Collaboration_Request_Options :: enum {None, Body, Query}

Collaboration_Route :: struct {
	verb: string,
	path: string,
	options: Collaboration_Request_Options,
}

// Methods take an optional explicit Matrix session in slot 2, followed by
// route IDs in order and then a body or query table when applicable.
collaboration_route :: proc(method: string) -> (Collaboration_Route, bool) {
	switch method {
	case "GetCapabilities": return {"GET", "/capabilities", .None}, true
	case "StartSession": return {"POST", "/me/games/{}/collab-sessions", .Body}, true
	case "ListSessions": return {"GET", "/me/collab-sessions", .Query}, true
	case "EndSession": return {"DELETE", "/me/collab-sessions/{}", .None}, true
	case "RotateJoinCode": return {"POST", "/me/collab-sessions/{}/join-code", .None}, true
	case "Invite": return {"POST", "/me/collab-sessions/{}/invites", .Body}, true
	case "ListSessionInvites": return {"GET", "/me/collab-sessions/{}/invites", .Query}, true
	case "RevokeInvite": return {"DELETE", "/me/collab-sessions/{}/invites/{}", .None}, true
	case "ListSessionJoinRequests": return {"GET", "/me/collab-sessions/{}/join-requests", .Query}, true
	case "ApproveJoinRequest": return {"POST", "/me/collab-sessions/{}/join-requests/{}/approve", .None}, true
	case "DenyJoinRequest": return {"POST", "/me/collab-sessions/{}/join-requests/{}/deny", .None}, true
	case "RemoveParticipant": return {"DELETE", "/me/collab-sessions/{}/participants/{}", .None}, true
	case "ListInvites": return {"GET", "/me/collab-invites", .Query}, true
	case "AcceptInvite": return {"POST", "/me/collab-invites/{}/accept", .None}, true
	case "DeclineInvite": return {"POST", "/me/collab-invites/{}/decline", .None}, true
	case "RequestJoin": return {"POST", "/collab/join", .Body}, true
	case "ListJoinRequests": return {"GET", "/me/collab-join-requests", .Query}, true
	case "CancelJoinRequest": return {"POST", "/me/collab-join-requests/{}/cancel", .None}, true
	case "GetSession": return {"GET", "/collab/sessions/{}", .None}, true
	case "ListParticipants": return {"GET", "/collab/sessions/{}/participants", .None}, true
	case "Heartbeat": return {"POST", "/collab/sessions/{}/heartbeat", .None}, true
	case "LeaveSession": return {"POST", "/collab/sessions/{}/leave", .None}, true
	case "SendSignal": return {"POST", "/collab/sessions/{}/signals", .Body}, true
	case "PollSignals": return {"GET", "/collab/sessions/{}/signals", .Query}, true
	}
	return {}, false
}

collaboration_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(Service)
	service^ = Service_Init(&CollaborationService_Class, "CollaborationService", data_model)
	return &service.object
}

collaboration_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Service)object)
}

collaboration_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	if _, found := collaboration_route(key); found {
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

collaboration_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	route, found := collaboration_route(method)
	if !found { return 0, false }
	if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
		vm.PushBoolean(L, false)
		vm.PushNil(L)
		vm.PushString(L, "Collaboration requires Studio permissions")
		return 3, true
	}

	arg := 3
	path := route.path
	for marker := strings.index(path, "{}"); marker >= 0; marker = strings.index(path, "{}") {
		id := vm.ArgString(L, arg)
		if id == "" || id == "." || id == ".." {
			vm.PushBoolean(L, false)
			vm.PushNil(L)
			vm.PushString(L, "Invalid collaboration route identifier")
			return 3, true
		}
		path = strings.concatenate(
			{path[:marker], kinemium_url_encode(id), path[marker+2:]},
			context.temp_allocator,
		)
		arg += 1
	}

	options := kinemium_options_empty()
	switch route.options {
	case .None:
	case .Body: options = kinemium_options_json(L, arg)
	case .Query: options = kinemium_options_query(L, arg)
	}
	return kinemium_domain_call(L, cast(^Service)object, 2, route.verb, path, options), true
}

Register_CollaborationService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&CollaborationService_Class,
		collaboration_construct,
		collaboration_destroy,
		creatable = false,
		get = collaboration_get,
		namecall = collaboration_namecall,
	)
}
