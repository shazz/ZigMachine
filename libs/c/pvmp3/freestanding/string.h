/* The three <string.h> functions pvmp3 calls (mp3_mem_funcs.h), for wasm32-freestanding, which has
 * no libc headers: Zig's compiler_rt defines them. The board's native build uses picolibc's. */
#ifndef ZM_PVMP3_STRING_H
#define ZM_PVMP3_STRING_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
void *memcpy(void *dst, const void *src, size_t n);
void *memmove(void *dst, const void *src, size_t n);
void *memset(void *dst, int c, size_t n);
#ifdef __cplusplus
}
#endif
#endif
