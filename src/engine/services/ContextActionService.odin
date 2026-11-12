package services

// wire:service

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:fmt"
import "core:slice"
import "core:strings"

ContextActionService_Class := classes.Class_Info {
	name   = "ContextActionService",
	parent = &Service_Class,
}

Context_Action_Input :: union {
	enums.KeyCode,
	enums.UserInputType,
	enums.PlayerActions,
}

Context_Action :: struct {
	id:           u64,
	name:         string,
	inputs:       []Context_Action_Input,
	callback_ref: i32,
	priority:     f64,
	capabilities: vm.Thread_Security_Capabilities,
}

ContextActionService :: struct {
	using service: Service,
	actions:       [dynamic]Context_Action,
	next_id:       u64,
}

context_action_construct :: proc(
	renderer: ^classes.Renderer_Object,
	model: rawptr,
) -> ^classes.Object {
	service := new(ContextActionService)
	service.service = Service_Init(&ContextActionService_Class, "ContextActionService", model)
	return &service.object
}

context_action_release :: proc(L: ^vm.State, action: Context_Action) {
	if L != nil {vm.ReleaseValue(L, action.callback_ref)}
	delete(action.name)
	delete(action.inputs)
}

context_action_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^ContextActionService)object
	L: ^vm.State
	if registry := object.signal_registry; registry != nil && registry.vm_state != nil {
		L = registry.vm_state.L
	}
	for action in service.actions {context_action_release(L, action)}
	delete(service.actions)
	classes.Object_Destroy(object)
	free(service)
}

context_action_unbind :: proc(L: ^vm.State, service: ^ContextActionService, name: string) {
	for action, index in service.actions {
		if action.name == name {
			context_action_release(L, action)
			ordered_remove(&service.actions, index)
			return
		}
	}
}

context_action_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "BindAction", "BindActionAtPriority", "UnbindAction":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

context_action_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^ContextActionService)object
	switch method {
	case "BindAction", "BindActionAtPriority":
		name := vm.ArgString(L, 2)
		if !vm.IsFunction(
			L,
			3,
		) {return vm.RaiseError(L, "action callback must be a function"), true}
		if vm.ArgBoolean(
			L,
			4,
		) {return vm.RaiseError(L, "action touch buttons are unavailable"), true}
		first_input := 5
		priority := f64(enums.ContextActionPriority.Medium)
		if method == "BindActionAtPriority" {
			priority = vm.ArgNumber(L, 5)
			first_input = 6
		}
		count := vm.StackTop(L) - first_input + 1
		if count <= 0 {return vm.RaiseError(L, "action requires an input"), true}

		inputs := make([]Context_Action_Input, count, context.temp_allocator)
		for &input, index in inputs {
			item := enums.Arg_Item(L, first_input + index, en)
			switch item.enum_type.name {
			case "KeyCode":
				input = enums.KeyCode(item.value)
			case "UserInputType":
				input = enums.UserInputType(item.value)
			case "PlayerActions":
				input = enums.PlayerActions(item.value)
			case:
				return vm.RaiseError(L, "expected KeyCode, UserInputType, or PlayerActions"), true
			}
		}

		context_action_unbind(L, service, name)
		service.next_id += 1
		append(
			&service.actions,
			Context_Action {
				id = service.next_id,
				name = strings.clone(name),
				inputs = slice.clone(inputs),
				callback_ref = vm.RetainValue(L, 3),
				priority = priority,
				capabilities = vm.GetThreadSecurityCapabilities(L),
			},
		)
		for i := len(service.actions) - 1;
		    i > 0 && service.actions[i - 1].priority <= priority;
		    i -= 1 {
			service.actions[i - 1], service.actions[i] = service.actions[i], service.actions[i - 1]
		}
		return 0, true
	case "UnbindAction":
		context_action_unbind(L, service, vm.ArgString(L, 2))
		return 0, true
	}
	return 0, false
}

context_action_matches :: proc(
	input: Context_Action_Input,
	value: classes.InputObject_Value,
) -> bool {
	switch key in input {
	case enums.KeyCode:
		return key == value.KeyCode
	case enums.UserInputType:
		return key == value.UserInputType
	case enums.PlayerActions:
		if value.UserInputType != .Keyboard {return false}
		switch key {
		case .CharacterForward:
			return value.KeyCode == .W || value.KeyCode == .Up
		case .CharacterBackward:
			return value.KeyCode == .S || value.KeyCode == .Down
		case .CharacterLeft:
			return value.KeyCode == .A || value.KeyCode == .Left
		case .CharacterRight:
			return value.KeyCode == .D || value.KeyCode == .Right
		case .CharacterJump:
			return value.KeyCode == .Space
		}
	}
	return false
}

context_action_dispatch :: proc(
	L: ^vm.State,
	model: ^DataModel,
	input: classes.InputObject_Value,
	input_index: int,
) -> bool {
	if model == nil {return false}
	descriptor := Find_Service(model.registry, "ContextActionService")
	if descriptor == nil || descriptor.object == nil {return false}
	service := cast(^ContextActionService)descriptor.object
	if len(service.actions) == 0 {return false}
	en := model.registry.classes.enums
	// The callback may change the bindings. IDs identify the original matching
	// actions without keeping pointers into a list that can be reallocated.
	matches: [dynamic]u64
	defer delete(matches)
	for action in service.actions {
		for key in action.inputs {
			if context_action_matches(key, input) {
				append(&matches, action.id)
				break
			}
		}
	}

	for id in matches {
		for action in service.actions {
			if action.id != id {continue}
			vm.PushRegistryReference(L, action.callback_ref)
			vm.PushString(L, action.name)
			_ = enums.Push_Item_By_Value(L, en, "UserInputState", i64(input.UserInputState))
			vm.PushValue(L, input_index)
			previous := vm.GetThreadSecurityCapabilities(L)
			vm.SetThreadSecurityCapabilities(L, action.capabilities)
			ok, err := vm.ProtectedCall(L, 3, 1)
			vm.SetThreadSecurityCapabilities(L, previous)
			defer delete(err)
			if !ok {
				fmt.eprintf("Context action callback failed: %s\n", err)
				break
			}
			pass := false
			if vm.IsUserdataType(L, -1, &en.item_binding) {
				item := cast(^enums.Enum_Item)vm.UserdataValue(L, -1)
				pass =
					item.enum_type.name == "ContextActionResult" &&
					item.value == i64(enums.ContextActionResult.Pass)
			}
			vm.Pop(L)
			if !pass {return true}
			break
		}
	}
	return false
}

Register_ContextActionService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ContextActionService_Class,
		context_action_construct,
		context_action_destroy,
		creatable = false,
		get = context_action_get,
		namecall = context_action_namecall,
		methods = []string{"BindAction", "BindActionAtPriority", "UnbindAction"},
	)
}
