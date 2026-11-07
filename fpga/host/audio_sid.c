/* The SID engine where the players are native C's neighbours: BARD (snd.elf), ZIGGY with
 * ZM_AUDIO=1 and the native host. The players' machineSidLoad / machineSidRender imports
 * (machine/sdk/audio.zig) are answered here by cRSID itself (host/crsid.c: libs/c/crsid/zm_sid.c on the patched
 * tree fpga/build/crsid from libs/c/crsid/patch.sh), not by the wasm2c of machine-audio.wasm's
 * copy: the same integer C, native, which is what makes it fit BARD (fpga/review/SID_BARD_STUDY.md).
 * The page runs the wasm copy; apps/sid_check.mjs holds the two to the same samples.
 * On BARD host/crsid.c is built -march=rv32im -mno-div (cycles/sound.mk): GCC then turns cRSID's
 * constant divides into multiplies instead of calls to the core's 400-cycle __divsi3. */
#include <stdio.h>

#include "../../libs/c/crsid/zm_sid.h"
#include "haudio.h"

#define AUDIO_MEM_BYTES (48u * 65536u) /* machine/sdk/audio.zig AUDIO_PAGES */

u32 w2c_aud_machineSidLoad(struct w2c_aud* a, u32 file_abs, u32 len, u32 subtune) {
    (void)a;
    uint32_t cap = AUDIO_MEM_BYTES; /* the players' memory: a load past it is a player bug */
    if (file_abs > cap || len > cap - file_abs) return ZM_SID_SHORT;
    return zm_sid_load(g_aud.memory.data + file_abs, len, subtune);
}

void w2c_aud_machineSidRender(struct w2c_aud* a, u32 dst_abs, u32 n) {
    (void)a;
    if (dst_abs > AUDIO_MEM_BYTES || n > (AUDIO_MEM_BYTES - dst_abs) / 2 || (dst_abs & 1)) return;
    zm_sid_render((int16_t*)(void*)(g_aud.memory.data + dst_abs), n);
}

/* load_paula's .sid (host/audio.c): play it, or say why not (PSID only, as the page says it). */
int audio_sid_load(const char* name, uint32_t len, uint32_t tune) {
    static const char* const WHY[] = {"", "not a .sid", "RSID not supported", "bad length"};
    w2c_audio* p = &g_aud.player;
    if (w2c_audio_audioLoadSid(p, len, tune)) return 1;
    uint32_t st = w2c_audio_audioSidStatus(p) >> 8 & 0xFFu;
    printf("ZM SID refused %s: %s\n", name, st < 4 ? WHY[st] : "?");
    return 1;
}
