/* tests/dcache/: everything in the firmware window (M runs there, rtl/seal), the stack at 1 MiB. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
    .text 0x40000000 : { *(.text.start) *(.text*) }
    .rodata : { *(.rodata*) *(.srodata*) }
    .data : { *(.data*) *(.sdata*) *(.sbss*) *(.bss*) *(COMMON) }
    /DISCARD/ : { *(.riscv.attributes) *(.comment) }
    __stack_top = 0x40100000;
}
