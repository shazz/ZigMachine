/* Present the window's W x H picture of palette indices (kestrel_window8.c; the colours: kestrel_palette.c) on
 * plane 0. Up to 320x200 uses the normal plane; anything up to 400x280 the fullscreen (overscan) plane, centred.
 * Only what changed reaches the plane: the last picture shown is kept (`shown`), each present compares the new one
 * a word (four pixels) at a time and stores only the words that differ, and only palette entries added since the
 * last present are written (all of them after a compaction renumbered the indices, when the whole picture is
 * rewritten too). So a repaint that changed nothing stores nothing, and a scrolling pattern view stores its rows.
 * The current SDL cursor (kestrel_render.c) is drawn on top at the mouse position (a port that draws its own
 * pointer, kestrel_input.c drawsOwnPointer, gets none from the host), and put back from `shown` when it moves.
 *
 *   kestrel_plane_init()                once from boot(): plane registers, black background
 *   kestrel_plane_origin(w, h, &x, &y)  where a w x h picture's (0,0) lands in the plane (for kestrel_input_origin)
 *   kestrel_plane_colours()             palette entries in use
 *   kestrel_plane_changed()             1 when the last present's picture differed from the one before
 *   kestrel_plane_cursor()              once a frame with no present: move the pointer over the last picture */
#include "kestrel_render_priv.h"

void kestrel_log(const char *m);
const Uint32 *kestrel_cursor_image(int *w, int *h, int *hx, int *hy);
void kestrel_ptrbox_plane(int full, int px, int py, int w, int h);
__attribute__((import_module("env"), import_name("hwVideoBase"))) extern int hwVideoBase(void);

#define REG_BACKGROUND 0x04
#define REG_FB_STRIDE 0x34
#define REG_FB_BASE 0x44
#define REG_FB_MODE 0x54
#define OFF_PAL 0x0100
#define OFF_VRAM 0x1100
#define FB_MODE_NORMAL 0
#define FB_MODE_FULLSCREEN 1

static Uint8 *vbase;
static int pw = 320, ph = 200, ox, oy;
static Uint8 *shown;                       /* the last picture presented (cursor aside), pw x ph of it used */
static int sw, sh, full = 1;               /* shown's size; full: rewrite every word at the next present */
static unsigned pal_written;               /* palette entries already in the plane's registers */
static int changed;

static void plane_regs(void)
{
    Uint8 mode = pw > 320 ? FB_MODE_FULLSCREEN : FB_MODE_NORMAL;
    if (vbase[REG_FB_MODE] != mode) vbase[REG_FB_MODE] = mode;
    if (*(Uint16 *)(vbase + REG_FB_STRIDE) != pw) *(Uint16 *)(vbase + REG_FB_STRIDE) = (Uint16)pw;
    if (*(Uint32 *)(vbase + REG_FB_BASE) != OFF_VRAM) *(Uint32 *)(vbase + REG_FB_BASE) = OFF_VRAM;
}

void kestrel_plane_init(void)
{
    vbase = (Uint8 *)(uintptr_t)hwVideoBase();
    *(Uint32 *)(vbase + REG_BACKGROUND) = 0xFF000000u;
}

static void plane_size(int w, int h)
{
    int big = w > 320 || h > 200;
    int npw = big ? 400 : 320, nph = big ? 280 : 200;
    if (npw == pw && nph == ph && vbase[REG_FB_MODE] == (big ? FB_MODE_FULLSCREEN : FB_MODE_NORMAL)) return;
    pw = npw; ph = nph;
    memset(vbase + OFF_VRAM, 0, (size_t)pw * (size_t)ph);
    full = 1;
}

void kestrel_plane_origin(int w, int h, int *x, int *y)
{
    int big = w > 320 || h > 200;
    *x = ((big ? 400 : 320) - w) / 2;
    *y = ((big ? 280 : 200) - h) / 2;
}

unsigned kestrel_plane_colours(void) { return kestrel_pal_n; }
int kestrel_plane_changed(void) { return changed; }

/* The cursor: the rectangle it was last drawn in (picture coordinates, clipped) and its pixels as palette
 * indices, resolved BEFORE anything is stored (a new colour may compact the palette, which renumbers `shown`). */
#define CMAX 4096
static int cur_x, cur_y, cur_w, cur_h, cur_mx = -100000, cur_my;
static const Uint32 *cur_img;
static Uint8 cidx[CMAX], cvis[CMAX];
static int nx, ny, nw, nh, nx0, ny0, ncw;  /* the new rectangle, the image's top-left and width */

static void cursor_resolve(int w, int h)
{
    int cw, chh, hx, hy;
    const Uint32 *cp = kestrel_cursor_image(&cw, &chh, &hx, &hy);
    SDL_GetMouseState(&cur_mx, &cur_my);
    cur_img = cp; nw = nh = 0;
    if (!cp || cw * chh > CMAX) return;
    nx0 = cur_mx - hx; ny0 = cur_my - hy; ncw = cw;
    nx = nx0 < 0 ? 0 : nx0; ny = ny0 < 0 ? 0 : ny0;
    nw = (nx0 + cw > w ? w : nx0 + cw) - nx; nh = (ny0 + chh > h ? h : ny0 + chh) - ny;
    if (nw <= 0 || nh <= 0) { nw = nh = 0; return; }
    for (int i = 0; i < cw * chh; i++)
        if ((cvis[i] = (cp[i] >> 24) >= 128)) cidx[i] = kestrel_colour_index(cp[i]);
}

/* Put `shown` back under the old cursor, draw the new one (resolved), remember where. */
static void cursor_move(int w)
{
    for (int py = cur_y; py < cur_y + cur_h; py++)
        memcpy(vbase + OFF_VRAM + (oy + py) * pw + ox + cur_x, shown + py * w + cur_x, (size_t)cur_w);
    for (int py = ny; py < ny + nh; py++)
        for (int px = nx; px < nx + nw; px++) {
            int i = (py - ny0) * ncw + px - nx0;
            if (cvis[i]) vbase[OFF_VRAM + (oy + py) * pw + ox + px] = cidx[i];
        }
    cur_x = nx; cur_y = ny; cur_w = nw; cur_h = nh;
}

/* Palette entries added since the last write (all of them after a compaction). */
static void write_palette(void)
{
    if (kestrel_palette_compacted) pal_written = 0;
    for (unsigned i = pal_written; i < kestrel_pal_n; i++) {
        Uint32 c = kestrel_pal_rgb[i];
        *(Uint32 *)(vbase + OFF_PAL + i * 4) = 0xFF000000u | (c & 255) << 16 | (c & 0xFF00) | (c >> 16 & 255);
    }
    pal_written = kestrel_pal_n;
}

/* Copy rows of `from` (w wide) into `shown` and the plane: every word when `all`, else those that differ. */
static int copy_changed(const Uint8 *from, int w, int h, int all)
{
    int diff = 0;
    for (int y = 0; y < h; y++) {
        Uint32 cols = all ? ~0u : kestrel_defer_row_cols(y);   /* 16-pixel columns drawn there */
        if (!cols) continue;
        Uint8 *dst = vbase + OFF_VRAM + (oy + y) * pw + ox;
        if (((ox | w) & 3) == 0) {
            const Uint32 *s = (const Uint32 *)(const void *)(from + y * w);
            Uint32 *o = (Uint32 *)(void *)(shown + y * w), *d = (Uint32 *)(void *)dst;
            int nw = w >> 2;                            /* <= 100 words: 32 columns cover a row */
            while (cols) {                              /* each run of drawn 16-pixel columns */
                int c0 = __builtin_ctz(cols), c1 = c0;
                while (c1 < 31 && (cols >> (c1 + 1) & 1)) c1++;
                cols &= c1 == 31 ? 0 : ~0u << (c1 + 1);
                int x1 = c1 == 31 ? nw : 4 * c1 + 4;
                if (x1 > nw) x1 = nw;
                for (int x = 4 * c0; x < x1; x += 4) {  /* a column (4 words) compared at once */
                    int e = x + 4 < x1 ? x + 4 : x1;
                    if (!all && e == x + 4 && !((s[x] ^ o[x]) | (s[x + 1] ^ o[x + 1]) | (s[x + 2] ^ o[x + 2]) | (s[x + 3] ^ o[x + 3]))) continue;
                    for (int i = x; i < e; i++) {
                        Uint32 v = s[i];
                        if (all || v != o[i]) { o[i] = v; d[i] = v; diff = 1; KD_STAT(words, 1); }
                    }
                }
            }
            continue;
        }
        for (int x = 0; x < w; x++)
            if (all || from[y * w + x] != shown[y * w + x]) { shown[y * w + x] = from[y * w + x]; dst[x] = from[y * w + x]; diff = 1; }
    }
    return diff;
}

/* Once a frame when nothing was presented: if the pointer moved (or changed shape), put back the last
 * picture's pixels under the old cursor and draw the new one. A port that repaints only on changes
 * (klystrack) keeps a live pointer without repainting. */
void kestrel_plane_cursor(void)
{
    if (!vbase || !shown) return;
    int cw, chh, hx, hy, mx, my;
    const Uint32 *cp = kestrel_cursor_image(&cw, &chh, &hx, &hy);
    SDL_GetMouseState(&mx, &my);
    if (cp == cur_img && mx == cur_mx && my == cur_my) return;
    cursor_resolve(sw, sh);
    if (kestrel_palette_compacted) copy_changed(shown, sw, sh, 1);   /* renumbered: the plane gets it all again */
    cursor_move(sw);
    write_palette();
    kestrel_palette_compacted = 0;
}

static int shown_size(int w, int h)
{
    if (shown && sw == w && sh == h) return 1;
    free(shown);
    shown = malloc((size_t)w * (size_t)h);
    kestrel_palette_track(KPAL_SHOWN, shown, shown ? (unsigned)(w * h) : 0);
    if (!shown) { kestrel_log("kestrel_plane: no memory for the shown picture, nothing presented"); return 0; }
    sw = w; sh = h; full = 1; cur_w = cur_h = 0;
    return 1;
}

void kestrel_plane_present8(const Uint8 *src, int w, int h)
{
    if (!vbase) return;
    if (w > 400) w = 400;
    if (h > 280) h = 280;
    plane_size(w, h);
    kestrel_plane_origin(w, h, &ox, &oy);
    kestrel_ptrbox_plane(pw > 320, ox, oy, w, h); /* the board's pointer stops at the picture's edge */
    if (!shown_size(w, h)) return;
    cursor_resolve(w, h);
    if (kestrel_palette_compacted) full = 1;
    changed = copy_changed(src, w, h, full);
    cursor_move(w);
    write_palette();
    plane_regs();
    full = 0;
    kestrel_palette_compacted = 0;
    kestrel_palette_presented();
#ifdef KESTREL_DEFER_STATS
    kestrel_defer_stats_log();
#endif
}
