package classes

CharacterAnimator_Class := Class_Info {
	name   = "CharacterAnimator",
	parent = &Instance_Class,
}

CharacterAnimator :: struct {
	using object: Object,
}

character_animator_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	anim := new(CharacterAnimator)
	anim.object = Object_Init(&CharacterAnimator_Class, "CharacterAnimator")
	return &anim.object
}

character_animator_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^CharacterAnimator)object)
}

Register_CharacterAnimator :: proc(registry: ^Registry) {
	Register_Class(registry, &CharacterAnimator_Class, character_animator_construct, character_animator_destroy)
}