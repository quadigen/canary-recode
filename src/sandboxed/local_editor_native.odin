#+build !js
package sandboxed

import "core:os"

local_editor_directory :: proc() -> string {
	return os.get_env("KINEMIUM_EDITOR_DIR", context.temp_allocator)
}
