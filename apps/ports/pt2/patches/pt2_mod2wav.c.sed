# KESTREL: 64 KB -> 4 KB static (mod2wav works in chunks of this size; it only sets the chunk length)
s/^#define FADEOUT_CHUNK_SAMPLES 16384$/#define FADEOUT_CHUNK_SAMPLES 1024 \/* KESTREL *\//
