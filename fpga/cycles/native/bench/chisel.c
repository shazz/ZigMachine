/* CHISEL from the bench, two ways:
 *   chisel_fill / chisel_copy   the registers in the shared memory, then the system's hwBlit
 *                               (cycles/bblit.c): GO, spin on BUSY, invalidate the D$ lines of
 *                               the box. What every cart pays (libs/zig/chisel.zig).
 *   chisel_go_fill / _wait      the same registers, then GO stored straight to CHISEL's window
 *                               and no wait: the cart runs on while CHISEL works (the contention
 *                               tests), and its bare cost shows without bblit's bookkeeping.
 * A register is stored only when it changes, as the libraries do: every store is a bus write,
 * and CHISEL's tap already holds what memory holds. Destinations are in VRAM (BENCH_BLIT_OFF):
 * an op whose D is below OFF_VRAM runs the machine's software blitter instead. */
#include "bench.h"

#define BUSY (1u << 31)

static void w8(uint32_t off, uint8_t v) {
    volatile uint8_t* p = g.vreg + off;
    if (*p != v) *p = v;
}
static void w16(uint32_t off, uint16_t v) {
    volatile uint16_t* p = (volatile uint16_t*)(g.vreg + off);
    if (*p != v) *p = v;
}
static void w32(uint32_t off, uint32_t v) {
    volatile uint32_t* p = (volatile uint32_t*)(g.vreg + off);
    if (*p != v) *p = v;
}

static void hw_blit(void) { SYS(ZM_ENV_hwBlit, void (*)(struct w2c_env*))(g.env); }

/* D, its stride, X0 = Y0 = 0, W x H, and the halftone off (a sniffed pattern would dither). */
static void dest(uint32_t off, uint32_t stride, uint32_t w, uint32_t h) {
    w32(ZM_BLIT_D_BASE, off);
    w16(ZM_BLIT_D_STRIDE, (uint16_t)stride);
    w32(ZM_BLIT_X0, 0);
    w32(ZM_BLIT_W, w | h << 16); /* W, then H at +2 */
    for (uint32_t i = 0; i < 32; i += 4) w32(ZM_BLIT_HALFTONE + i, 0);
}

static void fill_regs(uint32_t off, uint32_t stride, uint32_t w, uint32_t h) {
    dest(off, stride, w, h);
    w8(ZM_BLIT_CON, 0);
    w8(ZM_BLIT_CON2, 0);
    w8(ZM_BLIT_COLOR, 0x5A);
}

void chisel_fill(uint32_t off, uint32_t stride, uint32_t w, uint32_t h) {
    fill_regs(off, stride, w, h);
    w8(ZM_BLIT_COMMAND, ZM_BLIT_CMD_FILL);
    hw_blit();
}

/* src_abs: a linear address in the cart's RAM (CON2.SRC_ABS), rows `stride` apart too. */
void chisel_copy(uint32_t off, uint32_t src_abs, uint32_t stride, uint32_t w, uint32_t h) {
    dest(off, stride, w, h);
    w8(ZM_BLIT_CON, ZM_CON_USEB);
    w8(ZM_BLIT_CON2, ZM_CON2_SRC_ABS);
    w8(ZM_BLIT_MINTERM, ZM_MT_B);
    w8(ZM_BLIT_COLOR_KEY, 0);
    w32(ZM_BLIT_B_BASE, src_abs);
    w16(ZM_BLIT_B_STRIDE, (uint16_t)stride);
    w8(ZM_BLIT_COMMAND, ZM_BLIT_CMD_BLIT);
    hw_blit();
}

void chisel_go_fill(uint32_t off, uint32_t stride, uint32_t w, uint32_t h) {
    fill_regs(off, stride, w, h);
    *(volatile uint8_t*)NATIVE_ZMB_WINDOW = ZM_BLIT_CMD_FILL; /* GO: after every register store */
}

void chisel_wait(void) {
    while (*(volatile uint32_t*)NATIVE_ZMB_WINDOW & BUSY) {
    }
}
