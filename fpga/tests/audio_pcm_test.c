/* host/audio_pcm.c on its own (tests/test_audio_pcm.py): the stream ring as the players see it,
 * their memory a plain buffer, audioStreamStart / audioStreamStop recorded. Prints one line per
 * check, "ok <name>" or "FAIL <name>: <why>". */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "haudio.h"

#define SONG 0x200000u
#define RING 32768u
#define CUSHION 4096u

struct w2c_aud g_aud;
static int g_starts, g_stops;
static float g_rate;
u32 w2c_audio_audioSongPtr(w2c_audio* p) { (void)p; return SONG; }
void w2c_audio_audioStreamStart(w2c_audio* p, f32 rate) { (void)p, g_starts++, g_rate = rate; }
void w2c_audio_audioStreamStop(w2c_audio* p) { (void)p, g_stops++; }

static int g_bad;
static void check(int ok, const char* name, const char* why) {
    printf(ok ? "ok %s\n" : "FAIL %s: %s\n", name, why);
    g_bad += !ok;
}
static uint8_t* ring(void) { return g_aud.memory.data + SONG; }
static void fx(uint8_t op, const uint8_t* pcm, uint32_t len, uint32_t rate, uint8_t a) {
    audio_fx f = {.op = op, .a = a, .pcm = (uintptr_t)pcm, .len = len, .rate = rate};
    if (!audio_pcm_effect(&f)) check(0, "effect", "an FX_SAMPLE / FX_STREAM op was not taken");
}
static void reset(void) {
    memset(ring(), 0xEE, RING);
    fx(FX_STREAM_STOP, NULL, 0, 0, 0);
    g_starts = g_stops = 0;
}

int main(void) {
    g_aud.memory.data = calloc(1, SONG + RING);
    static uint8_t smp[10000], big[100000];
    for (uint32_t i = 0; i < sizeof smp; i++) smp[i] = (uint8_t)(i * 7 + 1);
    for (uint32_t i = 0; i < sizeof big; i++) big[i] = (uint8_t)(i * 13 + 5);

    reset(); /* a one-shot: CUSHION written at once, then ahead of the channel, then silence, then off */
    fx(FX_SAMPLE, smp, sizeof smp, 22050, 0);
    check(g_starts == 1 && g_rate == 22050.0f, "sample_starts_the_ring", "audioStreamStart(22050) not called once");
    check(!memcmp(ring(), smp, CUSHION) && ring()[CUSHION] == 0xEE, "cushion_at_once", "not exactly CUSHION bytes");
    audio_pcm_refill(4000); /* 22050 Hz: 2000 bytes read */
    check(!memcmp(ring(), smp, 2000 + CUSHION) && ring()[2000 + CUSHION] == 0xEE, "refill_ahead", "not read + CUSHION");
    audio_pcm_refill(12000); /* 8000 read: past the end, silence after it */
    check(!memcmp(ring(), smp, sizeof smp) && ring()[sizeof smp] == 0 && ring()[12095] == 0,
          "silence_after_a_one_shot", "the ring past the sample is not silent");
    check(g_stops == 0, "plays_to_its_end", "stopped before the channel read it all");
    audio_pcm_refill(4002); /* 10001 read: all of it */
    check(g_stops == 1, "off_at_its_end", "the channel was not stopped once the sample was read");
    audio_pcm_refill(44100);
    check(g_stops == 1, "nothing_after_the_end", "refilled or stopped again after the end");

    reset(); /* a looped sample longer than the ring: wraps in the sample and in the ring */
    fx(FX_SAMPLE, big, sizeof big, 44100, 1);
    for (int i = 0; i < 300; i++) audio_pcm_refill(1000); /* 300000 read: three laps of the sample */
    uint32_t w = (300000u + CUSHION) % RING, at = (300000u + CUSHION - 1) % sizeof big;
    check(ring()[(w + RING - 1) % RING] == big[at] && g_stops == 0, "loop_wraps", "the newest byte is not the sample's");

    reset(); /* the cart's feed: appended at the cursor, wrapping; a sample is not refilled after it */
    fx(FX_SAMPLE, smp, sizeof smp, 22050, 1);
    fx(FX_STREAM_START, NULL, 0, 10000, 0);
    fx(FX_STREAM_FEED, big, RING - 100, 0, 0);
    fx(FX_STREAM_FEED, big + 50000, 300, 0, 0);
    check(!memcmp(ring(), big + 50000 + 100, 200) && !memcmp(ring() + RING - 100, big + 50000, 100),
          "feed_wraps", "the second feed did not wrap at the ring's end");
    audio_pcm_refill(44100);
    check(!memcmp(ring(), big + 50100, 200), "feed_owns_the_ring", "a sample refilled over a stream");

    reset(); /* error paths: an empty sample plays nothing; a stop with none playing does nothing */
    fx(FX_SAMPLE, smp, 0, 22050, 0);
    fx(FX_SAMPLE_STOP, NULL, 0, 0, 0);
    check(g_starts == 0 && g_stops == 0 && ring()[0] == 0xEE, "empty_and_idle_stop", "something played or stopped");
    fx(FX_SAMPLE, smp, sizeof smp, 22050, 1);
    audio_pcm_forget(); /* a song took song RAM */
    memset(ring(), 0xEE, RING);
    audio_pcm_refill(44100);
    uint32_t touched = 0;
    for (uint32_t i = 0; i < RING; i++) touched += ring()[i] != 0xEE;
    check(touched == 0, "forget_stops_refilling", "the ring was written over the song");
    audio_fx other = {.op = FX_PLAY};
    check(!audio_pcm_effect(&other), "not_its_op", "took an sfxPlay");
    return g_bad != 0;
}
