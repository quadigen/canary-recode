package classes

import assetstore "../assetstore"
import audio "../audio"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import signals "../signals"
import vm "../vm"
import fmt "core:fmt"
import "core:math"
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
	editable_revision:        u64,
	editable_sample_rate:     int,
	ended:                    ^signals.Signal,
	loaded_event:             ^signals.Signal,
	played_event:             ^signals.Signal,
	paused_event:             ^signals.Signal,
	resumed_event:            ^signals.Signal,
	stopped_event:            ^signals.Signal,
	did_loop_event:           ^signals.Signal,
	has_started:              bool,
	last_cursor_frames:       u64,
	cursor_valid:             bool,
}


Sound_Fire_Event :: proc(sound: ^Sound, signal: ^signals.Signal) {
	if signal == nil ||
	   sound.object.signal_registry == nil ||
	   sound.object.signal_registry.signal_registry == nil {
		return
	}
	L := sound.object.signal_registry.signal_registry.L
	if L != nil {signals.Fire(L, signal, 0)}
}

Sound_Push_Event :: proc(L: ^vm.State, object: ^Object, slot: ^^signals.Signal) {
	if slot^ == nil {slot^ = Object_Create_Hierarchy_Signal(object)}
	signals.Push(L, slot^)
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
	case "Ended":
		Sound_Push_Event(L, object, &sound.ended)
		return true
	case "Loaded":
		Sound_Push_Event(L, object, &sound.loaded_event)
		return true
	case "Played":
		Sound_Push_Event(L, object, &sound.played_event)
		return true
	case "Paused":
		Sound_Push_Event(L, object, &sound.paused_event)
		return true
	case "Resumed":
		Sound_Push_Event(L, object, &sound.resumed_event)
		return true
	case "Stopped":
		Sound_Push_Event(L, object, &sound.stopped_event)
		return true
	case "DidLoop":
		Sound_Push_Event(L, object, &sound.did_loop_event)
		return true

	case "EditableSound":
		if source := Sound_Editable_Source(sound);
		   source != nil {Push_Object(L, &source.object)} else {vm.PushNil(L)}
		return true

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

Sound_update :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	sound := cast(^Sound)object
	if sound.editable_sample_rate > 0 && audio.is_loaded(&sound.sound) {
		sound.time_position =
			f64(audio.get_cursor_frames(&sound.sound)) / f64(sound.editable_sample_rate)
	}
	if sound.looped && sound.is_playing && audio.is_loaded(&sound.sound) {
		cursor := audio.get_cursor_frames(&sound.sound)
		if sound.cursor_valid && cursor < sound.last_cursor_frames {
			Sound_Fire_Event(sound, sound.did_loop_event)
		}
		sound.last_cursor_frames = cursor
		sound.cursor_valid = true
	} else {
		sound.cursor_valid = false
	}
	if sound.is_playing && !sound.looped && audio.at_end(&sound.sound) {
		sound.is_playing = false
		sound.playing = false
		sound.has_started = false
		sound.cursor_valid = false
		if sound.ended != nil {signals.Fire(ctx.L, sound.ended)}
	}
}

Sound_Play :: proc(sound: ^Sound) -> bool {
	was_playing := sound.is_playing && audio.is_playing(&sound.sound)
	if sound.content.object_kind == 2 &&
	   sound.sound_path == "" &&
	   !audio.is_playing(&sound.sound) {
		source := Sound_Editable_Source(sound)
		if source == nil || source.revision != sound.editable_revision {
			Sound_Reload(sound)
		}
	}
	if !audio.is_loaded(&sound.sound) {
		if !Sound_Load_Source(sound) {
			sound.is_loaded = false
			sound.is_playing = false
			sound.playing = false
			return false
		}
	}

	if !audio.is_playing(&sound.sound) {
		if sound.editable_sample_rate > 0 &&
		   audio.at_end(&sound.sound) {_ = audio.seek_frames(&sound.sound, 0)}
		if !audio.play(&sound.sound) {
			return false
		}
	}

	sound.is_playing = true
	sound.is_paused = false
	sound.playing = true
	sound.has_started = true
	if !was_playing {
		sound.cursor_valid = false
		Sound_Fire_Event(sound, sound.played_event)
	}
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
	sound.cursor_valid = false
	Sound_Fire_Event(sound, sound.paused_event)
}

Sound_Resume :: proc(sound: ^Sound) {
	if !audio.is_loaded(&sound.sound) || !sound.is_paused {
		return
	}

	if !audio.play(&sound.sound) {return}
	sound.is_playing = true
	sound.is_paused = false
	sound.playing = true
	sound.has_started = true
	sound.cursor_valid = false
	Sound_Fire_Event(sound, sound.resumed_event)
}

Sound_Stop :: proc(sound: ^Sound) {
	was_started := sound.has_started
	if audio.is_loaded(&sound.sound) {
		audio.stop_sound(&sound.sound)
	}

	sound.is_playing = false
	sound.is_paused = true
	sound.playing = false
	sound.time_position = 0
	sound.cursor_valid = false
	sound.has_started = false
	if was_started {Sound_Fire_Event(sound, sound.stopped_event)}
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


Sound_Editable_Source :: proc(sound: ^Sound) -> ^EditableSound {
	if sound.content.object_kind != 2 || sound.sound_path != "" {return nil}
	return EditableSound_Of_Handle(sound.content.object_id)
}

Sound_Load_Source :: proc(sound: ^Sound) -> bool {
	if sound.sound_path == "" && sound.content.object_kind == 2 {
		source := Sound_Editable_Source(sound)
		if source == nil {return false}
		if !audio.load_pcm(
			&sound.sound,
			source.samples,
			source.sample_rate,
			source.channels,
		) {return false}
		sound.editable_revision = source.revision
		sound.editable_sample_rate = source.sample_rate
		sound.length = f64(len(source.samples) / source.channels) / f64(source.sample_rate)
		sound.is_loaded = true
		audio.set_volume(&sound.sound, f32(sound.volume))
		audio.set_pitch(&sound.sound, f32(sound.playback_speed))
		audio.set_looping(&sound.sound, b32(sound.looped))
		Sound_Fire_Event(sound, sound.loaded_event)
		return true
	}

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
	Sound_Fire_Event(sound, sound.loaded_event)
	return true
}

Sound_Reload :: proc(sound: ^Sound) {
	if audio.is_loaded(&sound.sound) {
		audio.unload_sound(&sound.sound)
	}
	sound.is_loaded = false
	sound.cursor_valid = false
	sound.has_started = false
	sound.editable_revision = 0
	sound.editable_sample_rate = 0
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

	case "EditableSound":
		content := datatypes.Content{}
		if !vm.IsNoneOrNil(L, value_index) {
			source := object_from_argument(L, value_index)
			if source == nil || !Is_A_Class(source, &EditableSound_Class) {
				_ = vm.RaiseError(L, "expected EditableSound or nil")
				return true
			}
			content = datatypes.Content_From_Object(source)
		}
		delete(sound.sound_path)
		sound.sound_path = ""
		delete(sound.content.uri)
		sound.content = content
		Sound_Reload(sound)
		return true

	case "AudioContent":
		content := datatypes.Content_Clone(
			datatypes.Arg_Content(L, value_index, datatype_registry),
		)
		delete(sound.content.uri)
		sound.content = content
		if content.object_kind == 2 {
			delete(sound.sound_path)
			sound.sound_path = ""
		}
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
		position := vm.ArgNumber(L, value_index)
		if math.is_nan(position) || math.is_inf(position) {return true}
		sound.time_position = max(0, position)
		sound.cursor_valid = false
		if sound.editable_sample_rate > 0 && audio.is_loaded(&sound.sound) {
			sound.time_position = clamp(sound.time_position, 0, sound.length)
			_ = audio.seek_frames(
				&sound.sound,
				u64(sound.time_position * f64(sound.editable_sample_rate)),
			)
		}
		return true

	case "Playing":
		if vm.ArgBoolean(L, value_index) {
			_ = Sound_Play(sound)
		} else {
			Sound_Stop(sound)
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
	if sound.ended != nil {signals.Destroy(sound.ended)}
	if sound.loaded_event != nil {signals.Destroy(sound.loaded_event)}
	if sound.played_event != nil {signals.Destroy(sound.played_event)}
	if sound.paused_event != nil {signals.Destroy(sound.paused_event)}
	if sound.resumed_event != nil {signals.Destroy(sound.resumed_event)}
	if sound.stopped_event != nil {signals.Destroy(sound.stopped_event)}
	if sound.did_loop_event != nil {signals.Destroy(sound.did_loop_event)}
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
	if src.content.object_kind == 2 && src.sound_path == "" {
		dst.is_loaded = false
		dst.is_playing = false
		dst.is_paused = true
		dst.playing = false
		dst.time_position = 0
		dst.length = 0
	}
}

Register_Sound :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Sound_Class,
		Sound_construct,
		Sound_destroy,
		_step = Sound_update,
		_step_phase = .Update,
		clone = Sound_clone,
		get = Sound_get,
		set = Sound_set,
		properties = []string {
			"AudioContent",
			"EditableSound",
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
