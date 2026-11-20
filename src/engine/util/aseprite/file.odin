#+build !js

package aseprite

import "core:os"

load_from_file :: proc(path: string, allocator := context.allocator) -> (ase: ^Ase, err: Error) {
	data, read_err := os.read_entire_file(path, allocator)
	if read_err != nil {
		return nil, .File_Read_Failed
	}
	defer delete(data, allocator)
	return load_from_memory(data, allocator)
}
