/* Keeping the C64's time when ZIGGY cannot run all of it (SW_SID_ON_BARD; included by kestrel_sw.c).
 *
 * The C64 is clocked by the frame's real time (kestrel_sw.c sw_run_c64): its CIAs, its VIC's raster lines, and
 * so the IRQs that run SID-Wizard's player, follow the clock, and the SID writes they make are stamped with it
 * (kestrel_sw_bard.c). But the 6502 that time asks for costs ZIGGY more than the time itself: SID-Wizard's main
 * loop never idles (it redraws, scans keys, polls), ~5,100 instructions a 60th of a second. Run all of it and
 * the frame takes longer than the time it emulated: the next frame owes more, and so on, to the cap, where the
 * C64 (and its music) falls behind real time.
 *
 * So the main program gets the CPU that is left, as on a C64 whose main loop is slow: each frame the
 * emulation may take PACE_SHARE of the real time it covers (hostMicros); past that (and never in the frame's
 * first PACE_FREE, so the editor always moves on), for the rest of the frame,
 * the 6502 runs only with interrupts masked (an IRQ handler: the player, the raster splits) and the main
 * program waits where it was (libcRSID's idle state, the one between a PSID's calls) until the next frame. Time
 * goes on, the IRQs come on time and run whole, so the song keeps its tempo; the editor answers a little slower.
 * Where the host has no clock (hostMicros() == 0: every harness), nothing is held: the C64 runs as upstream, and
 * the output is the same on every host. */

#define PACE_SHARE_NUM 60                      /* the emulation's share of the frame's real time: 60 % (the rest */
#define PACE_SHARE_DEN 100                     /* is the picture, FRESCO's passes and the frame's glue) */
#define PACE_FREE_NUM 1                        /* the main program always runs the frame's first tenth: never */
#define PACE_FREE_DEN 10                       /* starved, whatever the IRQs cost */
#define PACE_CHECK 32                          /* C64 samples (~1.5 ms of C64 time) between two looks at the clock */

__attribute__((import_module("env"), import_name("hostMicros"))) extern uint32_t hostMicros(void);

static uint32_t sw_pace_t0, sw_pace_allow, sw_pace_free; /* this frame: its start, how long it may take (us), its free samples */
static int sw_pace_hold, sw_pace_holding;      /* the main program waits from now on / is waiting now */
static uint32_t sw_pace_held_frames;           /* frames where it waited (sidwizard's log, the README) */

static void sw_pace_release(void)
{
    if (sw_pace_holding) { C64->Finished = 0; sw_pace_holding = 0; }
}

static void sw_pace_begin(uint32_t samples)
{
    sw_pace_release();
    sw_pace_hold = 0;
    sw_pace_t0 = hostMicros();
    sw_pace_allow = (uint32_t)((uint64_t)samples * 1000000u / 22050u * PACE_SHARE_NUM / PACE_SHARE_DEN);
    sw_pace_free = samples * PACE_FREE_NUM / PACE_FREE_DEN;
}

/* Before C64 sample i of the frame. */
static void sw_pace_step(uint32_t i)
{
#ifdef SW_PACE_FORCE                           /* measuring (frame_cost has no clock): hold from the free tenth on */
    if (!sw_pace_hold && i >= sw_pace_free) {
#else
    if (!sw_pace_t0) return;                   /* no host clock: as upstream */
    if (!sw_pace_hold && i >= sw_pace_free && i % PACE_CHECK == 0 && hostMicros() - sw_pace_t0 > sw_pace_allow) {
#endif
        sw_pace_hold = 1;
        sw_pace_held_frames++;
    }
    if (!sw_pace_hold) return;
    enum { I_FLAG = 0x04 };
    if (cRSID_C64.CPU.ST & I_FLAG) return;     /* an IRQ handler (or a SEI section) runs to its end */
    if (!cRSID_C64.Finished) { C64->Finished = 1; sw_pace_holding = 1; }  /* the main program waits */
}
