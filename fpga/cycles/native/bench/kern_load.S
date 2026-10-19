/* The bench's load kernels (bench.h), as kern_store.S: eight accesses a loop body, n a
 * multiple of 8, a0 = the pointer, a1 = n, a2 = the stride; caller-saved registers only. */
#define FN(name) .globl name; .type name, @function; .balign 64; name:

    .text
/* n loads of a word, sequential, never used: one D$ miss a 32-byte line, then hits. */
FN(k_ld_seq)
    srli a1, a1, 3
1:  lw t0, 0(a0)
    lw t1, 4(a0)
    lw t2, 8(a0)
    lw t3, 12(a0)
    lw t4, 16(a0)
    lw t5, 20(a0)
    lw t6, 24(a0)
    lw a3, 28(a0)
    addi a0, a0, 32
    addi a1, a1, -1
    bnez a1, 1b
    mv a0, a3
    ret

/* n loads a2 bytes apart: with a2 = 32 each one is a new line, so each misses. */
FN(k_ld_stride)
    srli a1, a1, 3
1:  .rept 8
    lw t0, 0(a0)
    add a0, a0, a2
    .endr
    addi a1, a1, -1
    bnez a1, 1b
    mv a0, t0
    ret

/* n dependent loads: each address is the word the last load returned (the chain is
 * built by the test's prep), so a load's whole latency is on the path. */
FN(k_ld_chase)
    srli a1, a1, 3
1:  .rept 8
    lw a0, 0(a0)
    .endr
    addi a1, a1, -1
    bnez a1, 1b
    ret

/* n store-then-load pairs on one word, a2 bytes apart: read after write. */
FN(k_raw)
    srli a1, a1, 3
1:  .rept 8
    sw a1, 0(a0)
    lw t0, 0(a0)
    add a0, a0, a2
    .endr
    addi a1, a1, -1
    bnez a1, 1b
    mv a0, t0
    ret

/* n words copied a0 <- a1 (a2 = n): eight loads then eight stores. */
FN(k_cpy_w)
    srli a2, a2, 3
1:  lw t0, 0(a1)
    lw t1, 4(a1)
    lw t2, 8(a1)
    lw t3, 12(a1)
    lw t4, 16(a1)
    lw t5, 20(a1)
    lw t6, 24(a1)
    lw a3, 28(a1)
    sw t0, 0(a0)
    sw t1, 4(a0)
    sw t2, 8(a0)
    sw t3, 12(a0)
    sw t4, 16(a0)
    sw t5, 20(a0)
    sw t6, 24(a0)
    sw a3, 28(a0)
    addi a0, a0, 32
    addi a1, a1, 32
    addi a2, a2, -1
    bnez a2, 1b
    ret

/* n loads of one word: an uncached register (a CSR, CHISEL's STATUS: a status poll's
 * latency), or a misaligned word in RAM (each load traps: tests_align.c). */
FN(k_csr_rd)
    srli a1, a1, 3
1:  .rept 8
    lw t0, 0(a0)
    .endr
    addi a1, a1, -1
    bnez a1, 1b
    mv a0, t0
    ret

/* n words read as four lbu, three shifts and three ors each: a misaligned lw done by hand. */
FN(k_lw_bytes)
    srli a1, a1, 3
1:  .rept 8
    lbu t0, 0(a0)
    lbu t1, 1(a0)
    lbu t2, 2(a0)
    lbu t3, 3(a0)
    slli t1, t1, 8
    slli t2, t2, 16
    slli t3, t3, 24
    or t0, t0, t1
    or t2, t2, t3
    or t0, t0, t2
    .endr
    addi a1, a1, -1
    bnez a1, 1b
    mv a0, t0
    ret
