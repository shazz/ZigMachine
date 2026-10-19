/* The bench's compute and I$ kernels (bench.h): the baselines a memory figure is read
 * against. n is the op count, a multiple of 8. ALU ops are independent (throughput); mul, div
 * and the FPU ops are each a chain on the last result (latency). */
#define FN(name) .globl name; .type name, @function; .balign 64; name:

    .text
FN(k_alu)
    srli a0, a0, 3
1:  .irp r, t0, t1, t2, t3, t4, t5, t6, a3
    addi \r, \r, 1
    .endr
    addi a0, a0, -1
    bnez a0, 1b
    mv a0, t0
    ret

FN(k_mul)
    srli a0, a0, 3
    li a2, 3
    li a3, 0x01234567
1:  .rept 8
    mul a3, a3, a2
    .endr
    addi a0, a0, -1
    bnez a0, 1b
    mv a0, a3
    ret

/* A 32-bit divide chain: the dividend keeps its top bit (or a4), so an early-out divider
 * shows its full latency; the `or` is one ALU cycle a divide (k_alu measures it). */
FN(k_div)
    srli a0, a0, 3
    li a2, 3
    li a3, -1
    li a4, 0x80000000
1:  .rept 8
    divu a3, a3, a2
    or a3, a3, a4
    .endr
    addi a0, a0, -1
    bnez a0, 1b
    mv a0, a3
    ret

#ifdef __riscv_flen
/* f32 chains with fa1 = 1.0: no subnormal, no overflow, the same values every run. */
.macro FCHAIN op
    srli a0, a0, 3
    li t0, 1
    fcvt.s.w fa1, t0
    fmv.s fa0, fa1
1:  .rept 8
    \op fa0, fa0, fa1
    .endr
    addi a0, a0, -1
    bnez a0, 1b
    ret
.endm
FN(k_fadd)
    FCHAIN fadd.s
FN(k_fmul)
    FCHAIN fmul.s
FN(k_fdiv)
    FCHAIN fdiv.s
#endif

/* The I$ (16 KiB, 2 ways, 32-byte lines): a loop whose body fits (8 KiB of addi) against one
 * that cannot (24 KiB: every pass refetches every line). a0 = passes; 2048 / 6144 ops a pass. */
FN(k_icache_fit)
1:  .rept 2048
    addi t0, t0, 1
    .endr
    addi a0, a0, -1
    beqz a0, 2f
    j 1b                                /* a branch reaches 4 KiB only */
2:  mv a0, t0
    ret

FN(k_icache_over)
1:  .rept 6144
    addi t0, t0, 1
    .endr
    addi a0, a0, -1
    beqz a0, 2f
    j 1b                                /* a branch reaches 4 KiB only */
2:  mv a0, t0
    ret
