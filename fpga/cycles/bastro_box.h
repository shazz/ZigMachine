/* ASTROLABE's mailbox words (SPIKE, docs/ARM_FPU_COPROC.md): glass/src/astro_box.zig's layout
 * and machine/sdk/astro.zig's descriptor, as ZIGGY's firmware (cycles/bastro.c) sees them.
 * tests/test_astro_box.py checks every number here against those two files and soc/zm_astro.py. */
#ifndef ZM_BASTRO_BOX_H
#define ZM_BASTRO_BOX_H

#define ASTRO_WINDOW 0x94000000u /* soc/zm_astro.py: the RAM's 1024 words, uncached */

/* the protocol words (one writer each: G = glass, Z = ZIGGY) */
#define ASTRO_MAGIC 0u    /* G: ASTRO_ID while the worker runs */
#define ASTRO_VERSION 1u  /* G: ASTRO_PROTO */
#define ASTRO_BEAT 2u     /* G: +1 a poll while idle */
#define ASTRO_SEQ 3u      /* Z: the doorbell, written last */
#define ASTRO_TAKEN 4u    /* G: = SEQ once read */
#define ASTRO_DONE 5u     /* G: = SEQ once every result is in */
#define ASTRO_COUNT 6u    /* Z */
#define ASTRO_MEM_OFF 7u  /* Z: the DDR window offset of cart address 0 */
#define ASTRO_MEM_SIZE 8u /* Z */
#define ASTRO_ARM_NS 9u   /* G */
#define ASTRO_RET 10u     /* G */
#define ASTRO_DESC0 16u
#define ASTRO_ID 0x41535452u
#define ASTRO_PROTO 1u

/* the descriptor (machine/sdk/astro.zig) */
#define ASTRO_DESC_WORDS 20u
#define ASTRO_W_OP 0u
#define ASTRO_W_N 1u
#define ASTRO_W_C 6u
#define ASTRO_W_STATUS 8u
#define ASTRO_W_CYCLES 9u
#define ASTRO_W_S0 10u
#define ASTRO_W_R 16u
#define ASTRO_OP_MASK 0xFFFFu
#define ASTRO_OP_VADD 0x20u /* below it: a scalar op */
#define ASTRO_MAX_COUNT 48u
#define ASTRO_ST_BAD_DESC 4u
#define ASTRO_ST_TIMEOUT 5u

#endif
