/* ciolib's backend on the cart: a text screen of ciolib cells (kcio), drawn into the desk plane by
 * kestrel_desk.c. ciolib.c enters it where its libretro backend is (patches/ciolib.c.sed).
 *
 * Why not ciolib's SDL output: sdl_con.c (and retro.c) sit on bitmap_con.c, which renders every cell to a
 * 32-bit pixel buffer, two 640x400 screens of 1 MB plus a 1 MB copy per update: more than the cart window.
 * A cell model is what a text terminal needs here, and drawing a changed cell is 16 rows of 8 indices. The
 * shape follows curs_cio.c (cells, a mode palette, the cursor) and bitmap_con.c (attr2palette, map_rgb). */
#include <string.h>
#include "ciolib.h"
#include "vidmodes.h"
#include "kestrel_cio.h"
#include "kestrel_desk.h"
#include "kestrel_keys.h"
#include "kestrel_fiber.h"

bool retro_set = true;
struct kcio_screen kcio;
static int fonts[5];

static int k_attr2palette(uint8_t attr, uint32_t *fgp, uint32_t *bgp)
{
    uint32_t fg = attr & 0x0f, bg = (attr >> 4) & 0x0f;
    if (!(kcio.vflags & CIOLIB_VIDEO_BGBRIGHT)) bg &= 0x07;
    if (kcio.vflags & CIOLIB_VIDEO_NOBRIGHT) fg &= 0x07;
    if (fgp) *fgp = kcio.pal16[fg];
    if (bgp) *bgp = kcio.pal16[bg];
    return 1;
}

static void k_textmode(int mode)
{
    int vm = find_vmode(mode);
    if (vm < 0) vm = find_vmode(C80);
    struct video_params *v = &vparams[vm];
    kcio.cols = v->cols < KCIO_COLS ? v->cols : KCIO_COLS;
    kcio.rows = v->rows < KCIO_ROWS ? v->rows : KCIO_ROWS;
    memcpy(kcio.pal16, palettes[v->palette], sizeof kcio.pal16);
    kcio.cstart = v->curs_start * 16 / v->charheight;
    kcio.cend = v->curs_end * 16 / v->charheight;
    cio_textinfo.currmode = (unsigned char)v->mode;
    cio_textinfo.screenwidth = (unsigned char)kcio.cols;
    cio_textinfo.screenheight = (unsigned char)kcio.rows;
    cio_textinfo.winleft = cio_textinfo.wintop = 1;
    cio_textinfo.winright = (unsigned char)kcio.cols;
    cio_textinfo.winbottom = (unsigned char)kcio.rows;
    cio_textinfo.normattr = cio_textinfo.attribute = (unsigned char)v->default_attr;
    cio_textinfo.curx = cio_textinfo.cury = 1;
    kcio.cx = kcio.cy = 0;
    struct vmem_cell blank = { .legacy_attr = (uint8_t)v->default_attr, .ch = ' ', .font = (uint8_t)fonts[0] };
    k_attr2palette(blank.legacy_attr, &blank.fg, &blank.bg);
    for (int i = 0; i < KCIO_COLS * KCIO_ROWS; i++) kcio.cell[i] = blank;
    kcio.gen++;
}

static int in_screen(int sx, int sy, int ex, int ey, const void *p)
{
    return p && sx >= 1 && sy >= 1 && sx <= ex && sy <= ey && ex <= kcio.cols && ey <= kcio.rows;
}

static void touched(int sy, int ey) { for (int y = sy - 1; y < ey; y++) kcio.dirty |= 1u << y; }

static int k_vmem_puttext(int sx, int sy, int ex, int ey, struct vmem_cell *fill)
{
    if (!in_screen(sx, sy, ex, ey, fill)) return 0;
    touched(sy, ey);
    for (int y = sy - 1; y < ey; y++)
        for (int x = sx - 1; x < ex; x++) kcio.cell[y * KCIO_COLS + x] = *fill++;
    return 1;
}

static int k_vmem_gettext(int sx, int sy, int ex, int ey, struct vmem_cell *fill)
{
    if (!in_screen(sx, sy, ex, ey, fill)) return 0;
    for (int y = sy - 1; y < ey; y++)
        for (int x = sx - 1; x < ex; x++) *fill++ = kcio.cell[y * KCIO_COLS + x];
    return 1;
}

/* puttext's cells are (attr << 8 | ch): colours from the attribute, the current font. */
static int k_puttext(int sx, int sy, int ex, int ey, void *buf)
{
    uint16_t *b = buf;
    if (!in_screen(sx, sy, ex, ey, buf)) return 0;
    touched(sy, ey);
    for (int y = sy - 1; y < ey; y++)
        for (int x = sx - 1; x < ex; x++) {
            struct vmem_cell *c = &kcio.cell[y * KCIO_COLS + x];
            memset(c, 0, sizeof *c);
            c->ch = (uint8_t)(*b & 0xff);
            c->legacy_attr = (uint8_t)(*b++ >> 8);
            c->font = (uint8_t)fonts[0];
            k_attr2palette(c->legacy_attr, &c->fg, &c->bg);
        }
    return 1;
}

static void k_gotoxy(int x, int y)
{
    cio_textinfo.curx = (unsigned char)x;
    cio_textinfo.cury = (unsigned char)y;
    kcio.cx = x + cio_textinfo.winleft - 2;
    kcio.cy = y + cio_textinfo.wintop - 2;
}

static void k_setcursortype(int type)
{
    int vm = find_vmode(cio_textinfo.currmode);
    struct video_params *v = &vparams[vm < 0 ? find_vmode(C80) : vm];
    switch (type) {
    case _NOCURSOR: kcio.cstart = 0xff; kcio.cend = 0; break;
    case _SOLIDCURSOR: kcio.cstart = 0; kcio.cend = 15; break;
    default: kcio.cstart = v->curs_start * 16 / v->charheight; kcio.cend = v->curs_end * 16 / v->charheight;
    }
}

/* getch blocks (uifc's menus wait in it): the fiber sleeps until a key comes. */
static int key_ready(void *a) { (void)a; return kestrel_keys_waiting(); }
static int k_kbhit(void) { return kestrel_keys_waiting(); }
static int k_getch(void)
{
    if (!kfib_self() && !kestrel_keys_waiting()) return 0;   /* outside a fiber getch cannot wait */
    while (!kestrel_keys_waiting()) kfib_block(key_ready, 0, 0);
    return kestrel_keys_get();
}
static void k_beep(void) {}

static int k_setfont(int font, int force, int font_num)
{
    (void)force;
    if (font < 0 || font > 255 || font_num < 0 || font_num > 4 || !conio_fontdata[font].desc) return -1;
    fonts[font_num] = font;
    return 0;
}
static int k_getfont(int font_num) { return font_num >= 0 && font_num <= 4 ? fonts[font_num] : -1; }

static int k_setpalette(uint32_t e, uint16_t r, uint16_t g, uint16_t b)
{
    if (e >= TOTAL_DAC_SIZE) return 0;
    uint32_t v = (uint32_t)(r >> 8) << 16 | (uint32_t)(g >> 8) << 8 | (uint32_t)(b >> 8);
    if (kcio.rgb[e] != v) { kcio.rgb[e] = v; kcio.gen++; }   /* a redraw only for a real change */
    return 1;
}
static int k_getpalette(uint32_t e, uint8_t *r, uint8_t *g, uint8_t *b)
{
    if (e >= TOTAL_DAC_SIZE) return 0;
    *r = (uint8_t)(kcio.rgb[e] >> 16); *g = (uint8_t)(kcio.rgb[e] >> 8); *b = (uint8_t)kcio.rgb[e];
    return 1;
}
static int k_get_modepalette(uint32_t p[16]) { memcpy(p, kcio.pal16, sizeof kcio.pal16); return 1; }
/* No redraw: a cell holds its colours as palette entries already (attr2palette ran when it was written). */
static int k_set_modepalette(uint32_t p[16]) { memcpy(kcio.pal16, p, sizeof kcio.pal16); return 1; }
static uint32_t k_map_rgb(uint16_t r, uint16_t g, uint16_t b) { return 0xff000000u | ((uint32_t)(r & 0xff00) << 8) | (g & 0xff00) | (b >> 8); }
static int k_getvideoflags(void) { return kcio.vflags; }
static void k_setvideoflags(int f) { if (kcio.vflags != f) { kcio.vflags = f; kcio.gen++; } }
static int k_window_info(int *w, int *h, int *x, int *y)
{
    if (w) *w = 640; if (h) *h = 400; if (x) *x = 0; if (y) *y = 0;
    return 1;
}

int kestrel_cio_init(int mode)
{
    (void)mode;
    for (int i = 0; i < TOTAL_DAC_SIZE; i++)
        kcio.rgb[i] = (uint32_t)dac_default[i].red << 16 | (uint32_t)dac_default[i].green << 8 | dac_default[i].blue;
    cio_api.mode = CIOLIB_MODE_RETRO;
    cio_api.mouse = 0;
    cio_api.options = CONIO_OPT_FONT_SELECT | CONIO_OPT_PALETTE_SETTING | CONIO_OPT_EXTENDED_PALETTE | CONIO_OPT_BRIGHT_BACKGROUND;
    cio_api.puttext = k_puttext;
    cio_api.vmem_puttext = k_vmem_puttext;
    cio_api.vmem_gettext = k_vmem_gettext;
    cio_api.gotoxy = k_gotoxy;
    cio_api.setcursortype = k_setcursortype;
    cio_api.kbhit = k_kbhit;
    cio_api.getch = k_getch;
    cio_api.beep = k_beep;
    cio_api.textmode = k_textmode;
    cio_api.setfont = k_setfont;
    cio_api.getfont = k_getfont;
    cio_api.setpalette = k_setpalette;
    cio_api.getpalette = k_getpalette;
    cio_api.attr2palette = k_attr2palette;
    cio_api.get_modepalette = k_get_modepalette;
    cio_api.set_modepalette = k_set_modepalette;
    cio_api.map_rgb = k_map_rgb;
    cio_api.getvideoflags = k_getvideoflags;
    cio_api.setvideoflags = k_setvideoflags;
    cio_api.get_window_info = k_window_info;
    k_textmode(ciolib_initial_mode);
    return 1;
}
