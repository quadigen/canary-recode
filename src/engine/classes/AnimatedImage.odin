package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import aseprite "../util/aseprite"
import "core:image"
import "core:image/png"
import "core:math"
import "core:strings"
import "core:time"

Aseprite_Image_Playback :: struct {
	sprite:     ^aseprite.Ase,
	images:     []^kineffi.KineSkiaImage,
	ends_ms:    []f64,
	total_ms:   f64,
	elapsed_ms: f64,
	frame:      int,
	started:    bool,
	last_tick:  time.Tick,
}

animated_path_format :: proc(path: string) -> string {
	if strings.has_suffix(strings.to_lower(path, context.temp_allocator), ".gif") {return "gif"}
	lower := strings.to_lower(path, context.temp_allocator)
	if strings.has_suffix(lower, ".aseprite") ||
	   strings.has_suffix(lower, ".ase") {return "aseprite"}
	return ""
}

aseprite_image_frame :: proc(
	playback: ^Aseprite_Image_Playback,
	index: int,
) -> ^kineffi.KineSkiaImage {
	if playback.images[index] != nil {return playback.images[index]}
	sprite := playback.sprite
	pixels := sprite.frames[index].pixels
	img := image.Image {
		width    = sprite.w,
		height   = sprite.h,
		channels = 4,
		depth    = 8,
	}
	img.pixels = make([dynamic]u8, len(pixels) * 4)
	defer delete(img.pixels)
	copy(img.pixels[:], (cast([^]u8)raw_data(pixels))[:len(pixels) * 4])
	encoded: [dynamic]u8
	defer delete(encoded)
	if png.save_to_buffer(&encoded, &img) != nil {return nil}
	playback.images[index] = kineffi.Kine_Skia_Image_LoadFromMemory(
		raw_data(encoded),
		uintptr(len(encoded)),
	)
	return playback.images[index]
}

aseprite_image_destroy :: proc(playback: ^Aseprite_Image_Playback) {
	if playback == nil {return}
	for frame in playback.images {
		if frame != nil {kineffi.Kine_Skia_Image_Destroy(frame)}
	}
	delete(playback.images)
	delete(playback.ends_ms)
	aseprite.destroy(playback.sprite)
	free(playback)
}

ImageLabel_Load_Animated_Bytes :: proc(label: ^ImageLabel, data: []u8) -> bool {
	format := datatypes.Animated_Format(data)
	if format == "" {return false}
	label.animated_source = true
	if format == "gif" {
		label.stored_image = kineffi.Kine_Skia_Image_LoadFromMemory(
			raw_data(data),
			uintptr(len(data)),
		)
		return true
	}
	sprite, err := aseprite.load_from_memory(data)
	if err != .None {return true}
	playback := new(Aseprite_Image_Playback)
	playback.sprite = sprite
	playback.images = make([]^kineffi.KineSkiaImage, len(sprite.frames))
	playback.ends_ms = make([]f64, len(sprite.frames))
	for frame, i in sprite.frames {
		playback.total_ms += f64(max(frame.duration_ms, 10))
		playback.ends_ms[i] = playback.total_ms
	}
	label.stored_image = aseprite_image_frame(playback, 0)
	if label.stored_image == nil {
		aseprite_image_destroy(playback)
		return true
	}
	label.aseprite_playback = playback
	return true
}

ImageLabel_Advance_Aseprite :: proc(label: ^ImageLabel, milliseconds: f64) {
	p := label.aseprite_playback
	if p == nil || len(p.images) < 2 || p.total_ms <= 0 {return}
	p.elapsed_ms = math.mod(p.elapsed_ms + max(milliseconds, 0), p.total_ms)
	lo, hi := 0, len(p.ends_ms)
	for lo < hi {
		mid := (lo + hi) / 2
		if p.elapsed_ms < p.ends_ms[mid] {hi = mid} else {lo = mid + 1}
	}
	index := min(lo, len(p.ends_ms) - 1)
	if index == p.frame {return}
	if next := aseprite_image_frame(p, index); next != nil {
		p.frame = index
		label.stored_image = next
	}
}

ImageLabel_Tick_Aseprite :: proc(label: ^ImageLabel) {
	p := label.aseprite_playback
	if p == nil {return}
	now := time.tick_now()
	if p.started {
		ImageLabel_Advance_Aseprite(label, f64(time.tick_diff(p.last_tick, now)) / 1e6)
	}
	p.started = true
	p.last_tick = now
}
