/* The seal, end to end on the sealed VexRiscv (tests/test_seal_core.py).
 *
 * Phase 1: a table of cases. Each runs ONE access through a stub in the cart's
 * code window, in U (mret) or in M (jr): the stub does the access and ecalls.
 * Every case ends in the trap handler, which compares mcause (and mtval for an
 * access fault) with the table: 8 = U went through, 11 = M went through,
 * 1 = fetch access fault, 13/15 = load/store denied by the seal (a page fault:
 * ZmSealPlugin.scala says why), 2 = illegal instruction.
 * Then the victims the forbidden stores aimed at must be unchanged, and the
 * allowed stores must have landed. Fetch targets hold an `ecall`, planted by M,
 * so a fetch the seal wrongly allows shows up as 8/11 instead of 1.
 *
 * Phase 2: what a gate costs: 100 ecall round trips, and 100 calls from U into
 * an M function through an instruction-fetch fault (the call gate).
 *
 * The device (tests/tb/seal_core_tb.cpp): EXIT, CYCLE, REPORT, and GUARD, which
 * only U ever aims at: any bus access to it is a leak. */
    .include "seal.inc"
    .globl next_case, phase2, trap

    .section .text.fw, "ax"
    .globl _start
_start:
    la sp, m_stack_top
    la t0, trap
    csrw mtvec, t0
    li t0, ECALL                  /* plant the fetch targets */
    la t1, ro_ecall;   sw t0, 0(t1)
    la t1, data_ecall; sw t0, 0(t1)
    la t1, lin_ecall;  sw t0, 0(t1)
    li t1, VIDEO + 4;  sw t0, 0(t1)
    la s0, cases
    li s3, 0                      /* failures */
next_case:
    lw t2, 0(s0)
    bltz t2, phase1_done
    lw a0, 4(s0)
    li t1, STORED
    la t3, stubs
    andi t4, t2, 0xff
    slli t4, t4, 2
    add t3, t3, t4
    lw t3, 0(t3)
    andi t4, t2, U
    beqz t4, 1f
    csrw mepc, t3
    li t4, 0x1800
    csrc mstatus, t4              /* MPP = U */
    mret
1:  jr t3

trap:                             /* every phase-1 case ends here, in M */
    la sp, m_stack_top            /* never trust the cart's sp */
    csrr t0, mcause
    csrr t1, mtval
    lw t2, 8(s0)                  /* expected cause */
    bne t0, t2, case_fail
    li t3, 1;  beq t0, t3, check_tval
    li t3, 13; beq t0, t3, check_tval
    li t3, 15; bne t0, t3, case_ok
check_tval:
    lw t3, 4(s0)
    beq t1, t3, case_ok
case_fail:
    addi s3, s3, 1
    li t3, DEV
    la t4, cases                  /* report: case offset, cause, tval */
    sub t4, s0, t4
    sw t4, REPORT(t3)
    sw t0, REPORT(t3)
    sw t1, REPORT(t3)
case_ok:
    addi s0, s0, 12
    j next_case

    .macro EXPECT sym, value
    la t0, \sym
    lw t0, 0(t0)
    li t1, \value
    beq t0, t1, 1f
    addi s3, s3, 1
    li t2, DEV
    li t3, 0xbad0
    sw t3, REPORT(t2)
    sw t0, REPORT(t2)
1:
    .endm
phase1_done:
    EXPECT fw_secret, 0x0badf00d   /* forbidden stores never landed */
    EXPECT ro_word, 0x12345678
    EXPECT code_victim, 0x00000013
    EXPECT data_word, STORED      /* allowed ones did */
    EXPECT lin_word, STORED
    li t0, VIDEO
    lw t0, 0(t0)
    li t1, STORED
    beq t0, t1, 1f
    addi s3, s3, 1
1:  j phase2

