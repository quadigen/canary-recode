package classes

import "core:strings"

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

BindableEvent_Class := Class_Info{
	name   = "BindableEvent",
	parent = &Instance_Class,
}

BindableEvent :: struct {
	using object: Object,

	event: ^signals.Signal,
}

BindableEvent_Init :: proc() -> BindableEvent {
	return BindableEvent{
		object = Object_Init(&BindableEvent_Class),
	}
}

bindable_event_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	event := cast(^BindableEvent)object
	switch key {
	case "Event":
		if event.event == nil {
			if object.signal_registry == nil ||
			   object.signal_registry.signal_registry == nil {
				return false
			}
			event.event = signals.Create(object.signal_registry.signal_registry)
		}
		signals.Push(L, event.event)
		return true
	}
	return false
}

bindable_event_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	event := cast(^BindableEvent)object
	switch method {
	case "Fire":
		if event.event == nil {
			return 0, true
		}
		count := vm.StackTop(L) - 1
		signals.Signal_Fire_Arguments(L, event.event, 2, count)
		for index in 0 ..< count {
			vm.Pop(L)
		}
		return 0, true
	}
	return 0, false
}

bindable_event_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	event := new(BindableEvent)
	event^ = BindableEvent_Init()
	event.name = "BindableEvent"
	return &event.object
}

bindable_event_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^BindableEvent)object)
}

bindable_event_clone :: proc(source: ^Object, destination: ^Object) {
	_ = source
	_ = destination
}

BindableFunction_Class := Class_Info{
	name   = "BindableFunction",
	parent = &Instance_Class,
}

BindableFunction :: struct {
	using object: Object,

	function:      ^signals.Signal,
	event_name:    string,
	returns_event: bool,
}

BindableFunction_Init :: proc() -> BindableFunction {
	return BindableFunction{
		object    = Object_Init(&BindableFunction_Class),
		returns_event = true,
	}
}

bindable_function_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	function := cast(^BindableFunction)object
	switch key {
	case "Event":
		if function.function == nil {
			if object.signal_registry == nil ||
			   object.signal_registry.signal_registry == nil {
				return false
			}
			function.function =
				signals.Create(object.signal_registry.signal_registry)
		}
		signals.Push(L, function.function)
		return true
	case "Name":
		vm.PushString(L, function.event_name)
		return true
	case "OnInvoke":
		vm.PushNil(L)
		return true
	}
	return false
}

bindable_function_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	function := cast(^BindableFunction)object
	switch key {
	case "Name":
		function.event_name = strings.clone(vm.ArgString(L, value_index))
		return true
	}
	return false
}

bindable_function_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	function := cast(^BindableFunction)object
	switch method {
	case "Invoke":
		count := vm.StackTop(L) - 1
		if function.function != nil {
			signals.Signal_Fire_Arguments(L, function.function, 2, count)
		}
		for index in 0 ..< count {
			vm.Pop(L)
		}
		return 0, true
	}
	return 0, false
}

bindable_function_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	function := new(BindableFunction)
	function^ = BindableFunction_Init()
	function.name = "BindableFunction"
	return &function.object
}

bindable_function_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	function := cast(^BindableFunction)object
	delete(function.event_name)
	Object_Destroy(object)
	free(function)
}

bindable_function_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^BindableFunction)source
	dst := cast(^BindableFunction)destination
	dst.event_name = strings.clone(src.event_name)
	dst.returns_event = src.returns_event
}

Register_BindableFunction :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&BindableFunction_Class,
		bindable_function_construct,
		bindable_function_destroy,
		get      = bindable_function_get,
		set      = bindable_function_set,
		namecall = bindable_function_namecall,
		clone    = bindable_function_clone,
	)
}

Register_BindableEvent :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&BindableEvent_Class,
		bindable_event_construct,
		bindable_event_destroy,
		get      = bindable_event_get,
		namecall = bindable_event_namecall,
		clone    = bindable_event_clone,
	)
}