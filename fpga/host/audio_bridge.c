/* The cart's song bridge (haudio.h audio_bridge): docs/sealed-loader.js's
 * playSongByName / sndhCallByName / postSfx, read off the cart after its frame. It calls
 * audio_play, audio_sndh_call and audio_effects, which the players implement (host/audio.c)
 * or, with the players on the sound CPU, the mailbox forwards (cycles/bsound.c). */
#include <stdio.h>
#include <string.h>

#include "haudio.h"

#define NAME_MAX 64u /* libs/zig/zigos.zig g_song_name */
#define FX_CAP 32u   /* libs/zig/sfx_queue.zig CAP: the most one frame carries */

static int ends_with(const char* s, const char* tail) {
    size_t n = strlen(s), m = strlen(tail);
    return n >= m && strcmp(s + n - m, tail) == 0;
}

/* A name from the cart's memory, bounded and NUL-terminated. */
static void cart_name(struct w2c_env* e, uint32_t ptr, uint32_t len, char out[NAME_MAX + 1]) {
    if (len > NAME_MAX) len = NAME_MAX;
    if ((uint64_t)ptr + len > e->memory.size) len = 0;
    memcpy(out, e->memory.data + ptr, len);
    out[len] = 0;
}

static void sndh_calls(struct w2c_env* e) {
    const host_song_bridge* b = &host_songs;
    uint32_t n = b->sndh_poll ? b->sndh_poll(HOST_CART(e)) : 0;
    if (!n) return;
    char name[NAME_MAX + 1];
    cart_name(e, b->sndh_name_ptr(HOST_CART(e)), b->sndh_name_len(HOST_CART(e)), name);
    if (!ends_with(name, ".sndh") || strstr(name, "..") || name[0] == '/') return;
    for (uint32_t i = 0; i < n; i++) {
        uint32_t d0 = b->sndh_d0(HOST_CART(e), i);
        audio_sndh_call(name, d0);
    }
}

static uint32_t le32(const uint8_t* p) { return p[0] | p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }

/* The effects queue: `n` 16-byte entries (libs/zig/sfx_queue.zig) at sfxEntriesPtr. A play's or a
 * sample's bytes must lie in the cart's memory (the browser's Uint8Array would throw), else it is
 * dropped. */
static void effects(struct w2c_env* e) {
    const host_song_bridge* b = &host_songs;
    uint32_t n = b->sfx_poll ? b->sfx_poll(HOST_CART(e)) : 0;
    if (!n) return;
    uint32_t at = b->sfx_entries(HOST_CART(e));
    if (n > FX_CAP || (uint64_t)at + 16u * n > e->memory.size) {
        printf("ZM FX bad queue %lu at %08lx\n", (unsigned long)n, (unsigned long)at);
        return;
    }
    audio_fx fx[FX_CAP];
    uint32_t k = 0;
    for (uint32_t i = 0; i < n; i++) {
        const uint8_t* q = e->memory.data + at + 16u * i;
        audio_fx f = {.op = q[0], .a = q[1], .b = q[2], .len = le32(q + 8), .rate = le32(q + 12)};
        uint32_t ptr = le32(q + 4);
        int bytes = f.op == FX_PLAY || f.op == FX_SAMPLE;
        if (bytes && (uint64_t)ptr + f.len > e->memory.size) {
            printf("ZM FX %s out of the cart's memory\n", f.op == FX_PLAY ? "sfxPlay" : "samplePlay");
            continue;
        }
        if (bytes) f.pcm = (uintptr_t)(e->memory.data + ptr);
        fx[k++] = f;
    }
    audio_effects(fx, k);
}

int audio_bridge(struct w2c_env* e) {
    const host_song_bridge* b = &host_songs;
    int started = 0;
    if (b->poll && b->poll(HOST_CART(e))) {
        char name[NAME_MAX + 1];
        cart_name(e, b->name_ptr(HOST_CART(e)), b->name_len(HOST_CART(e)), name);
        audio_play(name, b->tune ? b->tune(HOST_CART(e)) : 0);
        started = 1;
    }
    sndh_calls(e);
    effects(e);
    return started;
}


/* env.hostAudioStreamStart / hostAudioFeed / hostAudioStreamStop (host/hstream.h): applied at once,
 * mid-frame, as the browser posts them; a feed's bytes are taken now (the cart may reuse its
 * buffer for the next block in the same frame: apps/zig/scenes/stream.zig does). */
void audio_stream_start(struct w2c_env* e, float rate) {
    (void)e;
    audio_fx f = {.op = FX_STREAM_START, .rate = rate > 0.0f ? (uint32_t)(rate + 0.5f) : 0u};
    audio_effects(&f, 1);
}

void audio_stream_feed(struct w2c_env* e, uint32_t ptr, uint32_t len) {
    if (!len) return;
    if ((uint64_t)ptr + len > e->memory.size) {
        printf("ZM FX audioFeed out of the cart's memory\n");
        return;
    }
    audio_fx f = {.op = FX_STREAM_FEED, .pcm = (uintptr_t)(e->memory.data + ptr), .len = len};
    audio_effects(&f, 1);
}

void audio_stream_stop(struct w2c_env* e) {
    (void)e;
    audio_fx f = {.op = FX_STREAM_STOP};
    audio_effects(&f, 1);
}
