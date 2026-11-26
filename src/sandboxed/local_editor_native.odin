#+build !js
package sandboxed

import "core:os"

local_editor_directory :: proc() -> string {
	return os.get_env("KINEMIUM_EDITOR_DIR", context.temp_allocator)
}

playtest_editor_tools_enabled :: proc() -> bool {
	return os.get_env("KINE_PLAYTEST_EDITOR_TOOLS", context.temp_allocator) == "1"
}
