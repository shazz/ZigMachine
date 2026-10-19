/* The sound CPU's register block as both firmwares see it (soc/zm_sound_regs.py, at
 * SOUND_WINDOW in both address maps), and the command protocol over its mailbox
 * (docs/FPGA_SOUND_CPU.md "Mailbox").
 *
 * One command at a time: the cart CPU (cycles/bsound.c) waits until ACK equals the last
 * SEQ it posted, writes the command's words, then SEQ last (a new value). The sound CPU
 * (cycles/sound/smain.c) runs it and writes ACK = SEQ. A command names a song the cart's
 * image holds: PTR/LEN are its bytes in DDR (the shared window), read by the sound CPU,
 * whose D-cache has never seen them (it only reads its own memory before). */
#ifndef ZM_SND_MAILBOX_H
#define ZM_SND_MAILBOX_H

#include <stdint.h>

#define SND_WINDOW 0x93000000u /* soc/zm_sound_cpu.py SOUND_WINDOW */
#define SND_REG(w) (*(volatile uint32_t*)(SND_WINDOW + 4u * (w)))
#define SND_BASE 0x40E00000u /* soc/zm_sound_cpu.py SOUND_BASE: the sound image, its reset vector */
#define SND_IMAGE_MAX 0x00200000u /* up to the cart's data at 16 MiB (cycles/sound.mk checks it) */
/* The sound CPU's console: a byte ring in DDR, under the debug mailbox page (bmailbox.h). The
 * sound CPU appends and counts (S_LOG); the cart CPU prints whole lines from it between frames,
 * so the two consoles never interleave inside a line. */
#define SND_LOG_ADDR 0x41FEF000u
#define SND_LOG_BYTES 0x10000u

/* soc/zm_sound_regs.py: word indexes. */
enum { SND_C2S = 0, SND_S2C = 32, SND_CTRL = 64, SND_CYCLES = 65, SND_IBUS_WAIT = 66, SND_DBUS_WAIT = 67,
       SND_PUTC = 68, SND_ID = 69 };
#define SND_ID_VALUE 0x5A4D5343u /* 'ZMSC' */
#define SND_RUN 1u

/* C2S: the command. */
enum { C_SEQ = 0, C_OP = 1, C_ARG = 2, C_PTR = 3, C_LEN = 4, C_NAME = 8 };
#define C_NAME_WORDS 16u /* 64 bytes, NUL-padded: libs/zig/zigos.zig g_song_name's 64 */
enum { OP_PLAY = 1, OP_SNDH_CALL = 2, OP_EFFECTS = 3 };
/* OP_EFFECTS: ARG effects (haudio.h audio_fx, libs/zig/sfx_queue.zig), C_FX_WORDS words each
 * from C_FX, over the name's words (the command has none): op | a << 8 | b << 16, the PCM's
 * address in DDR (a play's bytes, the cart's memory), len, rate. A frame's queue goes over in
 * as many commands as it needs, in its order. */
enum { C_FX = 8, C_FX_WORDS = 4 };
#define C_FX_MAX ((32u - C_FX) / C_FX_WORDS) /* 6 a command */

/* S2C: the answer and the sound CPU's counters (the cart prints them in the sim's report). */
enum { S_ACK = 0, S_READY = 1, S_PUSHED = 2, S_APPLIED = 3, S_STATUS = 4, S_RESYNCS = 5, S_ANCHORS = 6,
       S_RENDERS = 7, S_RENDER_CYCLES = 8, S_RENDER_MAX = 9, S_LOG = 10, S_DONE = 11 };
/* S_DONE: 0 while the sound firmware runs, else its exit code + 1 (the bench's end, a trap).
 * S2C[12..18]: the players' audio state for the cart's mirror (cycles/aud_state.h S_AS). */
#define S_READY_VALUE 0x52534D5Au /* 'ZMSR': the sound firmware is up and polling */

#endif
