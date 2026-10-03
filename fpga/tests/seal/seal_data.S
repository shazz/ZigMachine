/* The seal test's windows (seal.S): the cart's stubs and words, and the
 * case table: { stub | U, address, expected mcause }. */
    .include "seal.inc"
    .globl stubs, cases, m_stack_top, fw_secret, ro_word, ro_ecall, code_victim, code_ecall
    .globl data_word, data_ecall, lin_word, lin_ecall, u_ecalls, u_calls

    .section .text.cart, "ax"
stubs_code:
stub_load:  lw t1, 0(a0);  ecall
stub_store: sw t1, 0(a0);  ecall
stub_fetch: jr a0
stub_csr:   csrw mtvec, a0; ecall
stub_mret:  mret;          ecall
code_ecall: ecall
code_victim: nop
u_ecalls:
    li a7, 0
    li t2, 100
1:  ecall
    addi t2, t2, -1
    bnez t2, 1b
    li a7, 1
    ecall
u_calls:
    li a7, 0
    li t2, 99
1:  call m_function
    addi t2, t2, -1
    bnez t2, 1b
    li a7, 1
    call m_function

    .section .rodata.cart, "a"
ro_word:  .word 0x12345678
ro_ecall: .word 0

    .section .data.cart, "aw"
data_word:  .word 0
data_ecall: .word 0

    .section .data.linear, "aw"
lin_word:  .word 0
lin_ecall: .word 0

    .section .data.fw, "aw"
fw_secret: .word 0x0badf00d
stubs: .word stub_load, stub_store, stub_fetch, stub_csr, stub_mret
cases:
    CASE 0, fw_secret, 11             /* M reads it: the line is now in the D$ */
    CASE 0|U, fw_secret, 13           /* U may not, even from the cache */
    CASE 0|U, stub_load, 13           /* code is execute-only */
    CASE 0|U, ro_word, 8
    CASE 0|U, data_word, 8
    CASE 0|U, lin_word, 8
    CASE 0|U, VIDEO, 8
    CASE 0|U, GUARD, 13                /* the CSR bus */
    CASE 0|U, 0x00000000, 13           /* boot ROM */
    CASE 0|U, 0x3ffffffc, 13           /* just below the cart's DDR */
    CASE 0|U, 0x42000000, 13           /* just past it */
    CASE 0|U, 0x90800000, 13           /* just past the video window */
    CASE 1|U, code_victim, 15
    CASE 1|U, ro_word, 15
    CASE 1|U, fw_secret, 15           /* a store right before an ecall */
    CASE 1|U, GUARD, 15
    CASE 1|U, 0x42000000, 15
    CASE 1|U, data_word, 8
    CASE 1|U, lin_word, 8
    CASE 1|U, VIDEO, 8
    CASE 2|U, code_ecall, 8
    CASE 2|U, m_function, 1           /* firmware code */
    CASE 2|U, ro_ecall, 1
    CASE 2|U, data_ecall, 1
    CASE 2|U, lin_ecall, 1
    CASE 2|U, VIDEO + 4, 1
    CASE 3|U, 0, 2                    /* csrw mtvec */
    CASE 4|U, 0, 2                    /* mret */
    CASE 1, data_word, 11             /* M: everything ... */
    CASE 0, DEV + CYCLE, 11
    CASE 2, code_ecall, 11
    CASE 2, ro_ecall, 11
    CASE 2, lin_ecall, 1              /* ... but never runs what U can write */
    CASE 2, data_ecall, 1
    CASE 2, VIDEO + 4, 1
    .word -1
    .space 1024
m_stack_top:
