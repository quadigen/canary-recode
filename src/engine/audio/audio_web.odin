#+build js
package audio

import "core:strings"

foreign import "kinemium_audio"

@(default_calling_convention = "c")
foreign kinemium_audio {
	host_play_sound :: proc(path: cstring) ---
	host_pcm_load :: proc(samples: rawptr, frames, rate, channels: u32) -> u32 ---
	host_pcm_destroy :: proc(id: u32) ---
	host_pcm_play :: proc(id: u32) -> i32 ---
	host_pcm_pause :: proc(id: u32) ---
	host_pcm_playing :: proc(id: u32) -> i32 ---
	host_pcm_ended :: proc(id: u32) -> i32 ---
	host_pcm_volume :: proc(id: u32, value: f32) ---
	host_pcm_pitch :: proc(id: u32, value: f32) ---
	host_pcm_loop :: proc(id: u32, value: i32) ---
	host_pcm_cursor :: proc(id: u32) -> f64 ---
	host_pcm_seek :: proc(id: u32, seconds: f64) ---

}

Sound_Flag :: enum u32 {
	Loop,
}

Sound_Flags :: distinct bit_set[Sound_Flag;u32]

Sound :: struct {
	path:                         string,
	loaded:                       bool,
	playing:                      bool,
	volume:                       f32,
	looping:                      bool,
	pcm_id, pcm_rate, pcm_frames: u32,
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

load_pcm :: proc(sound: ^Sound, samples: []f32, rate, channels: int) -> bool {
	if sound == nil ||
	   channels < 1 ||
	   rate < 1 ||
	   len(samples) == 0 ||
	   len(samples) % channels != 0 {return false}
	unload_sound(sound)
	frames := u32(len(samples) / channels)
	id := host_pcm_load(raw_data(samples), frames, u32(rate), u32(channels))
	if id == 0 {return false}
	sound.pcm_id, sound.pcm_rate, sound.pcm_frames = id, u32(rate), frames
	sound.loaded = true
	return true
}

unload_sound :: proc(sound: ^Sound) {
	if sound == nil {return}
	if sound.pcm_id != 0 {host_pcm_destroy(sound.pcm_id)}
	if sound.path != "" {delete(sound.path)}
	sound^ = {}
}

play :: proc(sound: ^Sound) -> bool {
	if sound == nil || !sound.loaded {return false}
	if sound.pcm_id != 0 {return host_pcm_play(sound.pcm_id) != 0}
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
	if sound.pcm_id != 0 {host_pcm_pause(sound.pcm_id)}
	sound.playing = false
	return true
}

is_loaded :: proc(sound: ^Sound) -> bool {
	return sound != nil && sound.loaded
}

stop_sound :: proc(sound: ^Sound) -> bool {
	if sound == nil {return false}
	if sound.pcm_id != 0 {host_pcm_pause(sound.pcm_id); host_pcm_seek(sound.pcm_id, 0)}
	sound.playing = false
	return true
}

is_playing :: proc(sound: ^Sound) -> b32 {
	if sound != nil && sound.pcm_id != 0 {return b32(host_pcm_playing(sound.pcm_id) != 0)}
	return b32(sound != nil && sound.playing)
}

at_end :: proc(sound: ^Sound) -> bool {
	return sound != nil && sound.pcm_id != 0 && host_pcm_ended(sound.pcm_id) != 0
}

set_volume :: proc(sound: ^Sound, volume: f32) {
	if sound == nil {return}
	sound.volume = volume
	if sound.pcm_id != 0 {host_pcm_volume(sound.pcm_id, volume)}
}

set_pitch :: proc(sound: ^Sound, pitch: f32) {
	if sound != nil && sound.pcm_id != 0 {host_pcm_pitch(sound.pcm_id, pitch)}
}

set_pan :: proc(sound: ^Sound, pan: f32) {}

set_looping :: proc(sound: ^Sound, looping: b32) {
	if sound == nil {return}
	sound.looping = bool(looping)
	if sound.pcm_id != 0 {host_pcm_loop(sound.pcm_id, i32(looping))}
}

set_position :: proc(sound: ^Sound, x, y, z: f32) {}

set_velocity :: proc(sound: ^Sound, x, y, z: f32) {}

set_spatialization :: proc(sound: ^Sound, enabled: b32) {}

set_relative :: proc(sound: ^Sound, relative: bool) {}

get_cursor_frames :: proc(sound: ^Sound) -> u64 {
	if sound != nil &&
	   sound.pcm_id !=
		   0 {return u64(max(0.0, host_pcm_cursor(sound.pcm_id)) * f64(sound.pcm_rate))}
	return 0
}

get_length_frames :: proc(sound: ^Sound) -> u64 {
	if sound != nil {return u64(sound.pcm_frames)}
	return 0
}

seek_frames :: proc(sound: ^Sound, frame: u64) -> bool {
	if sound != nil &&
	   sound.pcm_id !=
		   0 {host_pcm_seek(sound.pcm_id, f64(min(frame, u64(sound.pcm_frames))) / f64(sound.pcm_rate)); return true}
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
