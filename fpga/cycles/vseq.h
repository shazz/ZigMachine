/* The video sequencer: the machine's frame, run on the cart CPU against the RTL
 * compositor (soc/zm_video_pipe.py), in exactly machine/video.zig's order.
 *
 *   vseq_clear    hwClear: per line, the global HBL handler, then a BG pass
 *   vseq_plane    hwRenderPlane(p): LATCH, then per line the plane's handler
 *                 (where video.zig calls it, with its line numbering), then a
 *                 PLANE pass folded into the picture
 *   vseq_mix_only no plane enabled: the cleared PFB is the picture
 *   vseq_present  the picture is complete; it is shown from the next VBL
 *
 * Handlers are plain calls between passes. Before each pass the sequencer
 * waits until the previous pass has read the CPU's state (`painted`), and
 * until every store the handler made has reached the compositor (`drained`):
 * the drain rule (rtl/video/README.md). ZM_NO_DRAIN builds the mutant that
 * skips the second wait, which the integration test requires to fail. */
#ifndef ZM_VSEQ_H
#define ZM_VSEQ_H

#include <stdint.h>

#include "host.h"

typedef struct {
    uint32_t swap_wait; /* cycles spent waiting for the shown picture to swap */
    uint32_t undrained; /* commands that found a CPU store still on its way */
} vseq_stats;

extern vseq_stats vseq;

/* After host_boot: where the region and the two pictures are, then every
 * snooped word stored again (boot wrote them before the snoop knew the region). */
void vseq_init(struct w2c_env* e, uint32_t fb0, uint32_t fb1);
void vseq_clear(struct w2c_env* e);
void vseq_plane(struct w2c_env* e, int p, int first);
void vseq_mix_only(void);
/* ZM_LINE_MAJOR builds only: the mutant order (vseq.c). */
void vseq_line_major(struct w2c_env* e, unsigned planes);
void vseq_present(void);
/* Until no command is queued or running: every row is in memory. */
void vseq_idle(void);

#endif
