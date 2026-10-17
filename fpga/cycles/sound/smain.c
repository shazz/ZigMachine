/* The sound CPU's firmware (soc/zm_sound_cpu.py, docs/FPGA_SOUND_CPU.md): the machine's
 * players (demo-audio.wasm through wasm2c, host/audio.c) into the audio core's write
 * queue (cycles/baudio.c), paced by the core's own sample counter and nothing else.
 *
 *   default        the cart CPU's mailbox commands (cycles/snd_mailbox.h, sent by
 *                  cycles/bsound.c): PLAY and SNDH_CALL, the song's bytes in the cart's image;
 *                  EFFECTS, the cart's sfx / ymWrite / requestModVolume / requestSndhMode
 *   ZM_SND_BENCH   no cart: ZM_SONG (linked in, cycles/bsongs.c) starts at once, then
 *                  ZM_FRAMES frames of 735 samples, each timed ("F frame cycles" and the
 *                  bus waits, as cycles/baudio_bench.c prints on the cart CPU), then the end
 *
 * Between commands it renders whenever a frame's worth (735 samples) is due, so the
 * sound stays a full lead (cycles/baudio.c ZMA_LATENCY) ahead of the core. */
#include <stdio.h>
#include <string.h>

#include "baudio.h"
#include "haudio.h"
#include "snd_mailbox.h"
#include "sound.h"
#include "trap.h"
#include "wasm-rt-exceptions.h"
#include "wasm-rt-impl.h"

#define FRAME 735u /* samples in a 60 Hz frame */
#define S2C(w) SND_REG(SND_S2C + (w))
#define C2S(w) SND_REG(SND_C2S + (w))

static void timed_pump(void) {
    uint32_t ts = zma_ts(), t0 = SND_REG(SND_CYCLES);
    baudio_pump(FRAME);
    if (zma_ts() == ts) return;
    uint32_t spent = SND_REG(SND_CYCLES) - t0;
    S2C(S_RENDERS) = S2C(S_RENDERS) + 1;
    S2C(S_RENDER_CYCLES) = spent;
    if (spent > S2C(S_RENDER_MAX)) S2C(S_RENDER_MAX) = spent;
    S2C(S_PUSHED) = baudio.pushed;
    S2C(S_RESYNCS) = baudio.resyncs;
    S2C(S_ANCHORS) = baudio.anchors;
}

#ifdef ZM_SND_BENCH
const host_song_bridge host_songs = {0}; /* host.h wants one; nothing polls it here */

static void run(void) {
    #define ZMA_NOW (*(volatile uint32_t*)0x92000008u) /* soc/zm_audio_soc.py AUDIO_WINDOW, word 2 */
    uint32_t t0 = SND_REG(SND_CYCLES);
    audio_play(ZM_SONG, ZM_TUNE);
#ifdef ZM_SND_MODE /* make snd-bench SND_MODE=3: zg.requestSndhMode before the first frame */
    printf("MODE asked %d got %lu\n", ZM_SND_MODE, (unsigned long)w2c_audio_audioSndhMode(&g_aud.player, ZM_SND_MODE));
#endif
    printf("LOAD %lu\n", (unsigned long)(SND_REG(SND_CYCLES) - t0));
    for (int f = 0; f < ZM_FRAMES; f++) {
        while ((int32_t)(zma_ts() - ZMA_NOW) > (int32_t)(2940u - FRAME)) {
        }
        uint32_t c0 = SND_REG(SND_CYCLES), i0 = SND_REG(SND_IBUS_WAIT), d0 = SND_REG(SND_DBUS_WAIT);
        audio_render(FRAME);
        printf("F %d %lu\nFW %d %lu %lu\n", f, (unsigned long)(SND_REG(SND_CYCLES) - c0), f,
               (unsigned long)(SND_REG(SND_IBUS_WAIT) - i0), (unsigned long)(SND_REG(SND_DBUS_WAIT) - d0));
    }
    baudio_report();
    sound_finish(0);
}
#else
static const uint8_t* g_song;
static int32_t g_song_len;

/* haudio.h's song store: the file the current command names, from the cart's image. */
int32_t audio_song(const char* name, uint8_t* dst, uint32_t cap) {
    if (g_song_len < 0) {
        printf("ZM SONG MISSING %s\n", name);
        return -1;
    }
    uint32_t n = (uint32_t)g_song_len < cap ? (uint32_t)g_song_len : cap;
    memcpy(dst, g_song, n);
    return (int32_t)n;
}

/* VexRiscv: invalidate the write-through D-cache (vboard.h zmv_flush_dcache), so a play's bytes
 * are read from DDR, not from a line an earlier effect left at the same address. */
static inline void flush_dcache(void) { __asm__ volatile(".word(0x500F)\n" ::: "memory"); }

/* OP_EFFECTS: the cart's frame of effects (cycles/bsound.c), applied as host/audio.c applies them. */
static void effects(uint32_t n) {
    audio_fx fx[C_FX_MAX];
    if (n > C_FX_MAX) {
        printf("ZM SND bad effects %lu\n", (unsigned long)n);
        return;
    }
    for (uint32_t i = 0; i < n; i++) {
        uint32_t w0 = C2S(C_FX + C_FX_WORDS * i);
        fx[i] = (audio_fx){.op = (uint8_t)w0, .a = (uint8_t)(w0 >> 8), .b = (uint8_t)(w0 >> 16),
                           .pcm = C2S(C_FX + C_FX_WORDS * i + 1), .len = C2S(C_FX + C_FX_WORDS * i + 2),
                           .rate = C2S(C_FX + C_FX_WORDS * i + 3)};
    }
    flush_dcache();
    audio_effects(fx, n);
}

static void command(void) {
    uint32_t op = C2S(C_OP), arg = C2S(C_ARG);
    if (op == OP_EFFECTS) {
        effects(arg);
        return;
    }
    uint32_t words[C_NAME_WORDS + 1] = {0};
    for (uint32_t i = 0; i < C_NAME_WORDS; i++) words[i] = C2S(C_NAME + i);
    const char* name = (const char*)words;
    g_song = (const uint8_t*)(uintptr_t)C2S(C_PTR);
    g_song_len = (int32_t)C2S(C_LEN);
    if (op == OP_PLAY) audio_play(name, arg);
    else if (op == OP_SNDH_CALL) audio_sndh_call(name, arg);
    else printf("ZM SND bad op %lu\n", (unsigned long)op);
}

static void run(void) {
    uint32_t last = C2S(C_SEQ);
    for (;;) {
        uint32_t seq = C2S(C_SEQ);
        if (seq != last) {
            command();
            last = seq;
            S2C(S_ACK) = seq;
        }
        timed_pump();
    }
}
#endif

int main(void) {
    trap_install();
    wasm_rt_init();
    if (wasm_rt_impl_try()) {
        printf("ZM WASMTRAP\n");
        sound_finish(1);
    }
    baudio_boot();
    S2C(S_ACK) = C2S(C_SEQ); /* the boot's nonce (cycles/bsound.c): this side is up */
    S2C(S_READY) = S_READY_VALUE;
    run();
    return 0;
}
