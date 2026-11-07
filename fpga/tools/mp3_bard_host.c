/* The BARD MP3 study's host twin of fpga/cycles/sound/mp3bench.c: the same adapter over a whole file,
 * the s16le PCM to <out.raw> (for tools/mp3_bard_snr.py) and each frame's hash, which must equal what
 * BARD prints for that frame. Built by tools/mp3_bard_bench.sh with the same decoder sources.
 *   mp3_bard_host <in.mp3> <out.raw> */
#include <stdio.h>
#include <stdlib.h>

#include "mp3bench.h"

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <in.mp3> <out.raw>\n", argv[0]);
        return 2;
    }
    FILE *fi = fopen(argv[1], "rb"), *fo = fopen(argv[2], "wb");
    if (!fi || !fo) {
        perror("mp3_bard_host");
        return 2;
    }
    static uint8_t buf[1 << 22];
    uint32_t left = (uint32_t)fread(buf, 1, sizeof buf, fi);
    const uint8_t *p = buf;
    if (left >= 10 && buf[0] == 'I' && buf[1] == 'D' && buf[2] == '3') { /* an ID3v2 tag: skipped whole */
        uint32_t tag = 10u + ((buf[6] & 0x7Fu) << 21 | (buf[7] & 0x7Fu) << 14 | (buf[8] & 0x7Fu) << 7 | (buf[9] & 0x7Fu)) +
                       (buf[5] & 0x10u ? 10u : 0u);
        if (tag > left) tag = left;
        p += tag;
        left -= tag;
    }
    static int16_t pcm[MP3_MAX_PCM];
    void *d = mp3a_open();
    int n, nch = 0, rate = 0, frames = 0;
    while ((n = mp3a_frame(d, &p, &left, pcm, &nch, &rate)) >= 0) {
        printf("MP3 %s %d rate %d ch %d n %d hash %08x\n", mp3a_name, frames++, rate, nch, n,
               (unsigned)mp3_hash(pcm, n * nch));
        fwrite(pcm, sizeof pcm[0], (size_t)n * nch, fo);
    }
    if (left > 4) fprintf(stderr, "%s: stopped at frame %d, %u bytes left, code %d\n", argv[1], frames, left, n);
    mp3a_close(d);
    fclose(fo);
    return frames ? 0 : 1;
}
