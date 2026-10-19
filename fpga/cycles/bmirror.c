/* The audio-state mirror's cart side (cycles/bmirror.h): the cart's field offsets, and the
 * frame's write into them. The cart's memory is this CPU's own (its D-cache is write-through),
 * so a field is read back for free and stored only when the state moved: a playing SNDH costs
 * its song_ms word and the YM registers that changed, a few stores a frame. */
#include "bmirror.h"

static struct {
    uint8_t* mem;
    uint32_t ym, mode, ms; /* offsets in mem; 0: not mirrored */
} g_at;

static uint32_t inside(uint64_t size, uint32_t at, uint32_t len) {
    return at && (uint64_t)at + len <= size ? at : 0u;
}

void audio_mirror_bind(uint8_t* mem, uint64_t size, uint32_t ym, uint32_t mode, uint32_t ms) {
    g_at.mem = mem;
    g_at.ym = inside(size, ym, AS_YM_REGS);
    g_at.mode = inside(size, mode, 1);
    g_at.ms = ms & 3u ? 0u : inside(size, ms, 4); /* a u32 field: stored as one word */
}

static uint32_t put(uint8_t* dst, const uint8_t* src, uint32_t n) {
    uint32_t stored = 0;
    for (uint32_t i = 0; i < n; i++) {
        if (dst[i] != src[i]) {
            dst[i] = src[i];
            stored++;
        }
    }
    return stored;
}

uint32_t audio_mirror_frame(const aud_state* s) {
    uint8_t* m = g_at.mem;
    uint32_t n = 0;
    if (!m) return 0;
    if (g_at.ym) n += put(m + g_at.ym, s->ym, AS_YM_REGS);
    if (g_at.mode) {
        uint8_t mode = (uint8_t)s->mode; /* sealed-loader.js: a Uint8Array of one */
        n += put(m + g_at.mode, &mode, 1);
    }
    if (g_at.ms) {
        uint32_t* ms = (uint32_t*)(void*)(m + g_at.ms); /* 4-aligned (bind), the memory calloc'd */
        if (*ms != s->ms) {
            *ms = s->ms;
            n++;
        }
    }
    return n;
}
