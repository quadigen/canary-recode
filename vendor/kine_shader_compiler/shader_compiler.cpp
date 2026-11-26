#include "shader_compiler.h"
#include "shader_cache.h"
#include <glslang/Public/ShaderLang.h>
#include <glslang/Include/PoolAlloc.h>
#include <SPIRV/GlslangToSpv.h>
#include "builtinResource.h"
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <vector>

namespace {
constexpr size_t max_source = 1024 * 1024;
constexpr size_t max_words = 16 * 1024 * 1024 / sizeof(uint32_t);
void message(char* dst, size_t capacity, const char* text) noexcept {
    if (!dst || !capacity) return;
    if (!text || !*text) text = "GLSL compilation failed";
    const size_t n = std::min(capacity - 1, std::strlen(text));
    std::memcpy(dst, text, n);
    dst[n] = '\0';
}

struct CompilerReference {
    bool active = glslang::InitializeProcess();
    ~CompilerReference() { if (active) glslang::FinalizeProcess(); }
};

struct RestorePool {
    glslang::TPoolAllocator* previous = &glslang::GetThreadPoolAllocator();
    ~RestorePool() { glslang::SetThreadPoolAllocator(previous); }
};
}

extern "C" int32_t Kine_Shader_Compile(const char* source, size_t length,
    uint32_t** words, size_t* word_count, char* error, size_t error_capacity) {
    if (words) *words = nullptr;
    if (word_count) *word_count = 0;
    if (error && error_capacity) error[0] = '\0';
    if (!words || !word_count || !source || length == 0 || length > max_source ||
        std::memchr(source, '\0', length)) {
        message(error, error_capacity, "Invalid GPUCompute shader input");
        return 0;
    }
    const auto cacheKey = kine_shader_cache::key("glslang-vulkan1.0-spirv1.0-compute", {source, length});
    std::vector<uint8_t> cached;
    if (kine_shader_cache::read(cacheKey, cached) && cached.size() >= 20 && cached.size() % 4 == 0) {
        auto* data = static_cast<uint32_t*>(std::malloc(cached.size()));
        if (data) { std::memcpy(data, cached.data(), cached.size()); *words = data; *word_count = cached.size()/4; return 1; }
    }
    try {
        kine_shader_cache::Timer timer;
        CompilerReference compiler;
        if (!compiler.active) {
            message(error, error_capacity, "Could not initialize Filament glslang");
            return 0;
        }
        glslang::TShader shader(EShLangCompute);

        glslang::TProgram program;
        RestorePool restore;
        const int n = static_cast<int>(length);
        const char* filename = "GPUCompute.comp";
        shader.setStringsWithLengthsAndNames(&source, &n, &filename, 1);
        shader.setEntryPoint("main");
        shader.setEnvInput(glslang::EShSourceGlsl, EShLangCompute, glslang::EShClientVulkan, 100);
        shader.setEnvClient(glslang::EShClientVulkan, glslang::EShTargetVulkan_1_0);
        shader.setEnvTarget(glslang::EShTargetSpv, glslang::EShTargetSpv_1_0);
        const auto flags = static_cast<EShMessages>(EShMsgSpvRules | EShMsgVulkanRules);

        if (!shader.parse(&DefaultTBuiltInResource, 450, false, flags)) {
            message(error, error_capacity, shader.getInfoLog());
            return 0;
        }
        program.addShader(&shader);
        if (!program.link(flags)) {
            message(error, error_capacity, program.getInfoLog());
            return 0;
        }
        const auto* intermediate = program.getIntermediate(EShLangCompute);
        if (!intermediate) {
            message(error, error_capacity, "glslang returned no compute intermediate");
            return 0;
        }
        glslang::SpvOptions options{};
        options.disableOptimizer = true;
        std::vector<unsigned int> result;
        glslang::GlslangToSpv(*intermediate, result, &options);
        static_assert(sizeof(unsigned int) == sizeof(uint32_t));
        if (result.size() < 5 || result.size() > max_words || result[0] != 0x07230203u) {
            message(error, error_capacity, "Invalid or oversized SPIR-V result");
            return 0;
        }
        auto* data = static_cast<uint32_t*>(std::malloc(result.size() * sizeof(uint32_t)));
        if (!data) {
            message(error, error_capacity, "Could not allocate SPIR-V result");
            return 0;
        }
        std::memcpy(data, result.data(), result.size() * sizeof(uint32_t));
        kine_shader_cache::write(cacheKey, data, result.size()*sizeof(uint32_t));
        *words = data;
        *word_count = result.size();
        return 1;
    } catch (const std::exception& ex) {
        message(error, error_capacity, ex.what());
    } catch (...) {
        message(error, error_capacity, "Unexpected native shader compiler failure");
    }
    return 0;
}
extern "C" void Kine_Shader_Free(uint32_t* words) { std::free(words); }
extern "C" size_t Kine_Shader_CacheRead(const char* identity, void** bytes) {
    if (!bytes || !identity) return 0;
    *bytes = nullptr;
    std::vector<uint8_t> data;
    if (!kine_shader_cache::read(kine_shader_cache::key("vulkan-driver-pipeline", identity), data)) return 0;
    *bytes = std::malloc(data.size());
    if (!*bytes) return 0;
    std::memcpy(*bytes, data.data(), data.size()); return data.size();
}
extern "C" void Kine_Shader_CacheWrite(const char* identity, const void* bytes, size_t size) {
    if (identity) kine_shader_cache::write(kine_shader_cache::key("vulkan-driver-pipeline", identity), bytes, size);
}
extern "C" void Kine_Shader_CacheStats(uint64_t* out) {
    if (!out) return;
    out[0]=kine_shader_cache::hits; out[1]=kine_shader_cache::misses; out[2]=kine_shader_cache::writes;
    out[3]=kine_shader_cache::corrupt; out[4]=kine_shader_cache::compile_ns;
}
