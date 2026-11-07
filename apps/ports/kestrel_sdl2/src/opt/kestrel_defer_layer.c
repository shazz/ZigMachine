/* A LAYER over the window (klystrack round 5): klystron draws its menus over every view, and moving the pointer
 * over a menu changes only the menu's highlight, yet each tile it dirties replayed EVERY command there, the
 * whole UI under the menu first (a sub-menu: ~7 est Mc a frame, board 5 fps before the list grew).
 *
 * kestrel_defer_layer() marks where the layer starts in this frame's list. The window as drawn by the
 * entries BELOW the mark is kept (the snapshot, window indices, renumbered with the window by palette
 * compactions). A change below the mark dirties a tile as before (kd_mark: `dirty`); a change above it only
 * the layer (`kd.dirty_hi`). At the present:
 *   below-dirty tiles  the entries below the mark replayed there, then copied to the snapshot
 *   layer-only tiles   copied back from the snapshot (what the entries below drew there, unchanged)
 *   both               the entries above the mark replayed there
 * The snapshot is (re)built whole the first frame of a mark, or when the mark moved in the list: every tile is
 * then below-dirty. A mark made inside a group, or while the frame draws at once, is ignored. */
#include "kestrel_defer.h"

static Uint8 *snap;
static int snap_ok;
static unsigned last_at = ~0u;

void kestrel_defer_layer(void)
{
    if (!kd.deferring || kd.immediate || kd.rbuf || kd.gopen || kd.above) return;
    kd.above = 1; kd.layer_at = kd.n;
}

/* The snapshot is palette-tracked only while it holds a picture: a stale one would keep its colours "in use"
 * and starve the compactions (the pattern tab after a menu: row changes ~8 -> ~15 est). */
void kd_layer_invalidate(void)
{
    if (snap_ok) kestrel_palette_track(KPAL_SLOTS - 1, NULL, 0);
    snap_ok = 0; last_at = ~0u;
}

/* The snapshot for a w x h window: allocated with the list (a malloc of its own found no room while a song
 * played). */
static int snap_buf(int w, int h)
{
    snap = kd.snap && kd.snap_w == w && kd.snap_h == h ? kd.snap : NULL;
    return snap != NULL;
}

/* Band ty's tiles in mask m copied from src to dst (w x h pictures). */
static void copy_tiles(Uint8 *dst, const Uint8 *src, int w, int h, int ty, Uint32 m)
{
    while (m) {
        int x0 = __builtin_ctz(m), x1 = x0;
        while (x1 < 31 && (m >> (x1 + 1) & 1)) x1++;
        m &= x1 == 31 ? 0 : ~0u << (x1 + 1);
        int px = x0 * TW, pw = (x1 - x0 + 1) * TW;
        if (px + pw > w) pw = w - px;
        for (int y = ty * TH; y < ty * TH + TH && y < h; y++) memcpy(dst + y * w + px, src + y * w + px, (size_t)pw);
    }
}

/* The frame's replay (kestrel_defer.c's present): dirty[] becomes every tile drawn. */
void kd_layer_replay(Uint32 *dirty, Uint32 cmask, Uint8 *fb, int fw, int fh)
{
    const int rows = (fh + TH - 1) / TH;
    if (!kd.above || !snap_buf(fw, fh)) {
        for (int ty = 0; ty < rows; ty++) dirty[ty] |= kd.dirty_hi[ty] & cmask;
        kd_layer_invalidate();
        kestrel_defer_replay(kd.list, 0, kd.n, dirty, fb, fw, fh);
        return;
    }
    unsigned at = kd.layer_at < kd.n ? kd.layer_at : kd.n;
    if (!snap_ok || at != last_at)                          /* a new mark: the snapshot drawn whole */
        for (int ty = 0; ty < rows; ty++) dirty[ty] = cmask;
    kestrel_defer_replay(kd.list, 0, at, dirty, fb, fw, fh);
    if (!snap_ok) kestrel_palette_track(KPAL_SLOTS - 1, snap, (unsigned)(fw * fh));   /* filled just below */
    for (int ty = 0; ty < rows; ty++) {
        Uint32 hi = kd.dirty_hi[ty] & cmask;
        copy_tiles(snap, fb, fw, fh, ty, dirty[ty]);
        copy_tiles(fb, snap, fw, fh, ty, hi & ~dirty[ty]);
        dirty[ty] |= hi;
    }
    kestrel_defer_replay(kd.list, at, kd.n, dirty, fb, fw, fh);
    snap_ok = 1; last_at = at;
}
