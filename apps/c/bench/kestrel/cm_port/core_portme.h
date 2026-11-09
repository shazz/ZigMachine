/* CoreMark port layer for the ZigMachine / KESTREL benchmark cart (wasm32).
 * Written from the EEMBC barebones template (Apache-2.0, Copyright 2018 EEMBC, original author Shay Gal-on):
 * the porting layer is the part CoreMark lets a platform write. The core_*.c files beside it are byte-for-byte
 * the upstream ones (apps/c/bench/third_party/coremark). Differences from the Atari (czietz) port:
 * the clock is env.hostMicros in microseconds, the data block is static (TOTAL_DATA_SIZE 2000), no libc. */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H
#include <stddef.h>

#define HAS_FLOAT 1
#define HAS_TIME_H 0
#define USE_CLOCK 0
#define HAS_STDIO 1
#define HAS_PRINTF 1
typedef unsigned int CORE_TICKS;                  /* microseconds */
#define EE_TICKS_PER_SEC 1000000

#ifndef COMPILER_VERSION
#define COMPILER_VERSION "clang (zig cc), wasm32"
#endif
#ifndef COMPILER_FLAGS
#define COMPILER_FLAGS "-O2"
#endif
#define MEM_LOCATION "Code and data in the cart window"

typedef signed short ee_s16;
typedef unsigned short ee_u16;
typedef signed int ee_s32;
typedef double ee_f32;
typedef unsigned char ee_u8;
typedef unsigned int ee_u32;
typedef ee_u32 ee_ptr_int;
typedef size_t ee_size_t;
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x) - 1) & ~3))

#define SEED_METHOD SEED_ARG
#define MEM_METHOD MEM_STATIC
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK 0
#define USE_SOCKET 0
#define MAIN_HAS_NOARGC 0
#define MAIN_HAS_NORETURN 0

extern ee_u32 default_num_contexts;
typedef struct CORE_PORTABLE_S { ee_u8 portable_id; } core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

/* the last timed region, for the cart (core_main only prints it) */
extern CORE_TICKS cm_last_ticks;
#endif
