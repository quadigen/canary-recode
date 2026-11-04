#+build !js

package services

// wire:service global="ExportService"

import "core:fmt"
import "core:path/filepath"
import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import serializer "../serializer"
import tracy "../util/odin-tracy"
import vm "../vm"
import strings "core:strings"

ExportService_Class := classes.Class_Info {
	name   = "ExportService",
	parent = &Service_Class,
}

ExportService :: struct {
	using service: Service,
}

export_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ExportService)
	service.service = Service_Init(&ExportService_Class, "ExportService", data_model)
	return &service.object
}

export_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^ExportService)object)
}

export_datamodel_to_file :: proc(service: ^ExportService, L: ^vm.State, path: string) -> serializer.Error {
	if path == "" {
		return serializer.Error_Make(.Invalid_Argument, -1, "the service, VM, or destination path is missing")
	}
	data, err := export_datamodel_snapshot(service, L)
	if !serializer.Error_Is_None(err) {return err}
	defer delete(data)
	tracy.ZoneNC("KINE Compress and Write", 0xD19A66)
	return serializer.Write_File_Data(path, data)
}

export_datamodel_snapshot :: proc(service: ^ExportService, L: ^vm.State) -> ([]u8, serializer.Error) {
	tracy.ZoneNC("KINE Scene Snapshot", 0xD19A66)
	if service == nil || L == nil {
		return nil, serializer.Error_Make(.Invalid_Argument, -1, "the service or VM is missing")
	}
	model := service.data_model
	if model == nil || model.registry == nil || model.registry.classes == nil {
		return nil, serializer.Error_Make(.Invalid_Argument, -1, "the ExportService has no DataModel registry")
	}

	// Terrain is a singleton service rather than an Instance, so the tree walk
	// never reaches it. Its voxel grid travels in the format's own section
	// instead, which is why a map edited with terrain still saves it.
	terrain_table: serializer.Kine_Terrain
	defer serializer.Kine_Terrain_Destroy(&terrain_table)
	terrain_object := DataModel_Get_Service(model, "Terrain")
	if terrain_object != nil {
		tracy.ZoneNC("KINE Collect Terrain Cells", 0xD19A66)
		Terrain_Write_Kine_Table(cast(^Terrain)terrain_object, &terrain_table)
	}

	return serializer.Serialize(
		model.registry.classes,
		L,
		&model.object,
		export_content_service_filter,
		&terrain_table,
	)
}

export_content_service_filter :: proc(parent: ^classes.Object, object: ^classes.Object) -> bool {
	if object == nil || object.class == nil {
		return true
	}

	if parent == nil || !classes.Is_A(parent, "DataModel") {
		return false
	}
	if !classes.Is_A(object, "Service") {
		return false
	}
	return !Map_Content_Service(object.name)
}

export_object_to_file :: proc(service: ^ExportService, L: ^vm.State, object: ^classes.Object, path: string) -> serializer.Error {
	if service == nil || L == nil || object == nil || path == "" {
		return serializer.Error_Make(.Invalid_Argument, -1, "the service, VM, instance, or destination path is missing")
	}
	model := service.data_model
	if model == nil || model.registry == nil || model.registry.classes == nil {
		return serializer.Error_Make(.Invalid_Argument, -1, "the ExportService has no DataModel registry")
	}
	return serializer.Serialize_To_File(model.registry.classes, L, object, path)
}

export_raise :: proc(L: ^vm.State, method: string, err: ^serializer.Error) -> (i32, bool) {
	detail := serializer.Error_String(err^)
	serializer.Error_Delete(err)
	message := strings.clone(fmt.tprintf("ExportService:%s failed: %s", method, detail))
	delete(detail)
	return vm.RaiseOwnedError(L, &message), true
}

export_object_from_argument :: proc(L: ^vm.State, index: int) -> ^classes.Object {
	binding := vm.UserdataBindingOf(L, index)
	if binding == nil || binding.name != "Instance" {
		return nil
	}
	object := cast(^classes.Object)vm.UserdataValue(L, index)
	if !classes.Object_Is_Accessible(L, object) {
		return nil
	}
	return object
}

export_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "ExportToFile", "Export", "ImportFile":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

export_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
service := cast(^ExportService)object
	switch method {
	case "ExportToFile":
		path := vm.ArgString(L, 2)
		if path == "" {
			return vm.RaiseError(L, "ExportService:ExportToFile expects a file path"), true
		}
		err := export_datamodel_to_file(service, L, path)
		if !serializer.Error_Is_None(err) {
			return export_raise(L, method, &err)
		}
		serializer.Error_Delete(&err)
		vm.PushBoolean(L, true)
		return 1, true
	case "Export":
		target := export_object_from_argument(L, 2)
		if target == nil {
			return vm.RaiseError(L, "ExportService:Export expects an Instance"), true
		}
		path := vm.ArgString(L, 3)
		if path == "" {
			return vm.RaiseError(L, "ExportService:Export expects a file path"), true
		}
		err := export_object_to_file(service, L, target, path)
		if !serializer.Error_Is_None(err) {
			return export_raise(L, method, &err)
		}
		serializer.Error_Delete(&err)
		vm.PushBoolean(L, true)
		return 1, true
	case "ImportFile":
		path := vm.ArgString(L, 2)
		if path == "" {
			return vm.RaiseError(L, "ExportService:ImportFile expects a file path"), true
		}
		model := service.data_model
		if model == nil ||
		   model.registry == nil ||
		   model.registry.classes == nil {
			return vm.RaiseError(L, "ExportService:ImportFile has no DataModel"), true
		}
		extension := filepath.ext(path)
		switch {
		case strings.equal_fold(extension, ".fbx"),
		     strings.equal_fold(extension, ".obj"),
		     strings.equal_fold(extension, ".glb"),
		     strings.equal_fold(extension, ".gltf"),
		     strings.equal_fold(extension, ".dae"),
		     strings.equal_fold(extension, ".blend"),
		     strings.equal_fold(extension, ".3mf"),
		     strings.equal_fold(extension, ".ply"),
		     strings.equal_fold(extension, ".stl"):
			if message := export_import_mesh_file(L, model.registry.classes, path); message != "" {
				return vm.RaiseError(L, message), true
			}
			return 1, true
		}
		imported, err := serializer.Deserialize_From_File(
			model.registry.classes,
			L,
			service,
			path,
		)
		if imported == nil || !serializer.Error_Is_None(err) {
			return export_raise(L, method, &err)
		}
		serializer.Error_Delete(&err)
		classes.Push_Object(L, imported)
		return 1, true
	}
	return 0, false
}

export_import_mesh_file :: proc(L: ^vm.State, registry: ^classes.Registry, path: string) -> string {
	absolute, path_err := filepath.abs(path)
	if path_err != nil {
		return "ExportService:ImportFile could not resolve the model path"
	}
	defer delete(absolute)
	c_path := strings.clone_to_cstring(absolute)
	defer delete(c_path)
	meshes := kineffi.Kine_Filament_ListMeshes(c_path)
	if meshes == nil {
		return "ExportService:ImportFile could not read any triangle meshes"
	}
	defer kineffi.Kine_Filament_DestroyMeshList(meshes)

	model, ok := classes.Push_New(registry, &vm.VM{L = L}, "Model", false)
	if !ok || model == nil {
		return "ExportService:ImportFile could not create a Model"
	}
	name := filepath.base(path)
	classes.Set_Name(model, name[:len(name) - len(filepath.ext(name))])
	count := kineffi.Kine_Filament_GetMeshListCount(meshes)
	for index in 1 ..= count {
		object, part_ok := classes.Push_New(registry, &vm.VM{L = L}, "MeshPart", false)
		if !part_ok || object == nil {
			classes.Destroy_Hierarchy(model)
			return "ExportService:ImportFile could not create a MeshPart"
		}
		vm.Pop(L)
		part := cast(^classes.MeshPart)object
		part.mesh_id = strings.clone(absolute)
		part.mesh_index = u32(index)
		// MeshPart renders with Size / 2 as its scale.
		part.size = datatypes.Vector3{2, 2, 2}
		mesh_name := string(kineffi.Kine_Filament_GetMeshListName(meshes, u32(index)))
		if mesh_name == "" {
			mesh_name = fmt.tprintf("MeshPart %d", index)
		}
		classes.Set_Name(object, mesh_name)
		classes.Set_Parent(object, model)
	}
	return ""
}

Register_ExportService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ExportService_Class,
		export_service_construct,
		export_service_destroy,
		creatable = false,
		get = export_service_get,
		namecall = export_service_namecall,
	)
}
