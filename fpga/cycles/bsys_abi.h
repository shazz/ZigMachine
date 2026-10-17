/* The one rule for which cart image a system image runs (decisions.md 2026-10-15): the
 * versions are major << 16 | minor, as fpga/cycles/sys_abi.txt numbers them. The major must
 * be equal (anything but an appended table entry changed); the cart's minor at most the
 * system's (it may call entries appended after it was built, never ones the system lacks).
 * glass applies the same rule (fpga/glass/src/system.zig); tests/test_cart_split.py holds both. */
#ifndef ZM_BSYS_ABI_H
#define ZM_BSYS_ABI_H

#include <stdint.h>

static inline int bsys_abi_ok(uint32_t need, uint32_t have) {
    return (need >> 16) == (have >> 16) && (need & 0xFFFFu) <= (have & 0xFFFFu);
}

#endif
