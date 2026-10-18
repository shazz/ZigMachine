/* After a CHISEL op, invalidate only the D-cache lines the op can have written (bblit.c step 4),
 * not the whole cache: the full invalidate cost ~130 cycles of sweep plus a refill of every hot
 * line the cart touches next (its stack, globals, tables), on every one of up to ~120 blits a frame.
 *
 * The cache: ZIGGY's D$ is vexgen GenZm's dBus, 4 KiB, 1 way, 32-byte lines, write-through
 * (VexRiscv_I16w2D4SealFpu: 128 lines). VexRiscv's MANAGEMENT instruction (DBusCachedPlugin,
 * opcode MISC-MEM, funct3 5, rs2 = imm = 0) invalidates every line when rs1 = x0 (vboard.h
 * zmv_flush_dcache) and only the line at rs1's index when rs1 != x0 (DataCache's flusher,
 * singleLine: lineId = rs1 >> 5, all ways). Write-through, so dropping a line never loses data,
 * and invalidating a line by its address is right whatever the geometry: only BDI_LINES, the
 * fallback's crossover, assumes it.
 *
 * What an op can write: machine/blitter.zig's opBox(), the clipped bounding box (FILL and BLIT:
 * the W x H rect; LINE: the endpoints' box; TRIANGLE: the vertices' box; every pixel the RTL
 * writes is inside it, rtl/blitter matches the machine pixel for pixel). Line by line, row by row,
 * or one contiguous span when that is fewer lines (a dense rect). The full invalidate when the
 * count passes BDI_LINES (a range that big costs more than the sweep), for an op the machine
 * refuses (D out of the region: it writes nothing, but this keeps the old behaviour) and for a
 * command it does not know. tests/test_blit_dcache.py: every byte any op changes is covered
 * (machine/blitter.zig natively), and on the board's core a planted stale line is dropped. */
#ifndef ZM_BDINVAL_H
#define ZM_BDINVAL_H

#include <stdint.h>

#include "dflush.h"
#include "zm_memmap.h"

#define BDI_LINE 32u
#define BDI_LINES 128u /* the D$'s line count: past it, the whole-cache sweep is cheaper */

#ifndef BDI_INVAL_LINE /* the host test (tests/blitter_ref/dinval_host.c) records instead */
static inline void bdi_inval_line(uintptr_t a) {
    register uintptr_t rs1 __asm__("a0") = a; /* x10: the encoding below names it */
    __asm__ volatile(".word(0x5500F)\n" ::"r"(rs1) : "memory");
}
#define BDI_INVAL_LINE(a) bdi_inval_line(a)
#endif

/* The whole cache, as vboard.h zmv_flush_dcache. dflush.h's two nops are what stop
 * `if (!bdi_range()) bdi_inval_all()` sweeping the whole cache after every range on the wrong
 * path (tests/dcache/ saw it). */
static inline void bdi_inval_all(void) { zm_dflush(); }

typedef struct {
    int32_t x0, y0, x1, y1; /* x1, y1 exclusive */
} bdi_box;

static inline uint16_t bdi_u16(const volatile uint8_t* r, uint32_t off) { return *(const volatile uint16_t*)(r + off); }
static inline int32_t bdi_s16(const volatile uint8_t* r, uint32_t off) { return *(const volatile int16_t*)(r + off); }
static inline int32_t bdi_min(int32_t a, int32_t b) { return a < b ? a : b; }
static inline int32_t bdi_max(int32_t a, int32_t b) { return a > b ? a : b; }

/* machine/blitter.zig clipRect(): the plane (height implied by the stride), then CLIP. */
static inline bdi_box bdi_clip(const volatile uint8_t* r, uint16_t ds) {
    bdi_box c = {0, 0, ds, ds == ZM_STRIDE_FULLSCREEN ? (int32_t)ZM_PHYSICAL_HEIGHT : (int32_t)ZM_HEIGHT};
    if (r[ZM_BLIT_CON] & ZM_CON_CLIP_EN) {
        int32_t cx = bdi_u16(r, ZM_BLIT_CLIP_X), cy = bdi_u16(r, ZM_BLIT_CLIP_Y);
        c.x0 = bdi_max(c.x0, cx);
        c.y0 = bdi_max(c.y0, cy);
        c.x1 = bdi_min(c.x1, cx + bdi_u16(r, ZM_BLIT_CLIP_W));
        c.y1 = bdi_min(c.y1, cy + bdi_u16(r, ZM_BLIT_CLIP_H));
    }
    return c;
}

/* machine/blitter.zig opBox(): 0 for a command with no box (the caller flushes everything). */
static inline int bdi_op_box(const volatile uint8_t* r, uint8_t cmd, bdi_box c, bdi_box* out) {
    int32_t x0 = bdi_s16(r, ZM_BLIT_X0), y0 = bdi_s16(r, ZM_BLIT_Y0);
    bdi_box b = {x0, y0, x0 + 1, y0 + 1};
    if (cmd == ZM_BLIT_CMD_FILL || cmd == ZM_BLIT_CMD_BLIT) {
        b.x1 = x0 + bdi_u16(r, ZM_BLIT_W);
        b.y1 = y0 + bdi_u16(r, ZM_BLIT_H);
    } else if (cmd == ZM_BLIT_CMD_LINE || cmd == ZM_BLIT_CMD_TRIANGLE) {
        int n = cmd == ZM_BLIT_CMD_LINE ? 2 : 3;
        for (int k = 1; k < n; k++) {
            int32_t x = bdi_s16(r, ZM_BLIT_X0 + 4u * k), y = bdi_s16(r, ZM_BLIT_Y0 + 4u * k);
            b.x0 = bdi_min(b.x0, x);
            b.y0 = bdi_min(b.y0, y);
            b.x1 = bdi_max(b.x1, x + 1);
            b.y1 = bdi_max(b.y1, y + 1);
        }
    } else {
        return 0;
    }
    *out = (bdi_box){bdi_max(b.x0, c.x0), bdi_max(b.y0, c.y0), bdi_min(b.x1, c.x1), bdi_min(b.y1, c.y1)};
    return 1;
}

static inline void bdi_span(uintptr_t first, uintptr_t end) { /* [first, end), end > first */
    for (uintptr_t a = first & ~(uintptr_t)(BDI_LINE - 1); a < end; a += BDI_LINE) BDI_INVAL_LINE(a);
}

/* Invalidate the lines op `cmd` (registers in the region r) can have written. 1 when that is done
 * (an empty box: nothing to do); 0 when the caller must invalidate the whole cache instead. */
static inline int bdi_range(const volatile uint8_t* r, uint8_t cmd) {
    uint16_t ds = bdi_u16(r, ZM_BLIT_D_STRIDE);
    uint32_t d_base = *(const volatile uint32_t*)(r + ZM_BLIT_D_BASE);
    bdi_box b;
    if (!bdi_op_box(r, cmd, bdi_clip(r, ds), &b)) return 0;
    if (b.x1 <= b.x0 || b.y1 <= b.y0) return 1; /* writes nothing (machine: destInRegion's empty box) */
    uint64_t last = (uint64_t)(uint32_t)(b.y1 - 1) * ds + (uint32_t)b.x1; /* one past the last byte */
    if ((uint64_t)d_base + last > ZM_REGION_BYTES) return 0; /* refused: writes nothing */
    uint32_t w = (uint32_t)(b.x1 - b.x0), rows = (uint32_t)(b.y1 - b.y0);
    uintptr_t first = (uintptr_t)r + d_base + (uint32_t)b.y0 * ds + (uint32_t)b.x0;
    uintptr_t end = (uintptr_t)r + d_base + (uintptr_t)last;
    uint32_t span_lines = (uint32_t)(((end - 1) >> 5) - (first >> 5) + 1);
    uint32_t row_lines = rows * ((w + BDI_LINE - 2) / BDI_LINE + 1); /* w bytes at any offset: at most */
    if (span_lines <= row_lines) {
        if (span_lines > BDI_LINES) return 0;
        bdi_span(first, end);
    } else {
        if (row_lines > BDI_LINES) return 0;
        for (uint32_t j = 0; j < rows; j++, first += ds) bdi_span(first, first + w);
    }
    return 1;
}

#endif
