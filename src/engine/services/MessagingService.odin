package services

// wire:service global="messagingService"

import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

MessagingService_Class := classes.Class_Info{
	name   = "MessagingService",
	parent = &Service_Class,
}

MessagingTopic :: struct {
	name:     string,
	signal:   ^signals.Signal,
	refcount: int,
}

MessagingService :: struct {
	using service: Service,
	topics: [dynamic]MessagingTopic,
}

messaging_find_topic :: proc(service: ^MessagingService, name: string) -> int {
	if service == nil {
		return -1
	}
	for topic, index in service.topics {
		if topic.name == name {
			return index
		}
	}
	return -1
}

messaging_ensure_topic :: proc(service: ^MessagingService, name: string) -> int {
	index := messaging_find_topic(service, name)
	if index >= 0 {
		return index
	}
	if service == nil ||
	   service.service.data_model == nil ||
	   service.service.data_model.registry == nil ||
	   service.service.data_model.registry.signal_registry == nil {
		return -1
	}
	append(
		&service.topics,
		MessagingTopic{
			name   = strings.clone(name),
			signal = signals.Create(service.service.data_model.registry.signal_registry),
		},
	)
	return len(service.topics) - 1
}

messaging_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(MessagingService)
	service.service = Service_Init(
		&MessagingService_Class,
		"MessagingService",
		data_model,
	)
	return &service.object
}

messaging_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "Subscribe", "Unsubscribe", "UnsubscribeAll", "Publish", "GetTopics", "GetSubscribers":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

messaging_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	service := cast(^MessagingService)object
	switch method {
	case "GetTopics":
		vm.NewTable(L, len(service.topics), 0)
		for topic, index in service.topics {
			vm.PushString(L, topic.name)
			vm.SetArrayValue(L, -2, index + 1)
		}
		return 1, true
	case "GetSubscribers":
		vm.NewTable(L, 0, 0)
		return 1, true
	case "Publish":
		topic := vm.ArgString(L, 2)
		index := messaging_ensure_topic(service, topic)
		if index >= 0 && service.topics[index].signal != nil {
			L := L
			vm.NewTable(L, 0, 0)
			vm.PushString(L, topic)
			vm.SetField(L, -2, "topic")
			signals.Fire(L, service.topics[index].signal, 1)
			vm.Pop(L)
		}
		return 0, true
	case "Subscribe":
		topic := vm.ArgString(L, 2)
		index := messaging_ensure_topic(service, topic)
		if index < 0 {
			vm.PushNil(L)
			return 1, true
		}
		signals.Push(L, service.topics[index].signal)
		return 1, true
	case "Unsubscribe", "UnsubscribeAll":
		return 0, true
	}
	return 0, false
}

messaging_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	service := cast(^MessagingService)object
	for topic in service.topics {
		if topic.signal != nil {
			signals.Destroy(topic.signal)
		}
	}
	delete(service.topics)
	classes.Object_Destroy(object)
	free(service)
}

Register_MessagingService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&MessagingService_Class,
		messaging_service_construct,
		messaging_service_destroy,
		creatable = false,
		get       = messaging_service_get,
		namecall  = messaging_service_namecall,
	)
}