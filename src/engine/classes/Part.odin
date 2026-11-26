package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:math"
import "core:strings"

Part_Class := Class_Info {
	name   = "Part",
	parent = &BasePart_Class,
}

PART_DEFAULT_GRAVITY :: datatypes.Vector3{0, -196.2, 0}

Part :: struct {
	using object:      Object,
	cframe:            datatypes.CFrame,
	pivot_offset:      datatypes.CFrame,
	color:             datatypes.Color3,
	size:              datatypes.Vector3,
	gravity:           datatypes.Vector3,
	transparency:      f64,
	anchored:          bool,
	can_collide:       bool,
	can_query:         bool,
	can_touch:         bool,
	collision_group:   string,
	shape:             enums.PartType,
	material:          enums.Material,
	surfaces:          [6]enums.SurfaceType,
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
		pivot_offset = datatypes.CFrame_Identity,
		color = datatypes.Color3{R = 1, G = 1, B = 1},
		size = datatypes.Vector3{4, 1, 2},
		gravity = PART_DEFAULT_GRAVITY,
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
	case "RightSurface", "TopSurface", "BackSurface", "LeftSurface", "BottomSurface", "FrontSurface":
		if enum_registry == nil {return false}
		face, _ := Part_Surface_Face(key)
		_ = enums.Push_Item_By_Value(L, enum_registry, "SurfaceType", i64(part.surfaces[int(face)]))
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
	case "PivotOffset":
		if datatype_registry == nil {return false}
		datatypes.Push_CFrame(L, datatype_registry, part.pivot_offset)
	case "GetPivot",
	     "PivotTo",
	     "GetVelocityAtPosition",
	     "ApplyImpulse",
	     "ApplyAngularImpulse",
	     "ApplyImpulseAtPosition",
	     "GetMass",
	     "CanCollideWith",
	     "GetConnectedParts",
	     "IsGrounded",
	     "GetJoints",
	     "GetNoCollisionConstraints":
		vm.PushUserdataMethod(L, key)
	case "Color":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, part.color)
	case "Mass":
		reg := object.signal_registry
		mass := f64(0)
		if reg != nil &&
		   reg.part_body.get_mass != nil {mass = reg.part_body.get_mass(reg.part_body_ctx, object)}
		vm.PushNumber(L, mass)
	case "Gravity":
		datatypes.Push_Vector3(L, part.gravity)
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
		Hierarchy_Touched()
	case "RightSurface", "TopSurface", "BackSurface", "LeftSurface", "BottomSurface", "FrontSurface":
		if enum_registry == nil {return false}
		face, _ := Part_Surface_Face(key)
		item := enums.Arg_Item(L, value_index, enum_registry, "SurfaceType")
		if item == nil {return true}
		part.surfaces[int(face)] = enums.SurfaceType(item.value)
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
	case "PivotOffset":
		if datatype_registry == nil {return false}
		part.pivot_offset = datatypes.Arg_CFrame(L, value_index, datatype_registry)
	case "Color":
		if datatype_registry == nil {return false}
		part.color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Gravity":
		gravity := datatypes.Arg_Vector3(L, value_index)
		if math.is_nan(gravity.x) ||
		   math.is_inf(gravity.x) ||
		   math.is_nan(gravity.y) ||
		   math.is_inf(gravity.y) ||
		   math.is_nan(gravity.z) ||
		   math.is_inf(gravity.z) {
			_ = vm.RaiseError(L, "Gravity components must be finite")
			return true
		}
		part.gravity = gravity
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

Part_Get_Pivot :: proc(part: ^Part) -> datatypes.CFrame {
	return datatypes.CFrame_Mul_CFrame(part.cframe, part.pivot_offset)
}

Part_Pivot_To :: proc(part: ^Part, target: datatypes.CFrame) {
	part.cframe = datatypes.CFrame_Mul_CFrame(target, datatypes.CFrame_Inverse(part.pivot_offset))
	part.position = datatypes.CFrame_Position(part.cframe)
	Hierarchy_Touched()
	Render_3D_Mark_Object_Dirty(&part.object)
	Object_Fire_Property_Changed(&part.object, "CFrame")
	if !part.destroyed {Object_Fire_Property_Changed(&part.object, "Position")}
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
	case "GetPivot":
		datatypes.Push_CFrame(L, datatype_registry, Part_Get_Pivot(part))
		return 1, true
	case "PivotTo":
		Part_Pivot_To(part, datatypes.Arg_CFrame(L, 2, datatype_registry))
		return 0, true
	case "GetVelocityAtPosition":
		point := datatypes.Arg_Vector3(L, 2)
		registry := part.signal_registry
		linear := Part_Linear_Velocity(registry, object)
		angular := Part_Angular_Velocity(registry, object)
		center := datatypes.CFrame_Position(part.cframe)
		datatypes.Push_Vector3(
			L,
			datatypes.Vec3_Add(
				linear,
				datatypes.Vec3_Cross(angular, datatypes.Vec3_Subtract(point, center)),
			),
		)
		return 1, true
	case "UnionAsync":
		return part_csg_namecall(L, object, .Union, enum_registry), true
	case "SubtractAsync":
		return part_csg_namecall(L, object, .Subtract, enum_registry), true
	case "IntersectAsync":
		return part_csg_namecall(L, object, .Intersect, enum_registry), true
	case "Negate":
		return part_csg_namecall(L, object, .Negate, enum_registry), true
	case "GetConnectedParts", "IsGrounded", "GetJoints", "GetNoCollisionConstraints":
		return part_joint_namecall(L, object, method)
	case "GetMass":
		reg := object.signal_registry
		mass := f64(0)
		if reg != nil &&
		   reg.part_body.get_mass != nil {mass = reg.part_body.get_mass(reg.part_body_ctx, object)}
		vm.PushNumber(L, mass)
		return 1, true
	case "CanCollideWith":
		other := Object_From_Argument(L, 2)
		if other == nil ||
		   !Is_A(other, "BasePart") {return vm.RaiseError(L, "expected BasePart"), true}
		reg := object.signal_registry
		vm.PushBoolean(
			L,
			reg != nil &&
			reg.part_body.can_collide_with != nil &&
			reg.part_body.can_collide_with(reg.part_body_ctx, object, other),
		)
		return 1, true
	case "ApplyAngularImpulse":
		impulse := datatypes.Arg_Vector3(L, 2)
		_ = Part_Apply_Angular_Impulse(object.signal_registry, object, impulse)
		return 0, true
	case "ApplyImpulseAtPosition":
		impulse := datatypes.Arg_Vector3(L, 2)
		position := datatypes.Arg_Vector3(L, 3)
		_ = Part_Apply_Impulse_At_Position(object.signal_registry, object, impulse, position)
		return 0, true
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
	dst.pivot_offset = src.pivot_offset
	dst.color = src.color
	dst.size = src.size
	dst.gravity = src.gravity
	dst.transparency = src.transparency
	dst.anchored = src.anchored
	dst.can_collide = src.can_collide
	dst.can_query = src.can_query
	dst.can_touch = src.can_touch
	dst.shape = src.shape
	dst.material = src.material
	dst.surfaces = src.surfaces
	delete(dst.material_variant)
	dst.material_variant = strings.clone(src.material_variant)
	dst.position = src.position
	dst.castshadow = src.castshadow

	delete(dst.collision_group)
	dst.collision_group = strings.clone(src.collision_group)
}

part_parallel_get :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "Anchored",
	     "CanCollide",
	     "CanQuery",
	     "CanTouch",
	     "CollisionGroup",
	     "MaterialVariant",
	     "Material",
	     "Transparency",
	     "Shape",
	     "CFrame",
	     "PivotOffset",
	     "Color",
	     "Gravity",
	     "Size",
	     "CastShadow",
	     "Position",
	     "GetPivot",
	     "RightSurface",
	     "TopSurface",
	     "BackSurface",
	     "LeftSurface",
	     "BottomSurface",
	     "FrontSurface":
		return part_get(L, object, d, e, key)
	}
	return false
}

part_parallel_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "GetPivot" {return 0, false}
	return part_namecall(L, object, d, e, method)
}

Register_Part :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Part_Class,
		part_construct,
		part_destroy,
		get = part_get,
		parallel_get = part_parallel_get,
		parallel_namecall = part_parallel_namecall,
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
			"RightSurface",
			"TopSurface",
			"BackSurface",
			"LeftSurface",
			"BottomSurface",
			"FrontSurface",
			"AssemblyLinearVelocity",
			"AssemblyAngularVelocity",
		},
		methods = []string {
			"ApplyImpulse",
			"UnionAsync",
			"SubtractAsync",
			"IntersectAsync",
			"Negate",
		},
		events = []string{"Touched"},
	)
}

Part_Surface_Face :: proc(key: string) -> (enums.NormalId, bool) {
	switch key {
	case "RightSurface":
		return .Right, true
	case "TopSurface":
		return .Top, true
	case "BackSurface":
		return .Back, true
	case "LeftSurface":
		return .Left, true
	case "BottomSurface":
		return .Bottom, true
	case "FrontSurface":
		return .Front, true
	}
	return .Front, false
}
