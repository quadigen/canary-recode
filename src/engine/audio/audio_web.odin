#+build js
package audio

import "core:strings"

foreign import "kinemium_audio"

@(default_calling_convention="c")
foreign kinemium_audio {
	host_play_sound :: proc(path: cstring) ---
}

init :: proc() {}

play_sound :: proc(path: string) {
	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)
	host_play_sound(cpath)
}
