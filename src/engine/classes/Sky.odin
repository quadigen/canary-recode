package classes

import assetstore "../assetstore"
import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:c"
import "core:strings"
import image "vendor:stb/image"

Sky_Class := Class_Info {
	name   = "Sky",
	parent = &Instance_Class,
}
Sky :: struct {
	using object:                        Object,
	faces:                               [6]string,
	sun_texture, moon_texture:           string,
	celestial_bodies_shown:              bool,
	sun_angular_size, moon_angular_size: f64,
	star_count:                          i32,
	orientation:                         datatypes.Vector3,
	revision:                            u64,
}
Sky_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	sky := new(Sky)
	sky.object = Object_Init(&Sky_Class, "Sky")
	sky.celestial_bodies_shown = true
	sky.sun_angular_size, sky.moon_angular_size = 21, 11
	sky.star_count = 3000
	sky.revision = 1
	return &sky.object
}
Sky_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	sky := cast(^Sky)object
	for face in sky.faces {delete(face)}
	delete(sky.sun_texture)
	delete(sky.moon_texture)
	Object_Destroy(object)
	free(sky)
}
Sky_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^Sky)source, cast(^Sky)destination
	for path, i in src.faces {dst.faces[i] = strings.clone(path)}
	dst.sun_texture, dst.moon_texture =
		strings.clone(src.sun_texture), strings.clone(src.moon_texture)
	dst.celestial_bodies_shown = src.celestial_bodies_shown
	dst.sun_angular_size, dst.moon_angular_size, dst.star_count =
		src.sun_angular_size, src.moon_angular_size, src.star_count
	dst.orientation = src.orientation
}
sky_string_field :: proc(sky: ^Sky, key: string) -> ^string {
	switch key {
	case "SkyboxRt", "SkyboxRightContent":
		return &sky.faces[0]
	case "SkyboxLf", "SkyboxLeftContent":
		return &sky.faces[1]
	case "SkyboxUp", "SkyboxUpContent":
		return &sky.faces[2]
	case "SkyboxDn", "SkyboxDownContent":
		return &sky.faces[3]
	case "SkyboxBk", "SkyboxBackContent":
		return &sky.faces[4]
	case "SkyboxFt", "SkyboxFrontContent":
		return &sky.faces[5]
	case "SunTextureId", "SunTextureContent":
		return &sky.sun_texture
	case "MoonTextureId", "MoonTextureContent":
		return &sky.moon_texture
	}
	return nil
}
Sky_get :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	sky := cast(^Sky)object
	if slot := sky_string_field(sky, key); slot != nil {
		if strings.has_suffix(
			key,
			"Content",
		) {datatypes.Push_Content(L, d, datatypes.Content_From_URI(slot^))} else {vm.PushString(L, slot^)}
		return true
	}
	switch key {
	case "CelestialBodiesShown":
		vm.PushBoolean(L, sky.celestial_bodies_shown)
	case "SunAngularSize":
		vm.PushNumber(L, sky.sun_angular_size)
	case "MoonAngularSize":
		vm.PushNumber(L, sky.moon_angular_size)
	case "StarCount":
		vm.PushNumber(L, f64(sky.star_count))
	case "SkyboxOrientation":
		datatypes.Push_Vector3(L, sky.orientation)
	case:
		return false
	}
	return true
}
Sky_set :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	sky := cast(^Sky)object
	if slot := sky_string_field(sky, key); slot != nil {
		value: string
		if strings.has_suffix(
			key,
			"Content",
		) {value = datatypes.Arg_Content(L, index, d).uri} else {value = vm.ArgString(L, index)}
		if slot^ != value {
			owned := strings.clone(value)
			delete(slot^)
			slot^ = owned
			sky.revision += 1
		}
		return true
	}
	switch key {
	case "CelestialBodiesShown":
		sky.celestial_bodies_shown = vm.ArgBoolean(L, index)
	case "SunAngularSize":
		sky.sun_angular_size = clamp(vm.ArgNumber(L, index), 0, 360)
	case "MoonAngularSize":
		sky.moon_angular_size = clamp(vm.ArgNumber(L, index), 0, 360)
	case "StarCount":
		sky.star_count = i32(clamp(vm.ArgNumber(L, index), 0, 5000))
	case "SkyboxOrientation":
		sky.orientation = datatypes.Arg_Vector3(L, index)
	case:
		return false
	}
	sky.revision += 1
	return true
}
Sky_Upload :: proc(sky: ^Sky, ctx: ^kineffi.KineFilamentContext) -> bool {
	when ODIN_OS == .JS {return false} else {
		if sky == nil || ctx == nil {return false}
		for path in sky.faces {if path == "" {return false}}
		combined: []u8
		defer delete(combined)
		size: i32
		for path, i in sky.faces {
			w, h, ch: c.int
			pixels: [^]u8
			if data, found := Texture_Resolve_Bytes(path); found && len(data) > 0 {
				pixels = image.load_from_memory(raw_data(data), c.int(len(data)), &w, &h, &ch, 4)
			} else {
				resolved := assetstore.Resolve_C_Path(path)
				defer delete(resolved)
				if resolved != nil {pixels = image.load(resolved, &w, &h, &ch, 4)}
			}
			if pixels == nil {assetstore.Report_Missing_Asset(path, "Sky face"); return false}
			defer image.image_free(pixels)
			if w <= 0 || w != h || w > 4096 || (i > 0 && i32(w) != size) {return false}
			if i == 0 {size = i32(w); combined = make([]u8, int(size) * int(size) * 4 * 6)}
			face_size := int(size) * int(size) * 4
			copy(combined[i * face_size:(i + 1) * face_size], pixels[:face_size])
		}
		return(
			kineffi.Kine_Filament_CreateSkyboxPixels(
				ctx,
				size,
				raw_data(combined),
				sky.celestial_bodies_shown,
			) !=
			0 \
		)
	}
}
Register_Sky :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Sky_Class,
		Sky_construct,
		Sky_destroy,
		get = Sky_get,
		set = Sky_set,
		clone = Sky_clone,
		properties = []string {
			"SkyboxRt",
			"SkyboxLf",
			"SkyboxUp",
			"SkyboxDn",
			"SkyboxBk",
			"SkyboxFt",
			"SunTextureId",
			"MoonTextureId",
			"CelestialBodiesShown",
			"SunAngularSize",
			"MoonAngularSize",
			"StarCount",
			"SkyboxOrientation",
		},
	)
}
