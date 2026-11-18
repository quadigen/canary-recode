#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Output is owned by the wrapper; release it with Kine_Shader_Free.
// Returns 1 on success, 0 on failure. Error is a caller-owned, NUL-terminated buffer.
int32_t Kine_Shader_Compile(const char* source, size_t length,
    uint32_t** words, size_t* word_count, char* error, size_t error_capacity);
void Kine_Shader_Free(uint32_t* words);
#ifdef __cplusplus
}
#endif
