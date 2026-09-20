package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

CharacterModel_Class := Class_Info {
	name = "CharacterModel",
	parent = &Model_Class,
}

CharacterModel :: struct {
	using object: Object,
	owner_user_id: u32,
}

CharacterModel_Root :: proc(model: ^CharacterModel) -> ^Part {
	if model == nil || model.destroyed {return nil}
	for child in model.children {
		if child != nil && !child.destroyed && child.name == "HumanoidRootPart" && Is_A(child, "Part") {
			return cast(^Part)child
		}
	}
	return nil
}

character_model_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	model := new(CharacterModel)
	model.object = Object_Init(&CharacterModel_Class, "CharacterModel")
	return &model.object
}

character_model_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^CharacterModel)object)
}

character_model_clone :: proc(source: ^Object, destination: ^Object) {
	(cast(^CharacterModel)destination).owner_user_id = (cast(^CharacterModel)source).owner_user_id
}

character_model_get :: proc(L: ^vm.State, object: ^Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool {
	model := cast(^CharacterModel)object
	switch key {
	case "OwnerUserId":
		vm.PushNumber(L, f64(model.owner_user_id))
	case "PrimaryPart", "RootPart":
		root := CharacterModel_Root(model)
		if root == nil {vm.PushNil(L)} else {Push_Object(L, &root.object)}
	case:
		return false
	}
	return true
}

Register_CharacterModel :: proc(registry: ^Registry) {
	Register_Class(registry, &CharacterModel_Class, character_model_construct, character_model_destroy, clone = character_model_clone, get = character_model_get)
}
