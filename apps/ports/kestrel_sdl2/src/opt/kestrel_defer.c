/* The window's drawing is RECORDED (copy, fill, clear, line) and replayed at the present only into the 16x8
 * tiles where it differs from the last present's. klystron redraws its whole UI on every repaint (30 a
 * second while a song plays, every pointer move while a menu is open), the same calls in the same order,
 * and most of them draw exactly what they drew last time.
 *
 * The frame's commands are compared with the last frame's BY POSITION: command i against last frame's
 * command i (what it draws: texture and its serial, source, clipped destination, colour mod, blend,
 * colour). Where the two differ, the tiles both of them touch are dirty; so are the tiles of any command
 * one frame has past the other's end. A tile no differing command touches gets the same commands, in the
 * same order, as last frame, so it holds the same picture already, provided its commands are idempotent:
 * opaque or keyed copies, opaque fills, clears and lines give the same pixels drawn twice as once. A
 * command that blends (alpha between 0 and 255, ADD, MOD, an ARGB texture) dirties its tiles every frame.
 * The replay runs every command of the frame, in order, clipped to the runs of dirty tiles of each 8-line
 * band, onto what those tiles held: exactly what drawing everything would have left there.
 *
 * Before a texture's pixels change or it is freed (kestrel_texture_touched), or when a frame has more
 * commands than the list holds, the commands so far are drawn in full and the rest of the frame draws at
 * once (and the next frame replays everything). */
#include "kestrel_render_priv.h"

#include "kestrel_defer.h"

static Uint8 *fb; static int fw, fh, cols, rows;
/* Both lists live in one block allocated once (3,072 commands each, 2 x 168 KB: a repaint makes ~2,300-2,700),
 * the second 2 KB past a 4 KB boundary from the first: the board's D$ (4 KB, direct-mapped) then never maps
 * cur[i] and prev[i], compared word by word, to the same line. */
static Uint8 *lists; static cmd_t *cur, *prev; static unsigned ncur, nprev, cap;
#define LIST_SKEW 2048
static Uint32 dirty[ROWS];
static int immediate, all_dirty = 1, deferring, no_lists;
static Uint8 band_drawn[ROWS];          /* the last present replayed something in this 8-line band */
static int all_drawn = 1;               /* ...or drew everything (immediate, not deferring) */
static unsigned serials;
static cmd_t spare;                     /* a command that does not fit the list */

/* For kestrel_plane.c: 0 when window row y is certainly what the last present showed. */
int kestrel_defer_row_changed(int y) { return all_drawn || y / TH >= ROWS || band_drawn[y / TH]; }

/* The lists: 3,072 a list, else 2,048 (cap x 56 B is a whole number of 4 KB either way). */
static void alloc_lists(void)
{
    for (unsigned n = 3072; n >= 2048 && !lists; n -= 1024)
        if ((lists = malloc(2 * (size_t)n * sizeof(cmd_t) + LIST_SKEW))) cap = n;
    if (!lists) { no_lists = 1; return; }
    cur = (cmd_t *)(void *)lists; prev = (cmd_t *)(void *)(lists + (size_t)cap * sizeof(cmd_t) + LIST_SKEW);
}

void kestrel_defer_target(Uint8 *b, int w, int h)
{
    fb = b; fw = w; fh = h; cols = (w + TW - 1) / TW; rows = (h + TH - 1) / TH;
    if (fb && !lists && !no_lists) alloc_lists();
    deferring = fb && lists && cols <= COLS && rows <= ROWS;  /* else everything is drawn at once */
    ncur = nprev = 0; immediate = 0; all_dirty = 1;
}

/* kestrel_defer_draw.c, on this window */
static void draw(const cmd_t *k, const SDL_Rect *r) { kestrel_defer_draw(k, r, fb, fw, fh); }

/* Everything recorded so far drawn in full; the rest of the frame draws at once. */
static void flush(void)
{
    if (!immediate) for (unsigned i = 0; i < ncur; i++) draw(&cur[i], NULL);
    immediate = 1;
}

void kestrel_texture_touched(SDL_Texture *t)
{
    if (ncur) flush();
    t->serial = ++serials;
}

/* A slot for the next command, or `spare` when the list is full. Every compared word must be written
 * (copies set them all; the others start from zero). */
static cmd_t *slot(void) { return ncur < cap ? &cur[ncur] : &spare; }
static cmd_t *zslot(void) { cmd_t *k = slot(); memset(k, 0, sizeof *k); return k; }

static void mark(const cmd_t *k)
{
    Uint32 b = k->box;
    if (b & NONE) return;
    Uint32 span = (2u << TX1(b)) - (1u << TX0(b));
    for (unsigned ty = TY0(b); ty <= TY1(b); ty++) dirty[ty] |= span;
}

static int same(const cmd_t *a, const cmd_t *b)
{
    const Uint32 *x = (const Uint32 *)a, *y = (const Uint32 *)b;
    for (unsigned i = 0; i < CMD_WORDS; i++) if (x[i] != y[i]) return 0;
    return 1;
}

static Uint32 box_of(int x0, int y0, int x1, int y1)
{
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 >= fw) x1 = fw - 1;
    if (y1 >= fh) y1 = fh - 1;
    if (x0 > x1 || y0 > y1) return NONE;
    return (Uint32)x0 / TW | (Uint32)x1 / TW << 5 | (Uint32)y0 / TH << 10 | (Uint32)y1 / TH << 16;
}

/* Whether copy k blends (kestrel_w8_idempotent says no). */
static int copy_blends(const cmd_t *k)
{
    SDL_Rect c = RECT(k->c), s = RECT(k->s);
    return !kestrel_w8_idempotent(k->tex, &c, &s, LO(k->oxy), HI(k->oxy), k->stepx, k->stepy);
}

/* k (filled; its box x0..x1, y0..y1 in pixels) joins the frame: compared with last frame's at its position,
 * kept, drawn now if the frame draws at once. blends: 1, 0, or -1 = a copy: ask copy_blends, only when k is
 * not last frame's command (the same command gets the same answer). */
static void commit(cmd_t *k, int x0, int y0, int x1, int y1, int blends)
{
    if (!deferring) { draw(k, NULL); return; }
    k->box = box_of(x0, y0, x1, y1);
    if (k == &spare) { flush(); draw(k, NULL); all_dirty = 2; return; }   /* not kept: compare nothing next frame */
    const cmd_t *p = ncur < nprev ? &prev[ncur] : NULL;
    int was = p && same(k, p);
    if (blends < 0) blends = was ? (p->box & BLENDS) != 0 : copy_blends(k);
    if (blends) k->box |= BLENDS;
    if (blends || !was) {
        mark(k);
        if (p) mark(p);
    }
    ncur++;
    if (immediate) draw(k, NULL);
}

void kestrel_defer_copy(SDL_Texture *t, const SDL_Rect *c, const SDL_Rect *s, int ox, int oy, Uint32 stepx, Uint32 stepy)
{
    cmd_t *k = slot();
    k->kind = C_COPY | (Uint32)t->blend << 4; k->mod = (Uint32)t->mr | (Uint32)t->mg << 8 | (Uint32)t->mb << 16;
    k->serial = t->serial; k->tex = t; k->colour = 0; k->stepx = stepx; k->stepy = stepy; R16(k->c, *c); R16(k->s, *s);
    k->oxy = P2(ox, oy);
    commit(k, c->x, c->y, c->x + c->w - 1, c->y + c->h - 1, -1);
}

void kestrel_defer_fill(const SDL_Rect *d, Uint32 c, unsigned a, SDL_BlendMode m)
{
    cmd_t *k = zslot();
    k->kind = C_FILL | (Uint32)m << 4 | (a & 255) << 8; k->colour = c; R16(k->c, *d);
    commit(k, d->x, d->y, d->x + d->w - 1, d->y + d->h - 1, !(m == SDL_BLENDMODE_NONE || (m == SDL_BLENDMODE_BLEND && a == 255)));
}

void kestrel_defer_clear(Uint32 c)
{
    cmd_t *k = zslot();
    k->kind = C_CLEAR; k->colour = c; R16(k->c, ((SDL_Rect){ 0, 0, fw, fh }));
    commit(k, 0, 0, fw - 1, fh - 1, 0);
}

void kestrel_defer_line(const SDL_Rect *clip, int x1, int y1, int x2, int y2, Uint32 c)
{
    cmd_t *k = zslot();
    k->kind = C_LINE | (clip ? 1u << 7 : 0); k->colour = c; R16(k->c, ((SDL_Rect){ x1, y1, x2, y2 }));
    if (clip) R16(k->s, *clip);
    commit(k, x1 < x2 ? x1 : x2, y1 < y2 ? y1 : y2, x1 < x2 ? x2 : x1, y1 < y2 ? y2 : y1, 0);
}

void kestrel_defer_present(void)
{
    all_drawn = !deferring || immediate;
    if (!deferring) return;
    for (unsigned i = ncur; i < nprev; i++) mark(&prev[i]);       /* last frame drew more */
    Uint32 cmask = (2u << (cols - 1)) - 1;
    for (int ty = 0; ty < rows; ty++) {
        if (all_dirty) dirty[ty] = ~0u;
        if (immediate) dirty[ty] = 0;                             /* already drawn in full */
        dirty[ty] &= cmask;
        band_drawn[ty] = dirty[ty] != 0;
    }
    if (!immediate) kestrel_defer_replay(cur, ncur, dirty, fb, fw, fh);
    memset(dirty, 0, sizeof dirty);
    cmd_t *t = prev; prev = cur; cur = t;
    nprev = all_dirty == 2 ? 0 : ncur;
    ncur = 0; immediate = 0; all_dirty = all_dirty == 2;
}
