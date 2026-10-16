/* The lean cart image (decisions.md 2026-10-15, cycles/split.mk): linked at ZM_CART_BASE
 * (CART_CPU_BASE + map_cart.zig CART_IMG_AT, --defsym), its header first, then code and
 * constants; its .bss follows and is zeroed by the system at every boot. No crt0, no libc.
 * What the cart must not have fails the link: .data (a warm boot could not restore it), TLS
 * (tp is the system's), a small-data gp base (gp is the system's). */
ENTRY(zm_cart_header)

SECTIONS
{
    . = ZM_CART_BASE;
    .zm_cart_hdr : { KEEP(*(.zm_cart_hdr)) }
    .text : { *(.text .text.*) }
    .rodata : ALIGN(8) { *(.rodata .rodata.* .srodata .srodata.*) }
    .data : ALIGN(8) { *(.data .data.* .sdata .sdata.*) }
    .tdata : { *(.tdata .tdata.*) }
    .tbss : { *(.tbss .tbss.*) }
    .bss (NOLOAD) : ALIGN(8) {
        __cart_bss_start = .;
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(8);
        __cart_bss_end = .;
    }
    /DISCARD/ : { *(.comment) *(.note .note.*) *(.eh_frame .eh_frame_hdr) *(.init_array* .fini_array*) }
}

ASSERT(ADDR(.zm_cart_hdr) == ZM_CART_BASE && SIZEOF(.zm_cart_hdr) > 0, "cart.ld: the header must open the image")
ASSERT(SIZEOF(.data) == 0, "cart.ld: a lean cart has no .data (the system zeroes .bss, it never copies .data)")
ASSERT(SIZEOF(.tdata) == 0 && SIZEOF(.tbss) == 0, "cart.ld: a lean cart has no TLS (tp points at the system's)")
ASSERT(!DEFINED(__global_pointer$), "cart.ld: no gp base (gp is the system's)")
