/* The players' `machine*` imports (machine/sdk/audio.zig): each chip call
 * becomes the audio core's register writes (audio_regs.h), stamped with the
 * sample it lands before. With ZM_AUDIO_SOFT (the native host) each call also
 * reaches the machine's own chips (machine-audio.wasm), the reference.
 *
 * The stamp: a player renders a block in pieces, machineRenderYm(off, len) and
 * machineMixPaula(off, len), and changes the chips between them. A change made
 * after the piece ending at sample `off + len` of the block is heard from that
 * sample on, so the stamp is the end of the latest piece rendered (the block's
 * start before any). That is exact for the players here: the SNDH player and
 * the MOD player render the YM and Paula over the same piece before changing
 * either again. */
#include "haudio.h"
#include "audio_regs.h"

#ifdef ZM_AUDIO_SOFT
#include "maud.h"
extern w2c_maud g_maud;
#define SOFT(call) (call)
#else
#define SOFT(call) ((void)0)
#endif

static uint32_t g_base, g_pos; /* the block's first sample; the stamp */

uint32_t zma_ts(void) { return g_pos; }
void zma_set_ts(uint32_t t) { g_base = g_pos = t; }

static void rendered(uint32_t off, uint32_t len) {
    uint32_t end = g_base + off + len;
    if ((int32_t)(end - g_pos) > 0) g_pos = end;
}

wasm_rt_memory_t* w2c_aud_memory(struct w2c_aud* a) { return &a->memory; }

void w2c_aud_machineAudioInit(struct w2c_aud* a) { (void)a; zma_init(); SOFT(w2c_maud_machineAudioInit(&g_maud)); }
void w2c_aud_machineAudioReset(struct w2c_aud* a) { (void)a; zma_reset(); SOFT(w2c_maud_machineAudioReset(&g_maud)); }
void w2c_aud_machinePaulaClearScopes(struct w2c_aud* a) { (void)a; SOFT(w2c_maud_machinePaulaClearScopes(&g_maud)); }
void w2c_aud_machineClear(struct w2c_aud* a, u32 n) { (void)a; SOFT(w2c_maud_machineClear(&g_maud, n)); (void)n; }
void w2c_aud_machineClamp(struct w2c_aud* a, u32 n) { (void)a; SOFT(w2c_maud_machineClamp(&g_maud, n)); (void)n; }

void w2c_aud_machineRenderYm(struct w2c_aud* a, u32 off, u32 len) {
    (void)a;
    SOFT(w2c_maud_machineRenderYm(&g_maud, off, len));
    rendered(off, len);
}

void w2c_aud_machineMixPaula(struct w2c_aud* a, u32 off, u32 len) {
    (void)a;
    SOFT(w2c_maud_machineMixPaula(&g_maud, off, len));
    rendered(off, len);
}

void w2c_aud_machineYmWrite(struct w2c_aud* a, u32 reg, u32 val) {
    (void)a;
    zma_ym(reg, val);
    SOFT(w2c_maud_machineYmWrite(&g_maud, reg, val));
}

void w2c_aud_machinePaulaTrigger(struct w2c_aud* a, u32 ch, u32 data, u32 len, u32 ls, u32 ll, f32 pan) {
    (void)a;
    zma_trigger(ch, data, len, ls, ll, pan);
    SOFT(w2c_maud_machinePaulaTrigger(&g_maud, ch, data, len, ls, ll, pan));
}

void w2c_aud_machinePaulaSetStep(struct w2c_aud* a, u32 ch, u32 step) {
    (void)a;
    zma_field(ch, ZMA_F_STEP, step);
    SOFT(w2c_maud_machinePaulaSetStep(&g_maud, ch, step));
}

void w2c_aud_machinePaulaSetVolume(struct w2c_aud* a, u32 ch, f32 vol) {
    (void)a;
    zma_field(ch, ZMA_F_VOL, zma_vol(vol));
    SOFT(w2c_maud_machinePaulaSetVolume(&g_maud, ch, vol));
}

void w2c_aud_machinePaulaSetPan(struct w2c_aud* a, u32 ch, f32 pan) {
    (void)a;
    zma_field(ch, ZMA_F_PAN, zma_pan(pan));
    SOFT(w2c_maud_machinePaulaSetPan(&g_maud, ch, pan));
}

void w2c_aud_machinePaulaSetPos(struct w2c_aud* a, u32 ch, u32 pos) {
    (void)a;
    zma_field(ch, ZMA_F_POS, pos & 0xFFFFFFu);
    SOFT(w2c_maud_machinePaulaSetPos(&g_maud, ch, pos));
}

void w2c_aud_machinePaulaSetActive(struct w2c_aud* a, u32 ch, u32 on) {
    (void)a;
    zma_field(ch, ZMA_F_CTRL, on ? 1u : 0u);
    SOFT(w2c_maud_machinePaulaSetActive(&g_maud, ch, on));
}
