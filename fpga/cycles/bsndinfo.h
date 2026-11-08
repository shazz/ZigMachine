/* The music block of the debug mailbox (glass/src/map_cart.zig "the music: who plays it",
 * docs/FPGA_GLASS.md): who runs the players, which player, the song, and what its renders
 * cost, for the glass's debug page. Written only by the CPU that runs the players
 * (cycles/baudio.c: BARD, or ZIGGY in a ZM_AUDIO=1 image), and by cycles/bsound.c when
 * BARD never answered. Each update is bracketed by SI_SEQ going odd then even.
 *
 * Header-only: both firmwares and the sound image include it, and no makefile lists it
 * as a source. The block is the state: nothing here keeps a copy. */
#ifndef ZM_BSNDINFO_H
#define ZM_BSNDINFO_H

#include <stdint.h>
#include <string.h>

#include "glass_cart.h" /* gen/: map_cart.zig's SND_INFO_*, SI_*, ROUTE_*, PLAYER_* */

#ifndef ZM_SND_INFO /* tests/test_snd_info.py points it at an array */
#define ZM_SND_INFO ((volatile uint32_t*)(0x42000000u - SND_INFO_FROM_TOP)) /* the window's end */
#endif

static inline void sndinfo_open(void) { ZM_SND_INFO[SI_SEQ] = ZM_SND_INFO[SI_SEQ] | 1u; }
static inline void sndinfo_close(void) { ZM_SND_INFO[SI_SEQ] = ZM_SND_INFO[SI_SEQ] + 1u; }

static inline void sndinfo_head(uint32_t route, uint32_t player, uint32_t native) {
    ZM_SND_INFO[SI_HEAD] = SND_INFO_VERSION | route << 8 | player << 16 | native << 24;
}

/* At the players' boot (or BARD's silence): a fresh block, no song. */
static inline void sndinfo_boot(uint32_t route) {
    for (uint32_t i = SI_SEQ + 1u; i < SND_INFO_WORDS; i++) ZM_SND_INFO[i] = 0;
    sndinfo_open();
    sndinfo_head(route, PLAYER_NONE, 0);
    ZM_SND_INFO[SI_MAGIC] = SND_INFO_MAGIC;
    sndinfo_close();
}

static inline int sndinfo_ends(const char* s, size_t n, const char* tail) {
    size_t m = strlen(tail);
    return n >= m && strcmp(s + n - m, tail) == 0;
}

/* host/audio.c audio_play's rule: the extension picks the player. */
static inline uint32_t sndinfo_player(const char* name) {
    size_t n = strlen(name);
    if (strcmp(name, "none") == 0) return PLAYER_NONE;
    if (sndinfo_ends(name, n, ".sndh")) return PLAYER_SNDH;
    if (sndinfo_ends(name, n, ".sap")) return PLAYER_SAP;
    if (sndinfo_ends(name, n, ".mod")) return PLAYER_MOD;
    if (sndinfo_ends(name, n, ".xm")) return PLAYER_XM;
    if (sndinfo_ends(name, n, ".ymraw")) return PLAYER_YM;
    if (sndinfo_ends(name, n, ".raw")) return PLAYER_PCM;
    if (sndinfo_ends(name, n, ".hip")) return PLAYER_HIP;
    if (sndinfo_ends(name, n, ".kt")) return PLAYER_KT;
    if (sndinfo_ends(name, n, ".sid")) return PLAYER_SID;
    return PLAYER_UNKNOWN;
}

/* A request: the song, not started yet (sndinfo_started says it did). */
static inline void sndinfo_song(uint32_t route, const char* name, uint32_t tune) {
    uint32_t words[SND_INFO_WORDS - SI_NAME] = {0};
    strncpy((char*)words, name, SND_NAME_MAX);
    sndinfo_open();
    sndinfo_head(route, sndinfo_player(name), 0);
    ZM_SND_INFO[SI_TUNE] = tune;
    for (uint32_t i = SI_FLAGS; i < SI_NAME; i++) ZM_SND_INFO[i] = 0;
    for (uint32_t i = 0; i < SND_INFO_WORDS - SI_NAME; i++) ZM_SND_INFO[SI_NAME + i] = words[i];
    sndinfo_close();
}

/* The player started; `native` is audioSndhNative() for an SNDH, else 0. */
static inline void sndinfo_started(uint32_t native) {
    uint32_t head = ZM_SND_INFO[SI_HEAD];
    sndinfo_open();
    ZM_SND_INFO[SI_HEAD] = (head & 0x00FFFFFFu) | (native & 0xFFu) << 24;
    ZM_SND_INFO[SI_FLAGS] = ZM_SND_INFO[SI_FLAGS] | SIF_STARTED;
    sndinfo_close();
}

/* The cart claimed (held) or released the Paula channels (env.hostPaulaClaim, host/audio_paula.c):
 * the claim stopped every player, and the cart's own register writes play, so the page names
 * that instead of "idle". */
static inline void sndinfo_paula(uint32_t route, int held) {
    sndinfo_song(route, held ? "cart" : "none", 0);
    if (!held) return;
    sndinfo_open();
    sndinfo_head(route, PLAYER_PAULA, 0);
    ZM_SND_INFO[SI_FLAGS] = SIF_STARTED;
    sndinfo_close();
}

/* A cart's MP3 stream started (held) or stopped (env.hostMp3Ctl, host/audio_mp3.c): no file name
 * reaches BARD, so the song is "mp3". Stopped: back to no player. */
static inline void sndinfo_mp3(uint32_t route, int on) {
    sndinfo_song(route, on ? "mp3" : "none", 0);
    if (!on) return;
    sndinfo_open();
    sndinfo_head(route, PLAYER_MP3, 0);
    ZM_SND_INFO[SI_FLAGS] = SIF_STARTED;
    sndinfo_close();
}

/* A zg.requestSndhMode took effect: `mode` (1-3) is the mode now in force (map_cart.zig SIF_MODE_*). */
static inline void sndinfo_mode(uint32_t mode) {
    uint32_t flags = ZM_SND_INFO[SI_FLAGS] & ~(SIF_MODE_MASK << SIF_MODE_SHIFT);
    sndinfo_open();
    ZM_SND_INFO[SI_FLAGS] = flags | (mode & SIF_MODE_MASK) << SIF_MODE_SHIFT;
    sndinfo_close();
}

/* The load now is a window's mean, not one render's cost. A player that works in chunks costs
 * ~80 % on a render that runs a chunk and ~10 % on one that does not (the SID's 1024 samples a
 * chunk against BARD's 735-sample renders; MP3's 1152-sample frames gave 7 % / 470 %), and a
 * reader that samples one render a second (the glass's F11 line) sees the beat between the two:
 * 10 % for ten seconds, then 80 % (Matt, SID TEST, 7 Nov). The window is a second of renders;
 * the ZIGGY and BARD writers (cycles/baudio.c) keep one each. */
#define SND_LOAD_WINDOW 44100u
typedef struct {
    uint32_t cycles, samples; /* the window filling */
    uint32_t load_pm;         /* the last whole window: per mille of a 100 MHz CPU at 44.1 kHz */
} sndinfo_window;

/* One render: `cycles` for `samples`. The peak is the dearest render per sample (cross-multiplied);
 * SI_CYCLES / SI_SAMPLES are the last whole window's sums, published when it fills. */
static inline void sndinfo_render(sndinfo_window* w, uint32_t cycles, uint32_t samples) {
    if (!samples) return;
    uint32_t pc = ZM_SND_INFO[SI_PEAK_CYCLES], ps = ZM_SND_INFO[SI_PEAK_SAMPLES];
    w->cycles += cycles;
    w->samples += samples;
    int full = w->samples >= SND_LOAD_WINDOW, peak = !ps || (uint64_t)cycles * ps > (uint64_t)pc * samples;
    if (!full && !peak) return;
    sndinfo_open();
    if (full) {
        ZM_SND_INFO[SI_CYCLES] = w->cycles;
        ZM_SND_INFO[SI_SAMPLES] = w->samples;
        w->load_pm = w->cycles / w->samples * 441u / 1000u; /* cycles a sample x 44100 / 100 MHz */
        w->cycles = w->samples = 0;
    }
    if (peak) {
        ZM_SND_INFO[SI_PEAK_CYCLES] = cycles;
        ZM_SND_INFO[SI_PEAK_SAMPLES] = samples;
    }
    sndinfo_close();
}

#endif
