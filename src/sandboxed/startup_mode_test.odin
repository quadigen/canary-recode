#+build !js
package sandboxed

import target "../engine/target"
import "core:testing"

@(test)
editor_startup_mode_test :: proc(t: ^testing.T) {
	testing.expect(t, editor_available_for(.Editor, false, false))
	testing.expect(t, !editor_available_for(.Client, true, false))
	testing.expect(t, !editor_available_for(.Server, true, false))
	testing.expect(t, !editor_available_for(.Singleplayer, true, false))
	testing.expect(t, !editor_available_for(.Client, false, true))
	testing.expect(t, editor_available_for(.Client, true, true))
	testing.expect(t, editor_available_for(.Server, true, true))
	testing.expect(t, editor_available_for(.Singleplayer, true, true))
	testing.expect(t, !editor_available_for(.Standalone, false, false))
}
