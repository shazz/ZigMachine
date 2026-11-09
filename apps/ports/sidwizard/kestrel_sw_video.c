/* SID-Wizard's picture on plane 0 (included by kestrel_sw.c). The PC version's C64-UI mode at zoom 1
 * (upstream host/video_display.c displayScreen() and video_extra.c drawBigSprites(); not vendored, they are SDL
 * code), drawn as 8-bit palette indices straight into the 400x280 plane instead of 32-bit SDL surfaces:
 *
 *   y   0      black line              x 0..9      left border (black: no zoom/option buttons here)
 *   y   1..21  header sprites (7, x2)  x 10..329   the C64 screen, 40 columns
 *   y  23..230 26 text rows (VIC trick: row 26 from another screen bank)
 *   y 233..253 orderlist sprites       x 330..339  raster bars (the border colour of every raster line),
 *                                                  main-volume bar, disk-progress light
 *
 * Only what changed is stored: a text cell when its character, colour or charset changed (upstream's prevVRAM /
 * prevCRAM), a sprite byte when it or the sprite colour changed, a raster-bar row when its colour changed. The
 * cursor sprite is drawn last; the cells, header or orderlist under where it was and where it is are drawn again
 * first. Upstream's sprite blur is its "lofiborder" setting here (no blend colours: a 16-colour palette). */

#define SW_W 340
#define SW_H 254
#define SW_OX 30                           /* the picture's place in the 400x280 plane (centred) */
#define SW_OY 13
#define SW_STRIDE 400
#define SIDEBORDER_WIDTH 10
#define BORDER 23                          /* SPRITE_HEIGHT + 2: the header and orderlist borders */
#define CHARHEIGHT 8
#define SCREENHEIGHT 26
#define SW_VRAM_SIZE (SCREENWIDTH * SCREENHEIGHT)
#define INSCREEN_RASTER 0x80
#define ORDERLIST_RASTER 0x100
#define FIRSTROW_RASTER 0x30
#define FIRSTCOLUMN_RASTER 0x18
#define SPRITE_HEIGHT 21
#define TOPSPRITE_ADDRESS 0xD940
#define BOTTOMSPRITE_ADDRESS 0x0400
#define CURSORSPRITE_ADDRESS 0xD900
#define SW_BOTTOM_Y (SCREENHEIGHT * CHARHEIGHT + BORDER + 2)
#define PIANOROLL_TOGGLE_BUTTON_CHARWIDTH 2 /* upstream mouse.c: a click in the top border's first 2 columns */

/* palette: 0..15 text (pepto x 0.85 scanline fade x 1.5 brightness), 16..31 sprites/borders (pepto x 1.5) */
enum { SW_SPR = 16, SW_VOLBG = 32, SW_VOLWARN, SW_VOLSCALE, SW_SCOPEBG, SW_SCOPE, SW_DLGFG, SW_DLGBG, SW_NCOL };
static const Uint8 sw_pepto[16][3] = {
    {0x00,0x00,0x00}, {0xFF,0xFF,0xFF}, {0x68,0x37,0x2b}, {0x70,0xa4,0xb2}, {0x6f,0x3d,0x86}, {0x58,0x8d,0x43},
    {0x35,0x28,0x79}, {0xb8,0xc7,0x6f}, {0x6f,0x4f,0x25}, {0x43,0x39,0x00}, {0x9a,0x67,0x59}, {0x44,0x44,0x44},
    {0x6c,0x6c,0x6c}, {0x9a,0xd2,0x84}, {0x6c,0x5e,0xb5}, {0x95,0x95,0x95} };
static const Uint32 sw_extra_rgb[] = { 0x103060, 0xC03020, 0x80E0F0, 0x011008, 0x20FF90, 0x80E0FF, 0x031020 };

/* upstream's globals the mouse and keyboard code read (video.c / video_display.c) */
byte CursorX, CursorY;
static byte PianoRollMode;
unsigned char ScopeData[24 + 1];           /* audio.c fills these (OSCILLOSCOPE_SHOWS_ALL_CHANNELS) */
short ScopeDataCnt, ScopeDataLength = 24;

__attribute__((import_module("env"), import_name("hwVideoBase"))) extern int hwVideoBase(void);
static Uint8 *sw_vbase, *sw_fb;            /* the plane's registers; the picture's (0,0) in its VRAM */
static Uint8 sw_charset[2][0x800];         /* the two charsets, kept at start as upstream's surfaces are */
static Uint8 sw_prev_vram[SW_VRAM_SIZE], sw_prev_cram[SW_VRAM_SIZE], sw_prev_cs = 0xFF, sw_dirty[SW_VRAM_SIZE];
static Uint8 sw_top[7 * 64], sw_bottom[7 * 64], sw_top_col = 0xFF, sw_bottom_col = 0xFF, sw_bars[SW_H];
static int sw_refresh = 1, sw_dialog, sw_vol_sig = -1;
static uint32_t sw_drawn[SW_VRAM_SIZE], sw_frame_no;  /* the frame each text cell was last drawn in */
static int sw_sep_dirty;                    /* the cursor was or is over the separator lines */
static Uint32 sw_nib[16];                  /* 4 glyph bits -> 4 pixels of 0xFF (pixel 0 = bit 3) */
static Uint32 sw_dbl[16][2];               /* 4 sprite bits -> 8 pixels (each bit 2 wide) */
static struct { int x, y, w, h; } sw_cur;  /* where the cursor sprite was drawn */
static word sw_prev_progress;

static void sw_set_colour(int i, unsigned r, unsigned g, unsigned b)
{
    r = r > 255 ? 255 : r; g = g > 255 ? 255 : g; b = b > 255 ? 255 : b;
    *(Uint32 *)(sw_vbase + 0x100 + i * 4) = 0xFF000000u | b << 16 | g << 8 | r;
}

static void sw_video_init(void)
{
    sw_vbase = (Uint8 *)(uintptr_t)hwVideoBase();
    *(Uint32 *)(sw_vbase + 0x04) = 0xFF000000u;             /* background: black */
    sw_vbase[0x54] = 1;                                     /* fullscreen (overscan) plane: 400x280 */
    *(Uint16 *)(sw_vbase + 0x34) = SW_STRIDE;
    *(Uint32 *)(sw_vbase + 0x44) = 0x1100;
    memset(sw_vbase + 0x1100, 0, 400 * 280);
    sw_fb = sw_vbase + 0x1100 + SW_OY * SW_STRIDE + SW_OX;
    for (int c = 0; c < 16; c++) {
        const Uint8 *p = sw_pepto[c];
        sw_set_colour(c, p[0] * 51u / 40u, p[1] * 51u / 40u, p[2] * 51u / 40u);  /* x 0.85 x 1.5 */
        sw_set_colour(SW_SPR + c, p[0] * 3u / 2u, p[1] * 3u / 2u, p[2] * 3u / 2u);
    }
    for (int i = SW_VOLBG; i < SW_NCOL; i++) {
        Uint32 c = sw_extra_rgb[i - SW_VOLBG];
        sw_set_colour(i, c >> 16 & 255, c >> 8 & 255, c & 255);
    }
    for (int n = 0; n < 16; n++) {
        Uint8 px[8];
        for (int k = 0; k < 4; k++) px[2 * k] = px[2 * k + 1] = (n & (8 >> k)) ? 0xFF : 0;
        sw_nib[n] = (n & 8 ? 0xFFu : 0) | (n & 4 ? 0xFF00u : 0) | (n & 2 ? 0xFF0000u : 0) | (n & 1 ? 0xFF000000u : 0);
        memcpy(sw_dbl[n], px, 8);
    }
    memcpy(sw_charset[0], &cRSID_C64.ROMbanks[0x1800], 0x800);
    memcpy(sw_charset[1], &cRSID_C64.RAMbank[0xD000], 0x800);
}

static void sw_video_dialog(int on) { sw_dialog = on; sw_refresh = 1; }

/* One 8x8 cell at (x, y) of the picture (x a multiple of 4): glyph rows in colour fg on black. */
static void sw_glyph(int x, int y, const Uint8 *glyph, Uint8 fg, Uint8 bg)
{
    Uint32 f4 = fg * 0x01010101u, b4 = bg * 0x01010101u;
    Uint8 *p = sw_fb + y * SW_STRIDE + x;
    for (int j = 0; j < 8; j++, p += SW_STRIDE) {
        Uint8 b = glyph[j];
        ((Uint32 *)p)[0] = (sw_nib[b >> 4] & f4) | (~sw_nib[b >> 4] & b4);
        ((Uint32 *)p)[1] = (sw_nib[b & 15] & f4) | (~sw_nib[b & 15] & b4);
    }
}

static void sw_hline(int y, int x0, int x1, Uint8 c) { memset(sw_fb + y * SW_STRIDE + x0, c, (size_t)(x1 - x0)); }

#include "kestrel_sw_draw.c"
