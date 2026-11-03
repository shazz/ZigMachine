/* vsynth's true-colour scenario (HW 1.15.0, fpga/review/TRUECOLOR_PLANE.md): RGB565 planes of both
 * modes, layered with an 8-bit plane, every frame:
 *   plane 0 TRUECOLOR_FULL, stride 800, an odd FB_BASE: pixel i of the buffer is i & 0xFFFF, so its
 *            112,000 pixels show every 565 value; a copper list on border AND visible lines: an
 *            LBASE (odd ones too) every seventh line, a REG HSCROLL (0..299, odd ones too) every
 *            other line, so the copper must cover lines 0..279 as the machine does;
 *   plane 1 TRUECOLOR, stride 640, an odd FB_BASE, its handler rewriting HSCROLL every line (live)
 *            and the latched FB_BASE (which must not move this frame);
 *   plane 2 normal 8-bit over them, palettes of every alpha (the browser blends the canvases);
 *   plane 3 TRUECOLOR, an odd stride (701): every other row starts on an odd byte. */
#include "vsynth.h"
#include "zm_memmap.h"

#define LIST0 (ZM_OFF_VRAM + 0xF0000u) /* no plane's source reaches it */
#define SRC_TOP (ZM_OFF_VRAM + 0x90000u)
#define REG2(r, p) ((r) + (uint32_t)(p) * 2)

static const uint32_t k_base[4] = {ZM_OFF_VRAM + 1, ZM_OFF_VRAM + 0x40000u + 3, ZM_OFF_VRAM + 0x70000u,
                                   ZM_OFF_VRAM + 0x80000u + 1};

static uint32_t g_at;
static void put(uint32_t w) {
    vs_w32(g_at, w);
    g_at += 4;
}

static void list0(void) {
    g_at = LIST0;
    vs_w16(REG2(ZM_REG_FB_COPPER, 0), (LIST0 - ZM_OFF_VRAM) / 16u);
    for (uint32_t y = 0; y < ZM_RASTER_HEIGHT; y++) {
        uint32_t n = (y % 7 == 3) + (y % 2 == 0);
        if (!n) continue;
        put(0xF0000000u | y << 19 | n);
        if (y % 7 == 3) put(0x50000000u | (ZM_OFF_VRAM + vs_rnd() % (SRC_TOP - ZM_OFF_VRAM)));
        if (y % 2 == 0) put(0x20000000u | REG2(ZM_REG_HSCROLL, 0) << 20 | (vs_rnd() % 300));
    }
    put(0xF0000000u | 511u << 19);
}

void vs_tc_setup(void) {
    vs_fill(ZM_OFF_VRAM, ZM_VRAM_BYTES);
    for (uint32_t i = 0; i < 400u * 280u; i++) vs_w16(k_base[0] - 1 + 2 * i, i & 0xFFFFu);
    for (int p = 0; p < ZM_NB_PLANES; p++) vs_palette(p);
    for (uint32_t i = 0; i < ZM_PAL_ENTRIES; i++) vs_w32(ZM_OFF_PAL + 2 * ZM_PAL_BYTES + i * 4, vs_rnd());
    vs_plane(0, ZM_FB_MODE_TRUECOLOR_FULL, ZM_TRUECOLOR_FULL_STRIDE, k_base[0], 0);
    vs_plane(1, ZM_FB_MODE_TRUECOLOR, ZM_TRUECOLOR_STRIDE, k_base[1], 0);
    vs_plane(2, ZM_FB_MODE_NORMAL, 320, k_base[2], 0);
    vs_plane(3, ZM_FB_MODE_TRUECOLOR, 701, k_base[3], 0);
    vs_w16(REG2(ZM_REG_FB_HBL_ID, 0), 0);
}

void vs_tc_frame(int f) {
    for (int p = 0; p < ZM_NB_PLANES; p++) vs_w32(ZM_REG_FB_BASE + (uint32_t)p * 4, k_base[p]);
    vs_w16(REG2(ZM_REG_HSCROLL, 3), (uint32_t)f); /* odd on frame 1 */
    list0();
}

void vs_tc_hbl(uint32_t id, uint32_t plane, uint32_t line) {
    (void)id;
    if (plane == 1) {
        vs_w16(REG2(ZM_REG_HSCROLL, 1), (line * 5 + vs_rnd() % 3) % 301);
        vs_w32(ZM_REG_FB_BASE + 4u, vs_rnd()); /* latched: must not move this frame */
    }
    if (plane == 2) vs_w32(ZM_OFF_PAL + 2 * ZM_PAL_BYTES + (line & 255) * 4, vs_rnd());
}
