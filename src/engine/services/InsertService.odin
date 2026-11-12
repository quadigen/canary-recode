package services

// wire:service

import assetstore "../assetstore"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:strings"

InsertService_Class := classes.Class_Info {
	name   = "InsertService",
	parent = &Service_Class,
}

insert_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Service)
	service^ = Service_Init(&InsertService_Class, "InsertService", data_model)
	return &service.object
}

insert_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Service)object)
}

insert_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	if key != "CreateMeshPartAsync" {return false}
	vm.PushUserdataMethod(L, key)
	return true
}

insert_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "CreateMeshPartAsync" {return 0, false}
	mesh_id := vm.ArgString(L, 2)
	collision := enums.Arg_Item(L, 3, en, "CollisionFidelity")
	_ = enums.Arg_Item(L, 4, en, "RenderFidelity")
	if !insert_mesh_available(mesh_id) {
		return vm.RaiseError(L, "mesh asset is unavailable"), true
	}

	registry := object.signal_registry
	mesh, ok := classes.Push_New(registry, &vm.VM{L = L}, "MeshPart")
	if !ok {return vm.RaiseError(L, "could not create MeshPart"), true}
	part := cast(^classes.MeshPart)mesh
	part.mesh_id = strings.clone(mesh_id)
	part.collision_fidelity = enums.CollisionFidelity(collision.value)
	descriptor := classes.Find_Class(registry, "MeshPart")
	_ = classes.descriptor_set(L, mesh, descriptor, "RenderFidelity", 4)
	return 1, true
}

insert_mesh_available :: proc(mesh_id: string) -> bool {
	if bytes, found := assetstore.Resolve_Bytes(mesh_id); found {return len(bytes) != 0}
	if !strings.has_prefix(mesh_id, assetstore.PROJECT_ASSET_SCHEME) {return false}
	path := assetstore.Resolve_Path(mesh_id)
	defer delete(path)
	bytes, found := assetstore.Read_Asset_File(path)
	defer delete(bytes)
	return found && len(bytes) != 0
}

Register_InsertService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&InsertService_Class,
		insert_service_construct,
		insert_service_destroy,
		creatable = false,
		get = insert_service_get,
		namecall = insert_service_namecall,
		methods = []string{"CreateMeshPartAsync"},
	)
}
