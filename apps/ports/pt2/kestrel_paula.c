/* Paula for KESTREL: upstream's pt2_paula.c API (the replayer, the sampler and the editor write the
 * same AUDx registers) with an integer mixer, built INSTEAD of pt2_paula.c (Makefile).
 *
 * Why: upstream mixes in double (phase/delta per voice per sample) with BLEP synthesis, the A500/A1200
 * RC filters and a 2x-oversampled float path with dither. ZIGGY has an f32 FPU but no f64: on the
 * board that cost ~5,500 cycles a 48 kHz sample (pt2 fell from 28 to 10-13 fps while a module played;
 * apps/frame_cost.mjs agrees), so real-time audio was out of reach at any rate. Through the machine's
 * 8-bit mono stream the BLEP's alias suppression and the dither are inaudible.
 *
 * What is kept: Paula's DMA behaviour as upstream models it (AUDxLEN/AUDxLC latched at the DMA
 * restart, the period refetched once a sample, the 2-byte AUD_DAT buffer, period 0 = 65536, minimum
 * 113), the A500's 4.4 kHz RC low-pass (the default A1200 has none above hearing) and the "LED"
 * filter (E0x), both in fixed point. What is dropped: BLEP (output is point-sampled: several Paula
 * samples a mix sample are stepped over, so pitch stays right at any output rate) and the ~5 Hz
 * high-pass (DC removal, inaudible). Output is MONO, written to both channels of the S16 stream:
 * KESTREL's stream is mono, so panning would be summed away anyway. */
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>
#include "pt2_header.h"
#include "pt2_audio.h"
#include "pt2_paula.h"

#define PHASE_BITS 24 /* phase and delta: Q8.24 Paula samples per mix sample */
#define PHASE_ONE (1u << PHASE_BITS)
#define COEF_BITS 15  /* filter coefficients, Q15 */

typedef struct {
    bool active, sampleJustStarted, fetch; /* fetch: the first sample is owed (DMA just started) */
    int8_t AUD_DAT[2];
    const int8_t *location;
    uint16_t lengthCounter;
    int32_t sampleCounter;
    int32_t sample;        /* AUD_DAT[0] * volume: -8192..8128 */
    uint32_t phase, delta; /* Q8.24 */
    const int8_t *storedLocation;
    uint16_t storedLength;
    int32_t storedVol;     /* 0..64 */
    uint32_t storedDelta;
} kvoice_t;

/* KESTREL: samples are capped at 13312 bytes (pt2_config.c.sed), so Paula reads the null buffer for
 * at most that long; upstream sizes it for 0xFFFF words. */
static int8_t nullSample[0x4000 * 2];
static kvoice_t paula[PAULA_VOICES];
static uint64_t deltaDiv; /* PAULA_PAL_CLK / output rate, Q8.24 */
static bool useLowpass, useLED;
static int32_t lpA, lpState;                 /* one-pole: y += a * (x - y), state Q8 */
static int32_t ledA1, ledA2, ledB1, ledB2;   /* two-pole, Q15 */
static int32_t ledIn1, ledIn2, ledOut1, ledOut2;

/* Init only (a table, once per rate): double is fine here. */
void paulaSetup(double dOutputFreq, uint32_t amigaModel)
{
    ASSERT(dOutputFreq != 0.0);
    deltaDiv = (uint64_t)(PAULA_PAL_CLK / dOutputFreq * (double)PHASE_ONE);

    /* A500 rev 6A: R=360 ohm, C=0.1 uF -> ~4421 Hz (upstream's paulaSetup). The A1200's is ~34 kHz. */
    useLowpass = amigaModel == MODEL_A500;
    const double lpCut = 1.0 / ((2.0 * PI) * 360.0 * 1e-7);
    lpA = (int32_t)((1.0 - exp((-2.0 * PI) * fmin(lpCut, dOutputFreq / 2.0 - 1e-4) / dOutputFreq)) * (1 << COEF_BITS));
    lpState = 0;

    /* The "LED" 2-pole Sallen-Key, same values on both models: ~3091 Hz, Q ~0.66 (rcfilters' formula). */
    const double R1 = 10000.0, R2 = 10000.0, C1 = 6.8e-9, C2 = 3.9e-9;
    double cut = 1.0 / ((2.0 * PI) * sqrt(R1 * R2 * C1 * C2));
    const double q = sqrt(R1 * R2 * C1 * C2) / (C2 * (R1 + R2));
    if (cut >= dOutputFreq / 2.0) cut = dOutputFreq / 2.0 - 1e-4;
    const double a = 1.0 / tan((PI * cut) / dOutputFreq), r = 1.0 / q;
    const double a1 = 1.0 / (1.0 + r * a + a * a);
    ledA1 = (int32_t)lround(a1 * (1 << COEF_BITS));
    ledA2 = (int32_t)lround(2.0 * a1 * (1 << COEF_BITS));
    ledB1 = (int32_t)lround(2.0 * (1.0 - a * a) * a1 * (1 << COEF_BITS));
    ledB2 = (int32_t)lround((1.0 - r * a + a * a) * a1 * (1 << COEF_BITS));
    ledIn1 = ledIn2 = ledOut1 = ledOut2 = 0;
}

void paulaDisableFilters(void) { useLowpass = false; } /* upstream keeps the LED filter too */

int8_t *paulaGetNullSamplePtr(void) { return nullSample; }

void clearBlepState(void) {} /* no BLEP */

/* One Paula sample step: the DMA fetch when AUD_DAT is empty, then the next sample point. */
static void nextSample(kvoice_t *v)
{
    if (v->sampleCounter == 0) {
        if (!v->sampleJustStarted && --v->lengthCounter == 0) { /* AUDxLEN/AUDxLC latched on DMA restart */
            v->lengthCounter = v->storedLength;
            v->location = v->storedLocation;
        }
        v->sampleJustStarted = false;
        v->AUD_DAT[0] = *v->location++;
        v->AUD_DAT[1] = *v->location++;
        v->sampleCounter = 2;
    }
    v->sample = v->AUD_DAT[0] * v->storedVol; /* AUDxVOL is read here, as upstream */
    v->AUD_DAT[0] = v->AUD_DAT[1];
    v->sampleCounter--;
}

static void audxper(int32_t ch, uint16_t period)
{
    uint32_t p = period == 0 ? 65536u : period < 113 ? 113u : period;
    paula[ch].storedDelta = (uint32_t)(deltaDiv / p); /* used from the next period refetch */
}

static void audxvol(int32_t ch, uint16_t vol)
{
    int32_t v = vol & 127;
    paula[ch].storedVol = v > 64 ? 64 : v;
}

static void startDMA(int32_t ch)
{
    kvoice_t *v = &paula[ch];
    if (v->storedLocation == NULL) v->storedLocation = nullSample;
    v->location = v->storedLocation;
    v->lengthCounter = v->storedLength;
    v->sampleCounter = 0;
    v->sampleJustStarted = true;
    v->delta = v->storedDelta;
    v->phase = 0;
    v->fetch = true; /* fetched at the next mix sample, as upstream (after the tick's AUDxVOL write) */
    v->active = true;
}

void paulaWriteByte(uint32_t address, uint8_t data8)
{
    if (address != 0xBFE001) return; /* CIA-A: the "LED" filter bit only */
    bool on = (data8 & 2) != 0;
    if (on != useLED) ledIn1 = ledIn2 = ledOut1 = ledOut2 = 0;
    useLED = on;
}

void paulaWriteWord(uint32_t address, uint16_t data16)
{
    if (address == 0xDFF096) { /* DMACON */
        for (int32_t ch = 0; ch < PAULA_VOICES; ch++) {
            if (!(data16 & (1u << ch))) continue;
            if (data16 & 0x8000) startDMA(ch); else paula[ch].active = false;
        }
        return;
    }
    if (address < 0xDFF0A0 || address > 0xDFF0DF) return;
    int32_t ch = (int32_t)((address - 0xDFF0A0) >> 4);
    switch (address & 15) {
    case 4: paula[ch].storedLength = data16; break;
    case 6: audxper(ch, data16); break;
    case 8: audxvol(ch, data16); break;
    default: break;
    }
}

void paulaWritePtr(uint32_t address, const int8_t *ptr)
{
    if (address < 0xDFF0A0 || address > 0xDFF0DF || (address & 15) != 0) return;
    paula[(address - 0xDFF0A0) >> 4].storedLocation = ptr ? ptr : nullSample;
}

/* Add one voice into mix[0..n): point-sampled, every Paula sample the phase passes is stepped. */
static void mixVoice(kvoice_t *v, int32_t *mix, int32_t n)
{
    if (v->fetch) { v->fetch = false; nextSample(v); }
    int32_t s = v->sample;
    uint32_t phase = v->phase, delta = v->delta;
    for (int32_t j = 0; j < n; j++) {
        mix[j] += s;
        phase += delta;
        while (phase >= PHASE_ONE) { /* a period refetch: the new period, then the next sample */
            phase -= PHASE_ONE;
            delta = v->storedDelta;
            v->delta = delta;
            nextSample(v);
            s = v->sample;
        }
    }
    v->phase = phase;
}

static int32_t filter(int32_t x)
{
    if (useLowpass) {
        lpState += (int32_t)(((int64_t)((x << 8) - lpState) * lpA) >> COEF_BITS);
        x = lpState >> 8;
    }
    if (useLED) {
        int64_t acc = (int64_t)ledA1 * (x + ledIn2) + (int64_t)ledA2 * ledIn1 - (int64_t)ledB1 * ledOut1 - (int64_t)ledB2 * ledOut2;
        int32_t y = (int32_t)(acc >> COEF_BITS);
        ledIn2 = ledIn1; ledIn1 = x; ledOut2 = ledOut1; ledOut1 = y;
        x = y;
    }
    return x;
}

#define CHUNK 256

/* Mono mix of n samples into mix[] at the setup rate, with the Amiga filters: upstream's level, as
 * the (L+R)/2 of its output (each voice at +-1.0 x AUDIO_GAIN 2 x 32768/4 on its side). */
static void mixBlock(int32_t *mix, int32_t n)
{
    memset(mix, 0, (size_t)n * sizeof *mix);
    for (int32_t i = 0; i < PAULA_VOICES; i++) {
        kvoice_t *v = &paula[i];
        if (v->active && v->location != NULL && v->storedLocation != NULL) mixVoice(v, mix, n);
    }
    for (int32_t j = 0; j < n; j++) mix[j] = filter(mix[j]);
}

/* pt2_audio.c's outputAudio (pt2_audio.c.sed): n S16 stereo frames, the mono mix on both sides. */
void kestrel_paulaOutput(int16_t *target, int32_t numSamples)
{
    int32_t mix[CHUNK];
    while (numSamples > 0) {
        int32_t n = numSamples < CHUNK ? numSamples : CHUNK;
        mixBlock(mix, n);
        for (int32_t j = 0; j < n; j++) {
            int32_t m = mix[j];
            int16_t s = (int16_t)(m > INT16_MAX ? INT16_MAX : m < INT16_MIN ? INT16_MIN : m);
            *target++ = s;
            *target++ = s;
        }
        numSamples -= n;
    }
}

/* PAT2SMP's path (pt2_pat2smp.c): the same mix as float, on both channels (-4.0..4.0 as upstream). */
void paulaGenerateSamples(float *fOutL, float *fOutR, int32_t numSamples)
{
    int32_t mix[CHUNK];
    while (numSamples > 0) {
        int32_t n = numSamples < CHUNK ? numSamples : CHUNK;
        mixBlock(mix, n);
        for (int32_t j = 0; j < n; j++) *fOutL++ = *fOutR++ = (float)mix[j] * (1.0f / (64.0f * 128.0f));
        numSamples -= n;
    }
}
