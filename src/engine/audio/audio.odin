#+build !js
package audio

import miniaudio "vendor:miniaudio"
import "core:strings"

init :: proc() {
    engine: miniaudio.engine
    miniaudio.engine_init(nil, &engine)
    defer miniaudio.engine_uninit(&engine)
}

play_sound :: proc(path: string) {
    engine: miniaudio.engine
    miniaudio.engine_init(nil, &engine)
    defer miniaudio.engine_uninit(&engine)

    cpath := strings.clone_to_cstring(path)
    defer delete(cpath)

    sound: miniaudio.sound
    result := miniaudio.engine_play_sound(&engine, cpath, nil)
}
