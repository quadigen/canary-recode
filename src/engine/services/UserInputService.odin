package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

UserInputService_Class := classes.Class_Info{name = "UserInputService", parent = &Service_Class}

UserInputService :: struct {
	using service: Service,
	accelerometer_enabled: bool,
}

user_input_service_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(UserInputService)
	service.service = Service_Init(&UserInputService_Class, "UserInputService", data_model)
	return &service.object
}

user_input_service_get :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool {
	service := cast(^UserInputService)object
	if key != "AccelerometerEnabled" { return false }
	vm.PushBoolean(L, service.accelerometer_enabled)
	return true
}

user_input_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^UserInputService)object)
}

Register_UserInputService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(registry, &UserInputService_Class, user_input_service_construct, user_input_service_destroy, creatable = false, get = user_input_service_get)
}
