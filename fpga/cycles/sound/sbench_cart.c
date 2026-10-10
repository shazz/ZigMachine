/* The sound bench's cart side (cycles/sound.mk snd-bench): no cart and no players here.
 * Start the bench image on the sound CPU (cycles/bsound.c), print its console until it
 * ends (S_DONE), then end the sim with its code. */
#include <stdio.h>

#include "baudio.h"
#include "board.h"
#include "haudio.h"
#include "snd_mailbox.h"
#include "trap.h"

const zm_song zm_songs[] = {{0, 0, 0}}; /* the bench's song is in the sound image */
const host_song_bridge host_songs = {0};

int main(void) {
    trap_install();
    baudio_boot();
    if (!baudio.on) board_finish(2);
    while (!SND_REG(SND_S2C + S_DONE)) baudio_report_log();
    baudio_report_log();
    board_finish((int)SND_REG(SND_S2C + S_DONE) - 1);
}
