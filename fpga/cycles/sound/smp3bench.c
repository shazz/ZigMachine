/* snd-bench's MP3 mode (make snd-bench SONG=<file>.MP3 MUSIC=<dir> SND_MP3=1): the song image is an
 * .mp3, streamed into the MP3 player (libs/zig/players/mp3.zig) the way a cart streams it, so each
 * timed frame is the real player loop on BARD: the feed effects (host/audio_mp3.c), then the render
 * (pvmp3 through wasm2c, the Paula bytes). The feeds keep the player's ring under 64 KiB, as the MP3
 * PLAYER cart does from audioMp3Status(1). Prints "MP3 <frame> <status word> <frames decoded>" too. */
#include <stdio.h>
#include <string.h>

#include "baudio.h"
#include "haudio.h"
#include "smp3bench.h"

#define RING (64u * 1024u)
#define FEED (32u * 1024u)

static const uint8_t* g_img; /* the song image as linked (tools/song_pack.py's zm_songs): no copy */
static uint32_t g_len, g_fed;

void mp3_bench_start(const char* song) {
    for (const zm_song* s = zm_songs; s->name; s++)
        if (strcmp(s->name, song) == 0) g_img = s->data, g_len = s->len;
    if (!g_img) printf("ZM SONG MISSING %s\n", song);
    g_fed = 0;
    audio_fx f = {.op = FX_MP3_CTL, .a = 0};
    audio_effects(&f, 1);
    mp3_bench_feed();
}

void mp3_bench_feed(void) {
    uint32_t used = w2c_audio_audioMp3Status(&g_aud.player, 1);
    uint32_t room = RING - (g_fed - used), n = g_len - g_fed;
    if (n > room) n = room;
    if (n > FEED) n = FEED;
    if (n) {
        audio_fx f = {.op = FX_MP3_FEED, .pcm = (uintptr_t)(g_img + g_fed), .len = n};
        audio_effects(&f, 1);
        g_fed += n;
    }
    if (g_fed == g_len && g_len) {
        audio_fx e = {.op = FX_MP3_CTL, .a = 3};
        audio_effects(&e, 1);
    }
}

void mp3_bench_report(int frame) {
    printf("MP3 %d %08lx %lu\n", frame, (unsigned long)w2c_audio_audioMp3Status(&g_aud.player, 0),
           (unsigned long)w2c_audio_audioMp3Status(&g_aud.player, 2));
}
