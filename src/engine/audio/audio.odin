#+build !js
package audio

import "core:strings"
import miniaudio "vendor:miniaudio"

Sound :: struct {
	source: miniaudio.sound,
	loaded: bool,
}

Sound_Flags :: miniaudio.sound_flags

audio_engine: miniaudio.engine
initialized := false

init :: proc() -> bool {
	if initialized {
		return true
	}

	result := miniaudio.engine_init(nil, &audio_engine)
	if result != .SUCCESS {
		return false
	}

	initialized = true
	return true
}

shutdown :: proc() {
	if !initialized {
		return
	}

	miniaudio.engine_uninit(&audio_engine)
	initialized = false
}

is_initialized :: proc() -> bool {
	return initialized
}

get_engine :: proc() -> ^miniaudio.engine {
	if !initialized && !init() {
		return nil
	}

	return &audio_engine
}


set_master_volume :: proc(volume: f32) -> bool {
	engine := get_engine()
	if engine == nil {
		return false
	}

	miniaudio.engine_set_volume(engine, max(0.0, volume))
	return true
}

get_master_volume :: proc() -> f32 {
	engine := get_engine()
	if engine == nil {
		return 0
	}

	return miniaudio.engine_get_volume(engine)
}

set_master_gain_db :: proc(gain_db: f32) -> bool {
	engine := get_engine()
	if engine == nil {
		return false
	}

	miniaudio.engine_set_gain_db(engine, gain_db)
	return true
}

start :: proc() -> bool {
	engine := get_engine()
	if engine == nil {
		return false
	}

	return miniaudio.engine_start(engine) == .SUCCESS
}

stop :: proc() -> bool {
	if !initialized {
		return false
	}

	return miniaudio.engine_stop(&audio_engine) == .SUCCESS
}


play_sound :: proc(path: string) -> bool {
	engine := get_engine()
	if engine == nil {
		return false
	}

	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)

	return miniaudio.engine_play_sound(engine, cpath, nil) == .SUCCESS
}


load_sound :: proc(sound: ^Sound, path: string, flags: Sound_Flags = {}) -> bool {
	if sound == nil {
		return false
	}

	if sound.loaded {
		unload_sound(sound)
	}

	engine := get_engine()
	if engine == nil {
		return false
	}

	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)

	result := miniaudio.sound_init_from_file(engine, cpath, flags, nil, nil, &sound.source)

	if result != .SUCCESS {
		sound.loaded = false
		return false
	}

	sound.loaded = true
	return true
}

unload_sound :: proc(sound: ^Sound) {
	if sound == nil || !sound.loaded {
		return
	}

	miniaudio.sound_uninit(&sound.source)
	sound.loaded = false
}

play :: proc(sound: ^Sound) -> bool {
	if sound == nil || !sound.loaded {
		return false
	}

	return miniaudio.sound_start(&sound.source) == .SUCCESS
}

pause :: proc(sound: ^Sound) -> bool {
	if sound == nil || !sound.loaded {
		return false
	}

	return miniaudio.sound_stop(&sound.source) == .SUCCESS
}

is_loaded :: proc(sound: ^Sound) -> bool {
    return sound != nil && sound.loaded
}

stop_sound :: proc(sound: ^Sound) -> bool {
	if sound == nil || !sound.loaded {
		return false
	}

	return miniaudio.sound_stop(&sound.source) == .SUCCESS
}

is_playing :: proc(sound: ^Sound) -> b32 {
	if sound == nil || !sound.loaded {
		return false
	}

	return miniaudio.sound_is_playing(&sound.source)
}

set_volume :: proc(sound: ^Sound, volume: f32) {
	if sound == nil || !sound.loaded {
		return
	}

	miniaudio.sound_set_volume(&sound.source, max(0.0, volume))
}

set_pitch :: proc(sound: ^Sound, pitch: f32) {
	if sound == nil || !sound.loaded {
		return
	}

	miniaudio.sound_set_pitch(&sound.source, max(0.01, pitch))
}

set_pan :: proc(sound: ^Sound, pan: f32) {
	if sound == nil || !sound.loaded {
		return
	}

	miniaudio.sound_set_pan(&sound.source, clamp(pan, -1.0, 1.0))
}

set_looping :: proc(sound: ^Sound, looping: b32) {
	if sound == nil || !sound.loaded {
		return
	}

	miniaudio.sound_set_looping(&sound.source, looping)
}

set_position :: proc(sound: ^Sound, x, y, z: f32) {
	if sound == nil || !sound.loaded {
		return
	}

	miniaudio.sound_set_position(&sound.source, x, y, z)
}

set_velocity :: proc(sound: ^Sound, x, y, z: f32) {
	if sound == nil || !sound.loaded {
		return
	}

	miniaudio.sound_set_velocity(&sound.source, x, y, z)
}

set_spatialization :: proc(sound: ^Sound, enabled: b32) {
	if sound == nil || !sound.loaded {
		return
	}

	miniaudio.sound_set_spatialization_enabled(&sound.source, enabled)
}

set_relative :: proc(sound: ^Sound, relative: bool) {
	if sound == nil || !sound.loaded {
		return
	}

	if relative {
		miniaudio.sound_set_positioning(&sound.source, .relative)
	} else {
		miniaudio.sound_set_positioning(&sound.source, .absolute)
	}
}

get_cursor_frames :: proc(sound: ^Sound) -> u64 {
	if sound == nil || !sound.loaded {
		return 0
	}

	cursor: u64
	if miniaudio.sound_get_cursor_in_pcm_frames(&sound.source, &cursor) != .SUCCESS {
		return 0
	}

	return cursor
}

get_length_frames :: proc(sound: ^Sound) -> u64 {
	if sound == nil || !sound.loaded {
		return 0
	}

	length: u64
	if miniaudio.sound_get_length_in_pcm_frames(&sound.source, &length) != .SUCCESS {
		return 0
	}

	return length
}

seek_frames :: proc(sound: ^Sound, frame: u64) -> bool {
	if sound == nil || !sound.loaded {
		return false
	}

	return miniaudio.sound_seek_to_pcm_frame(&sound.source, frame) == .SUCCESS
}


listener_set_position :: proc(x, y, z: f32) -> bool {
	engine := get_engine()
	if engine == nil {
		return false
	}

	miniaudio.engine_listener_set_position(engine, 0, x, y, z)
	return true
}

listener_set_direction :: proc(x, y, z: f32) -> bool {
	engine := get_engine()
	if engine == nil {
		return false
	}

	miniaudio.engine_listener_set_direction(engine, 0, x, y, z)
	return true
}

listener_set_velocity :: proc(x, y, z: f32) -> bool {
	engine := get_engine()
	if engine == nil {
		return false
	}

	miniaudio.engine_listener_set_velocity(engine, 0, x, y, z)
	return true
}
