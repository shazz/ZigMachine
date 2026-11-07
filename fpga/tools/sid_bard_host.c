/* The host twin of the BARD SID bench (cycles/sound/sidbench.c): the same cRSID build and loop.
 * Prints the per-frame PCM hash BARD must match, and writes the whole render as a WAV to listen to.
 *   sid_bard_host <out.wav> <frames> <bench frames> [<earlier.sid> <subtune>]... <tune.sid> <subtune>
 * (tools/sid_bard_bench.sh builds and runs it; SID_RATE / SID_HQ as for the BARD build.) */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "sidbench.h"
#include "C64/C64.h"

extern cRSID_C64instance cRSID_C64; /* libcRSID.c: the C64, read for the filter census */

static void wav_header(FILE *f, uint32_t frames) {
    uint32_t data = frames * SID_FRAME * 4, rate = SID_RATE, byte_rate = SID_RATE * 4, riff = 36 + data;
    uint16_t pcm = 1, ch = 2, align = 4, bits = 16;
    uint32_t fmt_len = 16;
    fwrite("RIFF", 1, 4, f), fwrite(&riff, 4, 1, f), fwrite("WAVEfmt ", 1, 8, f), fwrite(&fmt_len, 4, 1, f);
    fwrite(&pcm, 2, 1, f), fwrite(&ch, 2, 1, f), fwrite(&rate, 4, 1, f), fwrite(&byte_rate, 4, 1, f);
    fwrite(&align, 2, 1, f), fwrite(&bits, 2, 1, f), fwrite("data", 1, 4, f), fwrite(&data, 4, 1, f);
}

static uint8_t *slurp(const char *path, uint32_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *d = malloc((size_t)n);
    if (d && fread(d, 1, (size_t)n, f) != (size_t)n) d = (free(d), NULL);
    fclose(f);
    *len = (uint32_t)n;
    return d;
}

/* cRSID keeps state across tunes (filter memories, the dither LFSR, statics), and BARD's bench plays
 * its tunes one after another in one image: so the host replays the tunes BARD played before this one,
 * bench_frames frames each, before it hashes. */
static int replay(char **tunes, int n, int frames, int16_t *pcm) {
    for (int i = 0; i < n; i++) {
        sid_tune_t t = {tunes[2 * i], NULL, 0, atoi(tunes[2 * i + 1])};
        t.data = slurp(t.name, &t.len);
        uint8_t *copy = t.data ? malloc(t.len) : NULL;
        if (!copy || sid_start(&t, copy)) return 1;
        for (int f = 0; f < frames; f++) sid_frame(pcm);
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 6 || argc % 2 == 1)
        return fprintf(stderr, "usage: %s out.wav frames bench_frames [earlier.sid sub]... tune.sid sub\n", argv[0]), 2;
    static int16_t pcm[SID_FRAME * 2];
    int frames = atoi(argv[2]), earlier = (argc - 6) / 2;
    sid_tune_t t = {argv[argc - 2], NULL, 0, atoi(argv[argc - 1])};
    t.data = slurp(t.name, &t.len);
    uint8_t *copy = t.data ? malloc(t.len) : NULL;
    FILE *w = fopen(argv[1], "wb");
    if (!copy || !w) return fprintf(stderr, "%s: cannot read the tune or write the WAV\n", argv[0]), 1;
    if (replay(argv + 4, earlier, atoi(argv[3]), pcm) || sid_start(&t, copy))
        return fprintf(stderr, "%s: cRSID refused a tune\n", argv[0]), 1;
    printf("SIDINFO %s frame_cycles %d timer %d realsid %d digi %d model %u\n", t.name, cRSID.FrameCycles,
           cRSID.TimerSource, cRSID.RealSIDmode, cRSID.PSIDdigiMode, cRSID_getSIDmodel(1));
    wav_header(w, (uint32_t)frames);
    clock_t c0 = clock();
    int filtered = 0; /* frames that end with a voice routed through the filter ($D417 bits 0-2) */
    for (int f = 0; f < frames; f++) {
        sid_frame(pcm);
        fwrite(pcm, 4, SID_FRAME, w);
        filtered += (cRSID_C64.IObankWR[0xD417] & 7) != 0;
        printf("SID %d hash %08lx\n", f, (unsigned long)sid_hash(pcm, SID_FRAME * 2));
    }
    printf("HOSTTIME %.3f s for %d frames, filter on in %d\n", (double)(clock() - c0) / CLOCKS_PER_SEC, frames,
           filtered);
    fclose(w);
    return 0;
}
