/* pt2's Paula on the machine's four HARDWARE Paula channels (HW 1.14.0, decisions.md 2026-11-02
 * "Paula channels for carts"): the replayer's register writes go to the host as they are, Amiga
 * addresses and all, stamped with the sample they were made at; the audio side plays them (in the
 * browser the worklet, on the board BARD into the PCM core). No mixing on the cart CPU.
 *
 * kestrel_paula.c keeps its software mixer and forwards every write here too: while the hardware
 * holds the channels its mix is skipped (kpaula_hw_block), and it still renders PAT2SMP / MOD2WAV
 * (offline, never forwarded). When the claim fails (a host with no audio side, an older machine)
 * the software path plays, as before.
 *
 * Chip RAM: the machine's channels read their own 1 MiB, never the cart's RAM, so a sample is
 * UPLOADED there (hostPaulaUpload) when a voice is about to play a region not yet copied: at the DMA
 * start, and when a playing voice gets an LC/LEN outside what it has (a loop elsewhere, a sample
 * swap, a 9xx offset's loop). song->sampleData (33 x maxSampleLength) maps 1:1 at chip offset 0;
 * any other pointer (the null sample) maps to chip RAM's never-written zeros at NULL_OFF. An edit
 * to a sample a voice is looping is heard at its next trigger. */
#include <stdint.h>
#include <stdbool.h>
#include "pt2_header.h"
#include "pt2_structs.h"
#include "pt2_config.h"
#include "pt2_paula.h"

__attribute__((import_module("env"), import_name("hostPaulaClaim"))) extern uint32_t hostPaulaClaim(uint32_t lead);
__attribute__((import_module("env"), import_name("hostPaulaUpload"))) extern void hostPaulaUpload(const void *src, uint32_t off, uint32_t len);
__attribute__((import_module("env"), import_name("hostPaulaWrite"))) extern void hostPaulaWrite(const void *entries, uint32_t n);
void kestrel_audio_quiet(int on); /* kestrel_sdl2 kestrel_audio.c: no stream while the hardware plays */

#define OUT_HZ 44100u
#define LEAD_MS 125u            /* kestrel_sdl.c AUDIO_LEAD_MS: the latency pt2 delays its visuals by */
#define CHIP 0x100000u          /* the machine's chip RAM (song RAM) */
#define NULL_OFF 0xE0000u       /* 128 KB of zeros at the top: no LEN reaches past it */
#define BATCH 256u
#define DONE_MAX 16u            /* regions uploaded since the last flush, not sent twice */

typedef struct { uint32_t t, addr, value, pad; } kentry;
typedef struct { const int8_t *lc; uint16_t len; bool dirty; const int8_t *lo, *hi; } kvhw; /* lo..hi: uploaded */

static int state;               /* 0 not tried, 1 the hardware plays, -1 software */
static uint32_t rate = 24000;   /* pt2's output rate (paulaSetup) */
static uint64_t clock;          /* samples output at `rate` since the claim */
static kentry buf[BATCH];
static uint32_t nbuf;
static uint16_t dmacon;
static kvhw v[PAULA_VOICES];
static const int8_t *done_lo[DONE_MAX], *done_hi[DONE_MAX];
static uint32_t ndone;

void kpaula_hw_rate(double hz) { if (!editor.pat2SmpOngoing && !editor.mod2WavOngoing) rate = (uint32_t)hz; }

static uint32_t now44(void) { return (uint32_t)(clock * OUT_HZ / rate); }

static void flush(void);

static void put(uint32_t addr, uint32_t value)
{
    if (nbuf == BATCH) flush();
    buf[nbuf++] = (kentry){now44(), addr, value, 0};
}

static uint32_t pool(void) { return (uint32_t)(MOD_SAMPLES + 2) * (uint32_t)config.maxSampleLength; }

static bool in_pool(const int8_t *p) { return song && p >= song->sampleData && p < song->sampleData + pool(); }

/* The voice's next region (LC, LEN words) into chip RAM, unless it already is. */
static void upload(kvhw *c)
{
    const int8_t *lo = c->lc, *hi = c->lc + (c->len ? c->len : 0x10000u) * 2u;
    if (!in_pool(lo)) return; /* the null sample: zeros already */
    if (hi > song->sampleData + pool()) hi = song->sampleData + pool();
    if (lo >= c->lo && hi <= c->hi) return;
    c->lo = lo, c->hi = hi;
    for (uint32_t i = 0; i < ndone; i++) if (lo >= done_lo[i] && hi <= done_hi[i]) return;
    hostPaulaUpload(lo, (uint32_t)(lo - song->sampleData), (uint32_t)(hi - lo));
    if (ndone < DONE_MAX) done_lo[ndone] = lo, done_hi[ndone++] = hi;
}

/* The batch out, after the uploads it needs: a playing voice whose LC/LEN changed (its next loop, a
 * sample swap) gets that region now, once both halves are written (pt2 writes LC, then LEN). */
static void flush(void)
{
    for (uint32_t ch = 0; ch < PAULA_VOICES; ch++)
        if (v[ch].dirty && (dmacon & (1u << ch))) v[ch].dirty = false, upload(&v[ch]);
    if (nbuf) hostPaulaWrite(buf, nbuf);
    nbuf = 0;
    ndone = 0;
}

static bool forwarded(void) { return state == 1 && !editor.pat2SmpOngoing && !editor.mod2WavOngoing; }

/* The stereo the replayer's mixer would give (pt2_audio.c: mid/side by stereoSeparation), on the
 * machine's pan law (one side full, the other 1 + pan): LRRL, -128..128. */
static int32_t pans_sep = -1; /* the separation the pans were sent for */
static void set_pans(void)
{
    int32_t sep = config.stereoSeparation < 0 ? 0 : config.stereoSeparation > 100 ? 100 : config.stereoSeparation;
    if (sep == pans_sep) return;
    pans_sep = sep;
    int32_t p = 256 * sep / (100 + sep);
    for (uint32_t ch = 0; ch < PAULA_VOICES; ch++) put(0xDFF0AC + 16 * ch, (uint16_t)(ch == 0 || ch == 3 ? -p : p));
}

void kpaula_hw_word(uint32_t address, uint16_t data16)
{
    if (!forwarded()) return;
    if (address == 0xDFF096) {
        for (uint32_t ch = 0; ch < PAULA_VOICES; ch++)
            if ((data16 & 0x8000) && (data16 & (1u << ch)) && !(dmacon & (1u << ch))) /* DMA start: what it latches */
                v[ch].lo = v[ch].hi = NULL, v[ch].dirty = false, upload(&v[ch]);
        dmacon = data16 & 0x8000 ? dmacon | (data16 & 15) : dmacon & ~(data16 & 15);
    } else if (address >= 0xDFF0A0 && address <= 0xDFF0DF && (address & 15) == 4) {
        kvhw *c = &v[(address - 0xDFF0A0) >> 4];
        c->len = data16;
        c->dirty = true;
    }
    put(address, data16);
}

void kpaula_hw_ptr(uint32_t address, const int8_t *ptr)
{
    if (!forwarded() || address < 0xDFF0A0 || address > 0xDFF0DF || (address & 15) != 0) return;
    uint32_t ch = (address - 0xDFF0A0) >> 4;
    v[ch].lc = ptr;
    v[ch].dirty = true;
    uint32_t off = in_pool(ptr) ? (uint32_t)(ptr - song->sampleData) : NULL_OFF;
    put(address, off >> 16);         /* AUDxLCH */
    put(address + 2, off & 0xFFFE);  /* AUDxLCL */
}

/* kestrel_paulaOutput's first move: claim the channels once, then the block's writes go out and the
 * clock moves on by the block. True: the hardware plays it (the caller outputs silence). */
bool kpaula_hw_block(int32_t numSamples)
{
    if (state == 0) {
        state = (uint64_t)pool() <= NULL_OFF && hostPaulaClaim(OUT_HZ * LEAD_MS / 1000u) ? 1 : -1;
        if (state > 0) kestrel_audio_quiet(1); /* the claim already silenced the ring: the loader's state */
    }
    if (state < 0) return false;
    set_pans(); /* at the claim, and when the separation is changed (CONFIG) */
    flush();
    clock += (uint64_t)numSamples;
    return true;
}
