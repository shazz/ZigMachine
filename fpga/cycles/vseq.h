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
#include "zm_memmap.h"

/* Free-running, mod 2^32: a reader takes differences. Under ZM_VSTAT (the board's images, never
 * the video sim's mutants: a counter read after a handler would drain its stores) the waits and
 * the handlers are timed too (cycles/vstat.h). */
typedef struct {
    uint32_t swap_wait; /* cycles spent waiting for the shown picture to swap */
    uint32_t undrained; /* commands that found a CPU store still on its way */
    uint32_t ready, drain, painted; /* ZM_VSTAT: cycles spent waiting for each status bit */
    uint32_t hbl, plan;             /* ZM_VSTAT: in the HBL handlers; in vseq_decide (+ vplan.c's compare) */
    uint32_t passes;                /* BG, PLANE and MIX passes issued */
} vseq_stats;

extern vseq_stats vseq;

/* What vseq_clear painted each line from: the dirty-line planner's (vplan.h)
 * background inputs. fill: one CLEAR, bg[0] is every line's colour. */
typedef struct {
    int fill;
    uint32_t bg[ZM_RASTER_HEIGHT];
    uint8_t beam[ZM_RASTER_HEIGHT];
} vseq_clear_rec;
extern vseq_clear_rec vseq_rec;
/* NULL: vseq_plane and vseq_mix_only pass over every line; else they skip each
 * line y with vseq_skip[y] (the picture's row is already right, vplan.h). The
 * first layer of the frame asks vseq_decide(y) instead, once per line in order,
 * which must also fill vseq_skip[y] for the layers above. Handlers are called
 * on every line they cover whatever is skipped. */
extern const uint8_t* vseq_skip;
extern int (*vseq_decide)(int y);

/* After host_boot: where the region and the two pictures are, then every
 * snooped word stored again (boot wrote them before the snoop knew the region). */
void vseq_init(struct w2c_env* e, uint32_t fb0, uint32_t fb1);
void vseq_clear(struct w2c_env* e);
void vseq_plane(struct w2c_env* e, int p, int first);
void vseq_mix_only(void);
/* ZM_LINE_MAJOR builds only: the mutant order (vseq.c). */
void vseq_line_major(struct w2c_env* e, unsigned planes);
void vseq_present(void);
/* Until the picture shown is the last one presented: the other is free to build. */
void vseq_wait_swap(void);
/* Until no command is queued or running: every row is in memory. */
void vseq_idle(void);
/* Plane p's ZM_FB_MODE_* as the cart last set it (the pointer's pixel width). */
uint8_t vseq_plane_mode(int p);

#endif
