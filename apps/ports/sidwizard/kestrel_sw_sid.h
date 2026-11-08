/* Where the SID's register writes go: the one switch for moving the SID to BARD (included by kestrel_sw.c).
 *
 *   SW_SID_ON_BARD 0   the C64's SID is emulated here, on ZIGGY: libcRSID's light engine reads its registers
 *                      straight from the C64's I/O page every sample (now)
 *   SW_SID_ON_BARD 1   every write to $D400-$D7FF (the SID and its mirrors) is handed to sw_sid_write(), with the
 *                      register, the value and the C64 cycle it happened at, after the instruction that wrote it;
 *                      the local SID render is then to be skipped (the CPU, CIAs, VIC and envelopes still run: the
 *                      6502 reads $D41B/$D41C back). sw_sid_write() is to put the write on the BARD queue
 *                      (feat/bard-queue, not on main yet: decisions.md "The BARD queue", libs/zig/bard.zig):
 *                      a C mirror of its ring (Cmd {t, addr = $D400 + reg, value, seq}) opened by
 *                      hostBardAttach(block, lead) with SID live's model, t = cycle x 44100 / 985248 on the
 *                      cart's 44.1 kHz clock. Building with 1 stops at the #error below until it lands.
 *
 * The capture costs nothing with 0: libcRSID's write path calls sw_io_write() for any I/O write already
 * (kestrel_sw_clock.c), which records the register only when this is 1. */
#ifndef SW_SID_ON_BARD
#define SW_SID_ON_BARD 0
#endif

#if SW_SID_ON_BARD
#error "SW_SID_ON_BARD needs the BARD message queue's SID_WRITE (feat/bard-queue): write sw_sid_write() over it"
static void sw_sid_write(unsigned reg, unsigned value, unsigned long long cycle);
#endif
