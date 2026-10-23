/* host/audio_bridge.c's effects queue on its own (tests/test_song_bytes.py): a cart memory of
 * plain bytes, its queue of 16-byte entries (libs/zig/sfx_queue.zig), and the effects the bridge
 * hands the players recorded. Prints one line per check, "ok <name>" or "FAIL <name>: <why>". */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "haudio.h"

#define MEM 0x10000u
#define QUEUE 0x100u

static struct w2c_env g_env;
static uint32_t g_n;
static audio_fx g_got[8];
static uint32_t g_ngot;

static u32 sfx_poll(w2c_cart* c) { (void)c; return g_n; }
static u32 sfx_entries(w2c_cart* c) { (void)c; return QUEUE; }
const host_song_bridge host_songs = {.sfx_poll = sfx_poll, .sfx_entries = sfx_entries};

void audio_play(const char* name, uint32_t tune) { (void)name, (void)tune; }
void audio_sndh_call(const char* name, uint32_t d0) { (void)name, (void)d0; }
int audio_live(void) { return 1; }
void audio_effects(const audio_fx* fx, uint32_t n) {
    for (uint32_t i = 0; i < n && g_ngot < 8; i++) g_got[g_ngot++] = fx[i];
}

static int g_bad;
static void check(int ok, const char* name, const char* why) {
    printf(ok ? "ok %s\n" : "FAIL %s: %s\n", name, why);
    g_bad += !ok;
}

static void put32(uint8_t* p, uint32_t v) { p[0] = v, p[1] = v >> 8, p[2] = v >> 16, p[3] = v >> 24; }
static void entry(uint32_t i, uint8_t op, uint8_t a, uint8_t b, uint32_t ptr, uint32_t len) {
    uint8_t* q = g_env.memory.data + QUEUE + 16u * i;
    memset(q, 0, 16);
    q[0] = op, q[1] = a, q[2] = b;
    put32(q + 4, ptr), put32(q + 8, len);
}

int main(void) {
    g_env.memory.data = calloc(1, MEM);
    g_env.memory.size = MEM;
    entry(0, FX_SONG, FX_SONG_SAP, 3, 0x1000, 0x800); /* in the window: handed over */
    entry(1, FX_SONG, FX_SONG_SNDH, 0, MEM - 0x10, 0x11); /* one byte past the window's end */
    entry(2, FX_SONG, FX_SONG_SNDH, 0, 0xFFFFFF00u, 0x200); /* ptr + len wraps 32 bits */
    entry(3, FX_SAMPLE_STOP, 0, 0, 0, 0);
    g_n = 4;
    audio_bridge(&g_env);
    check(g_ngot == 2, "only_the_good_entries", "the bridge did not hand over exactly 2 effects");
    const audio_fx* s = &g_got[0];
    check(s->op == FX_SONG && s->a == FX_SONG_SAP && s->b == 3 && s->len == 0x800,
          "song_fields", "op / kind / tune / len not carried");
    check(s->pcm == (uintptr_t)(g_env.memory.data + 0x1000), "song_bytes_in_the_cart", "pcm is not the cart's bytes");
    check(g_got[1].op == FX_SAMPLE_STOP, "order_kept", "the entry after the refused ones was lost");
    return g_bad != 0;
}
