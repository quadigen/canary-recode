#+build js
package audio

import "core:strings"

foreign import "kinemium_audio"

@(default_calling_convention="c")
foreign kinemium_audio {
	host_play_sound :: proc(path: cstring) ---
}

Sound_Flag :: enum u32 {
	Loop,
}

Sound_Flags :: distinct bit_set[Sound_Flag; u32]

Sound :: struct {
	path:    string,
	loaded:  bool,
	playing: bool,
	volume:  f32,
	looping: bool,
}

init :: proc() -> bool {
	return true
}

shutdown :: proc() {}

is_initialized :: proc() -> bool {
	return true
}

set_master_volume :: proc(volume: f32) -> bool {
	return true
}

get_master_volume :: proc() -> f32 {
	return 1
}

play_sound :: proc(path: string) -> bool {
	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)
	host_play_sound(cpath)
	return true
}

load_sound :: proc(sound: ^Sound, path: string, flags := Sound_Flags{}) -> bool {
	if sound == nil {return false}
	unload_sound(sound)
	sound.path = strings.clone(path)
	sound.loaded = true
	sound.volume = 1
	return true
}

unload_sound :: proc(sound: ^Sound) {
	if sound == nil {return}
	if sound.path != "" {delete(sound.path)}
	sound^ = {}
}

play :: proc(sound: ^Sound) -> bool {
	if sound == nil || !sound.loaded {return false}
	if sound.path != "" {
		cpath := strings.clone_to_cstring(sound.path)
		defer delete(cpath)
		host_play_sound(cpath)
	}
	sound.playing = true
	return true
}

pause :: proc(sound: ^Sound) -> bool {
	if sound == nil {return false}
	sound.playing = false
	return true
}

is_loaded :: proc(sound: ^Sound) -> bool {
	return sound != nil && sound.loaded
}

stop_sound :: proc(sound: ^Sound) -> bool {
	if sound == nil {return false}
	sound.playing = false
	return true
}

is_playing :: proc(sound: ^Sound) -> b32 {
	return b32(sound != nil && sound.playing)
}

set_volume :: proc(sound: ^Sound, volume: f32) {
	if sound == nil {return}
	sound.volume = volume
}

set_pitch :: proc(sound: ^Sound, pitch: f32) {}

set_pan :: proc(sound: ^Sound, pan: f32) {}

set_looping :: proc(sound: ^Sound, looping: b32) {
	if sound == nil {return}
	sound.looping = bool(looping)
}

set_position :: proc(sound: ^Sound, x, y, z: f32) {}

set_velocity :: proc(sound: ^Sound, x, y, z: f32) {}

set_spatialization :: proc(sound: ^Sound, enabled: b32) {}

set_relative :: proc(sound: ^Sound, relative: bool) {}

get_cursor_frames :: proc(sound: ^Sound) -> u64 {
	return 0
}

get_length_frames :: proc(sound: ^Sound) -> u64 {
	return 0
}

seek_frames :: proc(sound: ^Sound, frame: u64) -> bool {
	return false
}

listener_set_position :: proc(x, y, z: f32) -> bool {
	return true
}

listener_set_direction :: proc(x, y, z: f32) -> bool {
	return true
}

listener_set_velocity :: proc(x, y, z: f32) -> bool {
	return true
}
