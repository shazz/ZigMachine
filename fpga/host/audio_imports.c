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
 * either again; the SAP player renders the POKEY up to each write's sample. */
#include <string.h>

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

/* The YM registers as the players last wrote them: the machine's engine.ym.regs, which the
 * worklet mirrors into the cart (machine-audio.wasm is not on the board to hold them, the
 * audio core is). Read by cycles/aud_state.h's publisher; stored only when a value changes,
 * so a digi player's kHz volume writes cost a compare, not a DDR store. */
uint8_t zma_ym_regs[16];
static void ym_regs_clear(void) { memset(zma_ym_regs, 0, sizeof zma_ym_regs); } /* engine.init */
static void ym_regs_reset(void) { /* machine_audio.zig machineAudioReset: the mixer off, A..C silent */
    zma_ym_regs[7] = 0x3F;
    zma_ym_regs[8] = zma_ym_regs[9] = zma_ym_regs[10] = 0;
}

uint32_t zma_ts(void) { return g_pos; }
void zma_set_ts(uint32_t t) { g_base = g_pos = t; }

static void rendered(uint32_t off, uint32_t len) {
    uint32_t end = g_base + off + len;
    if ((int32_t)(end - g_pos) > 0) g_pos = end;
}

wasm_rt_memory_t* w2c_aud_memory(struct w2c_aud* a) { return &a->memory; }

void w2c_aud_machineAudioInit(struct w2c_aud* a) { (void)a; zma_init(); ym_regs_clear(); SOFT(w2c_maud_machineAudioInit(&g_maud)); }
void w2c_aud_machineAudioReset(struct w2c_aud* a) { (void)a; zma_reset(); ym_regs_reset(); SOFT(w2c_maud_machineAudioReset(&g_maud)); }
void w2c_aud_machinePaulaClearScopes(struct w2c_aud* a) { (void)a; SOFT(w2c_maud_machinePaulaClearScopes(&g_maud)); }
void w2c_aud_machineClear(struct w2c_aud* a, u32 n) { (void)a; SOFT(w2c_maud_machineClear(&g_maud, n)); (void)n; }
void w2c_aud_machineClamp(struct w2c_aud* a, u32 n) { (void)a; SOFT(w2c_maud_machineClamp(&g_maud, n)); (void)n; }

void w2c_aud_machineRenderYm(struct w2c_aud* a, u32 off, u32 len) {
    (void)a;
    SOFT(w2c_maud_machineRenderYm(&g_maud, off, len));
    rendered(off, len);
}

void w2c_aud_machineRenderPokey(struct w2c_aud* a, u32 off, u32 len) {
    (void)a;
    SOFT(w2c_maud_machineRenderPokey(&g_maud, off, len));
    rendered(off, len);
}

void w2c_aud_machinePokeyWrite(struct w2c_aud* a, u32 reg, u32 val) {
    (void)a;
    zma_pokey(reg, val);
    SOFT(w2c_maud_machinePokeyWrite(&g_maud, reg, val));
}

void w2c_aud_machinePokeyClock(struct w2c_aud* a, u32 pal) {
    (void)a;
    zma_put(ZMA_POKEY_CLOCK, pal ? 1u : 0u);
    SOFT(w2c_maud_machinePokeyClock(&g_maud, pal));
}

void w2c_aud_machineMixPaula(struct w2c_aud* a, u32 off, u32 len) {
    (void)a;
    SOFT(w2c_maud_machineMixPaula(&g_maud, off, len));
    rendered(off, len);
}

void w2c_aud_machineYmWrite(struct w2c_aud* a, u32 reg, u32 val) {
    (void)a;
    zma_ym(reg, val);
    if (zma_ym_regs[reg & 15u] != (uint8_t)val) zma_ym_regs[reg & 15u] = (uint8_t)val; /* ym.zig writeReg */
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
