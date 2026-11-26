#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif


int32_t Kine_Shader_Compile(const char* source, size_t length,
    uint32_t** words, size_t* word_count, char* error, size_t error_capacity);
void Kine_Shader_Free(uint32_t* words);
size_t Kine_Shader_CacheRead(const char* identity, void** bytes);
void Kine_Shader_CacheWrite(const char* identity, const void* bytes, size_t size);
void Kine_Shader_CacheStats(uint64_t* out);
#ifdef __cplusplus
}
#endif
