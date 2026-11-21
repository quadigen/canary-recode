#+build linux, windows
package gpucompute


Spirv_Descriptor :: struct {
	opcode, target, storage, dim, depth, arrayed, multisampled, sampled, format: u32,
	binding, set:                                                                u32,
	member_count, readonly_members:                                              u32,
	non_writable:                                                                bool,
	has_binding, has_set, block, buffer_block:                                   bool,
}

validate_descriptor_layout :: proc(
	words: []u32,
	count: u32,
	kinds: Binding_Layout,
	images: ^Image_Requirements,
	readonly: ^[MAX_CUSTOM_BINDINGS]bool,
) -> string {
	if len(words) < 5 || words[0] != 0x07230203 {return "invalid SPIR-V header"}
	descriptions := make(map[u32]Spirv_Descriptor)
	defer delete(descriptions)
	offset := 5
	for offset < len(words) {
		header := words[offset]
		n, op := int(header >> 16), header & 0xffff
		if n <= 0 || n > len(words) - offset {return "invalid SPIR-V instruction"}
		w := words[offset:offset + n]
		switch op {
		case 71:
			if n >= 3 {
				r := descriptions[w[1]]
				switch w[2] {
				case 2:
					r.block = true
				case 3:
					r.buffer_block = true
				case 24:
					r.non_writable = true
				case 33:
					if n >= 4 {r.binding = w[3]; r.has_binding = true}
				case 34:
					if n >= 4 {r.set = w[3]; r.has_set = true}
				}
				descriptions[w[1]] = r
			}
		case 72:
			if n >= 4 && w[3] == 24 {
				r := descriptions[w[1]]
				r.readonly_members += 1
				descriptions[w[1]] = r
			}
		case 21:
			if n >= 4 {
				r := descriptions[w[1]]
				r.opcode, r.target, r.storage = op, w[2], w[3]
				descriptions[w[1]] = r
			}
		case 22:
			if n >= 3 {
				r := descriptions[w[1]]
				r.opcode, r.target = op, w[2]
				descriptions[w[1]] = r
			}
		case 25:
			if n >= 9 {
				r := descriptions[w[1]]
				r.opcode, r.target, r.dim, r.depth, r.arrayed, r.multisampled, r.sampled, r.format =
					op, w[2], w[3], w[4], w[5], w[6], w[7], w[8]
				descriptions[w[1]] = r
			}
		case 27:
			if n >= 3 {
				r := descriptions[w[1]]
				r.opcode, r.target = op, w[2]
				descriptions[w[1]] = r
			}
		case 30:
			if n >= 2 {
				r := descriptions[w[1]]
				r.opcode = op
				r.member_count = u32(n - 2)
				descriptions[w[1]] = r
			}
		case 32:
			if n >= 4 {
				r := descriptions[w[1]]
				r.opcode, r.target, r.storage = op, w[3], w[2]
				descriptions[w[1]] = r
			}
		case 59:
			if n >= 4 {
				r := descriptions[w[2]]
				r.opcode, r.target, r.storage = op, w[1], w[3]
				descriptions[w[2]] = r
			}
		}
		offset += n
	}
	seen: [MAX_CUSTOM_BINDINGS]bool
	for _, r in descriptions {
		if r.opcode != 59 || (r.storage != 0 && r.storage != 2 && r.storage != 12) {continue}
		if !r.has_binding || !r.has_set || r.set != 0 || r.binding >= count || seen[r.binding] {
			return "shader descriptor set or binding does not match GPUCompute layout"
		}
		pointer := descriptions[r.target]
		target := descriptions[pointer.target]
		actual: Binding_Kind
		if r.storage == 2 && target.opcode == 30 && target.buffer_block {
			actual = .StorageBuffer
		} else if r.storage == 12 && target.opcode == 30 && target.block {
			actual = .StorageBuffer
		} else if r.storage == 2 && target.opcode == 30 && target.block {
			actual = .UniformBuffer
		} else if r.storage == 0 && target.opcode == 27 {
			img := descriptions[target.target]
			if img.opcode != 25 || img.sampled != 1 {return "invalid sampled image type"}
			if err := reflect_image(descriptions, img, false, &images[r.binding]);
			   err != "" {return err}
			actual = .SampledTexture
		} else if r.storage == 0 && target.opcode == 25 && target.sampled == 2 {
			if err := reflect_image(descriptions, target, true, &images[r.binding]);
			   err != "" {return err}
			actual = .StorageTexture
		} else {
			return "unsupported SPIR-V descriptor type"
		}
		if actual !=
		   kinds[r.binding] {return "shader descriptor type does not match GPUCompute layout"}


		readonly[r.binding] =
			actual == .UniformBuffer ||
			actual == .SampledTexture ||
			r.non_writable ||
			target.non_writable ||
			(actual == .StorageBuffer &&
					target.member_count > 0 &&
					target.readonly_members == target.member_count)
		seen[r.binding] = true
	}
	return ""
}


reflect_image :: proc(
	types: map[u32]Spirv_Descriptor,
	img: Spirv_Descriptor,
	storage: bool,
	out: ^Image_Requirement,
) -> string {
	out.declared = true
	if img.depth != 0 ||
	   img.multisampled != 0 {return "depth and multisampled images are not supported"}
	switch img.dim {
	case 0:
		if img.arrayed != 0 {return "1D texture arrays are not supported"}; out.dimension = .D1
	case 1:
		out.dimension = img.arrayed != 0 ? .D2Array : .D2
	case 2:
		if img.arrayed != 0 {return "3D texture arrays are not supported"}; out.dimension = .D3
	case:
		return "unsupported GPUCompute image dimension"
	}
	ty := types[img.target]
	if ty.opcode == 21 &&
	   ty.target == 32 &&
	   ty.storage == 0 {out.unsigned = true} else if ty.opcode != 22 || ty.target != 32 {
		return "GPUCompute supports float and unsigned integer image components"
	}
	if !storage {return ""}
	switch img.format {
	case 1:
		out.format = .RGBA32F
	case 2:
		out.format = .RGBA16F
	case 3:
		out.format = .R32F
	case 4:
		out.format = .RGBA8
	case 6:
		out.format = .RG32F
	case 13:
		out.format = .RG8
	case 15:
		out.format = .R8
	case 33:
		out.format = .R32UI
	case:
		return "unsupported storage image format"
	}
	if out.unsigned !=
	   (out.format == .R32UI) {return "storage image component type mismatches its format"}
	return ""
}
