/* memset / memmove for the VGM engine's C: libc's where there is one (BARD, the native host), the
 * compiler runtime's in the freestanding machine-audio.wasm build (build.zig addVgm). */
#ifndef ZM_VGM_MEM_H
#define ZM_VGM_MEM_H

#if __STDC_HOSTED__
#include <string.h>
#else
#include <stddef.h>
void *memset(void *dst, int c, size_t n);
void *memmove(void *dst, const void *src, size_t n);
#endif

#endif
