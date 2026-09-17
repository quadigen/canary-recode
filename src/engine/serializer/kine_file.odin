#+build !js

package serializer

import "core:os"
import classes "../classes"
import vm "../vm"

// Serialize_To_File writes an Instance hierarchy to a .KINE file on disk.
Serialize_To_File :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	object: ^classes.Object,
	path: string,
) -> bool {
	data, ok := Serialize(registry, L, object)
	if !ok {
		return false
	}
	defer delete(data)

	return os.write_entire_file(path, data) == 0
}

// Deserialize_From_File reads a .KINE file from disk and restores the
// Instance hierarchy under parent (which may be nil for a standalone root).
Deserialize_From_File :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	parent: ^classes.Object,
	path: string,
) -> (^classes.Object, bool) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != 0 {
		return nil, false
	}
	defer delete(data)

	return Deserialize(registry, L, parent, data)
}