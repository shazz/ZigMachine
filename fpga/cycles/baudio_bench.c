/* The players alone on the board SoC (soc/hp_sim.py), into the real write queue: what
 * one song costs the cart CPU, with no cart (cycles/audio.mk `audio-bench`). The song
 * starts, then 735 samples (a 60 Hz frame) are rendered a frame, each frame waiting
 * first (untimed) until the sound is a full lead behind, as cycles/baudio.c paces it.
 * Lines: "LOAD cycles" (the song's load and start), "F frame cycles", "ZM AUD ...". */
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
        t0 = board_cycles();
        audio_render(FRAME);
        printf("F %d %lu\n", f, (unsigned long)(board_cycles() - t0));
    }
    baudio_report();
    board_finish(0);
}
