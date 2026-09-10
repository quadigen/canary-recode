package services

// wire:service global="Selection"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Selection_Class := classes.Class_Info{
	name   = "Selection",
	parent = &Service_Class,
}

Selection :: struct {
	using service: Service,

	selected:              [dynamic]^classes.Object,
	selection_changed_ref: i32,
}

selection_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	selection := new(Selection)
	selection.service = Service_Init(&Selection_Class, "Selection", data_model)
	selection.selection_changed_ref = -1
	return &selection.object
}

selection_contains :: proc(items: []^classes.Object, object: ^classes.Object) -> bool {
	for item in items {
		if item == object {
			return true
		}
	}
	return false
}

selection_index_of :: proc(items: []^classes.Object, object: ^classes.Object) -> int {
	for item, index in items {
		if item == object {
			return index
		}
	}
	return -1
}

selection_equal :: proc(a, b: []^classes.Object) -> bool {
	if len(a) != len(b) {
		return false
	}
	for item, index in a {
		if item != b[index] {
			return false
		}
	}
	return true
}

selection_object_from_argument :: proc(L: ^vm.State, index: int) -> ^classes.Object {
	binding := vm.UserdataBindingOf(L, index)
	if binding == nil || binding.name != "Instance" {
		return nil
	}
	return cast(^classes.Object)vm.UserdataValue(L, index)
}

selection_read_instances :: proc(
	L: ^vm.State,
	index: int,
) -> (result: [dynamic]^classes.Object, ok: bool) {
	if !vm.IsTable(L, index) {
		return nil, false
	}

	count := vm.RawLen(L, index)
	for array_index := 1; array_index <= count; array_index += 1 {
		_ = vm.RawGetIndex(L, index, array_index)
		object := selection_object_from_argument(L, -1)
		vm.Pop(L)

		if object == nil || object.destroyed {
			delete(result)
			return nil, false
		}

		if !selection_contains(result[:], object) {
			append(&result, object)
		}
	}

	return result, true
}

selection_push_instances :: proc(L: ^vm.State, items: []^classes.Object) {
	vm.NewTable(L, len(items))
	for item, index in items {
		classes.Push_Object(L, item)
		vm.SetArrayValue(L, -2, index+1)
	}
}

selection_ensure_changed_signal :: proc(L: ^vm.State, selection: ^Selection) -> bool {
	if selection.selection_changed_ref > 0 {
		return true
	}

	stack_top := vm.StackTop(L)
	defer vm.SetStackTop(L, stack_top)

	if vm.GetGlobal(L, "Signal") != .Table {
		return false
	}
	if vm.GetField(L, -1, "new") != .Function {
		return false
	}

	ok, err := vm.ProtectedCall(L, 0, 1)
	if !ok {
		if err != "" {
			delete(err)
		}
		return false
	}

	selection.selection_changed_ref = vm.RetainValue(L)
	return selection.selection_changed_ref > 0
}

selection_fire_changed :: proc(L: ^vm.State, selection: ^Selection) {
	if !selection_ensure_changed_signal(L, selection) {
		return
	}

	stack_top := vm.StackTop(L)
	defer vm.SetStackTop(L, stack_top)

	vm.PushRegistryReference(L, selection.selection_changed_ref)
	signal_index := vm.StackTop(L)

	if vm.GetField(L, signal_index, "Fire") != .Function {
		return
	}

	vm.PushValue(L, signal_index)
	ok, err := vm.ProtectedCall(L, 1, 0)
	if !ok && err != "" {
		delete(err)
	}
}

Selection_Get :: proc(selection: ^Selection) -> []^classes.Object {
	if selection == nil {
		return nil
	}
	return selection.selected[:]
}

Selection_Set :: proc(
	selection: ^Selection,
	L: ^vm.State,
	items: []^classes.Object,
) -> bool {
	if selection == nil {
		return false
	}

	next: [dynamic]^classes.Object
	for item in items {
		if item == nil || item.destroyed {
			continue
		}
		if !selection_contains(next[:], item) {
			append(&next, item)
		}
	}

	if selection_equal(selection.selected[:], next[:]) {
		delete(next)
		return false
	}

	delete(selection.selected)
	selection.selected = next

	if L != nil {
		selection_fire_changed(L, selection)
	}
	return true
}

Selection_Add :: proc(
	selection: ^Selection,
	L: ^vm.State,
	items: []^classes.Object,
) -> bool {
	if selection == nil {
		return false
	}

	changed := false
	for item in items {
		if item == nil || item.destroyed || selection_contains(selection.selected[:], item) {
			continue
		}
		append(&selection.selected, item)
		changed = true
	}

	if changed && L != nil {
		selection_fire_changed(L, selection)
	}
	return changed
}

Selection_Remove :: proc(
	selection: ^Selection,
	L: ^vm.State,
	items: []^classes.Object,
) -> bool {
	if selection == nil {
		return false
	}

	changed := false
	for item in items {
		for {
			index := selection_index_of(selection.selected[:], item)
			if index < 0 {
				break
			}
			ordered_remove(&selection.selected, index)
			changed = true
		}
	}

	if changed && L != nil {
		selection_fire_changed(L, selection)
	}
	return changed
}

Selection_Clear :: proc(selection: ^Selection, L: ^vm.State) -> bool {
	if selection == nil || len(selection.selected) == 0 {
		return false
	}

	clear(&selection.selected)
	if L != nil {
		selection_fire_changed(L, selection)
	}
	return true
}

selection_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	selection := cast(^Selection)object

	switch key {
	case "SelectionThickness":
		vm.PushNumber(L, 0.02)

	case "SelectionChanged":
		if selection_ensure_changed_signal(L, selection) {
			vm.PushRegistryReference(L, selection.selection_changed_ref)
		} else {
			vm.PushNil(L)
		}

	case "Get", "Set", "Add", "Remove":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}

selection_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	selection := cast(^Selection)object

	switch method {
	case "Get":
		selection_push_instances(L, selection.selected[:])
		return 1, true

	case "Set":
		items, ok := selection_read_instances(L, 2)
		if !ok {
			return vm.RaiseError(L, "Selection:Set expects an array of Instances"), true
		}
		defer delete(items)
		_ = Selection_Set(selection, L, items[:])
		return 0, true

	case "Add":
		items, ok := selection_read_instances(L, 2)
		if !ok {
			return vm.RaiseError(L, "Selection:Add expects an array of Instances"), true
		}
		defer delete(items)
		_ = Selection_Add(selection, L, items[:])
		return 0, true

	case "Remove":
		items, ok := selection_read_instances(L, 2)
		if !ok {
			return vm.RaiseError(L, "Selection:Remove expects an array of Instances"), true
		}
		defer delete(items)
		_ = Selection_Remove(selection, L, items[:])
		return 0, true
	}

	return 0, false
}

selection_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	selection := cast(^Selection)object

	if selection.selection_changed_ref > 0 &&
	   selection.data_model != nil &&
	   selection.data_model.registry != nil &&
	   selection.data_model.registry.vm_state != nil &&
	   selection.data_model.registry.vm_state.L != nil {
		vm.ReleaseValue(
			selection.data_model.registry.vm_state.L,
			selection.selection_changed_ref,
		)
	}

	selection.selection_changed_ref = -1
	delete(selection.selected)
	selection.selected = nil

	classes.Object_Destroy(object)
	free(selection)
}

Register_Selection_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Selection_Class,
		selection_construct,
		selection_destroy,
		creatable = false,
		get = selection_get,
		namecall = selection_namecall,
	)
}
