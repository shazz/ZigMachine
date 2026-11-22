"""The stereo stream's host entries (system table 1.27, docs/project/DECISIONS.md 2026-11-20): zg.audioStreamStartStereo
(two rings, Paula channels 0 / 1 panned hard left / right), zg.audioFeedStereo (interleaved L,R signed
8-bit frames) and zg.audioStreamPlayed (the stream's sample counter, mono or stereo). Appended to the
table after 1.26's hostAudioScopes, so every older index stands and a 1.26 cart still runs; a cart that
imports one of them needs 1.27. host/hstream.h (-include, where the players run) defines the hooks; the
stub's no-op starts nothing and the counter answers 0 ("no sound here")."""

STEREO = {
    "hostAudioStreamStartStereo": ("void", ["u32"], "HOST_AUDIO_STREAM_START_STEREO"),
    "hostAudioFeedStereo": ("void", ["u32", "u32"], "HOST_AUDIO_FEED_STEREO"),
    "hostAudioStreamPlayed": ("u32", [], "HOST_AUDIO_STREAM_PLAYED"),
}
STEREO_DEFAULTS = """/* The stereo stream's hooks: the stub's no-op, the counter 0. host/hstream.h (-include) defines them where the players run. */
#ifndef HOST_AUDIO_STREAM_START_STEREO
#define HOST_AUDIO_STREAM_START_STEREO(e, rate) ((void)(e), (void)(rate))
#define HOST_AUDIO_FEED_STEREO(e, ptr, len) ((void)(e), (void)(ptr), (void)(len))
#define HOST_AUDIO_STREAM_PLAYED(e) ((void)(e), 0u)
#endif
"""
