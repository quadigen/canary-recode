package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

UISizeConstraint_Class := Class_Info {
	name   = "UISizeConstraint",
	parent = &Instance_Class,
}

UISizeConstraint :: struct {
	using object: Object,
	min_size:     datatypes.Vector2,
	max_size:     datatypes.Vector2,
}

UISizeConstraint_Init :: proc() -> UISizeConstraint {
	return UISizeConstraint {
		object = Object_Init(&UISizeConstraint_Class),
		min_size = {0, 0},
		max_size = {math.INF_F32, math.INF_F32},
	}
}

UISizeConstraint_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	constraint := new(UISizeConstraint)
	constraint^ = UISizeConstraint_Init()
	constraint.name = "UISizeConstraint"
	Gui_Layout_Mark_Dirty()
	return &constraint.object
}

UISizeConstraint_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Gui_Layout_Mark_Dirty()
	Object_Destroy(object)
	free(cast(^UISizeConstraint)object)
}

UISizeConstraint_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	constraint := cast(^UISizeConstraint)object

	if datatype_registry == nil {
		return false
	}

	switch key {
	case "MinSize":
		datatypes.Push_Vector2(L, datatype_registry, constraint.min_size)
	case "MaxSize":
		datatypes.Push_Vector2(L, datatype_registry, constraint.max_size)
	case:
		return false
	}

	return true
}

UISizeConstraint_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	constraint := cast(^UISizeConstraint)object

	if datatype_registry == nil {
		return false
	}

	switch key {
	case "MinSize":
		value := datatypes.Arg_Vector2(L, value_index, datatype_registry)
		constraint.min_size = {
			clamp(value.X, f32(0), constraint.max_size.X),
			clamp(value.Y, f32(0), constraint.max_size.Y),
		}
	case "MaxSize":
		value := datatypes.Arg_Vector2(L, value_index, datatype_registry)
		constraint.max_size = {
			max(value.X, constraint.min_size.X),
			max(value.Y, constraint.min_size.Y),
		}
	case:
		return false
	}

	Gui_Layout_Mark_Dirty()
	return true
}

UISizeConstraint_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UISizeConstraint)source
	dst := cast(^UISizeConstraint)destination

	dst.min_size = src.min_size
	dst.max_size = src.max_size
	Gui_Layout_Mark_Dirty()
}

Register_UISizeConstraint :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UISizeConstraint_Class,
		UISizeConstraint_construct,
		UISizeConstraint_destroy,
		get = UISizeConstraint_get,
		set = UISizeConstraint_set,
		clone = UISizeConstraint_clone,
		properties = []string{"MinSize", "MaxSize"},
	)
}

GuiObject_Constrain_Size :: proc(gui: ^GuiObject, width, height: f32) -> (f32, f32) {
	if gui == nil {
		return width, height
	}

	for child in gui.object.children {
		if child == nil || child.destroyed || !Is_A_Class(child, &UISizeConstraint_Class) {
			continue
		}

		constraint := cast(^UISizeConstraint)child
		return clamp(
			width,
			constraint.min_size.X,
			constraint.max_size.X,
		), clamp(height, constraint.min_size.Y, constraint.max_size.Y)
	}

	return width, height
}
