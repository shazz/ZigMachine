/* The MP3 player's (libs/zig/players/mp3.zig) one door into pvmp3: a frame in, its PCM out, no
 * pointers kept in anything the caller sees. The caller owns the state's memory (zm_mp3_state_size
 * bytes, 4-aligned) and hands one WHOLE frame a call (pvmp3's validate_input refuses a partial one);
 * pvmp3 keeps the bit reservoir itself. Built into demo-audio.wasm (build.zig addPvmp3), so the page,
 * the native host and BARD (wasm2c) run the same integer code. */
#include <stdint.h>

#include "pvmp3decoder_api.h"

typedef struct {
    tPVMP3DecoderExternal ext;
    uint32_t mem[1]; /* pvmp3_decoderMemRequirements() bytes */
} zm_mp3_state;

extern "C" {

uint32_t zm_mp3_state_size(void) { return (uint32_t)sizeof(tPVMP3DecoderExternal) + pvmp3_decoderMemRequirements() + 4u; }

void zm_mp3_init(void *state) {
    zm_mp3_state *s = (zm_mp3_state *)state;
    s->ext = tPVMP3DecoderExternal();
    s->ext.equalizerType = flat;
    s->ext.crcEnabled = 0;
    pvmp3_InitDecoder(&s->ext, s->mem);
}

/* Decode the frame at in[0..len) into out (interleaved, room for 2 x 1152). Returns the samples a
 * channel (0: the reservoir is still filling), or -(pvmp3's ERROR_CODE). info[0] = the rate,
 * info[1] = the channels. */
int32_t zm_mp3_decode(void *state, const uint8_t *in, uint32_t len, int16_t *out, uint32_t *info) {
    zm_mp3_state *s = (zm_mp3_state *)state;
    s->ext.pInputBuffer = (uint8 *)in;
    s->ext.inputBufferCurrentLength = (int32)len;
    s->ext.inputBufferMaxLength = 0;
    s->ext.inputBufferUsedLength = 0;
    s->ext.pOutputBuffer = out;
    s->ext.outputFrameSize = 2 * 1152;
    ERROR_CODE err = pvmp3_framedecoder(&s->ext, s->mem);
    if (err == NO_ENOUGH_MAIN_DATA_ERROR) return 0;
    if (err != NO_DECODING_ERROR) return -(int32_t)err;
    info[0] = (uint32_t)s->ext.samplingRate;
    info[1] = (uint32_t)s->ext.num_channels;
    return s->ext.outputFrameSize / s->ext.num_channels;
}
}
