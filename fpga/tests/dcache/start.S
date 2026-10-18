/* tests/dcache/: a stack, main(), its result to the harness's exit register. */
    .section .text.start
    .globl _start
_start:
    la sp, __stack_top
    call main
    li t0, 0xf0000000
    sw a0, 0(t0)
1:  j 1b
