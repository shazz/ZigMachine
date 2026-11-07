/* PacketVideo's fixed-point MP3 decoder (pvmp3, Apache-2.0, AOSP frameworks/av mp3dec; fetched by
 * tools/mp3_bard_fetch.sh) behind the bench's adapter (mp3bench.h). Its API is C (extern "C"). */
#include <stdlib.h>
#include <string.h>

#include "mp3bench.h"
#include "pvmp3decoder_api.h"

const char mp3a_name[] = "pvmp3";

typedef struct {
    tPVMP3DecoderExternal ext;
    void *mem;
} pv_t;

void *mp3a_open(void) {
    pv_t *d = (pv_t *)calloc(1, sizeof(pv_t));
    if (!d) return 0;
    d->mem = malloc(pvmp3_decoderMemRequirements());
    if (!d->mem) {
        free(d);
        return 0;
    }
    d->ext.equalizerType = flat;
    d->ext.crcEnabled = 0;
    pvmp3_InitDecoder(&d->ext, d->mem);
    return d;
}

void mp3a_close(void *p) {
    pv_t *d = (pv_t *)p;
    free(d->mem);
    free(d);
}

int mp3a_frame(void *p, const uint8_t **in, uint32_t *left, int16_t *pcm, int *nch, int *rate) {
    pv_t *d = (pv_t *)p;
    while (*left >= 4 && !mp3_frame_len(*in)) ++*in, --*left; /* resync */
    uint32_t len = *left >= 4 ? mp3_frame_len(*in) : 0;
    if (!len || len > *left) return -1;
    d->ext.pInputBuffer = (uint8 *)*in;
    d->ext.inputBufferCurrentLength = (int32)len;
    d->ext.inputBufferMaxLength = 0;
    d->ext.inputBufferUsedLength = 0;
    d->ext.pOutputBuffer = pcm;
    d->ext.outputFrameSize = MP3_MAX_PCM;
    ERROR_CODE err = pvmp3_framedecoder(&d->ext, d->mem);
    uint32_t used = (uint32_t)d->ext.inputBufferUsedLength;
    *in += used;
    *left -= used;
    if (err == NO_ENOUGH_MAIN_DATA_ERROR) return 0;
    if (err != NO_DECODING_ERROR) return -(int)err;
    *nch = d->ext.num_channels;
    *rate = d->ext.samplingRate;
    return d->ext.outputFrameSize / d->ext.num_channels;
}
