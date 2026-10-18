/* -include'd into env.c for host/vdirty_main.c: the span hooks report each HBL
 * handler's return, so the proof reads the background the way the board's
 * sequencer does (after the global handler, before the line is painted). */
#ifndef ZM_VDIRTY_SPANS_H
#define ZM_VDIRTY_SPANS_H
#define HOST_SPAN_CART 1
#define HOST_SPAN_BLIT 2
void vdh_span_enter(int kind);
void vdh_span_leave(void);
#define HOST_SPAN_ENTER(kind) vdh_span_enter(kind)
#define HOST_SPAN_LEAVE() vdh_span_leave()
#endif
