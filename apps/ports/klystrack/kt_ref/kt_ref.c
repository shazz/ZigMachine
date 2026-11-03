/* kt_ref: upstream klystron (cyd + music.c, untouched, from ../../upstream) renders a .kt song
 * natively, as klystrack's own WAV export does (src/export.c): the reference the BARD player
 * (libs/zig/players/kt*.zig) is measured against, and the per-feature profile of a song.
 *
 *   kt_ref <song.kt> <seconds> [--rate R] [--oversample N] [--raw out.s16] [--features] [--chorus upstream]
 *
 * As the klystrack cart plays a song (apps/ports/klystrack): cyd reserves the song's channels
 * (mused.c set_channels; export.c reserves all 32, which the four examples render the same with),
 * and the chorus LUT is the cart's integer one (kestrel_chorus.c, +-1/256 sample of upstream's
 * double sin(); --chorus upstream keeps upstream's). Defaults: 22050 Hz, no oversampling (the
 * cart's mused.c.sed / cyd.c.sed).
 * --raw writes interleaved stereo s16le; --features prints what the song's gated voices use,
 * counted once a tick (waveforms, filter, FX bus effects, ring/sync/FM, wavetable). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "snd/music.h"

static MusEngine mus;
static CydEngine cyd;
static MusSong song;
static CydWavetableEntry waves[CYD_WAVE_MAX_ENTRIES];

void kestrel_chorus_lut(Sint32 *lut, int n, int min_delay, int max_delay, int rate, int wrap); /* ../kestrel_chorus.c */

/* cydchr_set's LUT again, the cart's way (patches/cydchr.c.sed): the same entries, no double sin(). */
static void kestrel_chorus(void) {
    for (int i = 0; i < CYD_MAX_FX_CHANNELS; i++) {
        CydChorus *c = &cyd.fx[i].chr;
        if (c->lut_size) kestrel_chorus_lut(c->lut, c->lut_size, c->min_delay, c->max_delay, c->sample_rate, c->buf_size * 256);
    }
}

static struct {
    unsigned ticks, gated_ticks[33], flag_ticks[16], flt_ticks[3], max_gated;
    unsigned fx_ticks[CYD_MAX_FX_CHANNELS];
} st;

static const char *const FLAG_NAMES[16] = {"noise", "pulse", "triangle", "saw", "sync", "gate", "keysync", "metal",
                                           "ring", "filter", "fx", "ym_env", "wave", "wave_ovr_env", "lfsr", "fm"};

static int tick(void *udata) {
    int r = mus_advance_tick(udata);
    unsigned g = 0;
    st.ticks++;
    for (int i = 0; i < cyd.n_channels; i++) {
        CydChannel *c = &cyd.channel[i];
        if (!(c->flags & CYD_CHN_ENABLE_GATE)) continue;
        g++;
        for (int b = 0; b < 16; b++) if (c->flags >> b & 1) st.flag_ticks[b]++;
        if (c->flags & CYD_CHN_ENABLE_FILTER) st.flt_ticks[c->flttype % 3]++;
        if (c->flags & CYD_CHN_ENABLE_FX) st.fx_ticks[c->fx_bus & 7]++;
    }
    st.gated_ticks[g]++;
    if (g > st.max_gated) st.max_gated = g;
    return r;
}

static int version;

static void features(void) {
    printf("version %d; song: %d channels, rate %d Hz, speed %d/%d, length %d, %d instruments, master vol %d, flags %#x\n",
           version, song.num_channels, song.song_rate, song.song_speed, song.song_speed2, song.song_length,
           song.num_instruments, song.master_volume, song.flags);
    printf("ticks %u, gated voices max %u; ticks with N gated:", st.ticks, st.max_gated);
    for (int g = 0; g <= 32; g++) if (st.gated_ticks[g]) printf(" %d:%u", g, st.gated_ticks[g]);
    printf("\nvoice-ticks with flag:");
    for (int b = 0; b < 16; b++) if (st.flag_ticks[b]) printf(" %s:%u", FLAG_NAMES[b], st.flag_ticks[b]);
    printf("\nfilter lp/hp/bp: %u/%u/%u\n", st.flt_ticks[0], st.flt_ticks[1], st.flt_ticks[2]);
    for (int i = 0; i < CYD_MAX_FX_CHANNELS; i++) {
        CydFxSerialized *f = &song.fx[i];
        if (!st.fx_ticks[i] && !f->flags) continue;
        printf("fx bus %d: voice-ticks %u, chorus %d reverb %d crush %d; taps:", i, st.fx_ticks[i],
               !!(f->flags & CYDFX_ENABLE_CHORUS), !!(f->flags & CYDFX_ENABLE_REVERB),
               !!(f->flags & CYDFX_ENABLE_CRUSH));
        for (int t = 0; t < CYDRVB_TAPS; t++)
            if (f->rvb.tap[t].gain > CYDRVB_LOW_LIMIT) printf(" %d/%d", f->rvb.tap[t].delay, f->rvb.tap[t].gain);
        printf("\n");
    }
    int nw = 0;
    for (int i = 0; i < CYD_WAVE_MAX_ENTRIES; i++) if (waves[i].data) nw++;
    printf("wavetable entries: %d\n", nw);
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: kt_ref <song.kt> <seconds> [--rate R] [--oversample N] [--raw out] [--features]\n");
        return 2;
    }
    int rate = 22050, over = 0, feat = 0, up_chorus = 0;
    const char *raw = NULL;
    for (int i = 3; i < argc; i++) {
        if (!strcmp(argv[i], "--rate") && i + 1 < argc) rate = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--oversample") && i + 1 < argc) over = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--raw") && i + 1 < argc) raw = argv[++i];
        else if (!strcmp(argv[i], "--features")) feat = 1;
        else if (!strcmp(argv[i], "--chorus") && i + 1 < argc) up_chorus = !strcmp(argv[++i], "upstream");
    }
    if (!mus_load_song(argv[1], &song, waves)) {
        fprintf(stderr, "kt_ref: %s refused\n", argv[1]);
        return 1;
    }
    FILE *f = fopen(argv[1], "rb");
    if (f) {
        fseek(f, 8, SEEK_SET);
        version = fgetc(f);
        fclose(f);
    }
    cyd_init(&cyd, rate, song.num_channels);
    cyd.flags |= CYD_SINGLE_THREAD;
    cyd_set_oversampling(&cyd, over);
    mus_init_engine(&mus, &cyd);
    mus.volume = song.master_volume;
    mus_set_fx(&mus, &song);
    if (!up_chorus) kestrel_chorus();
    cyd.wavetable_entries = waves;
    cyd_set_callback(&cyd, tick, &mus, song.song_rate);
    mus_set_song(&mus, &song, 0);
    for (int i = 0; i < MUS_MAX_CHANNELS; i++) mus.channel[i].flags &= ~MUS_CHN_DISABLED;
    FILE *out = raw ? fopen(raw, "wb") : NULL;
    long total = (long)(atof(argv[2]) * rate);
    static Sint16 buf[2000 * 2];
    while (total > 0) {
        int n = total < 2000 ? (int)total : 2000;
        memset(buf, 0, sizeof buf);
        cyd_output_buffer_stereo(&cyd, (Uint8 *)buf, n * 4);
        if (out) fwrite(buf, 4, (size_t)n, out);
        total -= n;
    }
    if (out) fclose(out);
    if (feat) features();
    return 0;
}
