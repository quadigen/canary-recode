#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef struct KineAllocationHeader {
    size_t size;
    size_t padding;
} KineAllocationHeader;

static uintptr_t kine_heap_cursor;
static uintptr_t kine_heap_limit;

static int kine_init_heap(void) {
    if (kine_heap_cursor) return 1;
    const uintptr_t page_size = 65536;
    const uintptr_t reserve_pages = 2048;
    uintptr_t base_pages = (uintptr_t)__builtin_wasm_memory_size(0);
    if (__builtin_wasm_memory_grow(0, reserve_pages) == (size_t)-1) return 0;
    kine_heap_cursor = base_pages * page_size;
    kine_heap_limit = kine_heap_cursor + reserve_pages * page_size;
    return 1;
}

void *__wrap_malloc(size_t size) {
    if (!kine_init_heap()) return 0;
    uintptr_t header_address = (kine_heap_cursor + 15u) & ~(uintptr_t)15u;
    uintptr_t end = (header_address + sizeof(KineAllocationHeader) + size + 15u) & ~(uintptr_t)15u;
    if (end > kine_heap_limit) return 0;
    KineAllocationHeader *header = (KineAllocationHeader *)header_address;
    header->size = size;
    header->padding = 0;
    kine_heap_cursor = end;
    return (void *)(header + 1);
}

void __wrap_free(void *ptr) {
    (void)ptr;
}

void *__wrap_calloc(size_t count, size_t size) {
    size_t total = count * size;
    void *result = __wrap_malloc(total);
    if (result) memset(result, 0, total);
    return result;
}

void *__wrap_realloc(void *ptr, size_t size) {
    if (!ptr) return __wrap_malloc(size);
    if (!size) return 0;
    KineAllocationHeader *old_header = (KineAllocationHeader *)((uintptr_t)ptr - sizeof(KineAllocationHeader));
    void *result = __wrap_malloc(size);
    if (result) memcpy(result, ptr, old_header->size < size ? old_header->size : size);
    return result;
}

int __wrap_posix_memalign(void **out, size_t alignment, size_t size) {
    (void)alignment;
    *out = __wrap_malloc(size);
    return *out ? 0 : 12;
}

int __wrap_clock(void) {
    static int ticks;
    return ++ticks;
}

int kine_luau_clock(void) {
    return __wrap_clock();
}

int __wrap_strcmp(const char *left, const char *right) {
    const unsigned char *a = (const unsigned char *)left;
    const unsigned char *b = (const unsigned char *)right;
    while (*a && *a == *b) { ++a; ++b; }
    return (int)*a - (int)*b;
}
