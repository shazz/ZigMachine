/* The cart's song bridge (haudio.h audio_bridge): docs/sealed-loader.js's
 * playSongByName / sndhCallByName, read off the cart after its frame. It calls
 * audio_play and audio_sndh_call, which the players implement (host/audio.c) or,
 * with the players on the sound CPU, the mailbox forwards (cycles/bsound.c). */
#include <string.h>

#include "haudio.h"

#define NAME_MAX 64u /* libs/zig/zigos.zig g_song_name */

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
    uint32_t n = b->sndh_poll ? b->sndh_poll(&e->cart) : 0;
    if (!n) return;
    char name[NAME_MAX + 1];
    cart_name(e, b->sndh_name_ptr(&e->cart), b->sndh_name_len(&e->cart), name);
    if (!ends_with(name, ".sndh") || strstr(name, "..") || name[0] == '/') return;
    for (uint32_t i = 0; i < n; i++) {
        uint32_t d0 = b->sndh_d0(&e->cart, i);
        audio_sndh_call(name, d0);
    }
}

int audio_bridge(struct w2c_env* e) {
    const host_song_bridge* b = &host_songs;
    int started = 0;
    if (b->poll && b->poll(&e->cart)) {
        char name[NAME_MAX + 1];
        cart_name(e, b->name_ptr(&e->cart), b->name_len(&e->cart), name);
        audio_play(name, b->tune ? b->tune(&e->cart) : 0);
        started = 1;
    }
    sndh_calls(e);
    return started;
}

