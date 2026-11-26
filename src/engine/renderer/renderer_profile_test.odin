#+build !js

package renderer

import "core:testing"

@(test)
filament_profile_callback_depth_is_bounded :: proc(t: ^testing.T) {
	state := Filament_Profile_State{}
	for _ in 0 ..< 24 {
		filament_profile_callback(&state, cstring("nested-phase"), true)
	}
	testing.expect(t, state.depth == 24, "deep profiling must track nesting beyond the cache")

	for _ in 0 ..< 24 {
		filament_profile_callback(&state, cstring("nested-phase"), false)
	}
	testing.expect(t, state.depth == 0, "ending every phase must restore zero nesting")


	filament_profile_callback(&state, cstring("unmatched-phase"), false)
	testing.expect(t, state.depth == 0, "an unmatched end must not underflow")
}
