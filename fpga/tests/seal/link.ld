/* The seal test program (seal.S): one output section per window of
 * rtl/seal/zm_seal_map.vh, at the window's base. tests/test_seal_core.py checks
 * these addresses against the map, so the two cannot drift apart. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
    .fw     0x40000000 : { *(.text.fw) }
    .fwdata 0x40100000 : { *(.data.fw) }
    .code   0x40800000 : { *(.text.cart) }
    .rodata 0x41000000 : { *(.rodata.cart) }
    .data   0x41400000 : { *(.data.cart) }
    .linear 0x41800000 : { *(.data.linear) }
    /DISCARD/ : { *(.riscv.attributes) *(.comment) }
}
