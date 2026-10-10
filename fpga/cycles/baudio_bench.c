/* The players alone on the board SoC (soc/hp_sim.py), into the real write queue: what
 * one song costs the cart CPU, with no cart (cycles/audio.mk `audio-bench`). The song
 * starts, then 735 samples (a 60 Hz frame) are rendered a frame, each frame waiting
 * first (untimed) until the sound is a full lead behind, as cycles/baudio.c paces it.
 * Lines: "LOAD cycles" (the song's load and start), "F frame cycles", then "FC frame" and the
 * frame's delta of every ZMCycles counter (soc/zm_cycles.py COUNTERS: cycles, ibus_ack, ibus_wait,
 * dbus_rd, dbus_wr, dbus_wait), where the CPU's time went, and "ZM AUD ...". */
#include <stdio.h>

#include "baudio.h"
#include "board.h"
#include "haudio.h"
#include "trap.h"
#include "wasm-rt-exceptions.h"
#include "wasm-rt-impl.h"

#define ZMA_NOW (*(volatile uint32_t*)0x92000008u) /* soc/zm_audio_soc.py AUDIO_WINDOW, word 2 */
#define LEAD 2940u                                  /* cycles/baudio.c ZMA_LATENCY */
#define FRAME 735u

const host_song_bridge host_songs = {0}; /* no cart: the song is started by name */

int main(void) {
    trap_install();
    wasm_rt_init();
    if (wasm_rt_impl_try()) {
        printf("ZM WASMTRAP\n");
        board_finish(1);
    }
    baudio_boot();
    uint32_t t0 = board_cycles();
    audio_play(ZM_SONG, ZM_TUNE);
    printf("LOAD %lu\n", (unsigned long)(board_cycles() - t0));
    for (int f = 0; f < ZM_FRAMES; f++) {
        while ((int32_t)(zma_ts() - ZMA_NOW) > (int32_t)(LEAD - FRAME)) {
        }
        uint32_t c0[ZM_NCOUNT], c1[ZM_NCOUNT];
        board_counters(c0);
        t0 = board_cycles();
        audio_render(FRAME);
        uint32_t spent = board_cycles() - t0;
        board_counters(c1);
        printf("F %d %lu\nFC %d", f, (unsigned long)spent, f);
        for (int i = 0; i < ZM_NCOUNT; i++) printf(" %lu", (unsigned long)(c1[i] - c0[i]));
        printf("\n");
    }
    baudio_report();
    board_finish(0);
}
