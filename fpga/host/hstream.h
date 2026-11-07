/* The cart's stream (and Paula) imports where the players run (tools/host_gen.py's STREAM hooks): force-
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

/* The cart's Paula (HW 1.14.0): host/audio_bridge.c, as docs/sealed-loader.js's hostPaula*. */
uint32_t audio_paula_claim(struct w2c_env* e, uint32_t lead);
void audio_paula_upload(struct w2c_env* e, uint32_t src, uint32_t off, uint32_t len);
void audio_paula_write(struct w2c_env* e, uint32_t ptr, uint32_t n);
void audio_paula_release(struct w2c_env* e);

#define HOST_PAULA_CLAIM(e, lead) audio_paula_claim((e), (lead))
#define HOST_PAULA_UPLOAD(e, src, off, len) audio_paula_upload((e), (src), (off), (len))
#define HOST_PAULA_WRITE(e, ptr, n) audio_paula_write((e), (ptr), (n))
#define HOST_PAULA_RELEASE(e) audio_paula_release((e))

/* The MP3 stream (table 1.11): host/audio_bridge.c, host/audio_mp3.c or cycles/bsound.c. */
void audio_mp3_ctl(struct w2c_env* e, uint32_t op, uint32_t arg);
void audio_mp3_feed(struct w2c_env* e, uint32_t ptr, uint32_t len);
uint32_t audio_mp3_status(uint32_t which);

#define HOST_MP3_CTL(e, op, arg) audio_mp3_ctl((e), (op), (arg))
#define HOST_MP3_FEED(e, ptr, len) audio_mp3_feed((e), (ptr), (len))
#define HOST_MP3_STATUS(e, which) ((void)(e), audio_mp3_status((which)))

#endif
