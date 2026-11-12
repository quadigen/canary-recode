package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:strings"

Part_Class := Class_Info {
	name   = "Part",
	parent = &BasePart_Class,
}

Part :: struct {
	using object:      Object,
	cframe:            datatypes.CFrame,
	color:             datatypes.Color3,
	size:              datatypes.Vector3,
	transparency:      f64,
	anchored:          bool,
	can_collide:       bool,
	can_query:         bool,
	can_touch:         bool,
	collision_group:   string,
	shape:             enums.PartType,
	material:          enums.Material,
	material_variant:  string,
	castshadow:        bool,
	position:          datatypes.Vector3,
	touched:           ^signals.Signal,
	ownership_changed: ^signals.Signal,
	part_index:        int,
}

Part_Init :: proc() -> Part {
	return Part {
		object = Object_Init(&Part_Class),
		cframe = datatypes.CFrame_Identity,
		color = datatypes.Color3{R = 1, G = 1, B = 1},
		size = datatypes.Vector3{4, 1, 2},
		anchored = true,
		can_collide = true,
		can_query = true,
		can_touch = true,
		collision_group = strings.clone("Default"),
		transparency = 0,
		shape = enums.PartType.Block,
		material = enums.Material.SmoothPlastic,
		castshadow = true,
		position = datatypes.Vector3{0, 0, 0},
		part_index = -1,
	}
}

part_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	part := new(Part)
	part^ = Part_Init()
	part.name = "Part"
	return &part.object
}

part_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	part := cast(^Part)object
	if part.touched != nil &&
	   part.object.signal_registry != nil &&
	   part.object.signal_registry.signal_registry != nil {
		signals.Destroy(part.touched)
		part.touched = nil
	}
	if part.ownership_changed != nil &&
	   part.object.signal_registry != nil &&
	   part.object.signal_registry.signal_registry != nil {
		signals.Destroy(part.ownership_changed)
		part.ownership_changed = nil
	}
	delete(part.collision_group)
	delete(part.material_variant)
	Object_Destroy(object)
	free(part)
}

part_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	part := cast(^Part)object
	switch key {
	case "Anchored":
		vm.PushBoolean(L, part.anchored)
	case "CanCollide":
		vm.PushBoolean(L, part.can_collide)
	case "CanQuery":
		vm.PushBoolean(L, part.can_query)
	case "CanTouch":
		vm.PushBoolean(L, part.can_touch)
	case "CollisionGroup":
		vm.PushString(L, part.collision_group)
	case "MaterialVariant", "MaterialVariantSerialized":
		vm.PushString(L, part.material_variant)
	case "Material":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(L, enum_registry, "Material", i64(part.material))
	case "Transparency":
		vm.PushNumber(L, part.transparency)
	case "Shape":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(L, enum_registry, "PartType", i64(part.shape))
	case "CFrame":
		if datatype_registry == nil {return false}
		datatypes.Push_CFrame(L, datatype_registry, part.cframe)
	case "Color":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, part.color)
	case "Size":
		datatypes.Push_Vector3(L, part.size)
	case "CastShadow":
		vm.PushBoolean(L, part.castshadow)
	case "Position":
		datatypes.push_vector3(L, part.position)
	case "AssemblyLinearVelocity", "Velocity":
		datatypes.push_vector3(L, Part_Linear_Velocity(part.object.signal_registry, object))
	case "AssemblyAngularVelocity", "RotVelocity":
		datatypes.push_vector3(L, Part_Angular_Velocity(part.object.signal_registry, object))
	case "Touched":
		if part.touched == nil &&
		   part.object.signal_registry != nil &&
		   part.object.signal_registry.signal_registry != nil {
			part.touched = signals.Create(part.object.signal_registry.signal_registry)
		}
		if part.touched == nil {return false}
		signals.Push(L, part.touched)
	case "OwnershipChanged":
		if part.ownership_changed == nil &&
		   part.object.signal_registry != nil &&
		   part.object.signal_registry.signal_registry != nil {
			part.ownership_changed = signals.Create(part.object.signal_registry.signal_registry)
		}
		if part.ownership_changed == nil {return false}
		signals.Push(L, part.ownership_changed)
	case:
		return false
	}
	return true
}

part_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	part := cast(^Part)object
	switch key {
	case "Anchored":
		part.anchored = vm.ArgBoolean(L, value_index)
	case "CanCollide":
		part.can_collide = vm.ArgBoolean(L, value_index)
	case "CanQuery":
		part.can_query = vm.ArgBoolean(L, value_index)
	case "CanTouch":
		part.can_touch = vm.ArgBoolean(L, value_index)
	case "CollisionGroup":
		delete(part.collision_group)
		part.collision_group = strings.clone(vm.ArgString(L, value_index))
	case "Material":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "Material")
		part.material = enums.Material(item.value)
	case "MaterialVariant", "MaterialVariantSerialized":
		copy := strings.clone(vm.ArgString(L, value_index))
		delete(part.material_variant)
		part.material_variant = copy
	case "Shape":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "PartType")
		part.shape = enums.PartType(item.value)
	case "Transparency":
		part.transparency = vm.ArgNumber(L, value_index)
	case "CFrame":
		if datatype_registry == nil {return false}
		part.cframe = datatypes.Arg_CFrame(L, value_index, datatype_registry)
		part.position = {part.cframe.x, part.cframe.y, part.cframe.z}
	case "Color":
		if datatype_registry == nil {return false}
		part.color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Size":
		size := datatypes.Arg_Vector3(L, value_index)

		if size.x <= 0 || size.y <= 0 || size.z <= 0 {
			_ = vm.RaiseError(L, "Size components must be greater than zero")
			return true
		}

		part.size = size
	case "CastShadow":
		part.castshadow = vm.ArgBoolean(L, value_index)
	case "Position":
		v := datatypes.Arg_Vector3(L, value_index)
		part.position = v
		part.cframe.x = v.x
		part.cframe.y = v.y
		part.cframe.z = v.z
	case "AssemblyLinearVelocity", "Velocity":
		Part_Set_Linear_Velocity(
			part.object.signal_registry,
			object,
			datatypes.Arg_Vector3(L, value_index),
		)
	case "AssemblyAngularVelocity", "RotVelocity":
		Part_Set_Angular_Velocity(
			part.object.signal_registry,
			object,
			datatypes.Arg_Vector3(L, value_index),
		)
	case:
		return false
	}


	Hierarchy_Touched()
	return true
}

part_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	part := cast(^Part)object
	switch method {
	case "UnionAsync":
		return part_csg_namecall(L, object, .Union, enum_registry), true
	case "SubtractAsync":
		return part_csg_namecall(L, object, .Subtract, enum_registry), true
	case "IntersectAsync":
		return part_csg_namecall(L, object, .Intersect, enum_registry), true
	case "Negate":
		return part_csg_namecall(L, object, .Negate, enum_registry), true
	case "ApplyImpulse":
		impulse := datatypes.Arg_Vector3(L, 2)
		_ = Part_Apply_Impulse(part.object.signal_registry, object, impulse)
		return 0, true
	}
	return 0, false
}

part_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Part)source
	dst := cast(^Part)destination

	dst.cframe = src.cframe
	dst.color = src.color
	dst.size = src.size
	dst.transparency = src.transparency
	dst.anchored = src.anchored
	dst.can_collide = src.can_collide
	dst.can_query = src.can_query
	dst.can_touch = src.can_touch
	dst.shape = src.shape
	dst.material = src.material
	delete(dst.material_variant)
	dst.material_variant = strings.clone(src.material_variant)
	dst.position = src.position
	dst.castshadow = src.castshadow

	delete(dst.collision_group)
	dst.collision_group = strings.clone(src.collision_group)
}

Register_Part :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Part_Class,
		part_construct,
		part_destroy,
		get = part_get,
		set = part_set,
		namecall = part_namecall,
		clone = part_clone,
		properties = []string {
			"CanCollide",
			"Position",
			"CastShadow",
			"Color",
			"Anchored",
			"CFrame",
			"Shape",
			"CollisionGroup",
			"CanQuery",
			"CanTouch",
			"Transparency",
			"Size",
			"Material",
			"MaterialVariant",
			"AssemblyLinearVelocity",
			"AssemblyAngularVelocity",
		},
		methods = []string{"ApplyImpulse", "UnionAsync", "SubtractAsync", "IntersectAsync", "Negate"},
		events = []string{"Touched"},
	)
}
