/* The SID engine's door (libs/c/crsid/README.md): load a .sid, render its PCM. The same C runs on
 * BARD (native, fpga/host/audio_sid.c) and in machine-audio.wasm (the page's reference,
 * machine/audio/sid.zig), so the two render the same samples. */
#ifndef ZM_SID_H
#define ZM_SID_H

#include <stdint.h>

#define ZM_SID_RATE 22050u /* mono, the light engine; the player converts it to the mixer's 44.1 kHz */

/* zm_sid_load's answers (the player's status word carries them: libs/zig/players/sid.zig). */
enum {
    ZM_SID_OK = 0,
    ZM_SID_NOT_SID = 1, /* no PSID/RSID magic, or cRSID refused the header */
    ZM_SID_RSID = 2,    /* a real C64 program (RSID): not supported (BARD cannot run it, ~2x its budget) */
    ZM_SID_SHORT = 3,   /* shorter than its header, or longer than a C64 */
};

/* Load the `len` bytes at `file` (kept: cRSID reads its header while it plays) and start subtune
 * `subtune` (1-based, 0 = the file's default). Every load starts from a fresh C64. */
uint32_t zm_sid_load(uint8_t *file, uint32_t len, uint32_t subtune);

/* The next `n` samples (s16 mono at ZM_SID_RATE) into `dst`; silence when nothing is loaded. */
void zm_sid_render(int16_t *dst, uint32_t n);

#endif
