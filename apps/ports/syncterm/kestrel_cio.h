/* ciolib's KESTREL backend (kestrel_cio.c): the text screen drawn into the desk plane. */
#ifndef KESTREL_CIO_H
#define KESTREL_CIO_H
#include <stdbool.h>
extern bool retro_set;            /* ciolib.c's switch into a frame-driven backend (always true here) */
int kestrel_cio_init(int mode);   /* fills cio_api; 1 = ok */
#endif
