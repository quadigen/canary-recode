#+build linux, windows
package gpucompute

import kineffi "../bindings"

compile_shader :: proc(
	device: ^Device,
	source: string,
	count: u32,
	kinds: Binding_Layout = {},
	output: ^Custom_Pipeline = nil,
) -> string {
	when !kineffi.KINE_SHADER_COMPILER_LINKED {
		return "runtime shader compilation is not linked into this GPUCompute build"
	} else {
		if reason := custom_idle(device); reason != "" {return reason}
		if len(source) == 0 ||
		   len(source) > MAX_SHADER_SOURCE_BYTES {return "invalid GPUCompute GLSL source length"}
		if count == 0 || count > MAX_CUSTOM_BINDINGS {return "invalid GPUCompute binding count"}
		if reason := open(device); reason != "" {return reason}
		if !device.robust_access {return "custom compute requires Vulkan robustBufferAccess"}
		words: ^u32
		word_count: uint
		diagnostic := device.custom.diagnostic[:]
		status := kineffi.Kine_Shader_Compile(
			raw_data(source),
			uint(len(source)),
			&words,
			&word_count,
			&diagnostic[0],
			uint(len(diagnostic)),
		)
		defer kineffi.Kine_Shader_Free(words)
		if status == 0 {
			n := 0
			for n < len(diagnostic) && diagnostic[n] != 0 {n += 1}
			if n == 0 {return "GLSL compilation failed"}
			return string(diagnostic[:n])
		}
		if words == nil ||
		   word_count < 5 ||
		   word_count > 4 * 1024 * 1024 {return "invalid or oversized SPIR-V"}
		requirements: Image_Requirements
		readonly: [MAX_CUSTOM_BINDINGS]bool
		if reason := validate_descriptor_layout(
			(cast([^]u32)words)[:int(word_count)],
			count,
			kinds,
			&requirements,
			&readonly,
		); reason != "" {return reason}
		return custom_install_shader(
			device,
			(cast([^]u8)words)[:int(word_count) * 4],
			count,
			kinds,
			output,
			requirements,
			readonly,
		)
	}
}


create_shader_pipeline :: proc(
	device: ^Device,
	source: string,
	count: u32,
	kinds: Binding_Layout,
) -> (
	u32,
	string,
) {
	if reason := custom_idle(device); reason != "" {return 0, reason}
	if reason := open(device); reason != "" {return 0, reason}
	c := &device.custom
	if c.next_id == max(u32) {return 0, "GPUCompute IDs exhausted"}
	for &p in c.pipelines {
		if p.id != 0 {continue}
		if reason := compile_shader(device, source, count, kinds, &p.shader);
		   reason != "" {return 0, reason}
		c.next_id += 1
		p.id = c.next_id
		return p.id, ""
	}
	return 0, "GPUCompute pipeline count exceeded"
}
