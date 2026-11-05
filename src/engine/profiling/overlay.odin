
package profiling

import sdl3 "../platform"

enabled: bool = false

init :: proc() {
	reset_state()
}

shutdown :: proc() {
	shutdown_thread_state()
}

reset_state :: proc() {
	enabled = false
	set_collection_enabled(false)
}

is_enabled :: proc() -> bool {
	return enabled
}

set_enabled :: proc(on: bool) {
	enabled = on
	set_collection_enabled(on)
}

trigger_event :: proc(ev: sdl3.Event) {
	if ev.type == .KEY_DOWN && ev.key.scancode == .F2 {
		enabled = !enabled
		set_collection_enabled(enabled)
	}
}
