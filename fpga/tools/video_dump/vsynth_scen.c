/* vsynth's scenarios (vsynth.h). Each one aims at what the cart corpus cannot
 * reach; HBL handlers also write registers the machine latches per frame
 * (FB_BASE, HSCROLL outside scroll mode), so a compositor that re-reads them
 * per line, instead of latching them, differs. */
#include "vsynth.h"
#include "zm_memmap.h"

#define VRAM(k) (ZM_OFF_VRAM + (uint32_t)(k) * 0x40000u) /* 4 x 256 KiB slots */
#define REG2(r, p) ((r) + (uint32_t)(p) * 2)

static const uint32_t k_base[4] = {VRAM(0) + 3, VRAM(1) + 1, VRAM(2) + 5, VRAM(3) + 2};

static void setup_common(void) {
    vs_fill(ZM_OFF_VRAM, ZM_VRAM_BYTES);
    for (int p = 0; p < ZM_NB_PLANES; p++) vs_palette(p);
}

/* Per-line noise every scenario adds: a palette entry and the latched FB_BASE. */
static void scribble(uint32_t plane, uint32_t line) {
    vs_w32(ZM_OFF_PAL + plane * ZM_PAL_BYTES + (line & 255) * 4, 0xFF000000u | vs_rnd());
    vs_w32(ZM_REG_FB_BASE + plane * 4, vs_rnd()); /* latched: must not move this frame */
}

static void reset_bases(int f) {
    (void)f;
    for (int p = 0; p < ZM_NB_PLANES; p++) vs_w32(ZM_REG_FB_BASE + (uint32_t)p * 4, k_base[p]);
}

/* --- fullscreen: FB_MODE_FULLSCREEN, odd stride, hs > stride, legacy stride 400 --- */
static void fs_setup(void) {
    setup_common();
    vs_plane(0, ZM_FB_MODE_FULLSCREEN, 400, k_base[0], 0);
    vs_plane(1, ZM_FB_MODE_FULLSCREEN, 333, k_base[1], 0);
    vs_plane(2, ZM_FB_MODE_NORMAL, 400, k_base[2], 0); /* back-compat: stride 400 = fullscreen */
    vs_w16(REG2(ZM_REG_HSCROLL, 0), 137);
    vs_w16(REG2(ZM_REG_HSCROLL, 1), 1000);
}
static void fs_hbl(uint32_t id, uint32_t plane, uint32_t line) {
    (void)id;
    vs_w16(REG2(ZM_REG_HSCROLL, plane), line * 3 + plane); /* latched: next frame's fine scroll */
    scribble(plane, line);
}

/* --- scroll: HSCROLL per line, a non-320 normal stride, an unknown mode --- */
static void scroll_setup(void) {
    setup_common();
    vs_plane(0, ZM_FB_MODE_SCROLL, 640, k_base[0], 0);
    vs_plane(1, ZM_FB_MODE_NORMAL, 512, k_base[1], 0);
    vs_plane(2, 9, 320, k_base[2], 0); /* not a mode: normal */
}
static void scroll_hbl(uint32_t id, uint32_t plane, uint32_t line) {
    (void)id;
    if (plane == 0) vs_w16(REG2(ZM_REG_HSCROLL, 0), (line * 7 + vs_rnd() % 3) % 301);
    scribble(plane, line);
}

/* --- medium: RESOLUTION per line, 640 and 800 strides, a plane with no HBL --- */
static void med_setup(void) {
    setup_common();
    vs_plane(0, ZM_FB_MODE_MEDIUM, 640, k_base[0], 0);
    vs_plane(1, ZM_FB_MODE_MEDIUM, 800, k_base[1], 0);
    vs_plane(2, ZM_FB_MODE_MEDIUM, 640, k_base[2], 0);
    vs_w16(REG2(ZM_REG_FB_HBL_ID, 2), 0);
}
static void med_hbl(uint32_t id, uint32_t plane, uint32_t line) {
    (void)id;
    static const uint8_t res[4] = {ZM_RES_MEDIUM, ZM_RES_PLANES, ZM_RES_MEDIUM, ZM_RES_TRUECOLOR};
    vs_w8(ZM_REG_RESOLUTION, res[(line + plane) % 4 == 3 ? 3 : vs_rnd() % 3]);
    scribble(plane, line);
}

/* --- overscan: on-time, late and sparse flickers, a wide buffer, no handler --- */
static void ovs_setup(void) {
    setup_common();
    vs_plane(0, ZM_FB_MODE_OVERSCAN, 400, k_base[0], ZM_OVERSCAN_MAGIC_X);
    vs_plane(1, ZM_FB_MODE_OVERSCAN, 512, k_base[1], ZM_OVERSCAN_MAGIC_X + 10);
    vs_plane(2, ZM_FB_MODE_OVERSCAN, 400, k_base[2], ZM_OVERSCAN_MAGIC_X - ZM_OVERSCAN_X_TOL);
    vs_plane(3, ZM_FB_MODE_OVERSCAN, 400, k_base[3], ZM_OVERSCAN_MAGIC_X);
    vs_w16(REG2(ZM_REG_FB_HBL_ID, 3), 0);
}
static void ovs_hbl(uint32_t id, uint32_t plane, uint32_t line) {
    (void)id;
    int flick = plane == 2 ? (line == 10 || line == 100 || line == 250) : (int)(vs_rnd() % (plane + 2)) == 0;
    if (flick) vs_w16(ZM_REG_RES_FLICKER, vs_r16(ZM_REG_RES_FLICKER) + 1);
    scribble(plane, line);
}

/* --- beam: valid lists, drops (gap, x >= 400), more than BEAM_MAX, snapping --- */
static uint32_t beam_list(uint32_t line) {
    uint32_t n = 0, x = vs_rnd() % 12;
    switch (line % 7) {
    case 1: n = vs_rnd() % 20; break;
    case 2: n = vs_rnd() % ZM_BEAM_MAX; break;
    case 3: n = ZM_BEAM_MAX + vs_rnd() % 40; break;
    case 4: n = 30; break;
    case 5: n = 1; x = 0; break;
    default: return 0;
    }
    for (uint32_t i = 0; i < n && i < ZM_BEAM_MAX; i++) {
        uint32_t ex = line % 7 == 2 ? vs_rnd() % 512 : x;
        vs_w32(ZM_OFF_BEAM_TABLE + i * 4, ex << 16 | (vs_rnd() & 0xFFFF));
        x += line % 7 == 4 ? 7 + i % 3 : 6 + vs_rnd() % 16; /* 7 then 8 snaps into the gap */
    }
    return n;
}
static void beam_setup(void) {
    setup_common();
    vs_w16(ZM_REG_GLOBAL_HBL_ID, ZM_HBL_GLOBAL_ID);
    vs_w16(REG2(ZM_REG_FB_HBL_ID, 0), 0);
}
static void beam_hbl(uint32_t id, uint32_t plane, uint32_t line) {
    (void)plane;
    if (id != ZM_HBL_GLOBAL_ID) return;
    if (line % 7 == 0) vs_w32(ZM_REG_BACKGROUND, 0xFF000000u | vs_rnd());
    vs_w16(ZM_REG_BEAM_COUNT, beam_list(line));
}

/* --- layers: four modes stacked, BACKGROUND per line under them --- */
static void layer_setup(void) {
    setup_common();
    vs_plane(0, ZM_FB_MODE_NORMAL, 320, k_base[0], 0);
    vs_plane(1, ZM_FB_MODE_SCROLL, 700, k_base[1], 0);
    vs_plane(2, ZM_FB_MODE_MEDIUM, 640, k_base[2], 0);
    vs_plane(3, ZM_FB_MODE_FULLSCREEN, 400, k_base[3], 0);
    vs_w16(ZM_REG_GLOBAL_HBL_ID, ZM_HBL_GLOBAL_ID);
    vs_w8(ZM_REG_RESOLUTION, ZM_RES_MEDIUM);
}
static void layer_hbl(uint32_t id, uint32_t plane, uint32_t line) {
    if (id == ZM_HBL_GLOBAL_ID) {
        vs_w32(ZM_REG_BACKGROUND, 0xFF000000u | vs_rnd());
        return;
    }
    if (plane == 1) vs_w16(REG2(ZM_REG_HSCROLL, 1), vs_rnd() % 380);
    scribble(plane, line);
}

/* --- alpha: palettes of every alpha on four stacked modes, so the browser
 * blends canvases (zm_video_mix.v); and the same with no plane at all, where
 * the cleared PFB alone is the picture, its BACKGROUND half transparent --- */
static void alpha_palettes(void) {
    for (uint32_t i = 0; i < ZM_NB_PLANES * ZM_PAL_ENTRIES; i++) vs_w32(ZM_OFF_PAL + i * 4, vs_rnd());
}
static void alpha_setup(void) {
    setup_common();
    alpha_palettes();
    vs_plane(0, ZM_FB_MODE_OVERSCAN, 400, k_base[0], ZM_OVERSCAN_MAGIC_X);
    vs_plane(1, ZM_FB_MODE_NORMAL, 320, k_base[1], 0);
    vs_plane(2, ZM_FB_MODE_MEDIUM, 640, k_base[2], 0);
    vs_plane(3, ZM_FB_MODE_SCROLL, 640, k_base[3], 0);
    vs_w8(ZM_REG_RESOLUTION, ZM_RES_MEDIUM);
}
static void alpha_hbl(uint32_t id, uint32_t plane, uint32_t line) {
    if (id == ZM_HBL_GLOBAL_ID) {
        vs_w32(ZM_REG_BACKGROUND, vs_rnd());
        return;
    }
    if (plane == 0 && line % 5 == 0) vs_w16(ZM_REG_RES_FLICKER, vs_r16(ZM_REG_RES_FLICKER) + 1);
    vs_w32(ZM_OFF_PAL + plane * ZM_PAL_BYTES + (line & 255) * 4, vs_rnd());
}
static void bgalpha_setup(void) {
    alpha_setup();
    vs_w16(ZM_REG_GLOBAL_HBL_ID, ZM_HBL_GLOBAL_ID);
}

/* --- worst: the most a line can cost the compositor. Four medium planes with
 * 800-byte strides (800 columns 1:1, all 280 lines), blending, over a BEAM
 * list of BEAM_MAX entries on every line --- */
static void worst_setup(void) {
    alpha_setup();
    for (int p = 0; p < ZM_NB_PLANES; p++) vs_plane(p, ZM_FB_MODE_MEDIUM, ZM_RASTER_WIDTH, k_base[p], 0);
    vs_w16(ZM_REG_GLOBAL_HBL_ID, ZM_HBL_GLOBAL_ID);
}
static void worst_hbl(uint32_t id, uint32_t plane, uint32_t line) {
    if (id != ZM_HBL_GLOBAL_ID) {
        alpha_hbl(id, plane, line);
        return;
    }
    for (uint32_t i = 0; i < ZM_BEAM_MAX; i++) vs_w32(ZM_OFF_BEAM_TABLE + i * 4, (i * 6) << 16 | (vs_rnd() & 0xFFFF));
    vs_w16(ZM_REG_BEAM_COUNT, ZM_BEAM_MAX);
}

const vs_scenario vs_scenarios[] = {
    {"fullscreen", 2, 0x7, fs_setup, reset_bases, fs_hbl},
    {"scroll", 2, 0x7, scroll_setup, reset_bases, scroll_hbl},
    {"medium", 2, 0x7, med_setup, reset_bases, med_hbl},
    {"overscan", 3, 0xF, ovs_setup, reset_bases, ovs_hbl},
    {"beam", 2, 0x1, beam_setup, reset_bases, beam_hbl},
    {"layers", 2, 0xF, layer_setup, reset_bases, layer_hbl},
    {"alpha", 2, 0xF, alpha_setup, reset_bases, alpha_hbl},
    {"bgalpha", 2, 0x0, bgalpha_setup, reset_bases, alpha_hbl},
    {"worst", 2, 0xF, worst_setup, reset_bases, worst_hbl},
    {0, 0, 0, 0, 0, 0},
};
