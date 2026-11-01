/* tests/zmx/: a stack, a trap vector that counts and skips the faulting instruction (the
 * illegal-encoding probes of zmx.c), main(), its result to the harness's exit register. */
    .section .text.start
    .globl _start
_start:
    la sp, __stack_top
    la t0, zmx_trap
    csrw mtvec, t0
    li t0, 1 << 13 /* mstatus.FS = Initial: the core has the FPU and picolibc may touch it */
    csrs mstatus, t0
    call main
    li t0, 0xf0000000
    sw a0, 0(t0)
1:  j 1b

    .align 4
zmx_trap:
    csrw mscratch, t0
    addi sp, sp, -16
    sw t1, 0(sp)
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    la t0, zmx_traps
    lw t1, 0(t0)
    addi t1, t1, 1
    sw t1, 0(t0)
    lw t1, 0(sp)
    addi sp, sp, 16
    csrr t0, mscratch
    mret
