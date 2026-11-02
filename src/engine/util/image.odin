package util
import kineffi "../bindings"
import sdl3 "../platform"
import renderer "../renderer"
import "../services"
import "../signals"
import "../vm"
import "vendor:stb/image"

EngineImage :: struct {
	width:  i32,
	height: i32,
	pixels: [^]byte,
}

image_from_mem :: proc(loaded: []u8) -> EngineImage {
	width, height, channels: i32

	pixels := image.load_from_memory(
		raw_data(loaded),
		i32(len(loaded)),
		&width,
		&height,
		&channels,
		4,
	)

	if pixels == nil {
		return EngineImage{}
	}

	return EngineImage{width = width, height = height, pixels = pixels}
}
