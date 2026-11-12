package classes

import assetstore "../assetstore"
import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:slice"
import "core:strings"

PartOperation_Class := Class_Info {
	name   = "PartOperation",
	parent = &MeshPart_Class,
}
UnionOperation_Class := Class_Info {
	name   = "UnionOperation",
	parent = &PartOperation_Class,
}
NegateOperation_Class := Class_Info {
	name   = "NegateOperation",
	parent = &PartOperation_Class,
}
IntersectOperation_Class := Class_Info {
	name   = "IntersectOperation",
	parent = &PartOperation_Class,
}

part_operation_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	object := mesh_part_construct(renderer, data_model)
	object.class = &PartOperation_Class
	object.name = "PartOperation"
	return object
}

union_operation_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	object := mesh_part_construct(renderer, data_model)
	object.class = &UnionOperation_Class
	object.name = "UnionOperation"
	return object
}

negate_operation_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	object := mesh_part_construct(renderer, data_model)
	object.class = &NegateOperation_Class
	object.name = "NegateOperation"
	part := cast(^MeshPart)object
	part.can_collide = false
	part.can_query = false
	part.can_touch = false
	part.transparency = 0.5
	part.color = datatypes.Color3{1, 0.2, 0.2}
	return object
}

intersect_operation_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	object := mesh_part_construct(renderer, data_model)
	object.class = &IntersectOperation_Class
	object.name = "IntersectOperation"
	return object
}

part_operation_clone :: proc(source, destination: ^Object) {
	(cast(^MeshPart)destination).use_part_color = (cast(^MeshPart)source).use_part_color
}

Register_Part_Operations :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&PartOperation_Class,
		part_operation_construct,
		mesh_part_destroy,
		creatable = false,
		clone = part_operation_clone,
		properties = []string{"UsePartColor"},
	)
	Register_Class(
		registry,
		&UnionOperation_Class,
		union_operation_construct,
		mesh_part_destroy,
		creatable = false,
		get = mesh_part_get,
		set = mesh_part_set,
		namecall = mesh_part_namecall,
	)
	Register_Class(
		registry,
		&NegateOperation_Class,
		negate_operation_construct,
		mesh_part_destroy,
		creatable = false,
		get = mesh_part_get,
		set = mesh_part_set,
		namecall = mesh_part_namecall,
	)
	Register_Class(
		registry,
		&IntersectOperation_Class,
		intersect_operation_construct,
		mesh_part_destroy,
		creatable = false,
		get = mesh_part_get,
		set = mesh_part_set,
		namecall = mesh_part_namecall,
	)
}

Part_Csg_Operation :: enum u32 {
	Union,
	Subtract,
	Intersect,
	Negate,
}

part_csg_input :: proc(part: ^Part) -> (input: kineffi.Csg_Input, valid: bool) {
	f := part.cframe
	input.size = {part.size.x, part.size.y, part.size.z}
	input.transform = {
		f.x,
		f.y,
		f.z,
		f.r00,
		f.r01,
		f.r02,
		f.r10,
		f.r11,
		f.r12,
		f.r20,
		f.r21,
		f.r22,
	}
	input.shape = i32(part.shape)
	input.negative = i32(Is_A_Class(&part.object, &NegateOperation_Class))

	if Is_A_Class(&part.object, &MeshPart_Class) {
		mesh := cast(^MeshPart)part
		uri := MeshPart_Source_Path(mesh)
		if uri != "" {
			input.shape = -1
			input.mesh_index = mesh.mesh_index
			if data, found := assetstore.Resolve_Bytes(uri); found && len(data) > 0 {
				input.bytes = raw_data(data)
				input.length = uintptr(len(data))
				input.hint = strings.clone_to_cstring(assetstore.Format_Hint(uri))
				return input, true
			}
			input.path = assetstore.Resolve_C_Path(uri)
			return input, input.path != nil
		}
		if input.negative == 0 || mesh.editable_mesh_id != 0 {
			return input, false
		}
	}
	if input.shape < 0 || input.shape > 2 {
		data, found := highlight_shape_glb(part.shape)
		if !found {return input, false}
		input.bytes = raw_data(data)
		input.length = uintptr(len(data))
		input.hint = strings.clone_to_cstring("glb")
	}
	return input, true
}

// The caller owns the resulting unparented instance. Source instances are unchanged.
Part_Csg :: proc(
	L: ^vm.State,
	source: ^Object,
	others: []^Object,
	operation: Part_Csg_Operation,
	collision_fidelity: enums.CollisionFidelity,
) -> (
	result: ^Object,
	error_message: string,
) {
	when ODIN_OS == .JS || #config(KINE_ANDROID, false) {
		return nil, "Solid modeling is unavailable on this platform"
	} else {
		operands := make([]^Object, len(others) + 1)
		defer delete(operands)
		operands[0] = source
		copy(operands[1:], others)
		if operation == .Union && Is_A_Class(source, &NegateOperation_Class) {
			for object, index in others {
				if object != nil && !Is_A_Class(object, &NegateOperation_Class) {
					operands[0], operands[index + 1] = object, source
					break
				}
			}
		}
		inputs := make([]kineffi.Csg_Input, len(operands))
		defer {
			for input in inputs {
				delete(input.hint)
				delete(input.path)
			}
			delete(inputs)
		}
		for object, index in operands {
			if object == nil || object.destroyed || !Is_A_Class(object, &Part_Class) {
				return nil, "Solid modeling requires live parts"
			}
			input, valid := part_csg_input(cast(^Part)object)
			inputs[index] = input
			if !valid {return nil, "Could not resolve an operand's mesh"}
		}
		output: kineffi.Csg_Output
		status := kineffi.Kine_Csg_Apply(
			raw_data(inputs),
			u32(len(inputs)),
			u32(operation),
			&output,
		)
		defer kineffi.Kine_Csg_Free(&output)
		switch status {
		case 1:
			return nil, "An operand does not form a closed solid or has invalid dimensions"
		case 2:
			return nil, "The solid operation produced an empty result"
		case 3:
			return nil, "Manifold could not complete the solid operation"
		}
		if status != 0 || output.length > assetstore.MAX_ASSET_BYTES {
			return nil, "The resulting mesh exceeds the asset size limit"
		}

		id := assetstore.Register(
			slice.clone(output.data[:int(output.length)]),
			"solid.obj",
			.Mesh,
		)
		defer delete(id)
		if id == "" {return nil, "Could not store the resulting mesh"}
		class_name := "UnionOperation"
		#partial switch operation {
		case .Negate:
			class_name = "NegateOperation"
		case .Intersect:
			class_name = "IntersectOperation"
		case:
		}
		registry := source.signal_registry
		object, ok := Push_New(registry, &vm.VM{L = L}, class_name, false)
		if !ok {return nil, "Could not create the resulting solid"}
		part_clone(operands[0], object)
		mesh := cast(^MeshPart)object
		mesh.mesh_id = assetstore.Make_Uri(id)
		mesh.position = {output.center[0], output.center[1], output.center[2]}
		mesh.size = {output.size[0], output.size[1], output.size[2]}
		mesh.cframe.x, mesh.cframe.y, mesh.cframe.z =
			output.center[0], output.center[1], output.center[2]
		mesh.shape = .Block
		mesh.collision_fidelity = collision_fidelity
		mesh.use_part_color = true
		if operation == .Negate {
			mesh.can_collide = false
			mesh.can_query = false
			mesh.can_touch = false
			mesh.transparency = 0.5
			mesh.color = {1, 0.2, 0.2}
		}
		return object, ""
	}
}

part_csg_namecall :: proc(
	L: ^vm.State,
	source: ^Object,
	operation: Part_Csg_Operation,
	enum_registry: ^enums.Registry,
) -> i32 {
	storage: [255]^Object
	others: []^Object
	fidelity := enums.CollisionFidelity.Default
	if operation != .Negate {
		if !vm.IsTable(L, 2) {
			return vm.RaiseError(L, "Solid modeling expects an array of parts")
		}
		count := vm.RawLen(L, 2)
		if count == 0 || count > len(storage) {
			return vm.RaiseError(L, "Solid modeling expects between 1 and 255 other parts")
		}
		others = storage[:count]
		for index in 0 ..< count {
			_ = vm.RawGetIndex(L, 2, index + 1)
			others[index] = Object_From_Argument(L, -1)
			vm.Pop(L, 1)
		}
		if !vm.IsNoneOrNil(L, 3) {
			item := enums.Arg_Item(L, 3, enum_registry, "CollisionFidelity")
			if item == nil {return vm.RaiseError(L, "Expected Enum.CollisionFidelity")}
			fidelity = enums.CollisionFidelity(item.value)
		}
	}
	_, error_message := Part_Csg(L, source, others, operation, fidelity)
	if error_message != "" {return vm.RaiseError(L, error_message)}
	return 1
}
