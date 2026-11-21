#+build js
package classes

import gpu "../gpucompute"

gpu_compute_texture_file :: proc(
	device: ^gpu.Device,
	path: string,
	srgb, mips, nearest, clamp_address: bool,
) -> (
	u32,
	string,
) {
	return 0, "browser textures must be loaded from embedded assets or buffers"
}
