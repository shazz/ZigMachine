/* The video sequencer (vseq.h): machine/video.zig's frame order, issued as
 * passes to the RTL compositor, with the HBL handlers called between them. */
#include "vseq.h"

#include "vboard.h"
#include "vseq_wait.h"
#include "zm_memmap.h"

vseq_stats vseq;
vseq_clear_rec vseq_rec;
const uint8_t* vseq_skip;
int (*vseq_decide)(int y);
static uint8_t* g_r; /* the region: HW_VIDEO_BASE in the cart's linear memory */
static int g_fill;  /* this frame's clear was one CLEAR: the first layer's passes paint its lines */

static inline uint32_t r32(uint32_t off) { return *(volatile uint32_t*)(g_r + off); }
static inline uint16_t r16(uint32_t off) { return *(volatile uint16_t*)(g_r + off); }
static inline uint8_t r8(uint32_t off) { return *(volatile uint8_t*)(g_r + off); }
static inline void w32(uint32_t off, uint32_t v) { *(volatile uint32_t*)(g_r + off) = v; }
static inline void w16(uint32_t off, uint16_t v) { *(volatile uint16_t*)(g_r + off) = v; }

/* Every store the handlers made has reached the compositor (Fable #5). */
static inline uint32_t drain(void) {
    if (!(zmv_status() & ZMV_BIT(DRAINED))) vseq.undrained++; /* the race the rule closes was open */
#ifndef ZM_NO_DRAIN
    return wait_timed(ZMV_BIT(DRAINED));
#else
    return 0;
#endif
}

/* Write one command once the previous one has finished and the stores have landed. The
 * bookkeeping comes after the write, while the pass runs. ext: a line-major group's bits. */
void vseq_issue(int op, int plane, int line, int mix, int first, int fill, int ext) {
    uint32_t ready = wait_timed(ZMV_BIT(READY));
    uint32_t drained = drain();
    zmv_cmdx(op, plane, line, mix, first, fill, ext);
#ifdef ZM_VSTAT
    g_tcmd = board_cycles();
#endif
    vseq.ready += ready, vseq.drain += drained;
    vseq.passes += op == ZMV_BG || op == ZMV_PLANE || op == ZMV_MIX;
}

/* Run until the pass has read everything the next handler may change. ZM_VSTAT: the span from
 * the command's write, i.e. the pass's row load, fetch and paint as the CPU sees them. */
static inline void painted(void) {
    wait_bits(ZMV_BIT(PAINTED));
#ifdef ZM_VSTAT
    vseq.painted += board_cycles() - g_tcmd;
#endif
}

/* A pass: issued, and run until painted. */
static void pass(int op, int plane, int line, int mix, int first, int fill) {
    vseq_issue(op, plane, line, mix, first, fill, 0);
    painted();
}

/* A one-clock command (LATCH, PRESENT, CLEAR): issued and taken. */
static void instant(int op, int plane) {
    vseq_issue(op, plane, 0, 0, 0, 0, 0);
    wait_bits(ZMV_BIT(READY));
}

void vseq_latch(int p) { instant(ZMV_LATCH, p); }

void vseq_wait_painted(void) { painted(); }

uint16_t vseq_r16(uint32_t off) { return r16(off); }

void vseq_w16(uint32_t off, uint16_t v) { w16(off, v); }

int vseq_fill(void) { return g_fill; }

/* The back picture is free once the previous one is on screen (the swap at VBL). */
void vseq_wait_swap(void) {
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

/* With no global handler and no BEAM writes every line of the clear is BACKGROUND:
 * one CLEAR latches it (and counts the frame), and the first layer's passes paint
 * it where they would have loaded the BG pass's row. ZM_NO_FUSE: a BG pass a line. */
void vseq_clear(struct w2c_env* e) {
    uint16_t gid = r16(ZM_REG_GLOBAL_HBL_ID);
#ifndef ZM_NO_FUSE
    g_fill = !gid && !r16(ZM_REG_BEAM_COUNT);
    vseq_rec.fill = g_fill;
    if (g_fill) {
        vseq_rec.bg[0] = r32(ZM_REG_BACKGROUND); /* the colour the CLEAR latches */
        instant(ZMV_CLEAR, 0);
        copy_back(0, 1);
        return;
    }
#endif
    for (uint32_t y = 0; y < ZM_RASTER_HEIGHT; y++) {
        if (gid) hbl(e, gid, 0, y, 0);
        int beam = r16(ZM_REG_BEAM_COUNT) != 0;
        vseq_rec.bg[y] = r32(ZM_REG_BACKGROUND), vseq_rec.beam[y] = (uint8_t)beam;
        pass(ZMV_BG, 0, (int)y, 0, 0, 0);
        copy_back(beam, y == ZM_RASTER_HEIGHT - 1);
    }
}

uint8_t vseq_plane_mode(int p) { return r8(ZM_REG_FB_MODE + (uint32_t)p); }

int vseq_plane_handler(int p) { return r16(ZM_REG_FB_HBL_ID + 2u * (uint32_t)p) != 0; }

/* The raster lines a plane's handler runs on, and its first (video.zig renderPlane*): vseq.h. */
void vseq_plane_lines(int p, uint32_t* oy, uint32_t* rows) {
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
        vseq_plane_lines(p, &oy[p], &rows[p]);
        hid[p] = r16(ZM_REG_FB_HBL_ID + 2u * (uint32_t)p), hpos[p] = r16(ZM_REG_FB_HBL_POS + 2u * (uint32_t)p);
        if (first < 0) first = p, vseq_wait_swap();
        instant(ZMV_LATCH, p);
    }
    uint16_t gid = r16(ZM_REG_GLOBAL_HBL_ID);
    for (uint32_t y = 0; y < ZM_RASTER_HEIGHT; y++) {
        if (gid) hbl(e, gid, 0, y, 0);
        int beam = r16(ZM_REG_BEAM_COUNT) != 0;
        pass(ZMV_BG, 0, (int)y, 0, 0, 0);
        copy_back(beam, y == ZM_RASTER_HEIGHT - 1);
        for (int p = 0; p < 4; p++) {
            if (!((planes >> p) & 1)) continue;
            if (hid[p] && y >= oy[p] && y < oy[p] + rows[p]) hbl(e, hid[p], (u32)p, y - oy[p], hpos[p]);
            pass(ZMV_PLANE, p, (int)y, 1, p == first, 0);
        }
    }
}
#endif

/* One layer's passes (a plane's, or MIX), each line's after its handler. The first layer asks
 * vseq_decide which lines to skip, the next line while this line's pass runs: the comparison is
 * CPU work the sequencer would otherwise spend waiting. Later layers read vseq_skip. */
static void layer(struct w2c_env* e, int op, int p, int first, uint16_t hid, uint32_t oy, uint32_t rows, uint16_t hpos) {
    int ask = first && vseq_decide, next = ask ? decide(0) : 0;
    for (uint32_t y = 0; y < ZM_RASTER_HEIGHT; y++) {
        if (hid && y >= oy && y < oy + rows) hbl(e, hid, (u32)p, y - oy, hpos);
        int skip = ask ? next : vseq_skip && vseq_skip[y];
        if (!skip) vseq_issue(op, p, (int)y, 1, first, first && g_fill, 0);
        if (ask && y + 1 < ZM_RASTER_HEIGHT) next = decide((int)y + 1);
        if (!skip) painted(); /* a pass(): it has read what the next handler may change */
    }
}

void vseq_plane(struct w2c_env* e, int p, int first) {
    uint32_t oy, rows;
    vseq_plane_lines(p, &oy, &rows);
    uint16_t hid = r16(ZM_REG_FB_HBL_ID + 2u * (uint32_t)p), hpos = r16(ZM_REG_FB_HBL_POS + 2u * (uint32_t)p);
    if (first) vseq_wait_swap();
    instant(ZMV_LATCH, p);
    layer(e, ZMV_PLANE, p, first, hid, oy, rows, hpos);
}

void vseq_mix_only(void) {
    vseq_wait_swap();
    layer(NULL, ZMV_MIX, 0, 1, 0, 0, 0, 0);
}

void vseq_present(void) { instant(ZMV_PRESENT, 0); }

void vseq_idle(void) { wait_bits(ZMV_BIT(READY)); }
