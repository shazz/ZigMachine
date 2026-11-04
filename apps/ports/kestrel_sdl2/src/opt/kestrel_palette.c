/* The window's palette: ARGB -> 8-bit index, kept from one present to the next so the window can be drawn as
 * indices (kestrel_window8.c) and only what changed is copied to the plane (kestrel_plane.c). Index 0 is black
 * (the margins around the picture). A colour gets the next free index the first time it is drawn.
 *
 * Colours come and go (klystrack's VU and colour-modded text add a few each repaint: 272 different ones over
 * 300 frames of Starport2), so when all 256 are taken the palette is COMPACTED: the indices still used by the
 * window buffer or the shown picture keep their colours, renumbered in order, everything else is dropped, both
 * buffers are rewritten with the new numbers, and kestrel_pal_gen moves on (index caches are rebuilt). The
 * picture is unchanged. Only a picture that itself holds more than 255 colours draws the extras as the nearest
 * entry (logged once), as the per-present palette before it did. */
#include "kestrel_render_priv.h"

void kestrel_log(const char *m);

Uint32 kestrel_pal_rgb[256] = { 0xFF000000u };
unsigned kestrel_pal_n = 1, kestrel_pal_gen;
int kestrel_palette_compacted;

#define HSLOTS 1024                     /* open hash ARGB -> index; at most 256 live keys + cached nearest ones */
static Uint32 hkey[HSLOTS];
static Uint8 hval[HSLOTS], hused[HSLOTS];
static unsigned nkeys;
static Uint8 *tracked[2];
static unsigned tracked_n[2];
static int overflow_logged, stuck;          /* stuck: a compaction freed nothing; no other until the next present */

void kestrel_palette_track(int slot, Uint8 *buf, unsigned n) { tracked[slot] = buf; tracked_n[slot] = n; }
void kestrel_palette_presented(void) { stuck = 0; }

static unsigned slot_of(Uint32 c)
{
    unsigned h = (c * 2654435761u) >> 22;
    while (hused[h] && hkey[h] != c) h = (h + 1) & (HSLOTS - 1);
    return h;
}

static void remember(Uint32 c, Uint8 i)
{
    if (nkeys >= HSLOTS * 3 / 4) return;            /* full: not cached (only nearest-mapped extras get here) */
    unsigned h = slot_of(c);
    if (!hused[h]) { hused[h] = 1; hkey[h] = c; hval[h] = i; nkeys++; }
}

/* Keep the indices the tracked buffers use, renumbered in order; drop the rest and every cached nearest. */
static void compact(void)
{
    Uint8 used[256] = { 1 }, map[256];
    for (int s = 0; s < 2; s++)
        for (unsigned k = 0; tracked[s] && k < tracked_n[s]; k++) used[tracked[s][k]] = 1;
    unsigned n = 0;
    for (unsigned i = 0; i < kestrel_pal_n; i++)
        if (used[i]) { map[i] = (Uint8)n; kestrel_pal_rgb[n++] = kestrel_pal_rgb[i]; }
    for (int s = 0; s < 2; s++)
        for (unsigned k = 0; tracked[s] && k < tracked_n[s]; k++) tracked[s][k] = map[tracked[s][k]];
    kestrel_pal_n = n;
    stuck = n == 256;
    memset(hused, 0, sizeof hused);
    nkeys = 0;
    for (unsigned i = 1; i < n; i++) remember(kestrel_pal_rgb[i], (Uint8)i);
    kestrel_pal_gen++;
    kestrel_palette_compacted = 1;
}

static Uint8 nearest(Uint32 c)
{
    int r = c >> 16 & 255, g = c >> 8 & 255, b = c & 255;
    unsigned best = 0, bd = ~0u;
    for (unsigned i = 0; i < kestrel_pal_n; i++) {
        Uint32 p = kestrel_pal_rgb[i];
        int dr = (int)(p >> 16 & 255) - r, dg = (int)(p >> 8 & 255) - g, db = (int)(p & 255) - b;
        unsigned d = (unsigned)(dr * dr + dg * dg + db * db);
        if (d < bd) { bd = d; best = i; }
    }
    return (Uint8)best;
}

/* A colour not seen yet: the next index (after a compaction if all are taken), else the nearest. */
static Uint8 add_colour(Uint32 c)
{
    if (kestrel_pal_n == 256 && !stuck) compact();
    Uint8 i;
    if (kestrel_pal_n < 256) { i = (Uint8)kestrel_pal_n; kestrel_pal_rgb[kestrel_pal_n++] = c; }
    else {
        if (!overflow_logged) { kestrel_log("kestrel_palette: a picture with more than 256 colours, extras drawn as the nearest"); overflow_logged = 1; }
        i = nearest(c);
    }
    remember(c, i);
    return i;
}

Uint8 kestrel_colour_index(Uint32 c)
{
    c |= 0xFF000000u;
    if (c == 0xFF000000u) return 0;
    unsigned h = slot_of(c);
    if (hused[h]) return hval[h];
    return add_colour(c);
}
