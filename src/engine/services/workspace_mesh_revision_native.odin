#+build !js
package services

import "core:os"
import "core:time"

workspace_mesh_file_revision :: proc(path: string) -> u64 {
	file, stat_err := os.stat(path, context.allocator)
	if stat_err != nil {return 0}
	defer os.file_info_delete(file, context.allocator)
	revision := u64(time.to_unix_nanoseconds(file.modification_time))
	revision ~= u64(file.size) * 0x9e3779b97f4a7c15
	revision ~= u64(file.inode) * 0xbf58476d1ce4e5b9
	return revision
}
