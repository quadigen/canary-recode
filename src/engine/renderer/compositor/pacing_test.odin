#+build !js
package compositor

import "core:testing"

@(test)
background_frame_pacing_is_bounded :: proc(t: ^testing.T) {
	testing.expect(t, background_frame_delay(1, 0, 15) == 0)
	testing.expect(t, background_frame_delay(1_000_000, 1, 0) == 0)
	testing.expect(t, background_frame_delay(1, 2, 15) == 0)
	testing.expect(t, background_frame_delay(1_000_001, 1, 15) == 4)
	testing.expect(t, background_frame_delay(66_000_001, 1, 15) == 1)
	testing.expect(t, background_frame_delay(67_000_001, 1, 15) == 0)
}
