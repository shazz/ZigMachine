/* Compiled (never linked) with every native cart (cycles/native/native.mk): native.h's plain
 * numbers, which the assembly uses, against the generated table header and the machine's
 * memmap. A table or memmap change then fails the build here instead of a cart calling the
 * wrong entry on the board. */
#include <stddef.h>

#include "bsys_abi.h"
#include "native.h"
#include "zm_memmap.h"

_Static_assert(NATIVE_PAGES == ZM_SHARED_PAGES, "the header's page count is the system's (bsys.c)");
_Static_assert(NATIVE_REG_BACKGROUND == ZM_REG_BACKGROUND, "memmap");
_Static_assert(NATIVE_CART_RAM_BASE == ZM_CART_RAM_BASE, "memmap");
_Static_assert(NATIVE_MAGIC ==ZM_CART_HDR_MAGIC, "the cart header's magic");
_Static_assert((NATIVE_VERSION >> 16) == ZM_SYS_ABI_MAJOR && (NATIVE_VERSION & 0xFFFF) <= ZM_SYS_ABI_MINOR,
               "a system of this table runs the assembly cart (bsys_abi.h)");
_Static_assert(NATIVE_HDR_BYTES == sizeof(zm_cart_hdr), "zm_cart_hdr's size");
_Static_assert(offsetof(zm_cart_hdr, bind) == 32 && offsetof(zm_cart_hdr, songs) == 60 &&
                   offsetof(zm_cart_hdr, tag) == 80,
               "zm_cart_hdr's layout as hello_asm.S writes it");
_Static_assert(NATIVE_TABLE_FN == offsetof(zm_sys_table, fn), "zm_sys_table's fn[]");
_Static_assert(NATIVE_IX_w2c_env_memory == ZM_RT_w2c_env_memory, "table index");
_Static_assert(NATIVE_IX_guiOpenPlane == ZM_ENV_guiOpenPlane, "table index");
_Static_assert(NATIVE_IX_guiRect == ZM_ENV_guiRect, "table index");
_Static_assert(NATIVE_IX_guiText == ZM_ENV_guiText, "table index");
_Static_assert(NATIVE_IX_hwVideoBase == ZM_ENV_hwVideoBase, "table index");
_Static_assert(NATIVE_IX_romInstallPalettePlane == ZM_ENV_romInstallPalettePlane, "table index");
_Static_assert(sizeof native_none >= 10 * sizeof(void*), "the empty bridge covers the largest bridge");
