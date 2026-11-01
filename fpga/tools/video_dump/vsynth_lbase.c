/* vsynth's line-list scenario (HW 1.10.0, fpga/review/COPPER_LINEBASE.md): copper LBASE on a plane
 * of every mode, and HSCROLL on an overscan plane, rebuilt every frame (so frame 2 also proves that a
 * frame starts from FB_BASE again, not from frame 1's last LBASE):
 *   plane 0 overscan: FLICK every line (borders open, no handler), an LBASE every third line at an
 *            odd offset, REG HSCROLL every other line (0..499: past the row's end), colour 0, and at
 *            line 260 an LBASE outside VRAM: the list stops (the rest of that record unapplied);
 *   plane 1 normal: a flip, an LBASE every even visible line, odd ones run on by the stride, and a
 *            REG HSCROLL the normal mode ignores;
 *   plane 2 fullscreen, stride 333, HSCROLL 137 latched: LBASEs wrap their columns within the row;
 *   plane 3 medium, stride 640: an LBASE every fifth visible line. */
#include "vsynth.h"
#include "zm_memmap.h"

#define LISTS (ZM_OFF_VRAM + 0xF0000u) /* 4 lists of 16 KB: no plane's source reaches them */
#define LIST(p) (LISTS + (uint32_t)(p) * 0x4000u)
#define SRC_TOP (ZM_OFF_VRAM + 0xA0000u) /* LBASE sources below: line + rows + HSCROLL stay in VRAM */
#define REG2(r, p) ((r) + (uint32_t)(p) * 2)

static uint32_t g_at, g_words[8], g_n;
static void put(uint32_t w) {
    vs_w32(g_at, w);
    g_at += 4;
}
static void op(uint32_t w) { g_words[g_n++] = w; }
static void record(uint32_t y) { /* the words op() gathered, as line y's record */
    if (!g_n) return;
    put(0xF0000000u | y << 19 | g_n);
    for (uint32_t i = 0; i < g_n; i++) put(g_words[i]);
    g_n = 0;
}
static void begin(int p) {
    g_at = LIST(p), g_n = 0;
    vs_w16(REG2(ZM_REG_FB_COPPER, p), (LIST(p) - ZM_OFF_VRAM) / 16u);
}
static void end(void) { put(0xF0000000u | 511u << 19); }
static uint32_t src(void) { return ZM_OFF_VRAM + vs_rnd() % (SRC_TOP - ZM_OFF_VRAM); }
static uint32_t lbase(uint32_t v) { return 0x50000000u | v; }

static void list0(void) {
    begin(0);
    for (uint32_t y = 0; y < ZM_RASTER_HEIGHT; y++) {
        op(0x30000000u);
        if (y == 260) op(lbase(ZM_OFF_VRAM + ZM_VRAM_BYTES)); /* outside VRAM: stops here */
        else if (y % 3 == 1) op(lbase(src() | 1));
        if (y % 2 == 0) op(0x20000000u | REG2(ZM_REG_HSCROLL, 0) << 20 | (vs_rnd() % 500));
        if (y % 5 == 0) op(0x10001000u), op(0xFF000000u | vs_rnd());
        record(y);
    }
    end();
}

static void list1(int f) {
    begin(1);
    for (uint32_t ly = 0; ly < ZM_HEIGHT; ly += 2) {
        op(lbase(ZM_OFF_VRAM + 0x40000u + (ZM_HEIGHT - 1 - ly) * 320u + (uint32_t)f));
        op(0x20000000u | REG2(ZM_REG_HSCROLL, 1) << 20 | 77);
        record(ZM_RASTER_BORDER_Y + ly);
    }
    end();
}

static void list2(void) {
    begin(2);
    for (uint32_t y = 2; y < ZM_RASTER_HEIGHT; y += 7) op(lbase(src())), record(y);
    end();
}

static void list3(void) {
    begin(3);
    for (uint32_t y = ZM_RASTER_BORDER_Y; y < ZM_RASTER_BORDER_Y + ZM_HEIGHT; y += 5) op(lbase(src() + 2)), record(y);
    end();
}

void vs_lbase_setup(void) {
    vs_fill(ZM_OFF_VRAM, ZM_VRAM_BYTES);
    for (int p = 0; p < ZM_NB_PLANES; p++) vs_palette(p);
    vs_plane(0, ZM_FB_MODE_OVERSCAN, 400, ZM_OFF_VRAM + 3, ZM_OVERSCAN_MAGIC_X);
    vs_plane(1, ZM_FB_MODE_NORMAL, 320, ZM_OFF_VRAM + 0x40000u + 1, 0);
    vs_plane(2, ZM_FB_MODE_FULLSCREEN, 333, ZM_OFF_VRAM + 0x60000u, 0);
    vs_plane(3, ZM_FB_MODE_MEDIUM, 640, ZM_OFF_VRAM + 0x80000u, 0);
    vs_w16(REG2(ZM_REG_HSCROLL, 2), 137);
    vs_w8(ZM_REG_RESOLUTION, ZM_RES_MEDIUM);
    for (int p = 0; p < ZM_NB_PLANES; p++) vs_w16(REG2(ZM_REG_FB_HBL_ID, p), 0);
}

void vs_lbase_frame(int f) {
    list0();
    list1(f);
    list2();
    list3();
}

void vs_lbase_hbl(uint32_t id, uint32_t plane, uint32_t line) { (void)id, (void)plane, (void)line; }
