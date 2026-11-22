/* The VGM engine where the players are native C's neighbours: BARD (snd.elf), ZIGGY with ZM_AUDIO=1 and the
 * native host. The players' machineVgm* imports (machine/sdk/audio.zig) are answered by libs/c/vgm itself
 * (our own YM2612 + SN76489, included here as one unit), not by the wasm2c of machine-audio.wasm's copy: the
 * same integer C, native, which is what makes it fit BARD (docs/hardware/studies/YM2612_BARD_STUDY.md). The page runs
 * the wasm copy; apps/vgm_check.mjs holds the two to the same samples. */
#include <stdio.h>

#include "../../libs/c/sn76489/sn76489.c"
#include "../../libs/c/vgm/vgm_seq.c"
#include "../../libs/c/vgm/vgm_stream.c"
#include "../../libs/c/vgm/zm_inflate.c"
#include "../../libs/c/vgm/zm_vgm.c"
#include "../../libs/c/vgm/zm_vgm_out.c"
#include "../../libs/c/ym2612/ym2612.c"
#include "../../libs/c/ym2612/ym2612_eg.c"
#include "../../libs/c/ym2612/ym2612_render.c"
#include "haudio.h"

#define AUDIO_MEM_BYTES (48u * 65536u) /* machine/sdk/audio.zig AUDIO_PAGES */

u32 w2c_aud_machineVgmLoad(struct w2c_aud* a, u32 file_abs, u32 len, u32 cap) {
    (void)a;
    uint32_t mem = AUDIO_MEM_BYTES; /* the players' memory: a load past it is a player bug */
    if (file_abs > mem || cap > mem - file_abs || len > cap) return ZM_VGM_SHORT;
    return zm_vgm_load(g_aud.memory.data + file_abs, len, cap);
}

u32 w2c_aud_machineVgmRate(struct w2c_aud* a) {
    (void)a;
    return zm_vgm_rate();
}

void w2c_aud_machineVgmRender(struct w2c_aud* a, u32 dst_abs, u32 n) {
    (void)a;
    if (dst_abs > AUDIO_MEM_BYTES || n > (AUDIO_MEM_BYTES - dst_abs) / 4 || (dst_abs & 1)) return;
    zm_vgm_render((int16_t*)(void*)(g_aud.memory.data + dst_abs), n);
}

void w2c_aud_machineVgmRenderPaula(struct w2c_aud* a, u32 hl, u32 hr, u32 ll, u32 lr, u32 n) {
    (void)a;
    uint32_t at[4] = {hl, hr, ll, lr};
    for (int k = 0; k < 4; k++)
        if (at[k] > AUDIO_MEM_BYTES || n > AUDIO_MEM_BYTES - at[k]) return;
    uint8_t* m = g_aud.memory.data;
    zm_vgm_render_paula((int8_t*)(m + hl), (int8_t*)(m + hr), (int8_t*)(m + ll), (int8_t*)(m + lr), n);
}

/* load_paula's .vgm / .vgz (host/audio.c): play it, or say why not. */
int audio_vgm_load(const char* name, uint32_t len) {
    static const char* const WHY[] = {"", "not a VGM", "no YM2612 or SN76489", "truncated", "a bad or too big .vgz",
                                      "too big for the song RAM"};
    w2c_audio* p = &g_aud.player;
    if (w2c_audio_audioLoadVgm(p, len)) return 1;
    uint32_t st = w2c_audio_audioVgmStatus(p) >> 8 & 0xFFu;
    printf("ZM VGM refused %s: %s\n", name, st < 6 ? WHY[st] : "?");
    return 1;
}
