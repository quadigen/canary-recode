#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define KINE_ALIGN     16u
#define KINE_HDR       ((size_t)sizeof(KineBlock))
#define KINE_MIN_BLOCK 32u
#define KINE_INUSE     1u

typedef struct KineBlock {
    size_t size;      // total block size including header; bit0 = in use
    size_t prev_size; // total size of the physically previous block
} KineBlock;

static uintptr_t kine_arena_base;
static uintptr_t kine_arena_end;

static uintptr_t kine_rover;

#define KINE_FIX_ROVER(b, span)                                                    \
    do {                                                                          \
        uintptr_t kine_b = (uintptr_t)(b);                                         \
        uintptr_t kine_s = (uintptr_t)(span);                                      \
        if (kine_rover >= kine_b && kine_rover < kine_b + kine_s) {               \
            kine_rover = (kine_b + kine_s >= kine_arena_end)                       \
                             ? kine_arena_base : (kine_b + kine_s);                 \
        }                                                                          \
    } while (0)

#define KINE_SIZE(b)      ((b)->size & ~KINE_INUSE)
#define KINE_IS_USED(b)   (((b)->size & KINE_INUSE) != 0)
#define KINE_SET_FREE(b,s) ((b)->size = (s) & ~KINE_INUSE)
#define KINE_SET_USED(b,s) ((b)->size = ((s) & ~KINE_INUSE) | KINE_INUSE)

static int kine_init_heap(void) {
    if (kine_arena_base) return 1;
    const uintptr_t page_size = 65536;
    uintptr_t base_pages = (uintptr_t)__builtin_wasm_memory_size(0);
    uintptr_t want = 8192; // 512 MiB; the module grows to 4 GiB, so this fits
    uintptr_t got = 0;
    while (want >= 1024) {
        if (__builtin_wasm_memory_grow(0, want) != (size_t)-1) { got = want; break; }
        want >>= 1;
    }
    if (!got) return 0;

    kine_arena_base = base_pages * page_size;
    kine_arena_end = kine_arena_base + got * page_size;

    KineBlock *first = (KineBlock *)kine_arena_base;
    KINE_SET_FREE(first, kine_arena_end - kine_arena_base);
    first->prev_size = 0;
    kine_rover = kine_arena_base;
    return 1;
}

void *__wrap_malloc(size_t size) {
    if (!kine_init_heap()) return 0;
    if (size > (size_t)-1 - KINE_HDR - KINE_ALIGN) return 0;

    size_t need = (size + KINE_HDR + (KINE_ALIGN - 1u)) & ~(size_t)(KINE_ALIGN - 1u);
    if (need < KINE_MIN_BLOCK) need = KINE_MIN_BLOCK;

    uintptr_t start = kine_rover ? kine_rover : kine_arena_base;
    for (int pass = 0; pass < 2; ++pass) {
        uintptr_t p = (pass == 0) ? start : kine_arena_base;
        uintptr_t stop = (pass == 0) ? kine_arena_end : start;
        while (p < stop) {
            KineBlock *block = (KineBlock *)p;
            size_t block_size = KINE_SIZE(block);
            if (block_size == 0) break;
            if (!KINE_IS_USED(block) && block_size >= need) {
                size_t remainder = block_size - need;
                if (remainder >= KINE_MIN_BLOCK) {
                    KineBlock *rest = (KineBlock *)(p + need);
                    KINE_SET_FREE(rest, remainder);
                    rest->prev_size = need;
                    uintptr_t after = p + need + remainder;
                    if (after < kine_arena_end) ((KineBlock *)after)->prev_size = remainder;
                    block_size = need;
                }
                KINE_SET_USED(block, block_size);
                kine_rover = p + block_size;
                if (kine_rover >= kine_arena_end) kine_rover = kine_arena_base;
                return (void *)(block + 1);
            }
            p += block_size;
        }
    }
    return 0;
}

void __wrap_free(void *ptr) {
    if (!ptr) return;
    KineBlock *block = ((KineBlock *)ptr) - 1;
    size_t size = KINE_SIZE(block);
    KINE_SET_FREE(block, size);

    uintptr_t next = (uintptr_t)block + size;
    if (next < kine_arena_end) {
        KineBlock *after = (KineBlock *)next;
        if (!KINE_IS_USED(after)) {
            size += KINE_SIZE(after);
            KINE_SET_FREE(block, size);
            uintptr_t beyond = (uintptr_t)block + size;
            if (beyond < kine_arena_end) ((KineBlock *)beyond)->prev_size = size;
        }
    }

    KineBlock *result = block;
    if (block->prev_size) {
        KineBlock *prev = (KineBlock *)((uintptr_t)block - block->prev_size);
        if (!KINE_IS_USED(prev)) {
            size += KINE_SIZE(prev);
            KINE_SET_FREE(prev, size);
            uintptr_t beyond = (uintptr_t)prev + size;
            if (beyond < kine_arena_end) ((KineBlock *)beyond)->prev_size = size;
            result = prev;
        }
    }

    // Coalescing can swallow the block the next-fit rover was parked on. If the
    // rover now points inside the merged free block, snap it back to the block
    // start; otherwise the next malloc would read a bogus header from the
    // middle of a free region and corrupt the heap.
    if (kine_rover >= (uintptr_t)result && kine_rover < (uintptr_t)result + KINE_SIZE(result)) {
        kine_rover = (uintptr_t)result;
    }
}

void *__wrap_calloc(size_t count, size_t size) {
    if (count && size > (size_t)-1 / count) return 0;
    size_t total = count * size;
    void *result = __wrap_malloc(total);
    if (result) memset(result, 0, total);
    return result;
}

void *__wrap_realloc(void *ptr, size_t size) {
    if (!ptr) return __wrap_malloc(size);
    if (!size) { __wrap_free(ptr); return 0; }

    KineBlock *block = ((KineBlock *)ptr) - 1;
    size_t old_total = KINE_SIZE(block);
    size_t old_usable = old_total - KINE_HDR;

    if (size > (size_t)-1 - KINE_HDR - KINE_ALIGN) return 0;
    size_t need = (size + KINE_HDR + (KINE_ALIGN - 1u)) & ~(size_t)(KINE_ALIGN - 1u);
    if (need < KINE_MIN_BLOCK) need = KINE_MIN_BLOCK;

    if (need <= old_total) {
        size_t remainder = old_total - need;
        if (remainder >= KINE_MIN_BLOCK) {
            KINE_SET_USED(block, need);
            KineBlock *rest = (KineBlock *)((uintptr_t)block + need);
            KINE_SET_FREE(rest, remainder);
            rest->prev_size = need;
            uintptr_t after = (uintptr_t)block + need + remainder;
            if (after < kine_arena_end) ((KineBlock *)after)->prev_size = remainder;
        }
        KINE_FIX_ROVER(block, old_total);
        return ptr;
    }

    uintptr_t next = (uintptr_t)block + old_total;
    if (next < kine_arena_end) {
        KineBlock *after = (KineBlock *)next;
        if (!KINE_IS_USED(after)) {
            size_t combined = old_total + KINE_SIZE(after);
            if (combined >= need) {
                size_t remainder = combined - need;
                if (remainder >= KINE_MIN_BLOCK) {
                    KINE_SET_USED(block, need);
                    KineBlock *rest = (KineBlock *)((uintptr_t)block + need);
                    KINE_SET_FREE(rest, remainder);
                    rest->prev_size = need;
                    uintptr_t beyond = (uintptr_t)block + combined;
                    if (beyond < kine_arena_end) ((KineBlock *)beyond)->prev_size = remainder;
                } else {
                    KINE_SET_USED(block, combined);
                    uintptr_t beyond = (uintptr_t)block + combined;
                    if (beyond < kine_arena_end) ((KineBlock *)beyond)->prev_size = combined;
                }
                KINE_FIX_ROVER(block, combined);
                return ptr;
            }
        }
    }

    void *result = __wrap_malloc(size);
    if (result) {
        memcpy(result, ptr, old_usable < size ? old_usable : size);
        __wrap_free(ptr);
    }
    return result;
}

int __wrap_posix_memalign(void **out, size_t alignment, size_t size) {
    // Blocks are 16-byte aligned, which covers the alignments the engine uses.
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
