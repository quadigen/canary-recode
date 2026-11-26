package classes

import kineffi "../bindings"
import gpu "../gpucompute"
import vm "../vm"
import "core:strings"
import "core:time"

GPUCompute_Warmup :: struct {
	source: string,
	count:  u32,
	kinds:  gpu.Binding_Layout,
	ticket: u32,
}

GPUCompute_Render_Namecall :: proc(
	L: ^vm.State,
	compute: ^GPUCompute,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "GetCacheStats":
		stats: [5]u64
		when kineffi.KINE_SHADER_COMPILER_LINKED {kineffi.Kine_Shader_CacheStats(&stats[0])}
		vm.NewTable(L, 9)
		for name, i in ([5]string{"Hits", "Misses", "Writes", "CorruptEntries", "CompileNanoseconds"}) {
			vm.PushNumber(L, f64(stats[i])); vm.SetField(L, -2, name)
		}
		bridge: [4]u64; kineffi.Kine_Filament_ComputeTextureStats(&bridge[0])
		for name, i in ([4]string{"DirectTextureDispatches", "DirectTextureBytes", "PixelReadbackBytes", "PixelUploadBytes"}) {
			vm.PushNumber(L, f64(bridge[i])); vm.SetField(L, -2, name)
		}
		return 1, true
	case "QueuePipeline":
		source := vm.ArgString(L, 2)
		if len(source) == 0 ||
		   len(source) > gpu.MAX_SHADER_SOURCE_BYTES ||
		   compute.warmup_bytes + len(source) > 4 * 1024 * 1024 {
			return gpu_compute_nil_error(L, "warmup source budget exceeded")
		}
		count, kinds, err := gpu_compute_layout(L, 3)
		if err != "" {return gpu_compute_nil_error(L, err)}
		if compute.warmup_next ==
		   max(u32) {return gpu_compute_nil_error(L, "warmup ticket IDs exhausted")}
		for &job in compute.warmup {
			if job.ticket != 0 {continue}
			compute.warmup_next += 1
			job = {strings.clone(source), count, kinds, compute.warmup_next}
			compute.warmup_bytes += len(source)
			vm.PushNumber(L, f64(job.ticket)); return 1, true
		}
		return gpu_compute_nil_error(L, "warmup queue is full (16 jobs)")
	case "GetWarmupPendingCount":
		n := 0; for job in compute.warmup {if job.ticket != 0 {n += 1}}
		vm.PushNumber(L, f64(n)); return 1, true
	case "WarmupPipelines":
		limit := gpu_compute_integer(L, 2, 1, 4)
		started := time.tick_now(); completed := u32(0)
		vm.NewTable(L, 4)
		for &job in compute.warmup {
			if job.ticket == 0 {continue}
			id, err := gpu.create_shader_pipeline(
				&compute.device,
				job.source,
				job.count,
				job.kinds,
			)
			vm.NewTable(L, 3)
			vm.PushNumber(L, f64(job.ticket)); vm.SetField(L, -2, "Ticket")
			if err !=
			   "" {vm.PushString(L, err); vm.SetField(L, -2, "Error")} else {vm.PushNumber(L, f64(id)); vm.SetField(L, -2, "Pipeline")}
			vm.RawSetIndex(L, -2, int(completed + 1))
			compute.warmup_bytes -= len(job.source); delete(job.source); job = {}
			completed += 1

			if completed >= limit ||
			   time.duration_seconds(time.tick_since(started)) >= 0.004 {break}
		}
		return 1, true
	case "DispatchTexture":
		variant_object := Object_From_Argument(L, 2)
		if variant_object == nil ||
		   variant_object.destroyed ||
		   !Is_A(variant_object, "MaterialVariant") {
			return gpu_compute_nil_error(L, "DispatchTexture expects a live MaterialVariant")
		}
		variant := cast(^MaterialVariant)variant_object
		if variant.filament_shader == nil || variant.dirty || variant.compile_job != nil {
			return gpu_compute_nil_error(
				L,
				"MaterialVariant must be compiled before DispatchTexture",
			)
		}
		name := vm.ArgString(L, 3); source := vm.ArgString(L, 4)
		width := gpu_compute_integer(L, 5, 1, 1024); height := gpu_compute_integer(L, 6, 1, 1024)
		if len(name) == 0 ||
		   len(name) > 256 ||
		   strings.contains(name, "\x00") ||
		   len(source) == 0 ||
		   len(source) > gpu.MAX_SHADER_SOURCE_BYTES {
			return gpu_compute_nil_error(L, "invalid texture sampler or shader source")
		}
		when kineffi.KINE_SHADER_COMPILER_LINKED {
			words: ^u32; word_count: uint; diagnostic: [4096]u8
			if kineffi.Kine_Shader_Compile(
				   raw_data(source),
				   uint(len(source)),
				   &words,
				   &word_count,
				   &diagnostic[0],
				   uint(len(diagnostic)),
			   ) ==
			   0 {
				return gpu_compute_nil_error(L, strings.trim_right(string(diagnostic[:]), "\x00"))
			}
			defer kineffi.Kine_Shader_Free(words)
			bytecode := (cast([^]u32)words)[:int(word_count)]
			if err := gpu.validate_render_texture_shader(bytecode);
			   err != "" {return gpu_compute_nil_error(L, err)}
			uniform := strings.clone_to_cstring(name); defer delete(uniform)
			if !kineffi.Kine_Filament_Shader_DispatchTexture(
				variant.filament_shader,
				uniform,
				words,
				word_count * 4,
				width,
				height,
			) {
				return gpu_compute_nil_error(
					L,
					"direct texture output requires the shared Vulkan renderer and a sampler2d parameter; previous texture retained",
				)
			}
			variant.revision += 1; Render_3D_Mark_Dirty()
			vm.PushBoolean(L, true); return 1, true
		} else {return gpu_compute_nil_error(
				L,
				"direct texture compute is unavailable on this platform",
			)}
	}
	return 0, false
}
