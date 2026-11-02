package main

import "core:fmt"
import "core:time"

import kineffi "../src/engine/bindings"


GIF_BYTES := [?]u8 {
	0x47,
	0x49,
	0x46,
	0x38,
	0x39,
	0x61,
	0x01,
	0x00,
	0x01,
	0x00,
	0x91,
	0x00,
	0x00,
	0xFF,
	0x00,
	0x00,
	0x00,
	0x00,
	0xFF,
	0x00,
	0xFF,
	0x00,
	0xFF,
	0xFF,
	0xFF,
	0x21,
	0xF9,
	0x04,
	0x04,
	0x0A,
	0x00,
	0x00,
	0x00,
	0x2C,
	0x00,
	0x00,
	0x00,
	0x00,
	0x01,
	0x00,
	0x01,
	0x00,
	0x00,
	0x02,
	0x02,
	0x44,
	0x01,
	0x00,
	0x21,
	0xF9,
	0x04,
	0x04,
	0x14,
	0x00,
	0x00,
	0x00,
	0x2C,
	0x00,
	0x00,
	0x00,
	0x00,
	0x01,
	0x00,
	0x01,
	0x00,
	0x00,
	0x02,
	0x02,
	0x4C,
	0x01,
	0x00,
	0x3B,
}

draw_frame :: proc(
	surface: ^kineffi.KineSkiaSurface,
	image: ^kineffi.KineSkiaImage,
) -> (
	r, g, b, a: u8,
) {
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 255)
	kineffi.Kine_Skia_Surface_DrawImageSized(surface, image, 0, 0, 16, 16, 255)
	kineffi.Kine_Skia_Surface_Flush(surface)
	kineffi.Kine_Skia_Surface_GetPixel(surface, 8, 8, &r, &g, &b, &a)
	return
}

main :: proc() {
	image := kineffi.Kine_Skia_Image_LoadFromMemory(
		raw_data(GIF_BYTES[:]),
		uintptr(len(GIF_BYTES)),
	)
	assert(image != nil, "GIF failed to decode")
	defer kineffi.Kine_Skia_Image_Destroy(image)

	assert(kineffi.Kine_Skia_Image_GetWidth(image) == 1)
	assert(kineffi.Kine_Skia_Image_GetHeight(image) == 1)

	surface := kineffi.Kine_Skia_Surface_Create(16, 16)
	assert(surface != nil, "Skia surface creation failed")
	defer kineffi.Kine_Skia_Surface_Destroy(surface)

	r, g, b, a := draw_frame(surface, image)
	assert(r == 255 && g == 0 && b == 0 && a == 255, "first GIF frame should be red")

	time.sleep(150 * time.Millisecond)

	r, g, b, a = draw_frame(surface, image)
	assert(r == 0 && g == 0 && b == 255 && a == 255, "second GIF frame should be blue")


	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 255)
	kineffi.Kine_Skia_Surface_DrawImageScaled(
		surface,
		image,
		0,
		0,
		0,
		0,
		0,
		0,
		16,
		16,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		255,
	)
	kineffi.Kine_Skia_Surface_Flush(surface)
	kineffi.Kine_Skia_Surface_GetPixel(surface, 8, 8, &r, &g, &b, &a)
	assert(r == 0 && g == 0 && b == 255 && a == 255, "scaled GIF draw should be blue")

	fmt.println("GIF_IMAGE_SMOKE_PASSED")
}
