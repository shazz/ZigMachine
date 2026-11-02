# KESTREL: no reverb delay line at init (2 s of stereo Sint32 = 690 KiB at 44.1 kHz, times 8 FX buses, would not
# fit the cart window); patches/cydfx.c.sed allocates it the first time a song or the user enables reverb on a bus.
s/^\trvb->buffer = calloc(sizeof(\*rvb->buffer) \* 2, bufsize);$/\trvb->buffer = NULL; \/* KESTREL: allocated on demand by cydfx_set *\//
