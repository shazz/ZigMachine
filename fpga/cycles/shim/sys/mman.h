/* The wasm2c runtime includes <sys/mman.h> unconditionally, but with
 * WASM_RT_USE_MMAP=0 it calls nothing from it: memory is calloc'd. An empty
 * header is enough, and any accidental use fails at link time. */
#ifndef ZM_SHIM_SYS_MMAN_H
#define ZM_SHIM_SYS_MMAN_H
#endif
