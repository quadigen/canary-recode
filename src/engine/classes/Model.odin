package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

Model_Class := Class_Info {
	name   = "Model",
	parent = &Instance_Class,
}

Model :: struct {
	using object: Object,
	pivot:        datatypes.CFrame,
	pivot_set:    bool,
}

Model_Init :: proc() -> Model {
	return Model{object = Object_Init(&Model_Class), pivot = datatypes.CFrame_Identity}
}

Model_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	corner := new(Model)
	corner^ = Model_Init()
	corner.name = "Model"

	return &corner.object
}

Model_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^Model)object)
}

Model_clone :: proc(source: ^Object, destination: ^Object) {
	src, dst := cast(^Model)source, cast(^Model)destination
	dst.pivot, dst.pivot_set = src.pivot, src.pivot_set
}

Model_Get_Pivot :: proc(model: ^Model) -> datatypes.CFrame {
	if Is_A(&model.object, "CharacterModel") {
		if root := CharacterModel_Root(cast(^CharacterModel)model);
		   root != nil {return root.cframe}
	}
	if model.pivot_set {return model.pivot}

	low, high: datatypes.Vector3
	found := false
	Model_Bounds(&model.object, &low, &high, &found)
	cf := datatypes.CFrame_Identity
	if found {cf.x = (low.x + high.x) / 2; cf.y = (low.y + high.y) / 2; cf.z = (low.z + high.z) / 2}
	return cf
}

Model_Bounds :: proc(object: ^Object, low, high: ^datatypes.Vector3, found: ^bool) {
	for child in object.children {
		if child == nil || child.destroyed {continue}
		if Is_A(child, "Part") {
			part := cast(^Part)child
			cf := part.cframe
			extent := datatypes.Vector3 {
				(abs(cf.r00) * part.size.x +
					abs(cf.r01) * part.size.y +
					abs(cf.r02) * part.size.z) /
				2,
				(abs(cf.r10) * part.size.x +
					abs(cf.r11) * part.size.y +
					abs(cf.r12) * part.size.z) /
				2,
				(abs(cf.r20) * part.size.x +
					abs(cf.r21) * part.size.y +
					abs(cf.r22) * part.size.z) /
				2,
			}
			a := datatypes.Vector3{cf.x - extent.x, cf.y - extent.y, cf.z - extent.z}
			b := datatypes.Vector3{cf.x + extent.x, cf.y + extent.y, cf.z + extent.z}
			if !found^ {low^ = a; high^ = b; found^ = true}
			low.x = min(low.x, a.x); low.y = min(low.y, a.y); low.z = min(low.z, a.z)
			high.x = max(high.x, b.x); high.y = max(high.y, b.y); high.z = max(high.z, b.z)
		}
		Model_Bounds(child, low, high, found)
	}
}

Model_Transform_Children :: proc(
	object: ^Object,
	delta: datatypes.CFrame,
	changed: ^[dynamic]^Object,
) {
	for child in object.children {
		if child == nil || child.destroyed {continue}
		if Is_A(child, "Part") {
			part := cast(^Part)child
			part.cframe = datatypes.CFrame_Mul_CFrame(delta, part.cframe)
			part.position = {part.cframe.x, part.cframe.y, part.cframe.z}
			append(changed, child)
		} else if Is_A(child, "Model") {
			model := cast(^Model)child
			model.pivot = datatypes.CFrame_Mul_CFrame(delta, Model_Get_Pivot(model))
			model.pivot_set = true
		}
		Model_Transform_Children(child, delta, changed)
	}
}

Model_Pivot_To :: proc(model: ^Model, target: datatypes.CFrame) {
	changed: [dynamic]^Object
	defer delete(changed)
	delta := datatypes.CFrame_Mul_CFrame(target, datatypes.CFrame_Inverse(Model_Get_Pivot(model)))
	Model_Transform_Children(&model.object, delta, &changed)
	model.pivot, model.pivot_set = target, true
	if Is_A(&model.object, "CharacterModel") {
		cc := CharacterController_From_Model(cast(^CharacterModel)model)
		if cc != nil {
			if rotation := cast(^RotationController)CharacterController_Find(
				   cc,
				   "RotationController",
			   ); rotation != nil {
				_, yaw, _ := datatypes.CFrame_ToEulerAnglesYXZ(target)
				rotation.yaw = math.to_degrees(yaw)
				rotation.target_yaw = rotation.yaw
			}
		}
	}
	Hierarchy_Touched()

	for part in changed {
		if part.destroyed {continue}
		Object_Fire_Property_Changed(part, "CFrame")
		if !part.destroyed {Object_Fire_Property_Changed(part, "Position")}
	}
}

model_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "PivotTo", "GetPivot":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

model_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "PivotTo":
		model := cast(^Model)object
		Model_Pivot_To(model, datatypes.Arg_CFrame(L, 2, datatype_registry))
		if registry := object.signal_registry;
		   !object.destroyed && registry != nil && registry.model_pivoted != nil {
			registry.model_pivoted(registry.network_ownership_ctx, model)
		}
		return 0, true
	case "GetPivot":
		datatypes.Push_CFrame(L, datatype_registry, Model_Get_Pivot(cast(^Model)object))
		return 1, true
	}
	return 0, false
}

Register_Model :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Model_Class,
		Model_construct,
		Model_destroy,
		clone = Model_clone,
		get = model_get,
		namecall = model_namecall,
		methods = []string{"PivotTo", "GetPivot"},
	)
}
