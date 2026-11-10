/* The text screen kestrel_cio.c keeps (ciolib's cells) and kestrel_desk.c draws into the desk plane. */
#ifndef KESTREL_DESK_H
#define KESTREL_DESK_H
#include <stdint.h>
#include "ciolib.h"
#include "vidmodes.h"

#define KCIO_COLS 80                 /* 80 x 8 = 640: the desk's width at 1:1 */
#define KCIO_ROWS 25                 /* 25 x 16 = 400; the desk's last 80 rows hold the status line */

struct kcio_screen {
    struct vmem_cell cell[KCIO_COLS * KCIO_ROWS];
    int cols, rows;                  /* the text mode's size (at most KCIO_COLS x KCIO_ROWS) */
    int cx, cy;                      /* the cursor, 0-based screen cell */
    int cstart, cend;                /* its scan lines in the 16-line cell; cstart > cend: hidden */
    int vflags;                      /* CIOLIB_VIDEO_* */
    uint32_t pal16[16];              /* legacy attribute colour -> palette entry (the mode's palette) */
    uint32_t rgb[TOTAL_DAC_SIZE];  /* palette entry -> 0x00RRGGBB (dac_default, then setpalette) */
    unsigned gen;                    /* bumped when every cell must be redrawn (a palette or mode change) */
    uint32_t dirty;                  /* bit y: row y was written since it was last drawn */
};
extern struct kcio_screen kcio;

void kestrel_desk_boot(void);        /* the desk plane (or the medium fallback) and its first frame */
void kestrel_desk_frame(void);       /* draw the cells that changed, the cursor and the status line */
int kestrel_desk_on(void);           /* 1: in the desk mode; 0: the old host fallback */
void kestrel_desk_status(const char *s); /* the status line's text (under the 80x25 screen) */
#endif
