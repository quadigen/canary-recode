package services
// wire:service


import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:fmt"
import "core:strings"

CHANGE_HISTORY_MAX_WAYPOINTS :: 256

ChangeHistoryService_Class := classes.Class_Info {
	name   = "ChangeHistoryService",
	parent = &Service_Class,
}

Change_History_Waypoint :: struct {
	name:         string,
	display_name: string,
}

Change_History_Recording :: struct {
	id:           string,
	name:         string,
	display_name: string,
}

Finish_Recording_Operation :: enum {
	Commit,
	Cancel,
	Append,
}


Change_History_Hook_Proc :: proc(service: ^ChangeHistoryService, waypoint: string, ctx: rawptr)

ChangeHistoryService :: struct {
	using service:         Service,
	enabled:               bool,
	undo_stack:            [dynamic]Change_History_Waypoint,
	redo_stack:            [dynamic]Change_History_Waypoint,
	recording:             Change_History_Recording,
	recording_active:      bool,
	recording_serial:      u64,
	on_undo_hook:          Change_History_Hook_Proc,
	on_redo_hook:          Change_History_Hook_Proc,
	hook_ctx:              rawptr,
	on_undo:               ^signals.Signal,
	on_redo:               ^signals.Signal,
	on_recording_started:  ^signals.Signal,
	on_recording_finished: ^signals.Signal,
}

changehistory_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ChangeHistoryService)
	service.service = Service_Init(&ChangeHistoryService_Class, "ChangeHistoryService", data_model)
	service.enabled = true
	return &service.object
}


change_history_free_waypoint :: proc(waypoint: Change_History_Waypoint) {
	delete(waypoint.name)
	delete(waypoint.display_name)
}

change_history_free_recording :: proc(recording: Change_History_Recording) {
	delete(recording.id)
	delete(recording.name)
	delete(recording.display_name)
}

change_history_clear_stack :: proc(stack: ^[dynamic]Change_History_Waypoint) {
	for waypoint in stack^ {
		change_history_free_waypoint(waypoint)
	}
	clear(stack)
}


change_history_push_waypoint :: proc(
	service: ^ChangeHistoryService,
	waypoint: Change_History_Waypoint,
) {
	change_history_clear_stack(&service.redo_stack)
	append(&service.undo_stack, waypoint)
	if len(service.undo_stack) > CHANGE_HISTORY_MAX_WAYPOINTS {
		change_history_free_waypoint(service.undo_stack[0])
		ordered_remove(&service.undo_stack, 0)
	}
}

change_history_signal_slot :: proc(
	service: ^ChangeHistoryService,
	key: string,
) -> ^^signals.Signal {
	switch key {
	case "OnUndo":
		return &service.on_undo
	case "OnRedo":
		return &service.on_redo
	case "OnRecordingStarted":
		return &service.on_recording_started
	case "OnRecordingFinished":
		return &service.on_recording_finished
	}
	return nil
}

change_history_ensure_signal :: proc(
	service: ^ChangeHistoryService,
	slot: ^^signals.Signal,
) -> ^signals.Signal {
	if service == nil || slot == nil {return nil}
	if slot^ != nil {return slot^}
	registry := service.signal_registry
	if registry == nil {return nil}
	L := registry.vm_state
	if L == nil || registry.signal_registry == nil {return nil}
	slot^ = signals.Create(registry.signal_registry)
	return slot^
}

change_history_signal_active :: proc(signal: ^signals.Signal) -> bool {
	return(
		signal != nil &&
		!signal.destroyed &&
		(len(signal.listeners) > 0 || len(signal.waiters) > 0) \
	)
}

change_history_push_optional_string :: proc(L: ^vm.State, value: string) {
	if value == "" {
		vm.PushNil(L)
	} else {
		vm.PushString(L, value)
	}
}


change_history_arg_operation :: proc(L: ^vm.State, index: int) -> Finish_Recording_Operation {
	text := vm.DisplayString(L, i32(index))
	defer delete(text)

	dot := strings.last_index_byte(text, '.')
	name := dot >= 0 ? text[dot + 1:] : text

	switch name {
	case "Commit":
		return .Commit
	case "Cancel":
		return .Cancel
	case "Append":
		return .Append
	}
	_ = vm.RaiseError(L, "invalid FinishRecordingOperation")
	return .Commit
}


changehistory_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^ChangeHistoryService)object
	switch key {
	case "OnUndo", "OnRedo", "OnRecordingStarted", "OnRecordingFinished":
		signal := change_history_ensure_signal(service, change_history_signal_slot(service, key))
		if signal == nil {return false}
		signals.Push(L, signal)
	case "SetWaypoint",
	     "Undo",
	     "Redo",
	     "GetCanUndo",
	     "GetCanRedo",
	     "ResetWaypoints",
	     "SetEnabled",
	     "TryBeginRecording",
	     "FinishRecording",
	     "IsRecordingInProgress":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}


changehistory_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^ChangeHistoryService)object
	switch method {
	case "SetWaypoint":
		name := vm.ArgString(L, 2)
		if !service.enabled {return 0, true}
		change_history_push_waypoint(
			service,
			Change_History_Waypoint {
				name = strings.clone(name),
				display_name = strings.clone(name),
			},
		)
		return 0, true

	case "Undo":
		if len(service.undo_stack) == 0 {return 0, true}
		waypoint := pop(&service.undo_stack)
		append(&service.redo_stack, waypoint)

		if service.on_undo_hook != nil {
			service.on_undo_hook(service, waypoint.name, service.hook_ctx)
		}
		if change_history_signal_active(service.on_undo) {
			vm.PushString(L, waypoint.name)
			signals.Fire(L, service.on_undo, 1)
		}
		return 0, true

	case "Redo":
		if len(service.redo_stack) == 0 {return 0, true}
		waypoint := pop(&service.redo_stack)
		append(&service.undo_stack, waypoint)

		if service.on_redo_hook != nil {
			service.on_redo_hook(service, waypoint.name, service.hook_ctx)
		}
		if change_history_signal_active(service.on_redo) {
			vm.PushString(L, waypoint.name)
			signals.Fire(L, service.on_redo, 1)
		}
		return 0, true

	case "GetCanUndo":
		if len(service.undo_stack) == 0 {
			vm.PushBoolean(L, false)
			return 1, true
		}
		vm.PushBoolean(L, true)
		vm.PushString(L, service.undo_stack[len(service.undo_stack) - 1].name)
		return 2, true

	case "GetCanRedo":
		if len(service.redo_stack) == 0 {
			vm.PushBoolean(L, false)
			return 1, true
		}
		vm.PushBoolean(L, true)
		vm.PushString(L, service.redo_stack[len(service.redo_stack) - 1].name)
		return 2, true

	case "ResetWaypoints":
		change_history_clear_stack(&service.undo_stack)
		change_history_clear_stack(&service.redo_stack)
		return 0, true

	case "SetEnabled":
		service.enabled = vm.ArgBoolean(L, 2)
		return 0, true

	case "TryBeginRecording":
		name := vm.ArgString(L, 2)
		display_name := vm.ArgOptionalString(L, 3)
		if !service.enabled || service.recording_active {
			vm.PushNil(L)
			return 1, true
		}

		service.recording_serial += 1
		service.recording = Change_History_Recording {
			id           = fmt.aprintf("HistoryRecording_%d", service.recording_serial),
			name         = strings.clone(name),
			display_name = strings.clone(display_name != "" ? display_name : name),
		}
		service.recording_active = true


		id := strings.clone(service.recording.id, context.temp_allocator)

		if change_history_signal_active(service.on_recording_started) {
			vm.PushString(L, service.recording.name)
			change_history_push_optional_string(L, service.recording.display_name)
			signals.Fire(L, service.on_recording_started, 2)
		}

		vm.PushString(L, id)
		return 1, true

	case "FinishRecording":
		id := vm.ArgString(L, 2)
		operation := change_history_arg_operation(L, 3)
		if !service.recording_active || service.recording.id != id {
			return vm.RaiseError(L, "invalid recording identifier"), true
		}

		recording := service.recording
		service.recording = {}
		service.recording_active = false


		fire := change_history_signal_active(service.on_recording_finished)
		if fire {
			vm.PushString(L, recording.name)
			change_history_push_optional_string(L, recording.display_name)
			vm.PushString(L, recording.id)
			vm.PushString(
				L,
				operation == .Commit ? "Commit" : operation == .Cancel ? "Cancel" : "Append",
			)
			if vm.IsTable(L, 4) {vm.PushValue(L, 4)} else {vm.PushNil(L)}
		}

		switch operation {
		case .Commit:
			change_history_push_waypoint(
				service,
				Change_History_Waypoint {
					name = recording.name,
					display_name = recording.display_name,
				},
			)
			delete(recording.id)

		case .Cancel:
			change_history_free_recording(recording)

		case .Append:
			if len(service.undo_stack) > 0 {

				change_history_clear_stack(&service.redo_stack)
				change_history_free_recording(recording)
			} else {
				change_history_push_waypoint(
					service,
					Change_History_Waypoint {
						name = recording.name,
						display_name = recording.display_name,
					},
				)
				delete(recording.id)
			}
		}

		if fire {
			signals.Fire(L, service.on_recording_finished, 5)
		}
		return 0, true

	case "IsRecordingInProgress":
		if vm.IsNoneOrNil(L, 2) {
			vm.PushBoolean(L, service.recording_active)
		} else {
			id := vm.ArgString(L, 2)
			vm.PushBoolean(L, service.recording_active && service.recording.id == id)
		}
		return 1, true
	}
	return 0, false
}

changehistory_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^ChangeHistoryService)object
	change_history_clear_stack(&service.undo_stack)
	change_history_clear_stack(&service.redo_stack)
	delete(service.undo_stack)
	delete(service.redo_stack)
	if service.recording_active {
		change_history_free_recording(service.recording)
	}
	classes.Object_Destroy(object)
	free(service)
}

Register_ChangeHistoryService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ChangeHistoryService_Class,
		changehistory_construct,
		changehistory_destroy,
		creatable = false,
		get = changehistory_get,
		namecall = changehistory_namecall,
		methods = []string {
			"SetWaypoint",
			"Undo",
			"Redo",
			"GetCanUndo",
			"GetCanRedo",
			"ResetWaypoints",
			"SetEnabled",
			"TryBeginRecording",
			"FinishRecording",
			"IsRecordingInProgress",
		},
		events = []string{"OnUndo", "OnRedo", "OnRecordingStarted", "OnRecordingFinished"},
	)
}
