#+build linux, windows
package gpucompute

import kineffi "../bindings"

compile_shader :: proc(device: ^Device, source: string, count: u32) -> string {
    when !kineffi.KINE_SHADER_COMPILER_LINKED {
        return "runtime shader compilation is not linked into this GPUCompute build"
    } else {
        if reason := custom_idle(device); reason != "" {return reason}
        if len(source) == 0 || len(source) > MAX_SHADER_SOURCE_BYTES {return "invalid GPUCompute GLSL source length"}
        if count == 0 || count > MAX_CUSTOM_BINDINGS {return "invalid GPUCompute storage binding count"}
        if reason := open(device); reason != "" {return reason}
        if !device.robust_access {return "custom compute requires Vulkan robustBufferAccess"}
        if count > device.limits.maxPerStageDescriptorStorageBuffers || count > device.limits.maxDescriptorSetStorageBuffers {
            return "GPUCompute storage binding count exceeds Vulkan limits"
        }
        words: ^u32
        word_count: uint
        diagnostic := device.custom.diagnostic[:]
        status := kineffi.Kine_Shader_Compile(raw_data(source), uint(len(source)), &words, &word_count, &diagnostic[0], uint(len(diagnostic)))
        defer kineffi.Kine_Shader_Free(words)
        if status == 0 {
            n := 0
            for n < len(diagnostic) && diagnostic[n] != 0 {n += 1}
            if n == 0 {return "GLSL compilation failed"}
            return string(diagnostic[:n])
        }
        if words == nil || word_count < 5 || word_count > 4 * 1024 * 1024 {return "invalid or oversized SPIR-V"}
        return custom_install_shader(device, (cast([^]u8)words)[:int(word_count) * 4], count)
    }
}
