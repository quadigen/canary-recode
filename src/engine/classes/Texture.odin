package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"


Texture_Class := Class_Info {
	name   = "Texture",
	parent = &Decal_Class,
}

texture_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	texture := new(Decal)
	texture^ = Decal_Init()
	texture.object.class = &Texture_Class
	texture.name = "Texture"
	return &texture.object
}

Register_Texture :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Texture_Class,
		texture_construct,
		Decal_destroy,
		get = Decal_Get,
		set = Decal_Set,
		clone = Decal_clone,
		_step = Decal_Step,
		_step_phase = .Render_3D,
		properties = []string {
			"Texture",
			"Color3",
			"Transparency",
			"Face",
			"StudsPerTileU",
			"StudsPerTileV",
			"OffsetStudsU",
			"OffsetStudsV",
			"ZOffset",
			"Enabled",
			"Culling",
			"CastShadows",
			"ReceiveShadows",
		},
	)
}
