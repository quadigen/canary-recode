package services

// wire:service global="logService"

import "core:fmt"

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

        service.message_count += 1

        fmt.println(message)

        return 0, true

    case "Info":
        message := vm.ArgString(L, 2)

        service.message_count += 1
        service.info_count += 1

        fmt.printf("[INFO] %s\n", message)

        return 0, true

    case "Warn":
        message := vm.ArgString(L, 2)

        service.message_count += 1
        service.warning_count += 1

        fmt.eprintf("[WARN] %s\n", message)

        return 0, true

    case "Error":
        message := vm.ArgString(L, 2)

        service.message_count += 1
        service.error_count += 1

        fmt.eprintf("[ERROR] %s\n", message)

        return 0, true

    case "Clear":
        service.message_count = 0
        service.info_count = 0
        service.warning_count = 0
        service.error_count = 0

        return 0, true
    case "GetLogHistory":
        vm.NewTable(L, len(service.history), 0)

        for entry, i in service.history {
            vm.NewTable(L, 0, 3)

            vm.PushString(L, string(entry.message))
            vm.SetField(L, -2, "message")

            vm.PushString(L, entry.log_type)
            vm.SetField(L, -2, "type")

            vm.PushInteger(L, entry.timestamp)
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