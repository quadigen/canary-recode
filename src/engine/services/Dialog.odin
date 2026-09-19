package services

// wire:service global="DialogService"

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:sync"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import sdl3 "../platform"
import vm "../vm"

DIALOG_INTERNALS_CAPABILITY :: i64(2)

DialogService_Class := classes.Class_Info {
	name   = "DialogService",
	parent = &Service_Class,
}

DialogService :: struct {
	using service: Service,

	renderer: ^classes.Renderer_Object,

	mutex: sync.Mutex,

	pending:   bool,
	completed: bool,
	cancelled: bool,
	failed:    bool,

	result_path:      string,
	default_location: cstring,

	thread:     ^vm.State,
	thread_ref: i32,
}

dialog_folder_callback :: proc "c" (
	userdata: rawptr,
	filelist: [^]cstring,
	filter: i32,
) {
	context = runtime.default_context()

	service := cast(^DialogService)userdata
	if service == nil {
		return
	}

	sync.mutex_lock(&service.mutex)
	defer sync.mutex_unlock(&service.mutex)

	if len(service.result_path) > 0 {
		delete(service.result_path)
		service.result_path = ""
	}

	if service.default_location != nil {
		delete(service.default_location)
		service.default_location = nil
	}

	service.completed = true
	service.cancelled = false
	service.failed = false

	if filelist == nil {
		service.failed = true
		return
	}

	if filelist[0] == nil {
		service.cancelled = true
		return
	}

	service.result_path = strings.clone(string(filelist[0]))
}

DialogService_PickFolder :: proc(
	L: ^vm.State,
	service: ^DialogService,
	default_location: string,
) -> i32 {
	if service == nil || service.destroyed {
		return vm.RaiseError(L, "DialogService is unavailable")
	}

	if !vm.IsYieldable(L) {
		return vm.RaiseError(
			L,
			"DialogService:PickFolder() must be called from a yieldable thread",
		)
	}

	sync.mutex_lock(&service.mutex)

	if service.pending {
		sync.mutex_unlock(&service.mutex)

		return vm.RaiseError(
			L,
			"DialogService already has an open dialog",
		)
	}

	if len(service.result_path) > 0 {
		delete(service.result_path)
		service.result_path = ""
	}

	if service.default_location != nil {
		delete(service.default_location)
		service.default_location = nil
	}

	if len(default_location) > 0 {
		service.default_location = strings.clone_to_cstring(default_location)
	}

	service.pending = true
	service.completed = false
	service.cancelled = false
	service.failed = false

	service.thread = L

	vm.PushCurrentThread(L)
	service.thread_ref = vm.RetainValue(L)
	vm.Pop(L)

	window: ^sdl3.Window = nil

	if service.renderer != nil {
		window = service.renderer.Window
	}

	location := service.default_location

	sync.mutex_unlock(&service.mutex)

	sdl3.ShowOpenFolderDialog(
		dialog_folder_callback,
		service,
		window,
		location,
		false,
	)

	return vm.YieldThread(L)
}

dialog_service_step :: proc(
	object: ^classes.Object,
	ctx: ^classes.Class_Step_Context,
) {
	service := cast(^DialogService)object

	if service == nil || ctx == nil || ctx.L == nil {
		return
	}

	sync.mutex_lock(&service.mutex)

	if !service.pending || !service.completed {
		sync.mutex_unlock(&service.mutex)
		return
	}

	thread := service.thread
	thread_ref := service.thread_ref

	cancelled := service.cancelled
	failed := service.failed

	path := service.result_path

	service.result_path = ""

	service.pending = false
	service.completed = false
	service.cancelled = false
	service.failed = false

	service.thread = nil
	service.thread_ref = 0

	sync.mutex_unlock(&service.mutex)

	if thread == nil {
		if len(path) > 0 {
			delete(path)
		}

		if thread_ref > 0 {
			vm.ReleaseValue(ctx.L, thread_ref)
		}

		return
	}

	if !cancelled && !failed && len(path) > 0 {
		vm.PushString(thread, path)
	} else {
		vm.PushNil(thread)
	}

	_, _, err := vm.ResumeThread(
		thread,
		ctx.L,
		1,
	)

	if thread_ref > 0 {
		vm.ReleaseValue(ctx.L, thread_ref)
	}

	if len(path) > 0 {
		delete(path)
	}

	if err != "" {
		fmt.eprintf(
			"DialogService coroutine failed: %s\n",
			err,
		)

		delete(err)
	}
}

dialog_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(DialogService)

	service.service = Service_Init(
		&DialogService_Class,
		"DialogService",
		data_model,
	)

	service.renderer = renderer

	return &service.object
}

dialog_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "PickFolder":
		if !vm.ThreadHasSecurityCapability(
			L,
			DIALOG_INTERNALS_CAPABILITY,
		) {
			return false
		}

		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}

dialog_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^DialogService)object

	switch method {
	case "PickFolder":
		if !vm.ThreadHasSecurityCapability(
			L,
			DIALOG_INTERNALS_CAPABILITY,
		) {
			return vm.RaiseError(
				L,
				"DialogService:PickFolder() requires Internals capability",
			), true
		}

		default_location := vm.ArgOptionalString(
			L,
			2,
			"",
		)

		return DialogService_PickFolder(
			L,
			service,
			default_location,
		), true
	}

	return 0, false
}

dialog_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	service := cast(^DialogService)object

	sync.mutex_lock(&service.mutex)

	if len(service.result_path) > 0 {
		delete(service.result_path)
		service.result_path = ""
	}

	if service.default_location != nil {
		delete(service.default_location)
		service.default_location = nil
	}

	sync.mutex_unlock(&service.mutex)

	classes.Object_Destroy(object)
	free(service)
}

Register_DialogService_Class :: proc(
	registry: ^classes.Registry,
) {
	classes.Register_Class(
		registry,
		&DialogService_Class,
		dialog_service_construct,
		dialog_service_destroy,
		creatable = false,
		get = dialog_service_get,
		namecall = dialog_service_namecall,
		_step = dialog_service_step,
		_step_phase = .Update,
	)
}