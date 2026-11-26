#include "kinemium_runtime.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#else
#  include <dlfcn.h>
#endif

#if defined(__cplusplus)
static_assert(sizeof(void (*)(void)) == sizeof(void *),
              "This platform cannot load SDK function pointers from dlsym");
#else
_Static_assert(sizeof(void (*)(void)) == sizeof(void *),
               "This platform cannot load SDK function pointers from dlsym");
#endif

static void runtime_error(char *buffer, size_t capacity, const char *format, ...) {
    if (!buffer || capacity == 0) return;
    va_list values;
    va_start(values, format);
    (void)vsnprintf(buffer, capacity, format, values);
    va_end(values);
    buffer[capacity - 1] = '\0';
}

static void *runtime_symbol(void *library, const char *name) {
#ifdef _WIN32
    FARPROC function = GetProcAddress((HMODULE)library, name);
    void *address = NULL;
    memcpy(&address, &function, sizeof(address));
    return address;
#else
    return dlsym(library, name);
#endif
}

static void runtime_unload_module(void *library) {
    if (!library) return;
#ifdef _WIN32
    (void)FreeLibrary((HMODULE)library);
#else
    (void)dlclose(library);
#endif
}

void Kinemium_RuntimeClose(Kinemium_Runtime *api) {
    if (!api) return;
    if (api->library) runtime_unload_module(api->library);
    memset(api, 0, sizeof(*api));
}

static bool runtime_open(Kinemium_Runtime *api, const char *path,
                         char *error, size_t error_capacity, bool strict) {
    if (error && error_capacity) error[0] = '\0';
    if (!api || !path || !path[0]) {
        runtime_error(error, error_capacity, "Kinemium runtime: missing API or library path");
        return false;
    }
    if (api->library) {
        runtime_error(error, error_capacity, "Kinemium runtime: close the existing library first");
        return false;
    }
    /* Allow retry after failure; caller must have zero-initialized api. */
    memset(api, 0, sizeof(*api));

#ifdef _WIN32
    HMODULE module = LoadLibraryA(path);
    if (!module) {
        runtime_error(error, error_capacity,
                      "Kinemium runtime: LoadLibraryA('%s') failed (Win32 error %lu)",
                      path, (unsigned long)GetLastError());
        return false;
    }
    void *library = (void *)module;
#else
    void *library = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    if (!library) {
        const char *reason = dlerror();
        runtime_error(error, error_capacity, "Kinemium runtime: dlopen('%s'): %s",
                      path, reason ? reason : "unknown dynamic loader error");
        return false;
    }
#endif

    Kinemium_Runtime loaded;
    memset(&loaded, 0, sizeof(loaded));
    loaded.library = library;
    void *version_symbol = runtime_symbol(library, "Kinemium_GetABIVersion");
    if (!version_symbol) {
        runtime_error(error, error_capacity,
                      "Kinemium runtime: missing required symbol Kinemium_GetABIVersion");
        Kinemium_RuntimeClose(&loaded);
        return false;
    }
    memcpy(&loaded.GetABIVersion, &version_symbol, sizeof(version_symbol));
    loaded.abi_version = loaded.GetABIVersion();
    if (loaded.abi_version != KINEMIUM_ABI_MAJOR) {
        runtime_error(error, error_capacity,
                      "Kinemium runtime: incompatible ABI %u (expected %u)",
                      (unsigned)loaded.abi_version, (unsigned)KINEMIUM_ABI_MAJOR);
        Kinemium_RuntimeClose(&loaded);
        return false;
    }

    const char *first_missing = NULL;
#define KINEMIUM_RUNTIME_RESOLVE(return_type, name, arguments) do { \
    void *symbol = runtime_symbol(library, "Kinemium_" #name); \
    memcpy(&loaded.name, &symbol, sizeof(symbol)); \
    if (symbol) ++loaded.resolved_count; \
    else { ++loaded.missing_count; if (!first_missing) first_missing = "Kinemium_" #name; } \
} while (0);
    KINEMIUM_RUNTIME_SYMBOLS(KINEMIUM_RUNTIME_RESOLVE)
#undef KINEMIUM_RUNTIME_RESOLVE

    if (!loaded.Create || !loaded.Destroy) {
        runtime_error(error, error_capacity,
                      "Kinemium runtime: missing required symbol %s",
                      !loaded.Create ? "Kinemium_Create" : "Kinemium_Destroy");
        Kinemium_RuntimeClose(&loaded);
        return false;
    }
    if (strict && loaded.missing_count) {
        runtime_error(error, error_capacity,
                      "Kinemium runtime: %zu missing symbols (first: %s)",
                      loaded.missing_count, first_missing ? first_missing : "unknown");
        Kinemium_RuntimeClose(&loaded);
        return false;
    }
    *api = loaded;
    return true;
}

bool Kinemium_RuntimeOpen(Kinemium_Runtime *api, const char *path,
                          char *error, size_t error_capacity) {
    return runtime_open(api, path, error, error_capacity, false);
}

bool Kinemium_RuntimeOpenStrict(Kinemium_Runtime *api, const char *path,
                                char *error, size_t error_capacity) {
    return runtime_open(api, path, error, error_capacity, true);
}

bool Kinemium_RuntimeHasSymbol(const Kinemium_Runtime *api,
                               const char *symbol_name) {
    if (!api || !api->library || !symbol_name) return false;
#define KINEMIUM_RUNTIME_TEST(return_type, name, arguments) \
    if (strcmp(symbol_name, "Kinemium_" #name) == 0) return api->name != NULL;
    KINEMIUM_RUNTIME_SYMBOLS(KINEMIUM_RUNTIME_TEST)
#undef KINEMIUM_RUNTIME_TEST
    return false;
}
