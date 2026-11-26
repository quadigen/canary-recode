package native_api
import classes "../classes"
import datatypes "../datatypes"
import services "../services"
import vm "../vm"
import odin_runtime "base:runtime"

SDK_Raycast_Hit :: struct {
	instance: u64,
	position: SDK_Vector3,
	normal:   SDK_Vector3,
	distance: f64,
	material: i32,
}

@(export)
Kinemium_GetClassCount :: proc "c" (ctx: ^Context) -> u64 {
	context = odin_runtime.default_context()
	if ctx == nil {return 0}
	return u64(len(ctx.classes.classes))
}

@(export)
Kinemium_CopyClassName :: proc "c" (
	ctx: ^Context,
	index: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	if ctx == nil || index >= u64(len(ctx.classes.classes)) {return -1}
	descriptor := ctx.classes.classes[int(index)]
	if descriptor == nil || descriptor.info == nil {return -1}
	return sdk_copy_string(descriptor.info.name, buffer, capacity)
}

@(export)
Kinemium_ClassExists :: proc "c" (ctx: ^Context, name: cstring) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil {return false}
	return classes.Find_Class(ctx.classes, string(name)) != nil
}

@(export)
Kinemium_ClassIsCreatable :: proc "c" (ctx: ^Context, name: cstring) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil {return false}
	descriptor := classes.Find_Class(ctx.classes, string(name))
	return descriptor != nil && descriptor.creatable
}

@(export)
Kinemium_ClassGetPropertyCount :: proc "c" (ctx: ^Context, name: cstring) -> u64 {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil {return 0}
	props := classes.Class_Property_List(ctx.classes, string(name))
	defer delete(props)
	return u64(len(props))
}

@(export)
Kinemium_ClassCopyPropertyName :: proc "c" (
	ctx: ^Context,
	name: cstring,
	index: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil {return -1}
	props := classes.Class_Property_List(ctx.classes, string(name))
	defer delete(props)
	if index >= u64(len(props)) {return -1}
	return sdk_copy_string(props[int(index)], buffer, capacity)
}

@(export)
Kinemium_HandleCopyFullName :: proc "c" (
	ctx: ^Context,
	handle: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return -1}
	return sdk_copy_string(classes.Get_Full_Name(object), buffer, capacity)
}

@(export)
Kinemium_HandleIsDescendantOf :: proc "c" (ctx: ^Context, handle: u64, ancestor: u64) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	parent := resolve_handle(ctx, ancestor)
	if object == nil || parent == nil {return false}
	return classes.Is_Descendant_Of(object, parent)
}

@(export)
Kinemium_HandleClone :: proc "c" (ctx: ^Context, handle: u64) -> u64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || !object.archivable {sdk_error(ctx, "cannot clone instance"); return 0}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	cloned, ok := classes.Clone_Object(L, ctx.classes, object)
	if !ok {sdk_error(ctx, "instance clone failed"); return 0}
	sdk_clear_error(ctx)
	return register_handle(ctx, cloned)
}

@(export)
Kinemium_HandleDestroy :: proc "c" (ctx: ^Context, handle: u64) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return false}
	descriptor := find_object_descriptor(ctx, object)
	if descriptor == nil || !descriptor.creatable {
		sdk_error(ctx, "cannot destroy engine-owned service")
		return false
	}
	classes.Destroy_Hierarchy(object)
	classes.Flush_Pending_Destroy(ctx.classes)
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_HandleGetDescendantCount :: proc "c" (ctx: ^Context, handle: u64) -> u64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return 0}
	count: u64
	to_scan: [dynamic]^classes.Object
	defer delete(to_scan)
	append(&to_scan, object)
	for i := 0; i < len(to_scan); i += 1 {
		for child in classes.Get_Children(to_scan[i]) {
			if !child.destroyed {
				count += 1
				append(&to_scan, child)
			}
		}
	}
	return count
}

@(export)
Kinemium_PhysicsSetGravity :: proc "c" (ctx: ^Context, gravity: f64) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil {return false}
	object := services.DataModel_Get_Service(ctx.services.data_model, "Physics")
	return sdk_property_set(ctx, object, "Gravity", .Number, number = gravity)
}

@(export)
Kinemium_PhysicsGetGravity :: proc "c" (ctx: ^Context, output: ^f64) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || output == nil {return false}
	object := services.DataModel_Get_Service(ctx.services.data_model, "Physics")
	if object == nil {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_property_get(ctx, object, "Gravity") {return false}
	value, ok := vm.ToNumber(L, -1)
	if !ok {return false}
	output^ = value
	return true
}

@(export)
Kinemium_HandleApplyImpulse :: proc "c" (
	ctx: ^Context,
	handle: u64,
	impulse: SDK_Vector3,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || !classes.Is_A(object, "BasePart") {return false}
	return classes.Part_Apply_Impulse(
		ctx.classes,
		object,
		datatypes.Vector3{impulse.x, impulse.y, impulse.z},
	)
}

@(export)
Kinemium_HandleApplyAngularImpulse :: proc "c" (
	ctx: ^Context,
	handle: u64,
	impulse: SDK_Vector3,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || !classes.Is_A(object, "BasePart") {return false}
	return classes.Part_Apply_Angular_Impulse(
		ctx.classes,
		object,
		datatypes.Vector3{impulse.x, impulse.y, impulse.z},
	)
}

@(export)
Kinemium_Raycast :: proc "c" (
	ctx: ^Context,
	origin, direction: SDK_Vector3,
	output: ^SDK_Raycast_Hit,
) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || output == nil {return false}
	physics_object := services.DataModel_Get_Service(ctx.services.data_model, "Physics")
	workspace := services.DataModel_Get_Service(ctx.services.data_model, "Workspace")
	if physics_object == nil || workspace == nil {return false}
	hit_result, found := services.Physics_Raycast(
		cast(^services.Physics)physics_object,
		workspace,
		datatypes.Vector3{origin.x, origin.y, origin.z},
		datatypes.Vector3{direction.x, direction.y, direction.z},
	)
	if !found {return false}
	output^ = SDK_Raycast_Hit {
		instance = register_handle(ctx, cast(^classes.Object)hit_result.ObjectRef),
		position = SDK_Vector3 {
			hit_result.Position.x,
			hit_result.Position.y,
			hit_result.Position.z,
		},
		normal   = SDK_Vector3{hit_result.Normal.x, hit_result.Normal.y, hit_result.Normal.z},
		distance = f64(hit_result.Distance),
		material = i32(hit_result.Material),
	}
	return true
}
