#ifndef KINEMIUM_RUNTIME_H
#define KINEMIUM_RUNTIME_H


#include <stddef.h>
#include "kinemium.h"
#include "kinemium_runtime_symbols.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Kinemium_Runtime {
    void *library;
    uint32_t abi_version;
    size_t resolved_count;
    size_t missing_count;
#define KINEMIUM_RUNTIME_DECLARE(return_type, name, arguments) \
    return_type (*name) arguments;
    KINEMIUM_RUNTIME_SYMBOLS(KINEMIUM_RUNTIME_DECLARE)
#undef KINEMIUM_RUNTIME_DECLARE
} Kinemium_Runtime;


bool Kinemium_RuntimeOpen(Kinemium_Runtime *api, const char *path,
                          char *error, size_t error_capacity);


bool Kinemium_RuntimeOpenStrict(Kinemium_Runtime *api, const char *path,
                                char *error, size_t error_capacity);


bool Kinemium_RuntimeHasSymbol(const Kinemium_Runtime *api,
                               const char *symbol_name);


void Kinemium_RuntimeClose(Kinemium_Runtime *api);

#ifdef __cplusplus
}
#endif
#endif
