/* The Helix fixed-point MP3 decoder (RealNetworks, RPSL; chmorgan/libhelix-mp3, fetched by
 * tools/mp3_bard_fetch.sh) behind the bench's adapter (mp3bench.h). */
#include <stddef.h>

#include "mp3bench.h"
#include "mp3dec.h"

const char mp3a_name[] = "helix";

void *mp3a_open(void) { return MP3InitDecoder(); }

void mp3a_close(void *d) { MP3FreeDecoder(d); }

int mp3a_frame(void *d, const uint8_t **p, uint32_t *left, int16_t *pcm, int *nch, int *rate) {
    int off = MP3FindSyncWord(*p, (int)*left);
    if (off < 0) return -1;
    *p += off;
    *left -= (uint32_t)off;
    size_t n = *left;
    int err = MP3Decode(d, p, &n, pcm, 0);
    *left = (uint32_t)n;
    if (err == ERR_MP3_MAINDATA_UNDERFLOW) return 0; /* the reservoir is still filling */
    if (err) return err;
    MP3FrameInfo fi;
    MP3GetLastFrameInfo(d, &fi);
    *nch = fi.nChans;
    *rate = fi.samprate;
    return fi.outputSamps / fi.nChans;
}
