package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"


SelectionBox_Class := Class_Info {
	name   = "SelectionBox",
	parent = &Highlight_Class,
}

selection_box_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	box := new(Highlight)
	box^ = Highlight_Init()
	box.object.class = &SelectionBox_Class
	box.name = "SelectionBox"
	box.fill_transparency = 1
	return &box.object
}

selection_box_key :: proc(key: string) -> string {
	switch key {
	case "Transparency":
		return "OutlineTransparency"
	case "SurfaceTransparency":
		return "FillTransparency"
	case "Color3":
		return "OutlineColor"
	case "SurfaceColor3":
		return "FillColor"
	case "Visible":
		return "Enabled"
	}
	return key
}

selection_box_get :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	return highlight_get(L, object, d, e, selection_box_key(key))
}

selection_box_set :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	return highlight_set(L, object, d, e, selection_box_key(key), value_index)
}

Register_SelectionBox :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&SelectionBox_Class,
		selection_box_construct,
		highlight_destroy,
		get = selection_box_get,
		set = selection_box_set,
		clone = highlight_clone,
		_step = highlight_step,
		_step_phase = .Render_3D,
		properties = []string {
			"Adornee",
			"Transparency",
			"SurfaceTransparency",
			"Color3",
			"SurfaceColor3",
			"Visible",
			"Enabled",
			"DepthMode",
		},
	)
}
