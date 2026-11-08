/* The desk mode on the board (HW 1.17.0, RESOLUTION = RES_DESK, docs/GEM_DESK_MODE.md).
 * The scanout shows plane 0 itself (rtl/video/zm_video_desk.v), so a desk frame has no pass:
 * the sequencer only counts the frame (video.zig's clear() does no more) and paces it on the
 * swap, as vseq_mix_only does. */
#ifndef ZM_BDESK_H
#define ZM_BDESK_H
#include "host.h"
#include "sha256.h"

/* At boot, after host_boot_machine: the machine answers hwDeskAvailable() from the bitstream's
 * capability bit (STATUS.DESK; 0 on a bitstream without the mode). */
void bdesk_boot(struct w2c_env* e);
/* Before the cart's frame, in vseq_clear's place: 1 if RESOLUTION says desk, after FRAME + 1. */
int bdesk_clear(struct w2c_env* e);
/* After the cart's frame: 1 if the frame is a desk frame. Then `h` (a hashed frame) gets the
 * browser's desk hash: "desk", then hwRenderDesk(0)'s and hwRenderDesk(1)'s 614,400 bytes. The
 * picture is paced: the swap is waited for before PRESENT. */
int bdesk_frame(struct w2c_env* e, sha256_ctx* h);
/* A frame that began in desk mode and ends in another: the clear bdesk_clear skipped, now, so
 * the planes have a CLEAR colour and fill state to start from. FRAME was already counted, so the
 * clear's own count is taken back. The browser's PFB keeps the desk's pixels on this frame: this
 * one frame matches no oracle. */
void bdesk_leave(struct w2c_env* e);
#endif
