#+build !js
package audio

import miniaudio "vendor:miniaudio"
import "core:strings"

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

get_engine :: proc() -> ^miniaudio.engine {
	if !initialized && !init() {
		return nil
	}

	return &audio_engine
}

play_sound :: proc(path: string) -> bool {
	engine := get_engine()
	if engine == nil {
		return false
	}

	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)

	return miniaudio.engine_play_sound(
		engine,
		cpath,
		nil,
	) == .SUCCESS
}