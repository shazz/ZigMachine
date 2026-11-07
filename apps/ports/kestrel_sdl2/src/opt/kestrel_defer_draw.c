/* Draws the recorded window commands (kestrel_defer.c): one in full, or all of them clipped to the runs of
 * dirty tiles of each 8-line band. A copy draws with its recorded colour mod and blend, put back after. */
#include "kestrel_defer.h"

/* One command, clipped to r (NULL: everything). The texture's mod and blend are the recorded ones. */
void kestrel_defer_draw(const cmd_t *k, const SDL_Rect *r, Uint8 *fb, int fw, int fh)
{
    KD_STAT(draws, 1);
    if (OP(k) >= C_GROUP) return;                           /* a group's GROUP / KEY / OUT: no pixels */
    SDL_Rect c = RECT(k->c), s = RECT(k->s);
    SDL_BlendMode m = (SDL_BlendMode)(k->kind >> 4 & 7);
    if (OP(k) == C_LINE) {
        SDL_Rect clip = k->kind >> 7 & 1 ? s : (SDL_Rect){ 0, 0, fw, fh };
        if (r && !kestrel_clip_rect(&clip, NULL, NULL, fw, fh, r)) return;
        kestrel_w8_line(fb, fw, fh, &clip, c.x, c.y, c.w, c.h, k->colour);
        return;
    }
    int ox = LO(k->oxy), oy = HI(k->oxy);
    if (r && !kestrel_clip_rect(&c, &ox, &oy, fw, fh, r)) return;
    if (OP(k) == C_FILL) { kestrel_w8_fill(fb, fw, &c, k->colour, k->kind >> 8 & 255, m); return; }
    if (OP(k) == C_CLEAR) { kestrel_w8_fill(fb, fw, &c, k->colour, 255, SDL_BLENDMODE_NONE); return; }
    SDL_Texture *t = k->tex;
    if (k->stepx == 0x10000u && k->stepy == 0x10000u && kestrel_w8_unscaled(t, fb, fw, &c, s.x + ox, s.y + oy, k->mod, m)) return;
    Uint8 mr = t->mr, mg = t->mg, mb = t->mb; SDL_BlendMode bl = t->blend;
    t->mr = (Uint8)k->mod; t->mg = (Uint8)(k->mod >> 8); t->mb = (Uint8)(k->mod >> 16); t->blend = m;
    kestrel_w8_copy(t, fb, fw, &c, &s, ox, oy, k->stepx, k->stepy);
    t->mr = mr; t->mg = mg; t->mb = mb; t->blend = bl;
}

/* The window's draws go at once into buf, an 8-bit picture of window indices covering the window's rectangle
 * (x, y, w, h) (a klystrack cache of pattern rows, apps/ports/klystrack/kestrel_rows.c), instead of the list:
 * no entry is made or compared, and groups draw their commands (kestrel_defer_group.c). buf NULL: back to the
 * list. */
void kestrel_defer_redirect(Uint8 *buf, int w, int h, int x, int y)
{
    kd.rbuf = buf; kd.rw = w; kd.rh = h; kd.rx = x; kd.ry = y;
}

/* One command into buf, the window's rectangle (x, y, w, h) as its own 8-bit picture (kestrel_defer_redirect):
 * the command moved by (-x, -y) and drawn there, clipped to it. */
void kestrel_defer_draw_at(const cmd_t *k, Uint8 *buf, int w, int h, int x, int y)
{
    if (OP(k) >= C_GROUP) return;
    cmd_t m = *k;
    SDL_Rect c = RECT(k->c);
    if (OP(k) == C_LINE) {
        m.c[0] = P2(c.x - x, c.y - y); m.c[1] = P2(c.w - x, c.h - y);
        if (k->kind >> 7 & 1) { SDL_Rect s = RECT(k->s); m.s[0] = P2(s.x - x, s.y - y); }
    } else m.c[0] = P2(c.x - x, c.y - y);
    kestrel_defer_draw(&m, &(SDL_Rect){ 0, 0, w, h }, buf, w, h);
}

/* OCCLUSION (klystrack round 5): a tile wholly covered by an opaque command (a clear, an opaque fill, a raw8
 * cache's copy) shows nothing drawn there before it, so the replay leaves the commands before it out of that
 * tile. A scrolled pattern-rows cache (kestrel_rows.c) dirties its whole track a row change, and without this
 * the background, the bevel and the clears under it were drawn there again first (~3/4 of a row change's
 * pixels). Up to OCC_MAX occluders, the biggest kept; looked for only when many tiles are dirty. */
#define OCC_MAX 16
#define OCC_TILES 48                        /* fewer dirty tiles than this: no search (a repaint between rows) */
static struct { unsigned i; Uint32 cols; int ty0, ty1; } occ[OCC_MAX];
static unsigned nocc, next_occ;
static Uint32 hide[ROWS];                  /* tiles some occluder after the current command covers */

/* The tiles k covers wholly and opaquely: columns as a mask, bands ty0..ty1 (0: none). */
static Uint32 covers(const cmd_t *k, int fw, int fh, int *ty0, int *ty1)
{
    SDL_Rect c = RECT(k->c);
    if (OP(k) == C_FILL) { SDL_BlendMode m = (SDL_BlendMode)(k->kind >> 4 & 7);
        if (!(m == SDL_BLENDMODE_NONE || (m == SDL_BLENDMODE_BLEND && (k->kind >> 8 & 255) == 255))) return 0; }
    else if (OP(k) == C_COPY) {
        SDL_Texture *t = k->tex; SDL_Rect s = RECT(k->s);
        int sx = s.x + LO(k->oxy), sy = s.y + HI(k->oxy);
        if (!t->raw8 || !t->idx || k->stepx != 0x10000u || k->stepy != 0x10000u || sx < 0 || sy < 0 || sx + c.w > t->w || sy + c.h > t->h) return 0;
    } else if (OP(k) != C_CLEAR) return 0;
    int x0 = c.x < 0 ? 0 : c.x, y0 = c.y < 0 ? 0 : c.y, x1 = c.x + c.w > fw ? fw : c.x + c.w, y1 = c.y + c.h > fh ? fh : c.y + c.h;
    int tx0 = (x0 + TW - 1) / TW, tx1 = x1 == fw ? (x1 + TW - 1) / TW : x1 / TW;   /* the window's last partial tile is whole */
    *ty0 = (y0 + TH - 1) / TH; *ty1 = (y1 == fh ? (y1 + TH - 1) / TH : y1 / TH) - 1;
    if (tx1 <= tx0 || *ty1 < *ty0) return 0;
    return (tx1 >= 32 ? ~0u : (1u << tx1) - 1) & ~((1u << tx0) - 1);
}

static void find_occluders(const cmd_t *cmds, unsigned lo, unsigned n, const Uint32 *dirty, int fw, int fh)
{
    unsigned tiles = 0;
    nocc = next_occ = 0;
    for (int ty = 0; ty < ROWS; ty++) { hide[ty] = 0; tiles += __builtin_popcount(dirty[ty]); }
    if (tiles < OCC_TILES) return;
    for (unsigned c = 0, last = 0; c < kd.nocc[0]; c++) {   /* the candidates kestrel_defer.c kept, in order */
        unsigned i = kd.occ[0][c];
        if (i < lo || i >= n || (c && i <= last)) continue;
        last = i;
        const cmd_t *k = &cmds[i];
        int ty0, ty1;
        Uint32 cols = covers(k, fw, fh, &ty0, &ty1);
        if (!cols) continue;
        unsigned slot = nocc;
        if (nocc == OCC_MAX) {                          /* full: replace the smallest if this one is bigger */
            unsigned area = (unsigned)__builtin_popcount(cols) * (unsigned)(ty1 - ty0 + 1), best = area;
            for (unsigned j = 0; j < OCC_MAX; j++) {
                unsigned a = (unsigned)__builtin_popcount(occ[j].cols) * (unsigned)(occ[j].ty1 - occ[j].ty0 + 1);
                if (a < best) { best = a; slot = j; }
            }
            if (slot == OCC_MAX) continue;
            for (unsigned j = slot; j + 1 < OCC_MAX; j++) occ[j] = occ[j + 1];   /* kept in list order */
            slot = OCC_MAX - 1;
        } else nocc++;
        occ[slot].i = i; occ[slot].cols = cols; occ[slot].ty0 = ty0; occ[slot].ty1 = ty1;
    }
    for (unsigned j = 0; j < nocc; j++) for (int ty = occ[j].ty0; ty <= occ[j].ty1; ty++) hide[ty] |= occ[j].cols;
}

/* Command i is next: the occluders up to it no longer hide anything from it (hide = those after it). */
static void pass_occluders(unsigned i)
{
    while (next_occ < nocc && occ[next_occ].i <= i) {
        unsigned j0 = ++next_occ;
        for (int ty = occ[j0 - 1].ty0; ty <= occ[j0 - 1].ty1; ty++) {
            Uint32 h = 0;
            for (unsigned j = j0; j < nocc; j++) if (ty >= occ[j].ty0 && ty <= occ[j].ty1) h |= occ[j].cols;
            hide[ty] = h;
        }
    }
}

/* Every command replayed into the runs of dirty tiles of the bands it touches (less the tiles a later opaque
 * command covers wholly). */
void kestrel_defer_replay(const cmd_t *cmds, unsigned lo, unsigned n, const Uint32 *dirty, Uint8 *fb, int fw, int fh)
{
    find_occluders(cmds, lo, n, dirty, fw, fh);
    for (unsigned i = lo; i < n; i++) {
        const cmd_t *k = &cmds[i];
        Uint32 b = k->box;
        if (next_occ < nocc && occ[next_occ].i <= i) pass_occluders(i);
        if (OP(k) == C_GROUP) {                             /* none of its tiles dirty: skip all its commands */
            Uint32 u = k->stepx, any = 0;                   /* (not less hide: an occluder inside it must draw) */
            if (!(u & NONE))
                for (unsigned ty = TY0(u); ty <= TY1(u) && !any; ty++) any = dirty[ty] & ((2u << TX1(u)) - (1u << TX0(u)));
            if (!any) i += b & 0x3FFFFFu;
            continue;
        }
        if (b & NONE) continue;
        Uint32 span = (2u << TX1(b)) - (1u << TX0(b));
        unsigned whole = 1;                                 /* every tile it touches dirty: drawn once, unclipped */
        for (unsigned ty = TY0(b); ty <= TY1(b) && whole; ty++) whole = (dirty[ty] & ~hide[ty] & span) == span;
        if (whole) { kestrel_defer_draw(k, NULL, fb, fw, fh); continue; }
        for (unsigned ty = TY0(b); ty <= TY1(b);) {
            Uint32 m = dirty[ty] & ~hide[ty] & span;
            unsigned ty1 = ty + 1;                          /* the bands below with the same runs: one draw */
            while (ty1 <= TY1(b) && (dirty[ty1] & ~hide[ty1] & span) == m) ty1++;
            while (m) {
                int x0 = __builtin_ctz(m), x1 = x0;
                while (m >> (x1 + 1) & 1) x1++;
                m &= ~((2u << x1) - (1u << x0));
                SDL_Rect r = { x0 * TW, (int)ty * TH, (x1 - x0 + 1) * TW, (int)(ty1 - ty) * TH };
                kestrel_defer_draw(k, &r, fb, fw, fh);
            }
            ty = ty1;
        }
    }
}
