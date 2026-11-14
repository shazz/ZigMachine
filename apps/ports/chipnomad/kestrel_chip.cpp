// ChipNomad's AY chips on BARD (README "AY on BARD"): every register write the tracker makes goes on the BARD
// queue (kestrel_bard.cpp) stamped with its sample on the queue's 44.1 kHz clock, and BARD renders the chips
// (libs/c/ayumi, the same integer model as the cart's own, kestrel_ayumi.cpp). The cart still runs ChipNomad's
// audio callback for its clock (its ticks happen inside it) but renders nothing and feeds nothing.
//
// The chips are upstream's SoundChipAY (its registers stay the tracker's view: the pitch-conflict check reads
// them) with three overrides, made by ChipNomad's own chip factory (patches/chipnomad_lib.cpp.sed):
//   setRegister   also posted, at the write's sample: the callback's position x 2 (the cart runs 22050 Hz)
//   render        on BARD: the project's clock, type, pans and mix gain posted when they change; silence here
//   setTimerFunc  a software oscillator (AY2 PWM, sync, samples) steps per chip tick inside the model: it has no
//                 register stream, so the whole cart goes back to ZIGGY (the stream and BARD's queue cannot play at
//                 once) until its chips are made again (a project load)
// BARD is the default when the host answers the queue (asked for the first 60 frames, the stream quiet meanwhile);
// no answer, or a build with KESTREL_AY_ON_ZIGGY=1, renders on ZIGGY as before.
#include <string.h>
#include "common.h"
#include "kestrel_audio.h"
#include "kestrel_bard.h"

extern "C" void kestrel_log(const char *m);

#ifndef KESTREL_AY_ON_ZIGGY
#define KESTREL_AY_ON_ZIGGY 0
#endif
#define AY_ADDR 0xA000u
#define LEAD 6144u   // ~139 ms: a slow board frame and BARD's render, as SID-WIZARD's
#define TRIES 60
#define RATE_MUL 2u  // 44100 / the cart's 22050 (kestrel_main.cpp)

class KestrelChipAY;
static KestrelChipAY *chips[PROJECT_MAX_CHIPS];
static int on_bard, soft, tries;
static uint32_t pos, seg; // samples the callback finished, and how far into the one it is in

static uint32_t stamp() { return (pos + seg) * RATE_MUL; }
static void post(int chip, unsigned reg, uint32_t v) { kestrel_bq_push(stamp(), AY_ADDR + chip * 16u + reg, v); }

// ChipNomad's setPanning, as k / 200 (pan = 0.5 -/+ separation / 200): the pans BARD's table holds
static uint32_t pans(const ChipSetupAY &a)
{
    int s = a.stereoSeparation > 100 ? 100 : a.stereoSeparation, k[3] = {100, 100, 100};
    switch (a.stereoMode) {
    case StereoModeAY::ABC: k[0] = 100 - s; k[2] = 100 + s; break;
    case StereoModeAY::ACB: k[0] = 100 - s; k[1] = 100 + s; break;
    case StereoModeAY::BAC: k[1] = 100 - s; k[2] = 100 + s; break;
    }
    return (uint32_t)k[0] | (uint32_t)k[1] << 8 | (uint32_t)k[2] << 16 | 1u << 24; // equal-power
}

class KestrelChipAY : public SoundChipAY {
    int idx;
    unsigned written; // registers the tracker has written: a fresh chip on BARD is the cart's own model, the rest unset
    uint32_t sent_cfg, sent_pan, sent_gain;
public:
    KestrelChipAY(int i, int rate, ChipSetup s) : SoundChipAY(rate, s), idx(i), written(0) { forget(); chips[i] = this; }
    ~KestrelChipAY() override
    {
        if (chips[idx] == this) chips[idx] = nullptr;
        if (on_bard) post(idx, 14, 0); // no clock: BARD's chip off
    }
    void forget() { sent_cfg = sent_pan = sent_gain = 0xFFFFFFFFu; }
    // The project's set-up, posted when it changes. A configure is a fresh chip on BARD: the registers written so
    // far follow (only those: a register never written, e.g. the noise period, is not 0 in the model but unset).
    void sync()
    {
        const ChipSetupAY &a = chipnomadState->project.chipSetup.ay;
        uint32_t cfg = ((uint32_t)a.clock & 0xFFFFFFu) | (a.isYM ? 1u << 24 : 0);
        if (cfg != sent_cfg) {
            post(idx, 14, cfg);
            for (unsigned r = 0; r <= 13; r++) if (written >> r & 1) post(idx, r, getRegister((uint16_t)r));
            sent_cfg = cfg; sent_pan = sent_gain = 0xFFFFFFFFu;
        }
        uint32_t p = pans(a), g = (uint32_t)(0.6f * chipnomadState->mixVolume * 32768.0f + 0.5f); // chip_ay.cpp's ayVolumeScale
        if (p != sent_pan) { post(idx, 15, p); sent_pan = p; }
        if (g != sent_gain) { kestrel_bq_push(stamp(), AY_ADDR + 0x80u + (uint32_t)idx, g > 65535 ? 65535 : g); sent_gain = g; }
    }
    void setRegister(uint16_t reg, uint8_t value) override
    {
        SoundChipAY::setRegister(reg, value);
        if (reg <= 13) written |= 1u << reg;
        if (on_bard && reg <= 13 && sent_cfg != 0xFFFFFFFFu) post(idx, reg, value);
    }
    void setTimerFunc(int (*f)(SoundChip *self, void *ud), void *ud) override;
    void render(float *buffer, int samples) override
    {
        if (on_bard) { sync(); memset(buffer, 0, (size_t)samples * 2 * sizeof(float)); }
        else SoundChipAY::render(buffer, samples);
        if (idx == 0) seg += (uint32_t)samples; // the segment's writes came before it, the next segment's after
    }
};

static void to_ziggy(const char *why)
{
    if (!on_bard) return;
    kestrel_bq_close();
    on_bard = 0;
    kestrel_audio_quiet(0); // the next pump starts the stream (after the close: the stream stops the queue's player)
    kestrel_log(why);
}

void KestrelChipAY::setTimerFunc(int (*f)(SoundChip *self, void *ud), void *ud)
{
    SoundChipAY::setTimerFunc(f, ud);
    if (f && !soft) { soft = 1; to_ziggy("chipnomad: a software oscillator: the AY renders on ZIGGY"); }
}

// ChipNomad's chip factory (chipnomad_lib.cpp's defaultChipFactory, patched): a new set of chips may use BARD again.
SoundChip *kestrel_chip_ay(int index, int sampleRate, ChipSetup setup)
{
    soft = 0;
    return new KestrelChipAY(index, sampleRate, setup);
}

// Once a frame, before the audio pump: the queue asked for, the events let go.
extern "C" void kestrel_ay_frame(void)
{
    kestrel_bq_frame();
    if (KESTREL_AY_ON_ZIGGY || on_bard || soft || tries > TRIES) return;
    if (tries++ == 0) kestrel_audio_quiet(1); // nothing fed while the queue is asked for
    if (kestrel_bq_open(LEAD)) {
        on_bard = 1;
        for (KestrelChipAY *c : chips) if (c) { c->forget(); c->sync(); }
        kestrel_log("chipnomad: the AY plays on the sound side (BARD queue)");
    } else if (tries > TRIES) {
        kestrel_audio_quiet(0);
        kestrel_log("chipnomad: no BARD queue: the AY renders on ZIGGY");
    }
}

// Around each run of the audio callback: its writes are stamped from where it starts.
extern "C" void kestrel_ay_block(uint32_t frames, int done)
{
    if (done) pos += frames;
    seg = 0;
}
