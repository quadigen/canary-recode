package services

import classes "../classes"

Service_Class := classes.Class_Info{
	name   = "Service",
	parent = &classes.Instance_Class,
}

Service :: struct {
	using object: classes.Object,
	data_model: ^DataModel,
}

Service_Init :: proc(class: ^classes.Class_Info, name: string, data_model: rawptr) -> Service {
	return Service{
		object = classes.Object_Init(class, name),
		data_model = cast(^DataModel)data_model,
	}
}

Service_Get_Service :: proc(service: ^Service, name: string) -> ^classes.Object {
	if service == nil { return nil }
	return DataModel_Get_Service(service.data_model, name)
}

service_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(Service)
	service^ = Service_Init(&Service_Class, "Service", data_model)
	return &service.object
}

service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Service)object)
}

Register_Service_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(registry, &Service_Class, service_construct, service_destroy, creatable = false)
}
