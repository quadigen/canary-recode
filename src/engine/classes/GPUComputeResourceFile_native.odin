#+build !js
package classes

import assets "../assetstore"
import gpu "../gpucompute"
import "core:os"

gpu_compute_texture_file :: proc(
	device: ^gpu.Device,
	path: string,
	srgb, mips, nearest, clamp_address: bool,
) -> (
	u32,
	string,
) {
	resolved := assets.Resolve_Path(path)
	defer delete(resolved)
	if resolved == "" {return 0, "texture asset not found"}
	f, open_err := os.open(resolved)
	if open_err != nil {return 0, "texture asset could not be opened"}
	file_size, size_err := os.file_size(f)
	os.close(f)
	if size_err != nil ||
	   file_size <= 0 ||
	   file_size >
		   gpu.MAX_CUSTOM_BUFFER_BYTES {return 0, "texture asset exceeds encoded size limit"}
	data, err := os.read_entire_file(resolved, context.allocator)
	if err != nil {return 0, "texture asset could not be read"}
	defer delete(data)
	return gpu_compute_texture_encoded(device, data, srgb, mips, nearest, clamp_address)
}
