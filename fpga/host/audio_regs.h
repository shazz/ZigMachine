/* The machine's audio ABI (machine/sdk/audio.zig) as the audio core's register
 * writes (rtl/audio/zm_audio_core.v, docs/FPGA_AUDIO.md "The register map").
 * One encoding for both hosts: the board firmware queues these writes for the
 * RTL (cycles/baudio.c), and the native host logs them next to the machine's own
 * samples (host/audio_soft.c), so the two logs compare word for word.
 *
 * `zma_put(addr, data)` is the backend's: it receives a byte address in the
 * core's 1 KiB register block and the 32-bit value, at the current sample. */
#ifndef ZM_AUDIO_REGS_H
#define ZM_AUDIO_REGS_H

#include <math.h>
#include <stdint.h>

void zma_put(uint32_t addr, uint32_t data);

enum {
    ZMA_YM = 0x000,        /* + 4 r */
    ZMA_CTRL = 0x040,      /* bit 0: machineAudioReset */
    ZMA_CH = 0x100,        /* + 0x40 c + 4 f */
    ZMA_F_DATA = 0, ZMA_F_LEN = 1, ZMA_F_LS = 2, ZMA_F_LL = 3, ZMA_F_STEP = 4,
    ZMA_F_VOL = 5, ZMA_F_PAN = 6, ZMA_F_POS = 7, ZMA_F_CTRL = 8,
    ZMA_CHANNELS = 4,
};

static inline uint32_t zma_ch(uint32_t ch, uint32_t field) { return ZMA_CH + 0x40u * ch + 4u * field; }

/* VOLUME is VOL / 256 (0..511) and PAN is PAN / 128 (-128..128): the forms in
 * which the core's integer mix equals engine.zig's f32 mix exactly. A volume
 * or pan off that grid is rounded to the nearest step (docs/FPGA_AUDIO.md). */
static inline uint32_t zma_vol(float v) {
    float q = v * 256.0f;
    if (!(q > 0.0f)) return 0; /* NaN and negatives: silent */
    return q >= 511.0f ? 511u : (uint32_t)lrintf(q);
}
static inline uint32_t zma_pan(float p) {
    float q = p * 128.0f;
    if (q != q) q = 0.0f;
    long v = q <= -128.0f ? -128 : q >= 128.0f ? 128 : lrintf(q);
    return (uint32_t)v & 0x1FFu;
}

static inline void zma_ym(uint32_t reg, uint32_t val) {
    if (reg < 16) zma_put(ZMA_YM + 4u * reg, val & 0xFFu);
}
static inline void zma_reset(void) { zma_put(ZMA_CTRL, 1u); }

/* machinePaulaTrigger: the staged fields, the pan, then TRIGGER (pos 0, active). */
static inline void zma_trigger(uint32_t ch, uint32_t data, uint32_t len, uint32_t ls, uint32_t ll, float pan) {
    if (ch >= ZMA_CHANNELS) return;
    zma_put(zma_ch(ch, ZMA_F_DATA), data);
    zma_put(zma_ch(ch, ZMA_F_LEN), len);
    zma_put(zma_ch(ch, ZMA_F_LS), ls);
    zma_put(zma_ch(ch, ZMA_F_LL), ll);
    zma_put(zma_ch(ch, ZMA_F_PAN), zma_pan(pan));
    zma_put(zma_ch(ch, ZMA_F_CTRL), 2u);
}
static inline void zma_field(uint32_t ch, uint32_t field, uint32_t v) {
    if (ch < ZMA_CHANNELS) zma_put(zma_ch(ch, field), v);
}

/* machineAudioInit: engine.init()'s channel defaults (volume 1, pan 0, step 0,
 * pos 0, stopped) plus the chip reset; the core starts from its own reset. */
static inline void zma_init(void) {
    zma_reset();
    for (uint32_t c = 0; c < ZMA_CHANNELS; c++) {
        zma_field(c, ZMA_F_VOL, 256u);
        zma_field(c, ZMA_F_PAN, 0u);
        zma_field(c, ZMA_F_STEP, 0u);
        zma_field(c, ZMA_F_POS, 0u);
    }
}

#endif
