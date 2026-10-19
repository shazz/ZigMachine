/* tests/blitpath/: the CSRs cycles/bblit.c reads, where tests/tb/dcache_tb.cpp answers them
 * (its device at 0xf0000000: +4 the cycle counter, +24 the program's word, here VBASE), and
 * CHISEL's window at the board's address (the harness answers its CYCLES word, 0 elsewhere).
 * The rest only lets vboard.h's inline helpers compile: bblit.c never calls them. */
#ifndef ZM_BLITPATH_CSR_H
#define ZM_BLITPATH_CSR_H

#define CSR_ZM_CYCLES_CYCLES_ADDR 0xf0000004u
#define CSR_ZMV_VBASE_ADDR 0xf0000018u
#define ZMB_WINDOW_ADDR 0x91000000u

#define CSR_ZMV_CMD_ADDR 0xf0000040u
#define CSR_ZMV_STATUS_ADDR 0xf0000044u
#define ZMV_WINDOW_ADDR 0x90000000u
#define ZMV_CMD_OP_SHIFT 0u
#define ZMV_CMD_OP_MASK 0x7u
#define ZMV_CMD_PLANE_SHIFT 3u
#define ZMV_CMD_PLANE_MASK 0x3u
#define ZMV_CMD_LINE_SHIFT 5u
#define ZMV_CMD_LINE_MASK 0x1ffu
#define ZMV_CMD_MIX_SHIFT 14u
#define ZMV_CMD_MIX_MASK 0x1u
#define ZMV_CMD_FIRST_SHIFT 15u
#define ZMV_CMD_FIRST_MASK 0x1u
#define ZMV_CMD_FILL_SHIFT 16u
#define ZMV_CMD_FILL_MASK 0x1u

#endif
