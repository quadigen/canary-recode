package util
import renderer "../renderer"
import sdl3 "../platform"
import "vendor:stb/image"
import "../vm"
import "../services"
import "../signals"
import kineffi "../bindings"

EngineImage :: struct {
    width: i32,
    height: i32,
    pixels: [^]byte
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

    defer image.image_free(pixels)

    return EngineImage{width = width, height = height, pixels = pixels}
}
