#+build linux, windows
package gpucompute
import kineffi "../bindings"
import "core:strings"
import vk "vendor:vulkan"

init_pipeline_cache :: proc(device: ^Device) {
	info := vk.PipelineCacheCreateInfo {
		sType = .PIPELINE_CACHE_CREATE_INFO,
	}
	when kineffi.KINE_SHADER_COMPILER_LINKED {
		identity := strings.clone_to_cstring(device.cache_identity); defer delete(identity)
		bytes: rawptr
		size := kineffi.Kine_Shader_CacheRead(identity, &bytes)
		defer kineffi.Kine_Shader_Free(cast(^u32)bytes)
		info.initialDataSize = int(size); info.pInitialData = bytes
		if device.procs.CreatePipelineCache(device.handle, &info, nil, &device.pipeline_cache) ==
		   .SUCCESS {return}
		info.initialDataSize = 0; info.pInitialData = nil
	}
	_ = device.procs.CreatePipelineCache(device.handle, &info, nil, &device.pipeline_cache)
}
save_pipeline_cache :: proc(device: ^Device) {
	when kineffi.KINE_SHADER_COMPILER_LINKED {
		if device.pipeline_cache == 0 {return}
		size: int
		if device.procs.GetPipelineCacheData(device.handle, device.pipeline_cache, &size, nil) !=
			   .SUCCESS ||
		   size <= 0 ||
		   size > 16 * 1024 * 1024 {return}
		data := make([]u8, size); defer delete(data)
		if device.procs.GetPipelineCacheData(
			   device.handle,
			   device.pipeline_cache,
			   &size,
			   raw_data(data),
		   ) !=
		   .SUCCESS {return}
		identity := strings.clone_to_cstring(device.cache_identity); defer delete(identity)
		kineffi.Kine_Shader_CacheWrite(identity, raw_data(data), uint(size))
	}
}
