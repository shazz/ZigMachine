/* The whole-D-cache invalidate, the one copy every firmware uses (vboard.h zmv_flush_dcache,
 * bdinval.h bdi_inval_all, sound/smain.c flush_dcache): VexRiscv's MANAGEMENT instruction
 * (DBusCachedPlugin, MISC-MEM funct3 5, rs1 = x0) drops every line of the write-through cache,
 * LiteX's flush_cpu_dcache.
 *
 * Behind two nops. Both cores (vexgen GenZm, cart and sound) resolve a branch in MEMORY
 * (earlyBranch = false), and DataCache starts its sweep from EXECUTE once no memory op is in
 * flight, so a flush fetched on the wrong side of a branch sweeps the cache before the branch
 * kills it: `if (x) flush()` paid ~130 cycles plus a refill of every hot line even when x was 0.
 * The nops keep the flush out of EXECUTE until any older branch has resolved. Speed only: a
 * missed sweep is never wrong, the cache is write-through. tests/test_blit_dcache.py proves it on
 * the board's core (a skipped flush leaves a line cached, a taken one drops it) and breaks it. */
#ifndef ZM_DFLUSH_H
#define ZM_DFLUSH_H

static inline void zm_dflush(void) { __asm__ volatile("nop\n nop\n .word(0x500F)\n" ::: "memory"); }

#endif
