/* The text screen (kcio, kestrel_cio.c) drawn into plane 0 in the desk mode (HW 1.17.0, docs/HW_API.md
 * "Desk mode"): 640x480 palette indices at 1:1, the 80x25 cells of 8x16 in rows 0..399, the status line in
 * the 80 rows under them. Only what changed is stored: each frame compares every cell with the one drawn
 * (a 16-byte compare), and a changed cell is 16 rows of two word stores. A colour gets a palette entry the
 * first time it is drawn (the board's palette mirror sees stores only, so each entry is stored once).
 * Where the machine has no desk mode (an older board bitstream: hwDeskAvailable 0) the plane is medium
 * res (640x200): the first line says so and the screen's first 11 rows show under it. */
#include <string.h>
#include "kestrel_desk.h"

__attribute__((import_module("env"), import_name("hwVideoBase"))) extern int hwVideoBase(void);
__attribute__((import_module("env"), import_name("hwDeskAvailable"))) extern unsigned hwDeskAvailable(void);

#define REG_RESOLUTION 0x00
#define REG_BACKGROUND 0x04
#define REG_FB_STRIDE 0x34
#define REG_FB_BASE 0x44
#define REG_FB_MODE 0x54
#define OFF_PAL 0x0100
#define OFF_VRAM 0x1100                /* 64-aligned: the board fetches the desk in 8-byte beats */
#define RES_MEDIUM 2
#define RES_DESK 3
#define FB_MODE_MEDIUM 3
#define W 640

static uint8_t *vbase, *fb;
static int desk, top, nrows;           /* desk mode?; first pixel row of the cells; cell rows shown */
static struct vmem_cell drawn[KCIO_COLS * KCIO_ROWS];
static uint8_t drawn_ok[KCIO_COLS * KCIO_ROWS];   /* drawn[] holds what is on screen (0: redraw) */
static unsigned drawn_gen = ~0u;
static int cur_x = -1, cur_y = -1, cur_on;        /* the cursor as drawn */
static unsigned frames;
static char status[KCIO_COLS + 1], status_drawn[KCIO_COLS + 1] = "\1";

/* --- colours: 0x00RRGGBB -> a palette entry, 0 is black (the margins) --- */
static uint32_t pal[256] = { 0 };
static unsigned npal = 1;
static uint8_t pal_entry(uint32_t rgb)
{
    for (unsigned i = 0; i < npal; i++) if (pal[i] == rgb) return (uint8_t)i;
    if (npal == 256) {                              /* full: the nearest (a text screen rarely gets here) */
        unsigned best = 0, bd = ~0u;
        for (unsigned i = 0; i < 256; i++) {
            int dr = (int)(pal[i] >> 16 & 255) - (int)(rgb >> 16 & 255), dg = (int)(pal[i] >> 8 & 255) - (int)(rgb >> 8 & 255),
                db = (int)(pal[i] & 255) - (int)(rgb & 255);
            unsigned d = (unsigned)(dr * dr + dg * dg + db * db);
            if (d < bd) { bd = d; best = i; }
        }
        return (uint8_t)best;
    }
    pal[npal] = rgb;
    *(volatile uint32_t *)(vbase + OFF_PAL + npal * 4) = 0xFF000000u | (rgb & 255) << 16 | (rgb & 0xFF00) | (rgb >> 16 & 255);
    return (uint8_t)npal++;
}
static uint8_t colour(uint32_t c)
{
    uint32_t rgb = (c & 0x80000000u) ? (c & 0xffffffu) : kcio.rgb[(c & 0xffffffu) % TOTAL_DAC_SIZE];
    return pal_entry(rgb);
}

/* --- one 8x16 glyph: rows of 8 indices as two little-endian words --- */
static const uint32_t nib[16] = {
    0x00000000, 0xff000000, 0x00ff0000, 0xffff0000, 0x0000ff00, 0xff00ff00, 0x00ffff00, 0xffffff00,
    0x000000ff, 0xff0000ff, 0x00ff00ff, 0xffff00ff, 0x0000ffff, 0xff00ffff, 0x00ffffff, 0xffffffff };
static void glyph(int x, int py, const uint8_t *bits, int tall, uint8_t fg, uint8_t bg, int c0, int c1)
{
    uint32_t fw = fg * 0x01010101u, bw = bg * 0x01010101u;
    uint32_t *d = (uint32_t *)(fb + (size_t)py * W + (size_t)x * 8);
    for (int r = 0; r < 16; r++, d += W / 4) {
        uint8_t b = bits ? bits[tall ? r : r / 2] : 0;
        if (r >= c0 && r <= c1) b = 0xff;           /* the cursor's scan lines */
        uint32_t m0 = nib[b >> 4], m1 = nib[b & 15];
        d[0] = (fw & m0) | (bw & ~m0);
        d[1] = (fw & m1) | (bw & ~m1);
    }
}
static const uint8_t *bits_of(int font, uint8_t ch, int *tall)
{
    const struct conio_font_data_struct *f = &conio_fontdata[font];
    if (f->eight_by_sixteen) { *tall = 1; return (const uint8_t *)f->eight_by_sixteen + ch * 16; }
    if (f->eight_by_eight) { *tall = 0; return (const uint8_t *)f->eight_by_eight + ch * 8; }
    *tall = 1;
    return (const uint8_t *)conio_fontdata[0].eight_by_sixteen + ch * 16;
}

static int blink_off(void) { return (frames >> 4) & 1; }
static int blinks(const struct vmem_cell *c)
{
    return (c->legacy_attr & 0x80) && !(kcio.vflags & (CIOLIB_VIDEO_BGBRIGHT | CIOLIB_VIDEO_NOBLINK | CIOLIB_VIDEO_BLINKALTCHARS));
}
static void draw_cell(int x, int y, int cursor)
{
    const struct vmem_cell *c = &kcio.cell[y * KCIO_COLS + x];
    int tall;
    const uint8_t *bits = bits_of(c->font, c->ch, &tall);
    if (blinks(c) && blink_off()) bits = 0;
    glyph(x, top + y * 16, bits, tall, colour(c->fg), colour(c->bg), cursor ? kcio.cstart : 99, cursor ? kcio.cend : -1);
}

static void draw_status(void)
{
    uint8_t fg = pal_entry(0xC0C0C0), bg = pal_entry(0x0000A8);
    int py = desk ? 432 : 0, tall;
    for (int x = 0; x < KCIO_COLS; x++) {
        uint8_t ch = (uint8_t)(status[x] ? status[x] : ' ');
        glyph(x, py, bits_of(0, ch, &tall), tall, fg, bg, 99, -1);
        if (!status[x]) for (; x < KCIO_COLS; x++) glyph(x, py, bits_of(0, ' ', &tall), tall, fg, bg, 99, -1);
    }
    memcpy(status_drawn, status, sizeof status);
}

void kestrel_desk_status(const char *s) { strncpy(status, s, KCIO_COLS); status[KCIO_COLS] = 0; }
int kestrel_desk_on(void) { return desk; }

void kestrel_desk_boot(void)
{
    vbase = (uint8_t *)(uintptr_t)hwVideoBase();
    fb = vbase + OFF_VRAM;
    *(volatile uint32_t *)(vbase + REG_BACKGROUND) = 0xFF000000u;
    *(volatile uint32_t *)(vbase + REG_FB_BASE) = OFF_VRAM;
    *(volatile uint32_t *)(vbase + OFF_PAL) = 0xFF000000u;
    desk = hwDeskAvailable() != 0;
    *(volatile uint16_t *)(vbase + REG_FB_STRIDE) = W;
    memset(fb, 0, (size_t)W * (desk ? 480 : 200));
    if (desk) { top = 0; nrows = KCIO_ROWS; vbase[REG_RESOLUTION] = RES_DESK; }
    else { top = 16; nrows = 11; vbase[REG_FB_MODE] = FB_MODE_MEDIUM; vbase[REG_RESOLUTION] = RES_MEDIUM; }
    if (!desk) kestrel_desk_status("No desk mode on this machine (HW 1.17.0): rows 1-11 of 25 shown");
}

/* Only the rows written since the last frame (kcio.dirty), and the rows holding blinking cells when the
 * blink flips, are compared cell by cell with what was drawn; an idle screen costs nothing. */
static uint32_t blink_rows;
/* Field by field: a cell's padding bytes are whatever cterm's stack held, so a word compare redraws them all. */
static int same(const struct vmem_cell *a, const struct vmem_cell *b)
{
    return a->ch == b->ch && a->legacy_attr == b->legacy_attr && a->font == b->font && a->fg == b->fg && a->bg == b->bg;
}
static void draw_row(int y, int all, int flip)
{
    uint32_t bit = 1u << y;
    blink_rows &= ~bit;
    for (int x = 0; x < kcio.cols; x++) {
        int i = y * KCIO_COLS + x;
        const struct vmem_cell *c = &kcio.cell[i];
        int b = blinks(c);
        if (b) blink_rows |= bit;
        if (!all && drawn_ok[i] && !(flip && b) && same(c, &drawn[i])) continue;
        drawn[i] = *c;
        drawn_ok[i] = 1;
        draw_cell(x, y, 0);
        if (x == cur_x && y == cur_y) cur_x = -1;    /* the cursor was drawn over: draw it again below */
    }
}

void kestrel_desk_frame(void)
{
    if (!vbase) return;
    frames++;
    int all = drawn_gen != kcio.gen, flip = (frames & 15) == 0;
    drawn_gen = kcio.gen;
    int rows = kcio.rows < nrows ? kcio.rows : nrows;
    uint32_t todo = all ? ~0u : kcio.dirty | (flip ? blink_rows : 0);
    kcio.dirty = 0;
    for (int y = 0; y < rows; y++) if (todo & (1u << y)) draw_row(y, all, flip);
    int on = kcio.cstart <= kcio.cend && !blink_off() && kcio.cx >= 0 && kcio.cx < kcio.cols && kcio.cy >= 0 && kcio.cy < rows;
    if (cur_x != kcio.cx || cur_y != kcio.cy || cur_on != on) {
        if (cur_x >= 0 && cur_y >= 0 && cur_y < rows && cur_x < kcio.cols) draw_cell(cur_x, cur_y, 0);
        if (on) draw_cell(kcio.cx, kcio.cy, 1);
        cur_x = kcio.cx; cur_y = kcio.cy; cur_on = on;
    }
    if (strcmp(status, status_drawn)) draw_status();
}
