# KESTREL: no chorus buffer / LUT at init (the LUT alone is 4 s of Sint32 = 690 KiB at 44.1 kHz per FX bus);
# patches/cydfx.c.sed allocates both the first time chorus is enabled on a bus.
s/^\tchr->buffer = calloc(chr->buf_size, sizeof(chr->buffer\[0\]) \* 2);$/\tchr->buffer = NULL; \/* KESTREL: allocated on demand by cydfx_set *\//
s/^\tchr->lut = calloc(sample_rate \* 4 \* CYD_CHORUS_OVERSAMPLE, sizeof(chr->buffer\[0\]));$/\tchr->lut = NULL;/
