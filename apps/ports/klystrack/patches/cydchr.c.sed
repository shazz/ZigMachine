# KESTREL: no chorus buffer / LUT at init (the LUT alone is 4 s of Sint32 = 690 KiB at 44.1 kHz per FX bus);
# patches/cydfx.c.sed allocates both the first time chorus is enabled on a bus.
s/^\tchr->buffer = calloc(chr->buf_size, sizeof(chr->buffer\[0\]) \* 2);$/\tchr->buffer = NULL; \/* KESTREL: allocated on demand by cydfx_set *\//
s/^\tchr->lut = calloc(sample_rate \* 4 \* CYD_CHORUS_OVERSAMPLE, sizeof(chr->buffer\[0\]));$/\tchr->lut = NULL;/
# KESTREL: the chorus LUT (4 s of entries, 88,200 at 22.05 kHz) without a double sin() per entry: ~630 Mc (6 s on
# the board) at every song load that enables a chorus. kestrel_chorus.c builds the same entries (+-1/256 sample)
# from an integer sine table.
/^#include <string.h>$/a\
void kestrel_chorus_lut(Sint32 *lut, int n, int min_delay, int max_delay, int rate, int wrap); /* KESTREL */
/^\t\tfor (int i = 0 ; i < chr->lut_size ; ++i)$/{
N
s/.*/\t\t_Static_assert(CHORUS_ACCURACY == 256, "kestrel_chorus.c scales by 256"); \/* KESTREL *\/\
\t\tkestrel_chorus_lut(chr->lut, chr->lut_size, min_delay, max_delay, chr->sample_rate, chr->buf_size * CHORUS_ACCURACY);/
}
