/* The sound CPU's board layer: its stdout is the console ring in DDR that the cart CPU
 * prints from (cycles/snd_mailbox.h SND_LOG_*), and its end is S_DONE, since only the
 * cart CPU reaches the sim's finish register. With ZM_SND_PUTC each character also goes
 * to PUTC, the sim's $write (soc/zm_sound_regs.py): for a sound CPU that never gets as far
 * as the cart's printing. */
#include <stdio.h>

#include "board.h"
#include "snd_mailbox.h"
#include "sound.h"

static uint32_t g_log; /* bytes written, as S_LOG */

static int ring_putc(char c, FILE* f) {
    (void)f;
    ((volatile char*)SND_LOG_ADDR)[g_log % SND_LOG_BYTES] = c;
    g_log++;
    if (c == '\n') SND_REG(SND_S2C + S_LOG) = g_log; /* whole lines only: the cart prints lines */
#ifdef ZM_SND_PUTC
    SND_REG(SND_PUTC) = (uint8_t)c;
#endif
    return (uint8_t)c;
}

static FILE g_ring = FDEV_SETUP_STREAM(ring_putc, NULL, NULL, _FDEV_SETUP_WRITE);
FILE* const stdin = &g_ring;
FILE* const stdout = &g_ring;
FILE* const stderr = &g_ring;

void sound_finish(int code) {
    printf("ZM SND END %d\n", code);
    SND_REG(SND_S2C + S_DONE) = (uint32_t)code + 1u;
    for (;;) {
    }
}

/* trap.c's end, and picolibc's exit() (main returning, abort, wasm2c's abort()). */
void board_finish(int code) { sound_finish(code); }
void _exit(int code) { sound_finish(code); }
