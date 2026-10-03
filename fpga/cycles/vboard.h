/* The video sim's SoC as the sequencer sees it (soc/video_sim.py): the video
 * pipeline's command and status registers, its read-back window, and the main
 * RAM's traffic counters. Addresses and fields come from csr_addr.h, generated
 * from the SoC's csr.json and soc/zm_video_pipe.py (tools/cycles_csr.py --video). */
#ifndef ZM_VBOARD_H
#define ZM_VBOARD_H

#include <stdint.h>

#include "board.h"

#define ZMV_REG(name) (*(volatile uint32_t*)CSR_ZMV_##name##_ADDR)
#define ZMV_FIELD(kind, name, v) (((uint32_t)(v) & ZMV_##kind##_##name##_MASK) << ZMV_##kind##_##name##_SHIFT)
#define ZMV_BIT(name) (ZMV_STATUS_##name##_MASK << ZMV_STATUS_##name##_SHIFT)

/* rtl/video/zm_video_comp.v's commands. */
enum { ZMV_BG = 0, ZMV_PLANE = 1, ZMV_LATCH = 2, ZMV_MIX = 3, ZMV_PRESENT = 4 };

static inline uint32_t zmv_status(void) { return ZMV_REG(STATUS); }

static inline void zmv_cmd(int op, int plane, int line, int mix, int first) {
    ZMV_REG(CMD) = ZMV_FIELD(CMD, OP, op) | ZMV_FIELD(CMD, PLANE, plane) | ZMV_FIELD(CMD, LINE, line) |
                   ZMV_FIELD(CMD, MIX, mix) | ZMV_FIELD(CMD, FIRST, first);
}

/* The compositor's own copy of register word `w` (offset / 4). */
static inline uint32_t zmv_reg(int w) { return ((volatile uint32_t*)ZMV_WINDOW_ADDR)[w]; }

/* VexRiscv: invalidate the (write-through) data cache, so loads see what the
 * video DMA wrote behind it (LiteX's flush_cpu_dcache). */
static inline void zmv_flush_dcache(void) { __asm__ volatile(".word(0x500F)\n" ::: "memory"); }

/* Main RAM traffic since reset, mod 2^32: soc/zm_simram.py COUNTERS order. */
#define ZMV_NRAM 5
static inline void zmv_ram_counters(uint32_t out[ZMV_NRAM]) {
    volatile uint32_t* r = (volatile uint32_t*)CSR_MAIN_RAM_CPU_RD_ADDR;
    for (int i = 0; i < ZMV_NRAM; i++) out[i] = r[i];
}

#endif
