/* Machine-mode trap entry: save every register in a frame on the stack, let
 * zm_trap (trap.c) look at it, restore and return. regs[i] is x<i>; regs[2]
 * holds the sp of the interrupted code, so zm_trap can read any operand, and
 * regs[0] holds ZERO: an emulated `sw zero, 0(a4)` (wasm2c clearing a struct at a
 * misaligned address) stores x0. Without it the slot was stale stack and the
 * emulation stored garbage: the MOD player's channel table, 2026-10-09. */
    .section .text.zm_trap_entry
    .globl zm_trap_entry
    .align 4
zm_trap_entry:
    addi sp, sp, -128
    .irp n, 1,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    sw x\n, (\n*4)(sp)
    .endr
    sw zero, 0(sp)
    addi t0, sp, 128
    sw t0, 8(sp)
    mv a0, sp
    call zm_trap
    .irp n, 1,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    lw x\n, (\n*4)(sp)
    .endr
    addi sp, sp, 128
    mret
