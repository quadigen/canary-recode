#+build linux, windows
package gpucompute

validate_render_texture_shader :: proc(words: []u32) -> string {
	images: Image_Requirements; readonly: [MAX_CUSTOM_BINDINGS]bool
	layout: Binding_Layout; layout[0] = .StorageTexture
	if err := validate_descriptor_layout(words, 1, layout, &images, &readonly);
	   err != "" {return err}
	if !images[0].declared ||
	   images[0].dimension != .D2 ||
	   images[0].format != .RGBA8 ||
	   images[0].unsigned {
		return "DispatchTexture requires exactly one rgba8 image2D at set=0 binding=0"
	}
	local := false
	for offset := 5; offset < len(words); {
		n, op := int(words[offset] >> 16), words[offset] & 0xffff
		if n <= 0 || n > len(words) - offset {return "invalid SPIR-V instruction"}
		w := words[offset:offset + n]

		if op == 59 &&
		   n >= 4 &&
		   w[3] == 9 {return "DispatchTexture does not accept push constants"}
		if op == 16 && n >= 3 && w[2] == 17 {
			if n != 6 ||
			   w[3] != 8 ||
			   w[4] != 8 ||
			   w[5] != 1 {return "DispatchTexture requires local_size=8,8,1"}
			local = true
		}
		if op == 331 {return "DispatchTexture requires a fixed workgroup size"}
		offset += n
	}
	if !local {return "DispatchTexture requires local_size=8,8,1"}
	return ""
}
