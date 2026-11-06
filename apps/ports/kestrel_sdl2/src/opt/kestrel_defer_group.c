/* GROUPS of window draws that are a pure function of a key: a klystron bevel (its area, offset and flags; ~10
 * to ~80 tile copies), a string of text (its font, position, cursor, bounds and bytes; one copy a glyph). The
 * caller asks kestrel_group_begin(key) first; when the list's entry at this position is last frame's same
 * group with the same key (and the same renderer and texture state, added below), its commands are still
 * there and stay as they are, the outputs it returned (a text's cursor and bounds) are handed back, and the
 * caller draws nothing: what kestrel_defer.c's entry-by-entry compare would have found equal anyway, without
 * making the calls. Otherwise the caller draws and calls kestrel_group_end(out).
 *
 * In the list a group is one GROUP entry (it draws nothing and touches no tile: kind = C_GROUP | nout << 16,
 * mod = key words, colour = where its key and outputs start in the arena, box = NONE | BLENDS if one of its
 * commands blends | the number of commands after it), then its commands. The arena is written in place like
 * the list: a group that did not change keeps its key where it is (nothing copied), a new one is appended;
 * when it is 3/4 full it starts over and every group draws once (kestrel_defer.c, kd.stale). Groups nest
 * two deep (a klystrack VIEW around its bevels and strings, kestrel_group_begin_ex): an outer group reused
 * skips the inner ones with it, an outer group drawn still reuses its inner ones; deeper ones are plain
 * commands of the groups around them. */
#include "kestrel_defer.h"

#define LEN(b) ((b) & 0x3FFFFFu)
#define DEPTH 8                         /* begins nested deeper are plain commands */
static unsigned depth, nopen, start[2], last_hit;
static Uint8 opened[DEPTH];             /* begin at that depth opened a group (slot nopen - 1) */

static int words_differ(const Uint32 *x, const Uint32 *y, unsigned n)
{
    for (unsigned i = 0; i < n; i++) if (x[i] != y[i]) return 1;
    return 0;
}

/* A key is the renderer/texture state (NS words) then the caller's words: stored together in the arena. */
#define NS 7
typedef struct { const Uint32 *st, *key; unsigned n; } gkey_t;   /* n: all of it, NS + the caller's */

static int key_differs(const Uint32 *a, const gkey_t *k)
{
    return words_differ(a, k->st, NS) || words_differ(a + NS, k->key, k->n - NS);
}

/* Last frame's group at entry i, if it had this key: its length, else -1. */
static int last_frames(unsigned i, Uint32 kind, const gkey_t *w, unsigned n)
{
    if (i >= kd.nlast || kd.stale) return -1;
    const cmd_t *p = &kd.list[i];
    if (p->kind != kind || p->mod != n || p->colour + n > kd.na) return -1;
    if (key_differs(kd.arena + p->colour, w)) return -1;
    unsigned len = LEN(p->box);
    return i + 1 + len <= kd.nlast ? (int)len : -1;
}

/* This frame drew fewer commands before this group than last frame did (a string that is gone, a shorter
 * list): entry i is not a group, but last frame's same group may sit a little further on. Then the entries
 * between are dropped (their tiles dirty) and last frame's rest moves down to i, so everything after it is
 * compared with what it really was rather than with whatever now sits at its position. */
#define RESYNC 256
static void resync(unsigned i, Uint32 kind, const gkey_t *w, unsigned n)
{
    if (i >= kd.nlast || kd.stale || OP(&kd.list[i]) == C_GROUP) return;   /* a group in place: a real change */
    for (unsigned j = i + 1; j < kd.nlast && j <= i + RESYNC; j++) {
        const cmd_t *p = &kd.list[j];
        if (p->kind != kind || p->mod != n || p->colour + n > kd.na || key_differs(kd.arena + p->colour, w)) continue;
        if (j + 1 + LEN(p->box) > kd.nlast) return;
        for (unsigned q = i; q < j; q++) kd_mark(&kd.list[q]);
        memmove(&kd.list[i], &kd.list[j], (kd.nlast - j) * sizeof(cmd_t));
        KD_STAT(resync, 1);
        kd.nlast -= j - i;
        return;
    }
}

/* miss: drawn even when last frame's group had this key (kestrel_group_begin_ex's caller says it may not be
 * reused: its commands are compared one by one, as a group with another key). */
static int group_begin(int can, const gkey_t *w, Uint32 *out, unsigned nout, int miss)
{
    unsigned n = w->n, d = depth++;
    if (d < DEPTH) opened[d] = 0;
    if (d >= DEPTH || nopen >= 2 || !can || !kd.deferring || kd.immediate || !kd.list || kd.rbuf) return 0;
    unsigned i = kd.n, a = kd.na;
    if (i + 1 > kd.cap) return 0;
    Uint32 kind = C_GROUP | nout << 16;
    cmd_t *g = &kd.list[i];
    int len = last_frames(i, kind, w, n);
    if (len < 0) { resync(i, kind, w, n); len = last_frames(i, kind, w, n); }
    if (len >= 0 && !miss) KD_STAT(ghit, 1); else KD_STAT(gmiss, 1);
    if (len >= 0 && !miss) {                                /* the same: its commands and key stay as they are */
        const Uint32 *po = kd.arena + g->colour + n;
        for (unsigned j = 0; j < nout; j++) out[j] = po[j];
        if (g->box & BLENDS)
            for (unsigned j = i + 1; j <= i + (unsigned)len; j++) if (kd.list[j].box & BLENDS) kd_mark(&kd.list[j]);
        last_hit = i;
        kd.n = i + 1 + (unsigned)len;
        depth--;
        return 1;
    }
    /* The group it replaces leaves its arena room to it when that is big enough (a string with other
     * letters, a bevel moved): only a longer key is appended, and the arena hardly grows. */
    if (i < kd.nlast && !kd.stale && OP(g) == C_GROUP && g->mod + (g->kind >> 16) >= n + nout && g->colour + g->mod <= kd.na)
        a = g->colour;
    else if (a + n + nout > KD_ARENA) return 0;               /* full: drawn as plain commands */
    else kd.na = a + n + nout;
    memcpy(kd.arena + a, w->st, NS * 4);
    memcpy(kd.arena + a + NS, w->key, (n - NS) * 4);
    if (i < kd.nlast) kd_mark(g);                            /* replaced, as any entry */
    memset(g, 0, sizeof *g);
    g->kind = kind; g->mod = n; g->colour = a; g->box = NONE;
    kd.n = i + 1; start[nopen++] = i; opened[d] = 1;
    return 0;
}

void kestrel_defer_group_end(const Uint32 *out, unsigned nout)
{
    if (!depth) return;
    unsigned d = --depth;
    if (d >= DEPTH || !opened[d]) return;
    opened[d] = 0;
    unsigned s = start[--nopen];
    if (!kd.deferring || !kd.list || s >= kd.n) return;          /* the list was let go meanwhile */
    cmd_t *g = &kd.list[s];
    for (unsigned j = 0; j < nout; j++) kd.arena[g->colour + g->mod + j] = out[j];
    Uint32 blends = 0, x0 = 31, y0 = 63, x1 = 0, y1 = 0;     /* and the tiles its commands touch, together */
    for (unsigned j = s + 1; j < kd.n; j++) {
        Uint32 b = kd.list[j].box;
        blends |= b & BLENDS;
        if (b & NONE) continue;
        if (TX0(b) < x0) x0 = TX0(b);
        if (TY0(b) < y0) y0 = TY0(b);
        if (TX1(b) > x1) x1 = TX1(b);
        if (TY1(b) > y1) y1 = TY1(b);
    }
    g->stepx = x0 > x1 ? NONE : x0 | x1 << 5 | y0 << 10 | y1 << 16;
    g->box = NONE | blends | (kd.n - s - 1);
}

/* The API (kestrel_port.h declares it for klystron's patches): the window renderer's state and the group's
 * texture (pointer, serial, colour mod, blend) lead the caller's key. */
int kestrel_window_state(SDL_Renderer *r, Uint32 w[4]);
int kestrel_group_begin(void *renderer, void *texture, const unsigned *key, unsigned n, unsigned *out, unsigned nout)
{
    Uint32 st[NS];
    SDL_Texture *t = texture;
    int can = t && kestrel_window_state(renderer, st);
    if (can) {
        st[4] = (Uint32)(uintptr_t)t; st[5] = t->serial;
        st[6] = (Uint32)t->mr | (Uint32)t->mg << 8 | (Uint32)t->mb << 16 | (Uint32)t->blend << 24;
    }
    gkey_t k = { st, key, NS + n };
    return group_begin(can, &k, out, nout, 0);
}
void kestrel_group_end(const unsigned *out, unsigned nout) { kestrel_defer_group_end(out, nout); }

/* A group with no texture of its own (a klystrack view: kestrel_view.c): the renderer's state and the caller's
 * key. miss: draw it (and compare its commands one by one) even if last frame's had this key. */
int kestrel_group_begin_ex(void *renderer, const unsigned *key, unsigned n, unsigned *out, unsigned nout, int miss)
{
    Uint32 st[NS] = { 0 };
    int can = kestrel_window_state(renderer, st);
    gkey_t k = { st, key, NS + n };
    return group_begin(can, &k, out, nout, miss);
}

/* The group just reused (begin answered 1) drawn after all: its entries are compared again as a miss's. */
int kestrel_group_redo(void *renderer, const unsigned *key, unsigned n, unsigned *out, unsigned nout)
{
    kd.n = last_hit;
    return kestrel_group_begin_ex(renderer, key, n, out, nout, 1);
}
