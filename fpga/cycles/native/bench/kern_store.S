/* The bench's probe and store kernels (bench.h): hand-unrolled RV32, so a figure is the access
 * and not what a compiler made of the loop. Every loop body is eight accesses and three
 * instructions of loop overhead (two when the pointer step is folded in); n is a multiple of 8.
 * a0 = the pointer, a1 = n, a2 = the stride or value where there is one. Only caller-saved
 * registers are used (k_time saves what it uses). */
#include "native.h"

#define FN(name) .globl name; .type name, @function; .balign 64; name:

    .text
/* k_time(body, arg): the cycles of body(arg), between two loads of the cycle counter with
 * nothing else in the window (no store: a C probe spilled its start time to the stack). */
FN(k_time)
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    sw s1, 4(sp)
    mv s1, a0
    mv a0, a1
    li t0, NATIVE_CSR_CYCLES
    lw s0, 0(t0)
    jalr s1
    li t0, NATIVE_CSR_CYCLES
    lw a0, 0(t0)
    sub a0, a0, s0
    lw s1, 4(sp)
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

/* n stores of a word, sequential. */
FN(k_st_sw)
    srli a1, a1, 3
1:  .irp o, 0, 4, 8, 12, 16, 20, 24, 28
    sw a0, \o(a0)
    .endr
    addi a0, a0, 32
    addi a1, a1, -1
    bnez a1, 1b
    ret

FN(k_st_sh)
    srli a1, a1, 3
1:  .irp o, 0, 2, 4, 6, 8, 10, 12, 14
    sh a0, \o(a0)
    .endr
    addi a0, a0, 16
    addi a1, a1, -1
    bnez a1, 1b
    ret

FN(k_st_sb)
    srli a1, a1, 3
1:  .irp o, 0, 1, 2, 3, 4, 5, 6, 7
    sb a0, \o(a0)
    .endr
    addi a0, a0, 8
    addi a1, a1, -1
    bnez a1, 1b
    ret

/* n stores to one word: what a posted buffer could merge or overlap best. */
FN(k_st_same)
    srli a1, a1, 3
1:  .rept 8
    sw a1, 0(a0)
    .endr
    addi a1, a1, -1
    bnez a1, 1b
    ret

/* n stores of a2 to one word: a register or palette entry rewritten with what it holds
 * (a real store, snooped by FRESCO, that changes nothing on screen). */
FN(k_st_val)
    srli a1, a1, 3
1:  .rept 8
    sw a2, 0(a0)
    .endr
    addi a1, a1, -1
    bnez a1, 1b
    ret

/* n stores a2 bytes apart (32: a new D$ line each, 64: every other line). */
FN(k_st_stride)
    srli a1, a1, 3
1:  .rept 8
    sw a0, 0(a0)
    add a0, a0, a2
    .endr
    addi a1, a1, -1
    bnez a1, 1b
    ret

/* n stores, each followed by 4 (16) ALU ops that do not depend on it: blocking stores add the
 * ops' cycles to the store's, a posted buffer hides them under it. */
FN(k_st_alu4)
    srli a1, a1, 3
1:  .irp o, 0, 4, 8, 12, 16, 20, 24, 28
    sw a0, \o(a0)
    addi t0, t0, 1
    addi t1, t1, 1
    addi t2, t2, 1
    addi t3, t3, 1
    .endr
    addi a0, a0, 32
    addi a1, a1, -1
    bnez a1, 1b
    ret

FN(k_st_alu16)
    srli a1, a1, 3
1:  .irp o, 0, 4, 8, 12, 16, 20, 24, 28
    sw a0, \o(a0)
    .irp r, t0, t1, t2, t3, t4, t5, t6, a3, a4, a5, a6, a7, t0, t1, t2, t3
    addi \r, \r, 1
    .endr
    .endr
    addi a0, a0, 32
    addi a1, a1, -1
    bnez a1, 1b
    ret

/* n halfword stores of a2 to one address (at an odd one, each traps: tests_align.c). */
FN(k_sh_val)
    srli a1, a1, 3
1:  .rept 8
    sh a2, 0(a0)
    .endr
    addi a1, a1, -1
    bnez a1, 1b
    ret

/* n words of a2 stored as four bytes each: what a cart can do instead of a misaligned sw. */
FN(k_sw_bytes)
    srli a1, a1, 3
1:  .rept 8
    sb a2, 0(a0)
    srli t0, a2, 8
    sb t0, 1(a0)
    srli t0, a2, 16
    sb t0, 2(a0)
    srli t0, a2, 24
    sb t0, 3(a0)
    .endr
    addi a1, a1, -1
    bnez a1, 1b
    ret

/* n halfwords of a2 stored as two bytes each. */
FN(k_sh_bytes)
    srli a1, a1, 3
1:  .rept 8
    sb a2, 0(a0)
    srli t0, a2, 8
    sb t0, 1(a0)
    .endr
    addi a1, a1, -1
    bnez a1, 1b
    ret
