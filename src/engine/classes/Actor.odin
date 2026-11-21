package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:strings"

Actor_Class := Class_Info {
	name   = "Actor",
	parent = &Model_Class,
}

Actor :: struct {
	using model: Model,
	actor_id:    u64,
	topics:      map[string]^signals.Signal,
}

next_actor_id: u64
live_actors: map[u64]^Actor

Actor_Is_Alive :: proc(id: u64) -> bool {
	actor := live_actors[id]
	return actor != nil && !actor.destroyed
}

Actor_Profile_Name :: proc(id: u64) -> string {
	if actor := live_actors[id]; actor != nil && !actor.destroyed {
		return Get_Full_Name(&actor.object)
	}
	return ""
}

Actor_Ancestor :: proc(object: ^Object) -> ^Actor {
	if object == nil {return nil}
	for ancestor := object.parent; ancestor != nil; ancestor = ancestor.parent {
		if Is_A_Class(ancestor, &Actor_Class) && !ancestor.destroyed {return cast(^Actor)ancestor}
	}
	return nil
}

Actor_Ancestor_ID :: proc(object: ^Object) -> u64 {
	if actor := Actor_Ancestor(object); actor != nil {return actor.actor_id}
	return 0
}

actor_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	actor := new(Actor)
	actor.model = Model_Init()
	actor.object = Object_Init(&Actor_Class, "Actor")
	next_actor_id += 1
	actor.actor_id = next_actor_id
	live_actors[actor.actor_id] = actor
	return &actor.object
}

actor_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	actor := cast(^Actor)object
	delete_key(&live_actors, actor.actor_id)
	if len(live_actors) == 0 {delete(live_actors); live_actors = nil}
	for topic, signal in actor.topics {
		signals.Destroy(signal)
		delete(topic)
	}
	delete(actor.topics)
	Object_Destroy(object)
	free(actor)
}

actor_get :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "SendMessage", "BindToMessage", "BindToMessageParallel":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return model_get(L, object, d, e, key)
}

actor_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	actor := cast(^Actor)object
	switch method {
	case "SendMessage", "BindToMessage", "BindToMessageParallel":
		topic := vm.ArgString(L, 2)
		if method == "SendMessage" {
			if signal := actor.topics[topic]; signal != nil {
				signals.Signal_Fire_Deferred(L, signal, 3, vm.StackTop(L) - 2)
			}
			return 0, true
		}
		if vm.ThreadActor(L) !=
		   actor.actor_id {return vm.RaiseError(L, "Actor messages must be bound by scripts belonging to that Actor"), true}
		if vm.ThreadIsParallel(
			L,
		) {return vm.RaiseError(L, "bind messages in the serial phase"), true}
		if !vm.IsFunction(L, 3) {return vm.RaiseError(L, "BindToMessage expects a function"), true}
		signal := actor.topics[topic]
		if signal == nil {
			if object.signal_registry ==
			   nil {return vm.RaiseError(L, "Actor signal registry unavailable"), true}
			signal = signals.Create(object.signal_registry.signal_registry)
			actor.topics[strings.clone(topic)] = signal
		}
		return signals.Connect_Lua(L, signal, false, method == "BindToMessageParallel", 3), true
	}
	return model_namecall(L, object, d, e, method)
}

actor_parallel_get :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	if key != "SendMessage" {return model_parallel_get(L, object, d, e, key)}
	vm.PushUserdataMethod(L, key)
	return true
}

actor_parallel_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "SendMessage" {return model_parallel_namecall(L, object, d, e, method)}
	return actor_namecall(L, object, d, e, method)
}

Register_Actor :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Actor_Class,
		actor_construct,
		actor_destroy,
		clone = Model_clone,
		get = actor_get,
		set = model_set,
		namecall = actor_namecall,
		parallel_get = actor_parallel_get,
		parallel_namecall = actor_parallel_namecall,
		methods = []string{"SendMessage", "BindToMessage", "BindToMessageParallel"},
	)
}
