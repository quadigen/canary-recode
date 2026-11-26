package services


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
	default_inputs: []Context_Action_Input,
	id:             u64,
	name:           string,
	inputs:         []Context_Action_Input,
	callback_ref:   i32,
	priority:       f64,
	capabilities:   vm.Thread_Security_Capabilities,
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
	delete(action.default_inputs)
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


context_action_set_bindings :: proc(
	L: ^vm.State,
	service: ^ContextActionService,
	en: ^enums.Registry,
) -> i32 {
	name := vm.ArgString(L, 2)
	action: ^Context_Action
	for &entry in service.actions {
		if entry.name == name {action = &entry; break}
	}
	if action == nil {return vm.RaiseError(L, "action is not bound")}
	count := vm.StackTop(L) - 2
	if count < 1 || count > 32 {return vm.RaiseError(L, "expected 1 to 32 input EnumItems")}
	inputs := make([]Context_Action_Input, count)
	for &input, i in inputs {
		index := i + 3
		if !vm.IsUserdataType(L, index, &en.item_binding) {
			delete(inputs)
			return vm.RaiseError(L, "expected KeyCode, UserInputType, or PlayerActions")
		}
		item := cast(^enums.Enum_Item)vm.UserdataValue(L, index)
		switch item.enum_type.name {
		case "KeyCode":
			input = enums.KeyCode(item.value)
		case "UserInputType":
			input = enums.UserInputType(item.value)
		case "PlayerActions":
			input = enums.PlayerActions(item.value)
		case:
			delete(inputs)
			return vm.RaiseError(L, "expected KeyCode, UserInputType, or PlayerActions")
		}
	}
	delete(action.inputs)
	action.inputs = inputs
	return 0
}
context_action_get_bindings :: proc(
	L: ^vm.State,
	service: ^ContextActionService,
	en: ^enums.Registry,
) -> i32 {
	name := vm.ArgString(L, 2)
	for action in service.actions {
		if action.name != name {continue}
		vm.NewTable(L, len(action.inputs))
		for input, i in action.inputs {
			switch key in input {
			case enums.KeyCode:
				_ = enums.Push_Item_By_Value(L, en, "KeyCode", i64(key))
			case enums.UserInputType:
				_ = enums.Push_Item_By_Value(L, en, "UserInputType", i64(key))
			case enums.PlayerActions:
				_ = enums.Push_Item_By_Value(L, en, "PlayerActions", i64(key))
			}
			vm.SetArrayValue(L, -2, i + 1)
		}
		return 1
	}
	vm.NewTable(L)
	return 1
}
context_action_reset_bindings :: proc(L: ^vm.State, service: ^ContextActionService) -> i32 {
	name := vm.ArgString(L, 2)
	for &action in service.actions {
		if action.name != name {continue}
		delete(action.inputs)
		action.inputs = slice.clone(action.default_inputs)
		return 0
	}
	return vm.RaiseError(L, "action is not bound")
}
context_action_encode_binding :: proc(en: ^enums.Registry, input: Context_Action_Input) -> string {
	kind: string
	value: i64
	switch key in input {
	case enums.KeyCode:
		kind, value = "KeyCode", i64(key)
	case enums.UserInputType:
		kind, value = "UserInputType", i64(key)
	case enums.PlayerActions:
		kind, value = "PlayerActions", i64(key)
	}
	for enum_type in en.types {
		if enum_type.name != kind {continue}
		for item in enum_type.items {
			if item.value == value {return fmt.tprintf("%s.%s", kind, item.name)}
		}
	}
	return ""
}
context_action_decode_binding :: proc(
	en: ^enums.Registry,
	token: string,
) -> (
	Context_Action_Input,
	bool,
) {
	for enum_type in en.types {
		switch enum_type.name {
		case "KeyCode", "UserInputType", "PlayerActions":
		case:
			continue
		}
		prefix := fmt.tprintf("%s.", enum_type.name)
		if !strings.has_prefix(token, prefix) {continue}
		for item in enum_type.items {
			if token[len(prefix):] != item.name {continue}
			switch enum_type.name {
			case "KeyCode":
				return enums.KeyCode(item.value), true
			case "UserInputType":
				return enums.UserInputType(item.value), true
			case "PlayerActions":
				return enums.PlayerActions(item.value), true
			}
		}
	}
	return Context_Action_Input{}, false
}
context_action_export_map :: proc(
	L: ^vm.State,
	service: ^ContextActionService,
	en: ^enums.Registry,
) -> i32 {
	vm.NewTable(L, 0, len(service.actions))
	for action in service.actions {
		vm.NewTable(L, len(action.inputs))
		for input, i in action.inputs {
			vm.PushString(L, context_action_encode_binding(en, input))
			vm.SetArrayValue(L, -2, i + 1)
		}
		vm.SetField(L, -2, action.name)
	}
	return 1
}
Context_Action_Map_Update :: struct {
	index:  int,
	inputs: []Context_Action_Input,
}


context_action_import_map :: proc(
	L: ^vm.State,
	service: ^ContextActionService,
	en: ^enums.Registry,
) -> i32 {
	if !vm.IsTable(L, 2) {return vm.RaiseError(L, "action map must be a table")}
	updates: [dynamic]Context_Action_Map_Update
	valid := true
	vm.PushNil(L)
	for vm.Next(L, 2) {
		name, key_ok := vm.ToString(L, -2)
		action_index := -1
		if key_ok {
			for action, i in service.actions {
				if action.name == name {action_index = i; break}
			}
		}
		if action_index < 0 || !vm.IsTable(L, -1) {
			valid = false
			vm.Pop(L)
			break
		}
		count := vm.RawLen(L, -1)
		if count < 1 || count > 32 {
			valid = false
			vm.Pop(L)
			break
		}
		inputs := make([]Context_Action_Input, count)
		for i in 0 ..< count {
			_ = vm.RawGetIndex(L, -1, i + 1)
			token, text_ok := vm.ToString(L, -1)
			binding, found := context_action_decode_binding(en, token)
			vm.Pop(L)
			if !text_ok || !found {valid = false; break}
			inputs[i] = binding
		}
		if !valid {
			delete(inputs)
			vm.Pop(L)
			break
		}
		append(&updates, Context_Action_Map_Update{index = action_index, inputs = inputs})
		vm.Pop(L)
	}
	if !valid {
		for update in updates {delete(update.inputs)}
		delete(updates)
		return vm.RaiseError(
			L,
			"invalid action map: expected bound action names and EnumType.Item arrays",
		)
	}
	for update in updates {
		action := &service.actions[update.index]
		delete(action.inputs)
		action.inputs = update.inputs
	}
	delete(updates)
	return 0
}
context_action_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "BindAction",
	     "BindActionAtPriority",
	     "UnbindAction",
	     "UnbindAllActions",
	     "GetBoundActionInfo",
	     "GetAllBoundActionInfo",
	     "SetActionBindings",
	     "GetActionBindings",
	     "ResetActionBindings",
	     "ExportActionMap",
	     "ImportActionMap":
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
	case "SetActionBindings":
		return context_action_set_bindings(L, service, en), true
	case "GetActionBindings":
		return context_action_get_bindings(L, service, en), true
	case "ResetActionBindings":
		return context_action_reset_bindings(L, service), true
	case "ExportActionMap":
		return context_action_export_map(L, service, en), true
	case "ImportActionMap":
		return context_action_import_map(L, service, en), true
	case "UnbindAllActions":
		for action in service.actions {context_action_release(L, action)}
		clear(&service.actions)
		return 0, true
	case "GetBoundActionInfo":
		name := vm.ArgString(L, 2)
		for action in service.actions {
			if action.name == name {context_action_push_info(L, en, action); return 1, true}
		}
		vm.NewTable(L, 0, 0)
		return 1, true
	case "GetAllBoundActionInfo":
		vm.NewTable(L, 0, len(service.actions))
		for action in service.actions {
			context_action_push_info(L, en, action)
			vm.SetField(L, -2, action.name)
		}
		return 1, true
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
				default_inputs = slice.clone(inputs),
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

context_action_push_info :: proc(L: ^vm.State, en: ^enums.Registry, action: Context_Action) {
	vm.NewTable(L, 0, 3)
	vm.PushNumber(L, action.priority)
	vm.SetField(L, -2, "priorityLevel")
	vm.PushBoolean(L, false)
	vm.SetField(L, -2, "createTouchButton")
	vm.NewTable(L, len(action.inputs))
	for input, i in action.inputs {
		switch key in input {
		case enums.KeyCode:
			_ = enums.Push_Item_By_Value(L, en, "KeyCode", i64(key))
		case enums.UserInputType:
			_ = enums.Push_Item_By_Value(L, en, "UserInputType", i64(key))
		case enums.PlayerActions:
			_ = enums.Push_Item_By_Value(L, en, "PlayerActions", i64(key))
		}
		vm.SetArrayValue(L, -2, i + 1)
	}
	vm.SetField(L, -2, "inputTypes")
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
		methods = []string {
			"BindAction",
			"BindActionAtPriority",
			"UnbindAction",
			"UnbindAllActions",
			"GetBoundActionInfo",
			"GetAllBoundActionInfo",
			"SetActionBindings",
			"GetActionBindings",
			"ResetActionBindings",
			"ExportActionMap",
			"ImportActionMap",
		},
	)
}
