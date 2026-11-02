# KESTREL: no reverb delay line at init (2 s of stereo Sint32 = 690 KiB at 44.1 kHz, times 8 FX buses, would not
# fit the cart window); patches/cydfx.c.sed allocates it the first time a song or the user enables reverb on a bus.
s/^\trvb->buffer = calloc(sizeof(\*rvb->buffer) \* 2, bufsize);$/\trvb->buffer = NULL; \/* KESTREL: allocated on demand by cydfx_set *\//
# KESTREL: a tap keeps its delay in samples (tap.position) instead of a read position stepped every sample: the
# read position is the write position minus the delay, the same sample as before, without 16 increments a sample.
/^#include <string.h>$/a\
static inline int kestrel_tap_pos(const CydReverb *rvb, int i) { int p = rvb->position - rvb->tap[i].position; return p < 0 ? p + rvb->size : p; } /* KESTREL */
/^\tfor (int i = 0 ; i < CYDRVB_TAPS ; ++i)$/{
N;N;N;N;N
/++rvb->tap\[i\]\.position;/d
}
s/rvb->buffer\[rvb->tap\[i\]\.position/rvb->buffer[kestrel_tap_pos(rvb, i)/g
s/^\trvb->tap\[idx\]\.position = (rvb->position - (delay_ms \* rvb->rate \/ 1000) + rvb->size) % rvb->size;$/\trvb->tap[idx].position = (delay_ms * rvb->rate \/ 1000) % rvb->size; \/* KESTREL: the delay in samples *\//
