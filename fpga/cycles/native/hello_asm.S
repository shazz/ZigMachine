/* KESTREL-only "hello world", by hand in RV32 assembly: hello.c instruction for instruction
 * in spirit, the same header, calls and picture (cycles/native/native.mk, decisions.md
 * 2026-10-17). The system calls it as it calls a wasm2c cart (cycles/bsys.c); a0 is always
 * the instance (16 bytes the system calloc's: env, mem, gui, frames), and frame's float dt
 * (fa0, or a1 on a soft-float system) is never read, so one image serves either ABI. Every
 * table index and offset is native.h's, which native_check.c holds to the generated header. */
#include "native.h"

#define I_ENV 0     /* struct w2c_env*: every machine/ROM call takes it first */
#define I_MEM 4     /* the shared memory's byte 0 */
#define I_GUI 8     /* the ROM's drawing context over plane 0 (0 = none) */
#define I_FRAMES 12
#define INST_BYTES 16
#define TEXT_LEN 11 /* "HELLO WORLD" */

/* t0 = table entry IX (zm_sys->fn[IX]), then call it: a0.. already hold the arguments. */
.macro SYSCALL ix
    lui t0, %hi(zm_sys)
    lw t0, %lo(zm_sys)(t0)
    lw t0, NATIVE_TABLE_FN + 4 * \ix(t0)
    jalr t0
.endm

    .section .zm_cart_hdr, "a"
    .globl zm_cart_header
    .balign 4
zm_cart_header:
    .word NATIVE_MAGIC                  /* "ZMCA" */
    .word NATIVE_VERSION                /* the table version it needs */
    .word NATIVE_HDR_BYTES
    .word __cart_bss_start, __cart_bss_end
    .word NATIVE_PAGES, NATIVE_CART_HIGH, INST_BYTES
    .word c_bind, c_instantiate, c_boot, c_nothing, c_frame, c_plane_enabled, c_nothing
    .word none, none, none, none, none  /* songs, input, dapp, exports, song files: all empty */
    .asciz "hello_asm"
    .org NATIVE_HDR_BYTES               /* the header is the section: fails if it overran */

    .section .rodata
    .balign 4
none: .space 64                         /* every bridge all NULLs, every list ended at once */
msg:  .ascii "HELLO WORLD"

    .section .bss
    .balign 4
    .globl zm_sys
zm_sys: .space 4                        /* zeroed by the system, then bind() fills it */

    .text
/* bind(table): keep the system's table. */
c_bind:
    lui t0, %hi(zm_sys)
    sw a0, %lo(zm_sys)(t0)
c_nothing:                              /* skip_boot, hbl_dispatch: nothing to do */
    ret

/* instantiate(cart, env): cart->env = env, cart->mem = w2c_env_memory(env)->data. */
c_instantiate:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    mv s0, a0
    sw a1, I_ENV(s0)
    mv a0, a1
    SYSCALL NATIVE_IX_w2c_env_memory
    lw a0, 0(a0)                        /* wasm_rt_memory_t.data */
    sw a0, I_MEM(s0)
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

/* boot(cart): the border colour, the text into the shared memory, the ROM's context over
 * plane 0 and GEM's palette entries. */
c_boot:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    mv s0, a0
    lw a0, I_ENV(s0)
    SYSCALL NATIVE_IX_hwVideoBase       /* a0 = the video registers' offset */
    lw t1, I_MEM(s0)
    add t2, t1, a0
    li t3, NATIVE_BORDER_RGBA
    sw t3, NATIVE_REG_BACKGROUND(t2)
    li t2, NATIVE_TEXT_AT               /* copy "HELLO WORLD" to mem + TEXT_AT */
    add t2, t1, t2
    lui t3, %hi(msg)
    addi t3, t3, %lo(msg)
    li t4, TEXT_LEN
1:  lbu t5, 0(t3)
    sb t5, 0(t2)
    addi t3, t3, 1
    addi t2, t2, 1
    addi t4, t4, -1
    bnez t4, 1b
    lw a0, I_ENV(s0)                    /* guiOpenPlane(env, plane 0, 320, 200) */
    li a1, 0
    li a2, 320
    li a3, 200
    SYSCALL NATIVE_IX_guiOpenPlane
    sw a0, I_GUI(s0)
    lw a0, I_ENV(s0)                    /* romInstallPalettePlane(env, 0) */
    li a1, 0
    SYSCALL NATIVE_IX_romInstallPalettePlane
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

/* frame(cart, dt): plane 0 black, the text white at x = 84 + bounce(frames & 127), y 96. */
c_frame:
    lw t0, I_GUI(a0)
    beqz t0, 9f                         /* no context: plane 0 stays off */
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    sw s1, 4(sp)
    mv s0, a0
    lw t1, I_FRAMES(s0)
    addi t2, t1, 1
    sw t2, I_FRAMES(s0)
    andi t1, t1, 127
    li t2, 64
    bltu t1, t2, 1f
    li t2, 127                          /* the way back: 127 - t */
    sub t1, t2, t1
1:  addi s1, t1, 84                     /* 116 - 32 + bounce, as hello.c */
    lw a0, I_ENV(s0)                    /* guiRect(env, gui, 0, 0, 320, 200, black) */
    lw a1, I_GUI(s0)
    li a2, 0
    li a3, 0
    li a4, 320
    li a5, 200
    li a6, GEM_BLACK
    SYSCALL NATIVE_IX_guiRect
    lw a0, I_ENV(s0)                    /* guiText(env, gui, TEXT_AT, 11, x, 96, white, black) */
    lw a1, I_GUI(s0)
    li a2, NATIVE_TEXT_AT
    li a3, TEXT_LEN
    mv a4, s1
    li a5, 96
    li a6, GEM_WHITE
    li a7, GEM_BLACK
    SYSCALL NATIVE_IX_guiText
    lw s1, 4(sp)
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
9:  ret

/* plane_enabled(cart, p): plane 0 only, once the ROM gave a context. */
c_plane_enabled:
    lw t0, I_GUI(a0)
    snez t0, t0
    seqz a0, a1
    and a0, a0, t0
    ret
