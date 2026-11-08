package classes

import assetstore "../assetstore"
import audio "../audio"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"
import fmt "core:fmt"
import "core:strings"

Sound_Class := Class_Info {
	name   = "Sound",
	parent = &Instance_Class,
}

Sound :: struct {
	using object:             Object,
	sound_path:               string,
	content:                  datatypes.Content,
	is_loaded:                bool,
	is_playing:               bool,
	is_paused:                bool,
	playing:                  bool,
	looped:                   bool,
	loopregion:               datatypes.NumberRange,
	playback_region:          datatypes.NumberRange,
	playback_regions_enabled: bool,
	playback_speed:           f64,
	playback_loudness:        f64,
	play_on_remove:           bool,
	roll_off_max_dist:        f64,
	roll_off_min_dist:        f64,
	roll_off_mode:            enums.RollOffMode,
	volume:                   f64,
	time_position:            f64,
	length:                   f64,
	sound:                    audio.Sound,
}

Sound_Init :: proc() -> Sound {
	return Sound {
		object = Object_Init(&Sound_Class),
		sound_path = "",
		content = {},
		is_loaded = false,
		is_playing = false,
		is_paused = true,
		playing = false,
		looped = false,
		loopregion = {},
		playback_region = {},
		playback_regions_enabled = false,
		playback_speed = 1.0,
		playback_loudness = 0,
		play_on_remove = false,
		roll_off_max_dist = 10000,
		roll_off_min_dist = 10,
		roll_off_mode = .Inverse,
		volume = 0.5,
		time_position = 0,
		length = 0,
	}
}

Sound_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	sound := cast(^Sound)object

	switch key {
	case "AudioContent":
		datatypes.Push_Content(L, datatype_registry, datatypes.Content_Clone(sound.content))
		return true

	case "SoundId":
		vm.PushString(L, sound.sound_path)
		return true

	case "IsLoaded":
		vm.PushBoolean(L, audio.is_loaded(&sound.sound))
		return true

	case "IsPaused":
		vm.PushBoolean(L, sound.is_paused)
		return true

	case "IsPlaying", "isPlaying":
		vm.PushBoolean(L, audio.is_loaded(&sound.sound) && audio.is_playing(&sound.sound))
		return true

	case "Playing":
		vm.PushBoolean(L, sound.playing)
		return true

	case "Looped":
		vm.PushBoolean(L, sound.looped)
		return true

	case "LoopRegion":
		datatypes.Push_NumberRange(L, datatype_registry, sound.loopregion)
		return true

	case "PlaybackRegion":
		datatypes.Push_NumberRange(L, datatype_registry, sound.playback_region)
		return true

	case "PlaybackRegionsEnabled":
		vm.PushBoolean(L, sound.playback_regions_enabled)
		return true

	case "PlaybackSpeed":
		vm.PushNumber(L, sound.playback_speed)
		return true

	case "PlaybackLoudness":
		vm.PushNumber(L, sound.playback_loudness)
		return true

	case "PlayOnRemove":
		vm.PushBoolean(L, sound.play_on_remove)
		return true

	case "RollOffMaxDistance":
		vm.PushNumber(L, sound.roll_off_max_dist)
		return true

	case "RollOffMinDistance":
		vm.PushNumber(L, sound.roll_off_min_dist)
		return true

	case "Volume":
		vm.PushNumber(L, sound.volume)
		return true

	case "TimePosition":
		vm.PushNumber(L, sound.time_position)
		return true

	case "TimeLength":
		vm.PushNumber(L, sound.length)
		return true
	}

	return false
}

Sound_Play :: proc(sound: ^Sound) -> bool {
	if !audio.is_loaded(&sound.sound) {
		if !Sound_Load_Source(sound) {
			sound.is_loaded = false
			sound.is_playing = false
			sound.playing = false
			return false
		}
	}

	if !audio.is_playing(&sound.sound) {
		if !audio.play(&sound.sound) {
			return false
		}
	}

	sound.is_playing = true
	sound.is_paused = false
	sound.playing = true
	return true
}

Sound_Pause :: proc(sound: ^Sound) {
	if !audio.is_loaded(&sound.sound) || !audio.is_playing(&sound.sound) {
		return
	}

	audio.pause(&sound.sound)
	sound.is_playing = false
	sound.is_paused = true
	sound.playing = false
}

Sound_Resume :: proc(sound: ^Sound) {
	if !audio.is_loaded(&sound.sound) || !sound.is_paused {
		return
	}

	audio.play(&sound.sound)
	sound.is_playing = true
	sound.is_paused = false
	sound.playing = true
}

Sound_Stop :: proc(sound: ^Sound) {
	if audio.is_loaded(&sound.sound) {
		audio.stop_sound(&sound.sound)
	}

	sound.is_playing = false
	sound.is_paused = true
	sound.playing = false
	sound.time_position = 0
}

Sound_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	sound := cast(^Sound)object

	switch method {
	case "Play":
		_ = Sound_Play(sound)
		return 0, true

	case "Pause":
		Sound_Pause(sound)
		return 0, true

	case "Resume":
		Sound_Resume(sound)
		return 0, true

	case "Stop":
		Sound_Stop(sound)
		return 0, true
	}

	return 0, false
}


Sound_Load_Source :: proc(sound: ^Sound) -> bool {
	path := sound.sound_path
	if path == "" {path = sound.content.uri}
	if path == "" {return false}
	resolved := assetstore.Resolve_Path(path)
	defer delete(resolved)
	if resolved == "" {
		assetstore.Report_Missing_Asset(path, "Sound")
		return false
	}
	if !audio.load_sound(&sound.sound, resolved) {
		fmt.println("Failed to load sound:", path)
		return false
	}
	sound.is_loaded = true
	audio.set_volume(&sound.sound, f32(sound.volume))
	audio.set_pitch(&sound.sound, f32(sound.playback_speed))
	audio.set_looping(&sound.sound, b32(sound.looped))
	return true
}

Sound_Reload :: proc(sound: ^Sound) {
	if audio.is_loaded(&sound.sound) {
		audio.unload_sound(&sound.sound)
	}
	sound.is_loaded = false
	sound.is_playing = false
	sound.is_paused = true
	sound.playing = false
	sound.time_position = 0
	sound.length = 0
	_ = Sound_Load_Source(sound)
}

Sound_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	sound := cast(^Sound)object

	switch key {
	case "SoundId":
		path := assetstore.Resolve_Ugc_Asset(vm.ArgString(L, value_index), .Audio)

		if sound.sound_path == path && audio.is_loaded(&sound.sound) {
			delete(path)
			return true
		}

		delete(sound.sound_path)
		sound.sound_path = path
		Sound_Reload(sound)
		return true

	case "AudioContent":
		content := datatypes.Content_Clone(
			datatypes.Arg_Content(L, value_index, datatype_registry),
		)
		delete(sound.content.uri)
		sound.content = content
		if sound.sound_path == "" {
			Sound_Reload(sound)
		}
		return true

	case "Looped":
		sound.looped = vm.ArgBoolean(L, value_index)

		if audio.is_loaded(&sound.sound) {
			audio.set_looping(&sound.sound, b32(sound.looped))
		}
		return true

	case "LoopRegion":
		sound.loopregion = datatypes.Arg_NumberRange(L, value_index, datatype_registry)
		return true

	case "PlaybackRegion":
		sound.playback_region = datatypes.Arg_NumberRange(L, value_index, datatype_registry)
		return true

	case "PlaybackRegionsEnabled":
		sound.playback_regions_enabled = vm.ArgBoolean(L, value_index)
		return true

	case "PlaybackSpeed":
		speed := vm.ArgNumber(L, value_index)
		if speed <= 0 {
			return true
		}

		sound.playback_speed = speed

		if audio.is_loaded(&sound.sound) {
			audio.set_pitch(&sound.sound, f32(speed))
		}
		return true

	case "PlayOnRemove":
		sound.play_on_remove = vm.ArgBoolean(L, value_index)
		return true

	case "RollOffMaxDistance":
		sound.roll_off_max_dist = max(0.0, vm.ArgNumber(L, value_index))
		return true

	case "RollOffMinDistance":
		sound.roll_off_min_dist = max(0.0, vm.ArgNumber(L, value_index))
		return true

	case "Volume":
		sound.volume = max(0.0, vm.ArgNumber(L, value_index))

		if audio.is_loaded(&sound.sound) {
			audio.set_volume(&sound.sound, f32(sound.volume))
		}
		return true

	case "TimePosition":
		sound.time_position = max(0.0, vm.ArgNumber(L, value_index))

		return true

	case "Playing":
		sound.playing = vm.ArgBoolean(L, value_index)

		if sound.playing {
			if !audio.is_loaded(&sound.sound) {
				if !Sound_Load_Source(sound) {
					sound.is_loaded = false
					sound.is_playing = false
					return true
				}
			}

			if !audio.is_playing(&sound.sound) {
				if audio.play(&sound.sound) {
					sound.is_playing = true
					sound.is_paused = false
				}
			}
		} else {
			if audio.is_loaded(&sound.sound) {
				audio.stop_sound(&sound.sound)
			}

			sound.is_playing = false
			sound.is_paused = true
		}

		return true
	}

	return false
}


Sound_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	sound := new(Sound)
	sound^ = Sound_Init()
	sound.name = "Sound"
	sound.sound = {}

	return &sound.object
}

Sound_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	sound := cast(^Sound)object

	if audio.is_loaded(&sound.sound) {
		audio.unload_sound(&sound.sound)
	}

	delete(sound.sound_path)
	delete(sound.content.uri)
	Object_Destroy(object)
	free(sound)
}

Sound_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Sound)source
	dst := cast(^Sound)destination

	dst.sound_path = strings.clone(src.sound_path)
	dst.content = datatypes.Content_Clone(src.content)

	dst.is_loaded = src.is_loaded
	dst.is_playing = src.is_playing
	dst.is_paused = src.is_paused
	dst.playing = src.playing

	dst.looped = src.looped
	dst.loopregion = src.loopregion
	dst.playback_region = src.playback_region
	dst.playback_regions_enabled = src.playback_regions_enabled
	dst.playback_speed = src.playback_speed

	dst.playback_loudness = src.playback_loudness
	dst.play_on_remove = src.play_on_remove

	dst.roll_off_max_dist = src.roll_off_max_dist
	dst.roll_off_min_dist = src.roll_off_min_dist
	dst.roll_off_mode = src.roll_off_mode

	dst.volume = src.volume
	dst.time_position = src.time_position
	dst.length = src.length
}

Register_Sound :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Sound_Class,
		Sound_construct,
		Sound_destroy,
		clone = Sound_clone,
		get = Sound_get,
		set = Sound_set,
		properties = []string {
			"AudioContent",
			"SoundId",
			"IsLoaded",
			"IsPaused",
			"IsPlaying",
			"Playing",
			"Looped",
			"LoopRegion",
			"PlaybackRegion",
			"PlaybackRegionsEnabled",
			"PlaybackSpeed",
			"PlaybackLoudness",
			"PlayOnRemove",
			"RollOffMaxDistance",
			"RollOffMinDistance",
			"RollOffMode",
			"Volume",
			"TimePosition",
			"TimeLength",
		},
		namecall = Sound_namecall,
		methods = []string{"Play", "Pause", "Resume", "Stop"},
		events = []string{"DidLoop", "Ended", "Loaded", "Paused", "Played", "Resumed", "Stopped"},
	)
}
