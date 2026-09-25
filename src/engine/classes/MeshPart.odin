package classes

import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import kineffi "../bindings"
import vm "../vm"

MeshPart_Class := Class_Info{
    name   = "MeshPart",
    parent = &Part_Class,
}

MeshPart :: struct {
    using part: Part,

    mesh_id:    string,
    texture_id: string,
    collision_fidelity: enums.CollisionFidelity,
    native_mesh: ^kineffi.KineFilamentMesh,
    native_context: ^kineffi.KineFilamentContext,
}

MeshPart_Init :: proc() -> MeshPart {
    return MeshPart{
        part = Part{
            object       = Object_Init(&MeshPart_Class),
            cframe       = datatypes.CFrame_Identity,
            color        = datatypes.Color3{
                R = 1,
                G = 1,
                B = 1,
            },
			size         = datatypes.Vector3{4, 1, 2},
            anchored     = false,
			can_collide  = true,
			can_query    = true,
			collision_group = strings.clone("Default"),
            transparency = 0,
            shape        = enums.PartType.Block,
            material     = enums.Material.SmoothPlastic,
        },
        mesh_id    = "",
        texture_id = "",
        collision_fidelity = enums.CollisionFidelity.Default,
    }
}

mesh_part_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
    mesh_part := new(MeshPart)
    mesh_part^ = MeshPart_Init()
    mesh_part.name = "MeshPart"

    return &mesh_part.object
}

mesh_part_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
    mesh_part := cast(^MeshPart)object

    if mesh_part.native_mesh != nil && mesh_part.native_context != nil {
        _ = kineffi.Kine_Filament_DestroyMesh(
            mesh_part.native_context,
            mesh_part.native_mesh,
        )
    }
    delete(mesh_part.mesh_id)
	delete(mesh_part.texture_id)
	delete(mesh_part.collision_group)

    Object_Destroy(object)
    free(mesh_part)
}

mesh_part_get :: proc(
    L: ^vm.State,
    object: ^Object,
    datatype_registry: ^datatypes.Registry,
    enum_registry: ^enums.Registry,
    key: string,
) -> bool {
    mesh_part := cast(^MeshPart)object

    switch key {
    case "MeshId":
        vm.PushString(L, mesh_part.mesh_id)

    case "TextureId":
        vm.PushString(L, mesh_part.texture_id)

    case "CollisionFidelity":
        if enum_registry == nil { return false }
        _ = enums.Push_Item_By_Value(
            L,
            enum_registry,
            "CollisionFidelity",
            i64(mesh_part.collision_fidelity),
        )

    case:
        return part_get(
            L,
            object,
            datatype_registry,
            enum_registry,
            key,
        )
    }

    return true
}

mesh_part_set :: proc(
    L: ^vm.State,
    object: ^Object,
    datatype_registry: ^datatypes.Registry,
    enum_registry: ^enums.Registry,
    key: string,
    value_index: int,
) -> bool {
    mesh_part := cast(^MeshPart)object

    switch key {
    case "MeshId":
        delete(mesh_part.mesh_id)
        mesh_part.mesh_id = strings.clone(vm.ArgString(L, value_index))

    case "TextureId":
        delete(mesh_part.texture_id)
        mesh_part.texture_id = strings.clone(vm.ArgString(L, value_index))

    case "CollisionFidelity":
        if enum_registry == nil { return false }
        item := enums.Arg_Item(L, value_index, enum_registry, "CollisionFidelity")
        if item != nil {
            mesh_part.collision_fidelity = enums.CollisionFidelity(item.value)
        }

    case:
        return part_set(
            L,
            object,
            datatype_registry,
            enum_registry,
            key,
            value_index,
        )
    }

    return true
}

mesh_part_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^MeshPart)source
	dst := cast(^MeshPart)destination

	delete(dst.mesh_id)
	delete(dst.texture_id)

	dst.mesh_id    = strings.clone(src.mesh_id)
	dst.texture_id = strings.clone(src.texture_id)
	dst.collision_fidelity = src.collision_fidelity
}

Register_MeshPart :: proc(registry: ^Registry) {
    Register_Class(
        registry,
        &MeshPart_Class,
        mesh_part_construct,
        mesh_part_destroy,
        get = mesh_part_get,
        set = mesh_part_set,
        clone = mesh_part_clone,
		properties = []string{"CollisionFidelity", "TextureId", "MeshId"},
    )
}
