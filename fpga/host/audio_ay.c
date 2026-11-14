/* The AY engine where the players are native C's neighbours: BARD (snd.elf), ZIGGY with ZM_AUDIO=1 and the
 * native host. The players' machineAy* imports (machine/sdk/audio.zig) are answered by libs/c/ayumi itself
 * (zm_ay_bank.c, included here as one unit), not by the wasm2c of machine-audio.wasm's copy: the same integer
 * C, native. The page runs the wasm copy; apps/chipnomad_bard_check.mjs holds the two to the same samples. */
#include "../../libs/c/ayumi/zm_ay.c"
#include "../../libs/c/ayumi/zm_ay_cfg.c"
#include "../../libs/c/ayumi/zm_ay_bank.c"
#include "haudio.h"

#define AUDIO_MEM_BYTES (48u * 65536u) /* machine/sdk/audio.zig AUDIO_PAGES */

void w2c_aud_machineAyReset(struct w2c_aud* a) {
    (void)a;
    zm_ay_bank_reset();
}

u32 w2c_aud_machineAyWrite(struct w2c_aud* a, u32 at, u32 value) {
    (void)a;
    return zm_ay_bank_write(at, value) != 0;
}

void w2c_aud_machineAyRender(struct w2c_aud* a, u32 dst_abs, u32 n) {
    (void)a;
    if (dst_abs > AUDIO_MEM_BYTES || n > (AUDIO_MEM_BYTES - dst_abs) / 4 || (dst_abs & 1)) return;
    zm_ay_bank_render((int16_t*)(void*)(g_aud.memory.data + dst_abs), n);
}
