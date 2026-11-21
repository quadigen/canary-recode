package services


import "core:math"
import "core:strings"
import "core:time"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

MESSAGING_MAX_TOPICS :: 1024
MESSAGING_MAX_TOPIC_LENGTH :: 128
MESSAGING_MAX_PAYLOAD :: 64 * 1024
MESSAGING_MAX_DEPTH :: 16
MESSAGING_MAX_PUBLISH_DEPTH :: 16

MessagingService_Class := classes.Class_Info {
	name   = "MessagingService",
	parent = &Service_Class,
}

MessagingService :: struct {
	using service: Service,
	topics:        map[string]^signals.Signal,
	publish_depth: int,
}

messaging_ensure_topic :: proc(service: ^MessagingService, name: string) -> ^signals.Signal {
	if signal, exists := service.topics[name]; exists {return signal}
	if len(service.topics) >= MESSAGING_MAX_TOPICS ||
	   service.data_model == nil ||
	   service.data_model.registry == nil ||
	   service.data_model.registry.signal_registry == nil {return nil}
	signal := signals.Create(service.data_model.registry.signal_registry)
	if signal == nil {return nil}
	service.topics[strings.clone(name)] = signal
	return signal
}


messaging_snapshot :: proc(L: ^vm.State, index, depth: int, budget: ^int) -> bool {
	if depth > MESSAGING_MAX_DEPTH || budget^ < 32 || !vm.CheckStack(L, 8) {return false}
	budget^ -= 32
	#partial switch vm.TypeOf(L, index) {
	case .Nil, .Boolean, .Integer:
		vm.PushValue(L, index)
	case .Number:
		n := vm.ArgNumber(L, index)
		if math.is_nan(n) || math.is_inf(n) {return false}
		vm.PushValue(L, index)
	case .String:
		s, _ := vm.ToString(L, index)
		if len(s) > budget^ {return false}
		budget^ -= len(s)
		vm.PushValue(L, index)
	case .Table:
		vm.NewTable(L)
		result := vm.StackTop(L)
		vm.PushNil(L)
		for vm.Next(L, index) {
			key := vm.StackTop(L) - 1
			key_type := vm.TypeOf(L, key)
			text: string
			number: int
			if key_type == .String {
				text, _ = vm.ToString(L, key)
				if strings.contains(text, "\x00") || len(text) > budget^ {return false}
				budget^ -= len(text)
			} else if key_type == .Number || key_type == .Integer {
				n := vm.ArgNumber(L, key)
				if math.is_nan(n) ||
				   n < -2147483648 ||
				   n > 2147483647 ||
				   n != math.floor(n) {return false}
				number = int(n)
			} else {return false}
			if !messaging_snapshot(L, key + 1, depth + 1, budget) {return false}
			if key_type ==
			   .String {vm.SetField(L, result, text)} else {vm.SetArrayValue(L, result, number)}
			vm.Pop(L)
		}
		vm.SetReadOnly(L, result)
	case:
		return false
	}
	return true
}

messaging_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(MessagingService)
	service.service = Service_Init(&MessagingService_Class, "MessagingService", data_model)
	service.topics = make(map[string]^signals.Signal)
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
	case "Subscribe",
	     "SubscribeAsync",
	     "Unsubscribe",
	     "UnsubscribeAll",
	     "Publish",
	     "PublishAsync",
	     "GetTopics",
	     "GetSubscribers":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

messaging_error :: proc(L: ^vm.State, message: string) -> (i32, bool) {
	return vm.RaiseError(L, message), true
}

messaging_disconnect_all :: proc(signal: ^signals.Signal) {
	if signal == nil {return}
	for len(signal.listeners) > 0 {
		signals.disconnect_listener(signal, signal.listeners[len(signal.listeners) - 1].id)
	}
}

messaging_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "Subscribe",
	     "SubscribeAsync",
	     "Unsubscribe",
	     "UnsubscribeAll",
	     "Publish",
	     "PublishAsync",
	     "GetTopics",
	     "GetSubscribers":
	case:
		return 0, false
	}
	service := cast(^MessagingService)object
	if service.destroyed ||
	   service.data_model == nil ||
	   service.data_model.registry == nil ||
	   service.data_model.registry.mode == .Client ||
	   service.data_model.registry.mode == .Editor {
		return messaging_error(
			L,
			"MessagingService is only available in a server or local game runtime",
		)
	}
	if vm.ThreadIsParallel(
		L,
	) {return messaging_error(L, "MessagingService requires the serial phase")}

	if method == "GetTopics" {
		vm.NewTable(L, len(service.topics), 0)
		i := 1
		for name in service.topics {
			vm.PushString(L, name)
			vm.SetArrayValue(L, -2, i)
			i += 1
		}
		return 1, true
	}
	if method == "UnsubscribeAll" && vm.IsNoneOrNil(L, 2) {
		for _, signal in service.topics {messaging_disconnect_all(signal)}
		return 0, true
	}
	topic, valid := vm.ToString(L, 2)
	if !valid ||
	   len(topic) == 0 ||
	   len(topic) > MESSAGING_MAX_TOPIC_LENGTH ||
	   strings.contains(topic, "\x00") {
		return messaging_error(
			L,
			"MessagingService topic must be a nonempty string of at most 128 bytes without NUL characters",
		)
	}
	signal := service.topics[topic]

	switch method {
	case "GetSubscribers":
		count := 0
		if signal != nil {count = len(signal.listeners)}
		vm.NewTable(L, count, 0)
		if signal != nil {
			for listener, i in signal.listeners {
				vm.PushInteger(L, i64(listener.id))
				vm.SetArrayValue(L, -2, i + 1)
			}
		}
		return 1, true
	case "Publish", "PublishAsync":
		if service.publish_depth >= MESSAGING_MAX_PUBLISH_DEPTH {
			return messaging_error(L, "MessagingService nested publish limit exceeded")
		}
		top := vm.StackTop(L)
		if top < 3 {return messaging_error(L, "MessagingService publish requires a payload")}
		vm.NewTable(L, 0, 3)
		budget := MESSAGING_MAX_PAYLOAD
		if !messaging_snapshot(L, 3, 0, &budget) {
			vm.SetStackTop(L, top)
			return messaging_error(
				L,
				"MessagingService payload is unsupported, too large or too deeply nested",
			)
		}
		vm.SetField(L, -2, "Data")
		vm.PushNumber(L, f64(time.to_unix_seconds(time.now())))
		vm.SetField(L, -2, "Sent")
		vm.PushString(L, topic)
		vm.SetField(L, -2, "topic")
		vm.SetReadOnly(L, -1)


		if signal != nil {
			service.publish_depth += 1
			signals.Fire(L, signal, 1)
			service.publish_depth -= 1
		}
		vm.SetStackTop(L, top)
		return 0, true
	case "Subscribe", "SubscribeAsync":
		has_callback := !vm.IsNoneOrNil(L, 3)
		if (method == "SubscribeAsync" || has_callback) && !vm.IsFunction(L, 3) {
			return messaging_error(L, "MessagingService subscription expects a callback function")
		}
		signal = messaging_ensure_topic(service, topic)
		if signal ==
		   nil {return messaging_error(L, "MessagingService topic limit reached or unavailable")}
		if has_callback {
			result := signals.Connect_Lua(L, signal, false, false, 3)


			connection := cast(^signals.KinemiumConnection)vm.UserdataValue(L, -1)
			if connection != nil && connection.signal_ref >= 0 {
				vm.ReleaseValue(L, connection.signal_ref)
				connection.signal_ref = -1
			}
			return result, true
		}
		signals.Push(L, signal)
		return 1, true
	case "Unsubscribe", "UnsubscribeAll":
		if method == "UnsubscribeAll" || vm.IsNoneOrNil(L, 3) {
			messaging_disconnect_all(signal)
			return 0, true
		}
		binding := vm.UserdataBindingOf(L, 3)
		if binding == nil || binding.tag != signals.CONNECTION_TAG {
			return messaging_error(L, "MessagingService unsubscribe expects a connection")
		}
		connection := cast(^signals.KinemiumConnection)vm.UserdataValue(L, 3)
		if connection != nil && signal != nil && connection.signal == signal {
			signals.Disconnect_Connection(connection)
		}
		return 0, true
	}
	return 0, false
}

messaging_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^MessagingService)object
	for name, signal in service.topics {
		signals.Destroy(signal)
		delete(name)
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
		get = messaging_service_get,
		namecall = messaging_service_namecall,
	)
}
