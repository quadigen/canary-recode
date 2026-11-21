package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

EDITABLE_SOUND_MAX_SAMPLES :: 8 * 1024 * 1024
EditableSound_Class := Class_Info {
	name   = "EditableSound",
	parent = &Instance_Class,
}

EditableSound :: struct {
	using object:          Object,
	samples:               []f32,
	sample_rate, channels: int,
	handle:                u32,
	revision:              u64,
}

editable_sound_handles: map[u32]^EditableSound
editable_sound_next_handle: u32

EditableSound_Of_Handle :: proc(id: u32) -> ^EditableSound {
	sound := editable_sound_handles[id]
	if sound == nil || sound.destroyed {return nil}
	return sound
}

EditableSound_Valid_Format :: proc(rate, channels, frames: f64) -> bool {
	return(
		rate >= 8000 &&
		rate <= 96000 &&
		rate == math.floor(rate) &&
		(channels == 1 || channels == 2) &&
		frames >= 1 &&
		frames <= f64(EDITABLE_SOUND_MAX_SAMPLES) / channels &&
		frames == math.floor(frames) \
	)
}

EditableSound_Resize :: proc(sound: ^EditableSound, rate, channels, frames: int) {
	if sound.sample_rate == rate &&
	   sound.channels == channels &&
	   len(sound.samples) == frames * channels {return}
	delete(sound.samples)
	sound.samples = make([]f32, frames * channels)
	sound.sample_rate, sound.channels = rate, channels
	sound.revision += 1
}

editable_sound_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	sound := new(EditableSound)
	sound.object = Object_Init(&EditableSound_Class, "EditableSound")
	EditableSound_Resize(sound, 44100, 1, 1)
	if editable_sound_handles == nil {editable_sound_handles = make(map[u32]^EditableSound)}
	for {
		editable_sound_next_handle += 1
		if editable_sound_next_handle != 0 &&
		   editable_sound_handles[editable_sound_next_handle] == nil {break}
	}
	sound.handle = editable_sound_next_handle
	editable_sound_handles[sound.handle] = sound
	return &sound.object
}

editable_sound_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	sound := cast(^EditableSound)object
	delete_key(&editable_sound_handles, sound.handle)
	delete(sound.samples)
	Object_Destroy(object)
	free(sound)
}

editable_sound_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^EditableSound)source, cast(^EditableSound)destination
	EditableSound_Resize(dst, src.sample_rate, src.channels, len(src.samples) / src.channels)
	copy(dst.samples, src.samples)
	dst.revision += 1
}

editable_sound_get :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	sound := cast(^EditableSound)object
	switch key {
	case "SampleRate":
		vm.PushNumber(L, f64(sound.sample_rate))
	case "Channels":
		vm.PushNumber(L, f64(sound.channels))
	case "FrameCount":
		vm.PushNumber(L, f64(len(sound.samples) / sound.channels))
	case "TimeLength":
		vm.PushNumber(L, f64(len(sound.samples) / sound.channels) / f64(sound.sample_rate))
	case "ReadSamplesBuffer", "WriteSamplesBuffer", "Resize", "Clear", "GetSample", "SetSample":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

editable_sound_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	sound := cast(^EditableSound)object
	frames := len(sound.samples) / sound.channels
	switch method {
	case "Resize":
		n := vm.ArgNumber(L, 2)
		if !EditableSound_Valid_Format(
			f64(sound.sample_rate),
			f64(sound.channels),
			n,
		) {return vm.RaiseError(L, "invalid EditableSound frame count"), true}
		if int(n) != frames {
			next := make([]f32, int(n) * sound.channels)
			copy(next, sound.samples)
			delete(sound.samples)
			sound.samples = next
			sound.revision += 1
		}
		return 0, true
	case "Clear":
		for &sample in sound.samples {sample = 0}
		sound.revision += 1
		return 0, true
	case "GetSample", "SetSample", "ReadSamplesBuffer", "WriteSamplesBuffer":
	case:
		return 0, false
	}
	start := vm.ArgNumber(L, 2)
	if !(start >= 0 &&
		   start <= f64(frames) &&
		   start == math.floor(start)) {return vm.RaiseError(L, "invalid sample frame"), true}
	if method == "GetSample" || method == "SetSample" {
		channel := vm.ArgNumber(L, 3)
		if !(start < f64(frames) &&
			   channel >= 0 &&
			   channel < f64(sound.channels) &&
			   channel ==
				   math.floor(
					   channel,
				   )) {return vm.RaiseError(L, "sample is outside the sound"), true}
		index := int(start) * sound.channels + int(channel)
		if method == "GetSample" {
			vm.PushNumber(L, f64(sound.samples[index]))
			return 1, true
		}
		value := vm.ArgNumber(L, 4)
		if !(value >= -1 &&
			   value <=
				   1) {return vm.RaiseError(L, "samples must be finite and between -1 and 1"), true}
		sound.samples[index] = f32(value)
		sound.revision += 1
		return 0, true
	}
	count := vm.ArgNumber(L, 3)
	if !(count >= 0 &&
		   count <= f64(frames) - start &&
		   count ==
			   math.floor(
				   count,
			   )) {return vm.RaiseError(L, "sample region is outside the sound"), true}
	region := sound.samples[int(start) * sound.channels:int(start + count) * sound.channels]

	if method == "ReadSamplesBuffer" {
		bytes := make([]u8, len(region) * 4, context.temp_allocator)
		for value, i in region {
			bits := transmute(u32)value
			for j in 0 ..< 4 {bytes[i * 4 + j] = u8(bits >> u32(j * 8))}
		}
		vm.PushBuffer(L, bytes)
		delete(bytes, context.temp_allocator)
		return 1, true
	}
	bytes := vm.ArgBuffer(L, 4)
	if len(bytes) !=
	   len(region) * 4 {return vm.RaiseError(L, "incorrect sample buffer size"), true}
	for i in 0 ..< len(region) {
		bits :=
			u32(bytes[i * 4]) |
			u32(bytes[i * 4 + 1]) << 8 |
			u32(bytes[i * 4 + 2]) << 16 |
			u32(bytes[i * 4 + 3]) << 24
		value := transmute(f32)bits
		if !(value >= -1 &&
			   value <=
				   1) {return vm.RaiseError(L, "samples must be finite and between -1 and 1"), true}
	}
	for &value, i in region {
		bits :=
			u32(bytes[i * 4]) |
			u32(bytes[i * 4 + 1]) << 8 |
			u32(bytes[i * 4 + 2]) << 16 |
			u32(bytes[i * 4 + 3]) << 24
		value = transmute(f32)bits
	}
	sound.revision += 1
	return 0, true
}

Register_EditableSound :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&EditableSound_Class,
		editable_sound_construct,
		editable_sound_destroy,
		clone = editable_sound_clone,
		get = editable_sound_get,
		namecall = editable_sound_namecall,
		properties = []string{"SampleRate", "Channels", "FrameCount", "TimeLength"},
		methods = []string {
			"ReadSamplesBuffer",
			"WriteSamplesBuffer",
			"Resize",
			"Clear",
			"GetSample",
			"SetSample",
		},
	)
}
