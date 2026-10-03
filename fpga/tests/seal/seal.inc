/* Shared by seal.S, seal_gate.S and seal_data.S. */
    .equ DEV, 0xf0000000
    .equ EXIT, 0x0
    .equ CYCLE, 0x4
    .equ REPORT, 0x8
    .equ GUARD, 0xf0000010
    .equ ECALL, 0x00000073
    .equ STORED, 0x5a5a1234
    .equ VIDEO, 0x90000000
    .equ U, 0x100
    .macro CASE kind, addr, cause
    .word \kind, \addr, \cause
    .endm

