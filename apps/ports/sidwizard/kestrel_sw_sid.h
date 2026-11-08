/* Where the SID's register writes go: the one switch for moving the SID to BARD (included by kestrel_sw.c).
 *
 *   SW_SID_ON_BARD 1   (the default) every write to $D400-$D7FF (the SID and its mirrors) goes on the BARD queue
 *                      (kestrel_sw_bard.c) with the C64 cycle it happened at, and the sound side's SID live
 *                      plays it (BARD on the board, the AudioWorklet on the page). The cart renders no SID: the
 *                      C64 is clocked by the frame's real time (kestrel_sw.c sw_run_c64), not by the audio.
 *   SW_SID_ON_BARD 0   upstream's way: libcRSID's light engine renders the SID here, on ZIGGY, reading its
 *                      registers from the C64's I/O page every sample, and that audio clocks the C64
 *                      (kestrel_audio_pump). Kept to measure the two against each other (README.md "Cost"). */
#ifndef SW_SID_ON_BARD
#define SW_SID_ON_BARD 1
#endif

#if SW_SID_ON_BARD
static void sw_sid_write(unsigned reg, unsigned value, unsigned long long cycle);
#endif
