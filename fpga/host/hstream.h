/* The cart's stream imports where the players run (tools/host_gen.py's STREAM hooks): force-
 * included into the generated env.c of the board firmware (cycles/board.mk) and of host_audio
 * (cycles/audio.mk), so zg.audioStreamStart / audioFeed / audioStreamStop reach the stream ring
 * (host/audio_bridge.c, host/audio_pcm.c) as docs/sealed-loader.js's do. */
#ifndef ZM_HSTREAM_H
#define ZM_HSTREAM_H

#include <stdint.h>

struct w2c_env;
void audio_stream_start(struct w2c_env* e, float rate);
void audio_stream_feed(struct w2c_env* e, uint32_t ptr, uint32_t len);
void audio_stream_stop(struct w2c_env* e);

#define HOST_AUDIO_STREAM_START(e, rate) audio_stream_start((e), (rate))
#define HOST_AUDIO_FEED(e, ptr, len) audio_stream_feed((e), (ptr), (len))
#define HOST_AUDIO_STREAM_STOP(e) audio_stream_stop((e))

#endif
