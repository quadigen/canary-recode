package services

// wire:service global="logService"

import "core:fmt"
import "core:strings"
import "base:runtime"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:bytes"
import "core:time"

LogService_Class := classes.Class_Info{
    name   = "LogService",
    parent = &Service_Class,
}

LogService :: struct {
    using service: Service,

    message_count: i64,
    info_count:    i64,
    warning_count: i64,
    error_count:   i64,
    history: [dynamic]LogEntry,
}

LOG_HISTORY_LIMIT :: 1000

LogEntry :: struct {
	message:   []u8,
	log_type:  string,
	timestamp: i64,
}

log_service_add_entry :: proc(
	service: ^LogService,
	message: string,
	log_type: string,
) {
	append(&service.history, LogEntry{
		message   = bytes.clone(transmute([]u8)message),
		log_type  = log_type,
		timestamp = time.to_unix_seconds(time.now()),
	})

	if len(service.history) > LOG_HISTORY_LIMIT {
		overflow := len(service.history) - LOG_HISTORY_LIMIT
		for index in 0 ..< overflow {
			delete(service.history[index].message)
		}
		remove_range(&service.history, 0, overflow)
	}
}

log_service_write :: proc(
	service: ^LogService,
	message: string,
	log_type: string,
) {
	if service == nil {
		return
	}
	service.message_count += 1
	switch log_type {
	case "Info":
		service.info_count += 1
	case "Warn":
		service.warning_count += 1
	case "Error":
		service.error_count += 1
	}
	log_service_add_entry(service, message, log_type)
	switch log_type {
	case "Info":
		fmt.printf("[INFO] %s\n", message)
	case "Warn":
		fmt.eprintf("[WARN] %s\n", message)
	case "Error":
		fmt.eprintf("[ERROR] %s\n", message)
	case:
		fmt.println(message)
	}
}

log_service_luau_print :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	registry := cast(^Registry)vm.UpvaluePointer(L)
	if registry == nil {
		return 0
	}
	service_descriptor := Find_Service(registry, "LogService")
	if service_descriptor == nil {
		return 0
	}
	service := cast(^LogService)Ensure_Service(registry, "LogService")
	if service == nil {
		return 0
	}
	parts: [dynamic]string
	for index := 1; index <= vm.StackTop(L); index += 1 {
		append(&parts, vm.DisplayString(L, i32(index)))
	}
	message := strings.concatenate(parts[:])
	delete(parts)
	log_service_write(service, message, "Log")
	return 0
}

log_service_luau_warn :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	registry := cast(^Registry)vm.UpvaluePointer(L)
	if registry == nil {
		return 0
	}
	service := cast(^LogService)Ensure_Service(registry, "LogService")
	if service == nil {
		return 0
	}
	parts: [dynamic]string
	for index := 1; index <= vm.StackTop(L); index += 1 {
		append(&parts, vm.DisplayString(L, i32(index)))
	}
	message := strings.concatenate(parts[:])
	delete(parts)
	log_service_write(service, message, "Warn")
	return 0
}

Install_Log_Globals :: proc(registry: ^Registry, vm_state: ^vm.VM) {
	vm.PushLightUserdata(vm_state.L, registry)
	vm.PushFunction(vm_state.L, "print", log_service_luau_print, 1)
	vm.SetGlobalFromStack(vm_state, "print")
	vm.PushLightUserdata(vm_state.L, registry)
	vm.PushFunction(vm_state.L, "warn", log_service_luau_warn, 1)
	vm.SetGlobalFromStack(vm_state, "warn")
}

log_service_clear_history :: proc(service: ^LogService) {
	for entry in service.history {
		delete(entry.message)
	}

	delete(service.history)
	service.history = nil
}

log_service_construct :: proc(
    renderer: ^classes.Renderer_Object,
    data_model: rawptr,
) -> ^classes.Object {
    service := new(LogService)

    service.service = Service_Init(
        &LogService_Class,
        "LogService",
        data_model,
    )

    return &service.object
}

log_service_get :: proc(
    L: ^vm.State,
    object: ^classes.Object,
    datatype_registry: ^datatypes.Registry,
    enum_registry: ^enums.Registry,
    key: string,
) -> bool {
    service := cast(^LogService)object

    switch key {
    case "MessageCount":
        vm.PushNumber(L, f64(service.message_count))

    case "InfoCount":
        vm.PushNumber(L, f64(service.info_count))

    case "WarningCount":
        vm.PushNumber(L, f64(service.warning_count))

    case "ErrorCount":
        vm.PushNumber(L, f64(service.error_count))

    case "Log", "Info", "Warn", "Error", "Clear", "GetLogHistory":
	    vm.PushUserdataMethod(L, key)

    case:
        return false
    }

    return true
}

log_service_namecall :: proc(
    L: ^vm.State,
    object: ^classes.Object,
    datatype_registry: ^datatypes.Registry,
    enum_registry: ^enums.Registry,
    method: string,
) -> (i32, bool) {
    service := cast(^LogService)object

    switch method {
    case "Log":
        message := vm.ArgString(L, 2)
        log_service_write(service, message, "Log")
        return 0, true

    case "Info":
        message := vm.ArgString(L, 2)

        log_service_write(service, message, "Info")
        return 0, true

    case "Warn":
        message := vm.ArgString(L, 2)

        log_service_write(service, message, "Warn")
        return 0, true

    case "Error":
        message := vm.ArgString(L, 2)

        log_service_write(service, message, "Error")
        return 0, true

    case "Clear":
        service.message_count = 0
        service.info_count = 0
        service.warning_count = 0
        service.error_count = 0
        log_service_clear_history(service)

        return 0, true
    case "GetLogHistory":
        vm.NewTable(L, len(service.history), 0)

        for entry, i in service.history {
            vm.NewTable(L, 0, 3)

            vm.PushString(L, string(entry.message))
            vm.SetField(L, -2, "message")

            vm.PushString(L, entry.log_type)
            vm.SetField(L, -2, "type")

            vm.PushNumber(L, f64(entry.timestamp))
            vm.SetField(L, -2, "timestamp")

            vm.RawSetIndex(L, -2, i + 1)
        }

        return 1, true
    }

    return 0, false
}

log_service_destroy :: proc(
    object: ^classes.Object,
    renderer: ^classes.Renderer_Object,
) {
    log_service_clear_history(cast(^LogService)object)
    classes.Object_Destroy(object)
    free(cast(^LogService)object)
}

Register_LogService_Class :: proc(registry: ^classes.Registry) {
    classes.Register_Class(
        registry,
        &LogService_Class,
        log_service_construct,
        log_service_destroy,
        creatable = false,
        get       = log_service_get,
        namecall  = log_service_namecall,
    )
}