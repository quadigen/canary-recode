#ifndef KINE_GAME_H
#define KINE_GAME_H
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define KINE_GAME_CALL __cdecl
#define KINE_GAME_EXPORT __declspec(dllexport)
#else
#define KINE_GAME_CALL
#define KINE_GAME_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define KINE_GAME_ABI_MAJOR 1u
#define KINE_GAME_ABI_MINOR 0u

typedef void *kine_game_context;
typedef void *kine_game_instance;
typedef struct { const char *data; size_t length; } kine_game_string;
typedef struct { float x, y, z; } kine_game_vector3;
typedef struct { float r, g, b; } kine_game_color3;

enum kine_game_role { KINE_GAME_SINGLEPLAYER, KINE_GAME_CLIENT, KINE_GAME_SERVER };
enum kine_game_kind {
    KINE_GAME_NIL, KINE_GAME_BOOLEAN, KINE_GAME_NUMBER, KINE_GAME_INTEGER,
    KINE_GAME_STRING, KINE_GAME_INSTANCE, KINE_GAME_VECTOR3, KINE_GAME_COLOR3
};

typedef struct {
    uint32_t kind;
    uint32_t reserved;
    union {
        int32_t boolean;
        double number;
        int64_t integer;
        kine_game_string string;
        kine_game_instance instance;
        kine_game_vector3 vector3;
        kine_game_color3 color3;
    } data;
} kine_game_value;

typedef struct {
    uint32_t size;
    uint32_t abi_major;
    uint32_t abi_minor;
    uint32_t role;
    kine_game_context context;
    void (KINE_GAME_CALL *log)(kine_game_context, kine_game_string);
    kine_game_instance (KINE_GAME_CALL *get_service)(kine_game_context, kine_game_string);
    kine_game_instance (KINE_GAME_CALL *create)(kine_game_context, kine_game_string);
    kine_game_instance (KINE_GAME_CALL *find_child)(kine_game_context, kine_game_instance, kine_game_string);
    int32_t (KINE_GAME_CALL *get)(kine_game_context, kine_game_instance, kine_game_string, kine_game_value *);
    int32_t (KINE_GAME_CALL *set)(kine_game_context, kine_game_instance, kine_game_string, const kine_game_value *);
    int32_t (KINE_GAME_CALL *call)(kine_game_context, kine_game_instance, kine_game_string,
        const kine_game_value *, int32_t, kine_game_value *, int32_t);
    kine_game_string (KINE_GAME_CALL *last_error)(kine_game_context);
    void (KINE_GAME_CALL *request_exit)(kine_game_context);
} kine_game_api;

typedef struct {
    uint32_t size;
    uint32_t abi_major;
    uint32_t abi_minor;
    uint32_t reserved;
    int32_t (KINE_GAME_CALL *start)(const kine_game_api *api);
    void (KINE_GAME_CALL *update)(double delta_seconds);
    void (KINE_GAME_CALL *stop)(void);
} kine_game_desc;

/* Called on the game thread. A returned descriptor must stay valid until unload.
 * start returns nonzero on success. If start is called, stop is called even on failure.
 * API calls are valid during start, update and stop. get/set return 1 on success;
 * call returns the number of outputs written, or -1 on error. Returned strings
 * are borrowed until the current lifecycle callback returns. Instance handles
 * are borrowed from the scene. Discard handles when their instances are destroyed. */
KINE_GAME_EXPORT const kine_game_desc *KINE_GAME_CALL kine_game_entry(void);

#ifdef __cplusplus
}
#endif
#endif
