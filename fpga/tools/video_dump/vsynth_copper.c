/* vsynth's copper scenario (HW 1.9.0, machine/copper.zig, fpga/review/COPPER_LIST.md): three
 * planes with copper lists, built once in VRAM's fourth slot (no enabled plane reads it), that
 * reach every op and every stop:
 *   plane 0 overscan: its handler flickers on lines y % 3 == 0, its list FLICKs on y % 4 == 0 (the
 *            two together, alone, and neither), PAL blocks of 1..3 entries on even lines, a PALREF
 *            of 7 entries every 5th line;
 *   plane 1 normal, no handler: PAL blocks of up to 40 entries, NOPs, then END at line 150;
 *   plane 2 scroll, no handler: REG HSCROLL on every covered line and a PAL, then at line 200 a
 *            reserved op: the list stops there (and its later records are never read). */
#include "vsynth.h"
#include "zm_memmap.h"

#define SLOT3 (ZM_OFF_VRAM + 3u * 0x40000u)
#define LIST(p) (SLOT3 + 0x1000u + (uint32_t)(p) * 0x8000u)
#define TABLE (SLOT3 + 0x20000u) /* PALREF's tables: 280 rows of 8 words */
#define REG2(r, p) ((r) + (uint32_t)(p) * 2)

static uint32_t g_at;
static void put(uint32_t w) {
    vs_w32(g_at, w);
    g_at += 4;
}
static uint32_t head(uint32_t y, uint32_t n) { return 0xF0000000u | y << 19 | n; }
static uint32_t pal_op(uint32_t first, uint32_t k) { return 0x10000000u | first << 20 | k << 12; }

/* A record for line y with n body words: put its HEAD now, its body after. */
static void begin_list(int p) {
    g_at = LIST(p);
    vs_w16(REG2(ZM_REG_FB_COPPER, p), (LIST(p) - ZM_OFF_VRAM) / 16u);
}

static void list0(void) {
    begin_list(0);
    for (uint32_t y = 0; y < ZM_RASTER_HEIGHT; y++) {
        uint32_t k = 1 + y % 3, n = (y % 4 == 0) + (y % 2 == 0 ? 1 + k : 0) + (y % 5 == 0 ? 2 : 0);
        if (n == 0) continue;
        put(head(y, n));
        if (y % 4 == 0) put(0x30000000u);
        if (y % 2 == 0) {
            put(pal_op((y * 7) & 0xFF, k));
            for (uint32_t i = 0; i < k; i++) put(0xFF000000u | vs_rnd());
        }
        if (y % 5 == 0) {
            put(0x40000000u | ((y * 3) & 0xF0) << 20 | 7u << 12);
            put(TABLE + y * 32 + (y & 1) * 4); /* odd rows start mid-beat */
        }
    }
    put(head(511, 0));
    for (uint32_t i = 0; i < ZM_RASTER_HEIGHT * 8; i++) vs_w32(TABLE + i * 4, 0xFF000000u | vs_rnd());
}

static void list1(void) {
    begin_list(1);
    for (uint32_t y = ZM_RASTER_BORDER_Y; y < 150; y++) {
        uint32_t k = 1 + vs_rnd() % 40, first = vs_rnd() % (257 - k), nops = y % 3;
        put(head(y, 1 + k + nops));
        for (uint32_t i = 0; i < nops; i++) put(0);
        put(pal_op(first, k));
        for (uint32_t i = 0; i < k; i++) put(0x80000000u | vs_rnd());
    }
    put(head(511, 0));
}

static void list2(void) {
    begin_list(2);
    for (uint32_t y = ZM_RASTER_BORDER_Y; y < ZM_RASTER_BORDER_Y + ZM_HEIGHT; y++) {
        if (y == 200) {
            put(head(y, 1));
            put(0x50000000u); /* reserved: the list stops */
            continue;
        }
        put(head(y, 3));
        put(0x20000000u | REG2(ZM_REG_HSCROLL, 2) << 20 | (vs_rnd() % 380));
        put(pal_op(vs_rnd() & 0xFF, 1));
        put(0xFF000000u | vs_rnd());
    }
    put(head(511, 0));
}

void vs_copper_setup(void) {
    vs_fill(ZM_OFF_VRAM, ZM_VRAM_BYTES);
    for (int p = 0; p < ZM_NB_PLANES; p++) vs_palette(p);
    vs_plane(0, ZM_FB_MODE_OVERSCAN, 400, ZM_OFF_VRAM + 3, ZM_OVERSCAN_MAGIC_X);
    vs_plane(1, ZM_FB_MODE_NORMAL, 320, ZM_OFF_VRAM + 0x40000u + 1, 0);
    vs_plane(2, ZM_FB_MODE_SCROLL, 700, ZM_OFF_VRAM + 0x80000u + 5, 0);
    vs_w16(REG2(ZM_REG_FB_HBL_ID, 1), 0);
    vs_w16(REG2(ZM_REG_FB_HBL_ID, 2), 0);
    list0();
    list1();
    list2();
}

void vs_copper_frame(int f) { (void)f; }

void vs_copper_hbl(uint32_t id, uint32_t plane, uint32_t line) {
    (void)id;
    if (plane == 0 && line % 3 == 0) vs_w16(ZM_REG_RES_FLICKER, vs_r16(ZM_REG_RES_FLICKER) + 1);
}
