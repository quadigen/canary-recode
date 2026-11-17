package classes

GuiBase_Class := Class_Info {
	name   = "GuiBase",
	parent = &Instance_Class,
}
GuiBase2d_Class := Class_Info {
	name   = "GuiBase2d",
	parent = &GuiBase_Class,
}
LayerCollector_Class := Class_Info {
	name   = "LayerCollector",
	parent = &GuiBase2d_Class,
}
BasePlayerGui_Class := Class_Info {
	name   = "BasePlayerGui",
	parent = &Instance_Class,
}

Register_GuiBase :: proc(registry: ^Registry) {
	for info in ([?]^Class_Info{&GuiBase_Class, &GuiBase2d_Class, &LayerCollector_Class, &BasePlayerGui_Class}) {
		register_abstract_gui_class(registry, info)
	}
}

register_abstract_gui_class :: proc(registry: ^Registry, info: ^Class_Info) {
	Register_Class(
		registry,
		info,
		proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {return nil},
		proc(object: ^Object, renderer: ^Renderer_Object) {Object_Destroy(object); free(object)},
		creatable = false,
		construct_with_ctx = proc(
			ctx: rawptr,
			renderer: ^Renderer_Object,
			data_model: rawptr,
		) -> ^Object {
			class := cast(^Class_Info)ctx
			object := new(Object)
			object^ = Object_Init(class, class.name)
			return object
		},
		construct_ctx = info,
	)
}
