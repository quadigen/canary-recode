package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:strings"


BoneAttachment_Class := Class_Info {
	name   = "BoneAttachment",
	parent = &Attachment_Class,
}

BoneAttachment :: struct {
	using attachment: Attachment,
	bone_name:        string,
}

bone_attachment_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	b := new(BoneAttachment)
	b.attachment = Attachment_Init()
	b.object.class = &BoneAttachment_Class
	b.object.name = "BoneAttachment"
	return &b.object
}

bone_attachment_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	b := cast(^BoneAttachment)object
	Cloth_Forget_Attachment(object)
	handles_forget_adornee(object)
	delete(b.bone_name)
	Object_Destroy(object)
	free(b)
}

bone_attachment_clone :: proc(source, destination: ^Object) {
	Attachment_clone(source, destination)
	src := cast(^BoneAttachment)source
	dst := cast(^BoneAttachment)destination
	dst.bone_name = strings.clone(src.bone_name)
}

bone_attachment_get :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums_registry: ^enums.Registry,
	key: string,
) -> bool {
	b := cast(^BoneAttachment)object
	switch key {
	case "BoneName":
		vm.PushString(L, b.bone_name)
	case:
		return Attachment_get(L, object, types, enums_registry, key)
	}
	return true
}

bone_attachment_set :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums_registry: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	b := cast(^BoneAttachment)object
	switch key {
	case "BoneName":
		delete(b.bone_name)
		b.bone_name = strings.clone(vm.ArgString(L, index))
	case:
		return Attachment_set(L, object, types, enums_registry, key, index)
	}
	return true
}

Register_BoneAttachment :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&BoneAttachment_Class,
		bone_attachment_construct,
		bone_attachment_destroy,
		clone = bone_attachment_clone,
		get = bone_attachment_get,
		set = bone_attachment_set,
		namecall = attachment_namecall,
		properties = []string {
			"BoneName",
			"CFrame",
			"Position",
			"Orientation",
			"Axis",
			"SecondaryAxis",
			"WorldCFrame",
			"WorldPosition",
			"WorldOrientation",
			"WorldAxis",
			"WorldSecondaryAxis",
		},
		methods = []string{"GetConstraints"},
	)
}
