/* A disk's executable boot sector on the board (bbootsec.c), before its cart: the browser's
 * flow for a ZigCart v2 disk (docs/sealed-loader.js), so sysinfo's "No virus" screen and
 * replicants_emlyn's crew note show here too. The sector's own 1 KB of wasm runs through the
 * wint interpreter (host/bootsec.h); nothing is built per disk.
 *
 * bmain.c's boot(): when bbootsec_wanted(), host_boot_machine (memory, machine, ROM), the
 * compositor brought up, bbootsec_run (hwInit, the sector's boot(), its frames until it asks
 * for its cart), then host_boot_cart, whose hwInit and boot() follow as the browser's req 2.
 *
 * Wanted: ZM_BOOTSEC (the board's images; a sim would spend hundreds of frames on it), the disk
 * booted for itself (not a program GEM launched off it: the browser's req 3 runs no sector),
 * no BOOTSEC_SKIP word (glass/src/map_cart.zig: the glass bringing GEM back over the disk, req
 * 4), and a sector that is executable (parseV2's $1234). A sector the interpreter refuses,
 * one that traps, overruns its fuel, sets an HBL handler (it has no hblDispatch: the browser
 * would throw) or never asks within BOOTSEC_MAX_FRAMES ends the phase; the cart boots anyway.
 * Its `beep` is silent here (the sound CPU starts with the cart): the one thing the browser
 * does that the board does not.
 *
 * Lines (sim, ZM_BOOTSEC=1): "ZM BOOTSEC start <status> <steps>", "ZM BOOTSEC end <frames>
 * <status> <steps>". */
#ifndef ZM_BBOOTSEC_H
#define ZM_BBOOTSEC_H

#include "host.h"

int bbootsec_wanted(void);              /* after bdisk_boot() */
/* After host_boot_machine() and vseq_init(); each frame a CART_BEAT from `beat` on; returns the last. */
uint32_t bbootsec_run(struct w2c_env* e, uint32_t beat);

#endif
