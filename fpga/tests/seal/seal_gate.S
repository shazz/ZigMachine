/* Phase 2 of the seal test (seal.S): what a gate costs, in cycles of the
 * device counter: 100 ecall round trips, then 100 calls from U into an M
 * function through an instruction-fetch fault (the call gate). */
    .include "seal.inc"
    .globl phase2, m_function

    .section .text.fw, "ax"
/* Phase 2: the gate costs, in cycles of the device's counter. */
phase2:
    la t0, gate_trap
    csrw mtvec, t0
    la t0, m_stack_top
    csrw mscratch, t0
    li s5, DEV
    lw s6, CYCLE(s5)
    la t0, u_ecalls
    csrw mepc, t0
    li t0, 0x1800
    csrc mstatus, t0
    mret
ecalls_done:
    lw t0, CYCLE(s5)
    sub t0, t0, s6
    sw t0, REPORT(s5)             /* 100 ecall round trips */
    lw s6, CYCLE(s5)
    la t0, u_calls
    csrw mepc, t0
    li t0, 0x1800
    csrc mstatus, t0
    mret
calls_done:
    lw t0, CYCLE(s5)
    sub t0, t0, s6
    sw t0, REPORT(s5)             /* 100 calls through the fetch-fault gate */
    sw s3, EXIT(s5)               /* exit code = failures */
1:  j 1b

/* The gate handler: the cart's sp is swapped out for M's at once. */
gate_trap:
    csrrw sp, mscratch, sp
    addi sp, sp, -8
    sw t0, 0(sp)
    sw t1, 4(sp)
    csrr t0, mcause
    li t1, 1
    beq t0, t1, fetch_gate
    li t1, 1                      /* ecall: a7 = 1 means done */
    beq a7, t1, gate_ecalls_done
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    j gate_return
fetch_gate:                       /* a U call into M code: is it an entry? */
    csrr t0, mtval
    la t1, m_function
    bne t0, t1, gate_bad          /* not an entry point: stop the cart */
    addi a0, a0, 1                /* the function's body */
    beq a7, zero, 1f
    j calls_done
1:  csrw mepc, ra                 /* return to the caller */
gate_return:
    lw t0, 0(sp)
    lw t1, 4(sp)
    addi sp, sp, 8
    csrrw sp, mscratch, sp
    mret
gate_ecalls_done:
    la sp, m_stack_top            /* M's own stack, and mscratch ready again */
    csrw mscratch, sp
    j ecalls_done
gate_bad:
    li t0, DEV
    li t1, 0xbad1
    sw t1, REPORT(t0)
    sw t1, EXIT(t0)
1:  j 1b
m_function:                       /* never executed: U's fetch of it is the call */
    ret

