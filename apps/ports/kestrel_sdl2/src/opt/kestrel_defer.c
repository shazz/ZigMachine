/* The window's drawing is RECORDED (copy, fill, clear, line) and replayed at the present only into the 16x8
 * tiles where it differs from the last present's. klystron redraws its whole UI on every repaint (30 a
 * second while a song plays, every pointer move while a menu is open), the same calls in the same order,
 * and most of them draw exactly what they drew last time.
 *
 * ONE list, rewritten in place: command i of this frame is compared with entry i, which still holds last
 * frame's command i (what it draws: texture and its serial, source, clipped destination, colour mod, blend,
 * colour). The same: nothing is stored. Different: the tiles both touch are dirty, and the entry is replaced;
 * so are the tiles of entries one frame has past the other's end. A tile no differing command touches gets the
 * same commands, in the same order, as last frame, so it holds the same picture already, provided its commands
 * are idempotent: opaque or keyed copies, opaque fills, clears and lines give the same pixels drawn twice as
 * once. A command that blends (alpha between 0 and 255, ADD, MOD, an ARGB texture) dirties its tiles every
 * frame. The replay runs every command, in order, clipped to the runs of dirty tiles of each 8-line band,
 * onto what those tiles held: exactly what drawing everything would have left there. Groups of commands
 * (a bevel, a string) skip their calls altogether when they did not change: kestrel_defer_group.c.
 *
 * Before a texture's pixels change or it is freed (kestrel_texture_touched), or when a frame has more
 * commands than the list holds, the commands so far are drawn in full and the rest of the frame draws at
 * once (and the next frame replays everything). */
#include "kestrel_defer.h"

void kestrel_log(const char *m);
size_t kestrel_heap_largest(void);         /* kestrel_heap.c, KESTREL_HEAP_PRESSURE */

static Uint8 *fb; static int fw, fh, cols, rows;
/* One block, allocated once: the list (4,096 commands, 224 KB: a repaint makes ~2,300-3,200, groups included),
 * then the group arena (64 KB). */
static Uint8 *block;
kd_t kd;                                /* the list and its state (kestrel_defer.h) */
static Uint32 dirty[ROWS];
static int all_dirty = 1, no_list;
static int busy;                        /* inside a call that holds pointers into the list */
static unsigned wait;                   /* presents until the list is (re)allocated; 0: not waiting */
static int let_go;                      /* the heap took it back: ask for room to spare first */
static Uint32 band_drawn[ROWS];         /* the 16-pixel columns the last present replayed in each 8-line band */
static int all_drawn = 1;               /* ...or drew everything (immediate, not deferring) */
static unsigned serials;
static cmd_t scratch;                   /* the command being made */
#define NEED(n) ((size_t)(n) * sizeof(cmd_t) + KD_ARENA * 4)

/* For kestrel_plane.c: the 16-pixel columns of window row y that may differ from what the last present showed
 * (bit x: pixels 16x .. 16x+15). */
Uint32 kestrel_defer_row_cols(int y) { return all_drawn || y / TH >= ROWS ? ~0u : band_drawn[y / TH]; }

/* The list (4,096, else 3,072 commands) at the END of the largest free block (a pad takes its start for the
 * time of the malloc): let go, it joins the free space the next allocations leave before it, so a song's
 * reverb/chorus buffer finds one block big enough. */
static void alloc_list(void)
{
    for (unsigned n = 4096; n >= 3072 && !block; n -= 1024) {
        size_t need = NEED(n), big = kestrel_heap_largest();
        if (big < need + 64) continue;
        void *pad = big > need + 4096 ? malloc(big - need - 64) : NULL;
        if ((block = malloc(need))) kd.cap = n;
        free(pad);
    }
    if (!block) { no_list = 1; return; }
    kd.list = (cmd_t *)(void *)block;
    kd.arena = (Uint32 *)(void *)(block + (size_t)kd.cap * sizeof(cmd_t));
}

/* The list is allocated at the first present, after the boot's own allocations. */
void kestrel_defer_target(Uint8 *b, int w, int h)
{
    fb = b; fw = w; fh = h; cols = (w + TW - 1) / TW; rows = (h + TH - 1) / TH;
    kd.deferring = fb && block && cols <= COLS && rows <= ROWS;  /* else everything is drawn at once */
    if (fb && !block && !no_list && !wait) wait = 1;
    kd.n = kd.nlast = kd.na = 0; kd.stale = 1; kd.immediate = 0; all_dirty = 1;
}

/* kestrel_heap.c, when a malloc fails: the song's reverb/chorus buffers matter more than this cache, so the
 * list goes back (the window then draws at once) and comes back when that much is free again. */
int kestrel_heap_pressure(void)
{
    if (!block || busy) return 0;
    free(block); block = NULL; kd.list = NULL; kd.arena = NULL;
    kd.n = kd.nlast = kd.cap = kd.na = 0; kd.deferring = 0; wait = 120; let_go = 1;
    kestrel_log("kestrel_defer: the heap is short, the window's draw cache let go (the window draws at once)");
    return 1;
}

static void take_list(void)
{
    if (!wait || --wait) return;
    if (let_go && kestrel_heap_largest() < NEED(4096) + 256 * 1024) { wait = 120; return; }   /* every ~4 s */
    alloc_list();
    if (!block) { no_list = 0; let_go = 1; wait = 120; return; }   /* try again later, with room to spare */
    let_go = 0;
    kestrel_defer_target(fb, fw, fh);
}

/* kestrel_defer_draw.c, on this window */
static void draw(const cmd_t *k, const SDL_Rect *r) { kestrel_defer_draw(k, r, fb, fw, fh); }

/* Everything recorded so far drawn in full; the rest of the frame draws at once. */
void kd_flush(void)
{
    if (!kd.immediate) for (unsigned i = 0; i < kd.n; i++) draw(&kd.list[i], NULL);
    kd.immediate = 1;
}

void kestrel_texture_touched(SDL_Texture *t)
{
    if (kd.n) { busy++; kd_flush(); busy--; }
    t->serial = ++serials;
}

void kd_mark(const cmd_t *k)
{
    Uint32 b = k->box;
    if (b & NONE) return;
    Uint32 span = (2u << TX1(b)) - (1u << TX0(b));
    for (unsigned ty = TY0(b); ty <= TY1(b); ty++) dirty[ty] |= span;
}

int kd_same(const cmd_t *a, const cmd_t *b)
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

/* The scratch command (filled; its box x0..x1, y0..y1 in pixels) joins the frame: compared with entry kd.n,
 * stored there if it differs, drawn now if the frame draws at once. blends: 1, 0, or -1 = a copy: ask
 * copy_blends, only when it is not last frame's command (the same command gets the same answer). */
static void commit(int x0, int y0, int x1, int y1, int blends)
{
    cmd_t *k = &scratch;
    if (kd.rbuf) { kestrel_defer_draw_at(k, kd.rbuf, kd.rw, kd.rh, kd.rx, kd.ry); return; }
    if (!kd.deferring) { draw(k, NULL); return; }
    k->box = box_of(x0, y0, x1, y1);
    if (kd.n >= kd.cap) { kd_flush(); draw(k, NULL); all_dirty = 2; return; }   /* not kept: compare nothing next frame */
    cmd_t *e = &kd.list[kd.n];
    int was = kd.n < kd.nlast && kd_same(k, e);
    if (was) {
        if (e->box & BLENDS) kd_mark(e);
    } else {
        if (blends < 0) blends = copy_blends(k);
        if (blends) k->box |= BLENDS;
        if (kd.n < kd.nlast) kd_mark(e);
        kd_mark(k);
        *e = *k;
        KD_STAT(stored, 1);
    }
    kd.n++;
    if (kd.immediate) draw(e, NULL);
}

void kestrel_defer_copy(SDL_Texture *t, const SDL_Rect *c, const SDL_Rect *s, int ox, int oy, Uint32 stepx, Uint32 stepy)
{
    busy++;
    cmd_t *k = &scratch;
    k->kind = C_COPY | (Uint32)t->blend << 4; k->mod = (Uint32)t->mr | (Uint32)t->mg << 8 | (Uint32)t->mb << 16;
    k->serial = t->serial; k->tex = t; k->colour = 0; k->stepx = stepx; k->stepy = stepy; R16(k->c, *c); R16(k->s, *s);
    k->oxy = P2(ox, oy);
    commit(c->x, c->y, c->x + c->w - 1, c->y + c->h - 1, -1);
    busy--;
}

void kestrel_defer_fill(const SDL_Rect *d, Uint32 c, unsigned a, SDL_BlendMode m)
{
    busy++;
    cmd_t *k = &scratch;
    memset(k, 0, sizeof *k);
    k->kind = C_FILL | (Uint32)m << 4 | (a & 255) << 8; k->colour = c; R16(k->c, *d);
    commit(d->x, d->y, d->x + d->w - 1, d->y + d->h - 1, !(m == SDL_BLENDMODE_NONE || (m == SDL_BLENDMODE_BLEND && a == 255)));
    busy--;
}

void kestrel_defer_clear(Uint32 c)
{
    busy++;
    cmd_t *k = &scratch;
    memset(k, 0, sizeof *k);
    k->kind = C_CLEAR; k->colour = c; R16(k->c, ((SDL_Rect){ 0, 0, fw, fh }));
    commit(0, 0, fw - 1, fh - 1, 0);
    busy--;
}

void kestrel_defer_line(const SDL_Rect *clip, int x1, int y1, int x2, int y2, Uint32 c)
{
    busy++;
    cmd_t *k = &scratch;
    memset(k, 0, sizeof *k);
    k->kind = C_LINE | (clip ? 1u << 7 : 0); k->colour = c; R16(k->c, ((SDL_Rect){ x1, y1, x2, y2 }));
    if (clip) R16(k->s, *clip);
    commit(x1 < x2 ? x1 : x2, y1 < y2 ? y1 : y2, x1 < x2 ? x2 : x1, y1 < y2 ? y2 : y1, 0);
    busy--;
}

void kestrel_defer_nop(void)
{
    busy++;
    cmd_t *k = &scratch;
    memset(k, 0, sizeof *k);
    k->kind = C_NOP;
    commit(1, 1, 0, 0, 0);                                  /* an empty box: no tile */
    busy--;
}

#ifdef KESTREL_DEFER_STATS
kd_stats_t kd_stats;
int snprintf(char *, unsigned long, const char *, ...);
void kestrel_defer_stats_log(void)
{
    static unsigned presents;
    if (++presents % 30 == 0) {
        char b[200];
        snprintf(b, sizeof b, "defer: entries %u stored %u groups %u/%u resync %u draws %u px idx %u argb %u fill %u tiles %u words %u",
                 kd_stats.entries, kd_stats.stored, kd_stats.ghit, kd_stats.gmiss, kd_stats.resync, kd_stats.draws,
                 kd_stats.px_idx, kd_stats.px_argb, kd_stats.px_fill, kd_stats.tiles, kd_stats.words);
        kestrel_log(b);
    }
    memset(&kd_stats, 0, sizeof kd_stats);
}
#endif

void kestrel_defer_present(void)
{
    KD_STAT(entries, kd.n);
    all_drawn = !kd.deferring || kd.immediate;
    if (!kd.deferring) { take_list(); return; }
    busy++;
    for (unsigned i = kd.n; i < kd.nlast; i++) kd_mark(&kd.list[i]);   /* last frame drew more */
    Uint32 cmask = (2u << (cols - 1)) - 1;
    for (int ty = 0; ty < rows; ty++) {
        if (all_dirty) dirty[ty] = ~0u;
        if (kd.immediate) dirty[ty] = 0;                              /* already drawn in full */
        dirty[ty] &= cmask;
        band_drawn[ty] = dirty[ty];
        KD_STAT(tiles, __builtin_popcount(dirty[ty]));
    }
    if (!kd.immediate) kestrel_defer_replay(kd.list, kd.n, dirty, fb, fw, fh);
    memset(dirty, 0, sizeof dirty);
    kd.nlast = all_dirty == 2 ? 0 : kd.n;
    kd.stale = !kd.nlast || kd.na > KD_ARENA * 3 / 4;                /* a full arena starts over next frame */
    if (kd.stale) kd.na = 0;
    kd.n = 0; kd.immediate = 0; all_dirty = all_dirty == 2;
    busy--;
}
