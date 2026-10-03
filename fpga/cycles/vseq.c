/* The video sequencer (vseq.h): machine/video.zig's frame order, issued as
 * passes to the RTL compositor, with the HBL handlers called between them. */
#include "vseq.h"

#include "vboard.h"
#include "zm_memmap.h"

vseq_stats vseq;
static uint8_t* g_r; /* the region: HW_VIDEO_BASE in the cart's linear memory */

static inline uint32_t r32(uint32_t off) { return *(volatile uint32_t*)(g_r + off); }
static inline uint16_t r16(uint32_t off) { return *(volatile uint16_t*)(g_r + off); }
static inline uint8_t r8(uint32_t off) { return *(volatile uint8_t*)(g_r + off); }
static inline void w32(uint32_t off, uint32_t v) { *(volatile uint32_t*)(g_r + off) = v; }
static inline void w16(uint32_t off, uint16_t v) { *(volatile uint16_t*)(g_r + off) = v; }

static void wait_bits(uint32_t bits) {
    while ((zmv_status() & bits) != bits) {
    }
}

/* Every store the handlers made has reached the compositor (Fable #5). */
static void drain(void) {
    if (!(zmv_status() & ZMV_BIT(DRAINED))) vseq.undrained++; /* the race the rule closes was open */
#ifndef ZM_NO_DRAIN
    wait_bits(ZMV_BIT(DRAINED));
#endif
}

/* Write one command once the previous one has finished and the stores have landed. */
static void issue(int op, int plane, int line, int mix, int first) {
    wait_bits(ZMV_BIT(READY));
    drain();
    zmv_cmd(op, plane, line, mix, first);
}

/* A pass: issued, and run until it has read everything the next handler may change. */
static void pass(int op, int plane, int line, int mix, int first) {
    issue(op, plane, line, mix, first);
    wait_bits(ZMV_BIT(PAINTED));
}

/* A one-clock command (LATCH, PRESENT): issued and taken. */
static void instant(int op, int plane) {
    issue(op, plane, 0, 0, 0);
    wait_bits(ZMV_BIT(READY));
}

/* The back picture is free once the previous one is on screen (the swap at VBL). */
static void wait_swap(void) {
    uint32_t t0 = board_cycles();
    while (zmv_status() & ZMV_BIT(PENDING)) {
    }
    vseq.swap_wait += board_cycles() - t0;
}

void vseq_init(struct w2c_env* e, uint32_t fb0, uint32_t fb1) {
    g_r = e->memory.data + ZM_HW_VIDEO_BASE;
    if ((uintptr_t)g_r % 8 || fb0 % 8 || fb1 % 8) board_finish(6); /* rows are 64-bit beats */
    ZMV_REG(VBASE) = (uint32_t)(uintptr_t)g_r;
    ZMV_REG(FB0) = fb0;
    ZMV_REG(FB1) = fb1;
    for (uint32_t off = 0; off < ZM_OFF_VRAM; off += 4) w32(off, r32(off));
    for (uint32_t i = 0; i < ZM_BEAM_MAX; i++) w32(ZM_OFF_BEAM_TABLE + i * 4, r32(ZM_OFF_BEAM_TABLE + i * 4));
}

/* video.zig writes these back to memory itself: copy the compositor's values, so
 * the next handler reads them where the machine leaves them. */
static void copy_back(int beam, int last) {
#ifdef ZM_NO_COPYBACK /* the mutant: the compositor's write-backs never reach the region */
    return;
#endif
    if (beam) {
        w32(ZM_REG_BACKGROUND, zmv_reg(ZM_REG_BACKGROUND / 4));
        w32(ZM_REG_BEAM_DROPPED, zmv_reg(ZM_REG_BEAM_DROPPED / 4));
        w16(ZM_REG_BEAM_COUNT, (uint16_t)zmv_reg(ZM_REG_BEAM_COUNT / 4));
    }
    if (last) w32(ZM_REG_FRAME, zmv_reg(ZM_REG_FRAME / 4));
}

void vseq_clear(struct w2c_env* e) {
    uint16_t gid = r16(ZM_REG_GLOBAL_HBL_ID);
    for (uint32_t y = 0; y < ZM_RASTER_HEIGHT; y++) {
        if (gid) w2c_env_hblDispatch(e, gid, 0, y, 0);
        int beam = r16(ZM_REG_BEAM_COUNT) != 0;
        pass(ZMV_BG, 0, (int)y, 0, 0);
        copy_back(beam, y == ZM_RASTER_HEIGHT - 1);
    }
}

/* The raster lines a plane's handler runs on, and its first (video.zig renderPlane*). */
static void plane_lines(int p, uint32_t* oy, uint32_t* rows) {
    uint8_t mode = r8(ZM_REG_FB_MODE + (uint32_t)p);
    uint16_t stride = r16(ZM_REG_FB_STRIDE + 2u * (uint32_t)p);
    int whole = mode == ZM_FB_MODE_FULLSCREEN || mode == ZM_FB_MODE_OVERSCAN;
    if (mode == ZM_FB_MODE_MEDIUM) whole = stride >= ZM_RASTER_WIDTH;
    else if (mode != ZM_FB_MODE_SCROLL && !whole) whole = stride == ZM_STRIDE_FULLSCREEN;
    *oy = whole ? 0 : ZM_RASTER_BORDER_Y;
    *rows = whole ? ZM_RASTER_HEIGHT : ZM_HEIGHT;
}

#ifdef ZM_LINE_MAJOR
/* The mutant: the order a beam-racing compositor would impose (frame() first,
 * then per line G, BG, and each plane's handler and pass), which
 * tools/video_order.py found changes badflicker and equinox. */
void vseq_line_major(struct w2c_env* e, unsigned planes) {
    uint32_t oy[4], rows[4];
    uint16_t hid[4], hpos[4];
    int first = -1;
    for (int p = 0; p < 4; p++) {
        if (!((planes >> p) & 1)) continue;
        plane_lines(p, &oy[p], &rows[p]);
        hid[p] = r16(ZM_REG_FB_HBL_ID + 2u * (uint32_t)p), hpos[p] = r16(ZM_REG_FB_HBL_POS + 2u * (uint32_t)p);
        if (first < 0) first = p, wait_swap();
        instant(ZMV_LATCH, p);
    }
    uint16_t gid = r16(ZM_REG_GLOBAL_HBL_ID);
    for (uint32_t y = 0; y < ZM_RASTER_HEIGHT; y++) {
        if (gid) w2c_env_hblDispatch(e, gid, 0, y, 0);
        int beam = r16(ZM_REG_BEAM_COUNT) != 0;
        pass(ZMV_BG, 0, (int)y, 0, 0);
        copy_back(beam, y == ZM_RASTER_HEIGHT - 1);
        for (int p = 0; p < 4; p++) {
            if (!((planes >> p) & 1)) continue;
            if (hid[p] && y >= oy[p] && y < oy[p] + rows[p]) w2c_env_hblDispatch(e, hid[p], (u32)p, y - oy[p], hpos[p]);
            pass(ZMV_PLANE, p, (int)y, 1, p == first);
        }
    }
}
#endif

void vseq_plane(struct w2c_env* e, int p, int first) {
    uint32_t oy, rows;
    plane_lines(p, &oy, &rows);
    uint16_t hid = r16(ZM_REG_FB_HBL_ID + 2u * (uint32_t)p), hpos = r16(ZM_REG_FB_HBL_POS + 2u * (uint32_t)p);
    if (first) wait_swap();
    instant(ZMV_LATCH, p);
    for (uint32_t y = 0; y < ZM_RASTER_HEIGHT; y++) {
        if (hid && y >= oy && y < oy + rows) w2c_env_hblDispatch(e, hid, (u32)p, y - oy, hpos);
        pass(ZMV_PLANE, p, (int)y, 1, first);
    }
}

void vseq_mix_only(void) {
    wait_swap();
    for (int y = 0; y < (int)ZM_RASTER_HEIGHT; y++) pass(ZMV_MIX, 0, y, 1, 1);
}

void vseq_present(void) { instant(ZMV_PRESENT, 0); }

void vseq_idle(void) { wait_bits(ZMV_BIT(READY)); }
