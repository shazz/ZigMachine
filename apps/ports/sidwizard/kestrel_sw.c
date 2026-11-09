/* SID-Wizard 1.97 (Hermit) as a ZigMachine cart: the PC version's design. Its native C64 program runs on its own
 * libcRSID's C64 (6502, CIAs, VIC raster bookkeeping, SID; upstream libcRSID/), with upstream's PC-host disk
 * traps (host/file.c), keyboard matrix (host/keyboard.c) and mouse (host/mouse.c) compiled unchanged but for
 * patches/*.sed. What upstream's SIDwizard.c main() and its SDL/ALSA host did is here, for the machine:
 *
 *   the clock    the C64 runs as fast as audio is owed: kestrel_audio_pump() asks for real time's worth of
 *                22.05 kHz samples each frame and every sample is cRSID_generateSample() (upstream's SDL audio
 *                callback did the same); every 110 samples (5 ms) is a pass of upstream's main loop
 *                (sw_tick: keys, the start-up key simulator, the disk traps)
 *   the picture  kestrel_sw_video.c: the C64-UI mode at zoom 1, palette indices into the 400x280 plane
 *   the keys     kestrel_sw_keys.c: the machine's key codes as SDL 1.2 key states (include/SDL.h)
 *   files        upstream's stdio over the floppy (read-only, flat) and C: as "/C" (KOS GEMDOS, read-write)
 *
 * The SID is the light engine (cRSID.HighQualitySID = 0, upstream's "-sidlight") at 22050 Hz, as BARD's .sid
 * player. SW_SID_ON_BARD (kestrel_sw_sid.h) is the switch that sends the SID's register writes to BARD instead. */
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include <libgen.h>
#include "SDL.h"
#include "kestrel_audio.h"
#include "kestrel_sw_sid.h"

void kestrel_log(const char *m);
void kestrel_quit(void);
int kestrel_c_mounted(void);

#include "libcRSID/libcRSID.c"     /* cRSID, cRSID_C64: the C64 and its SID (includes SIDwizard.h via VIC.h) */
#if SW_SID_ON_BARD
#include "kestrel_sw_bard.c"
#endif

/* SIDwizard.c's globals that host/file.c and host/keyboard.c use */
static char DriverTypePos = TUNE_DRIVERTYPE_POS_1SID, TuningTypePos = TUNE_TUNINGTYPE_POS_1SID;
static char *WorkfileExtension = WORKFILE_EXTENSION_1SID, *MagicString = MAGICSTRING_1SID;
static int ArgFileDataSize = 0;
static char GUImode = 0, TUImode = 0;
byte ShiftedKeypressSim = 0, CBMkeypressSim = 0;
static byte PianoKeyScanCodeRow, PianoKeyScanCodeColumn;
static byte BorderAlias = 1;                   /* "-lofiborder": no sprite blur (the picture is 16 colours) */
signed char Zoom = 1;
static cRSID_C64instance *C64 = &cRSID_C64;
static byte ArgMIDIname[MIDI_NAME_LENGTH_MAX + 1];   /* the config file's MIDI device (no MIDI here) */
static int sw_exit_dialog, sw_startup_menu = 1;
#define SID_Wizard_2SID SID_Wizard             /* patches/host__file.h.sed: only the 1-SID program is built */
#define SID_Wizard_3SID SID_Wizard
#define SID_Wizard_4SID SID_Wizard

#include "kestrel_sw_files.c"
#include "host/file.c"
#include "resources/chargen.h"
#include "host/buttoncharset.h"
#include "kestrel_sw_video.c"
#include "host/mouse.c"
#include "host/keyboard.c"
static void sw_reset_editor(void);
#include "kestrel_sw_keys.c"
#include "kestrel_sw_keysim.c"
#include "kestrel_sw_pace.c"
#include "kestrel_sw_idle.c"
#include "kestrel_sw_cpu.c"
#include "kestrel_sw_rt.c"
#include "kestrel_sw_prof.c"
#ifdef SW_CPU_TEST
#include "kestrel_sw_cpu_test.c"
#endif

#define SW_RATE 22050
#define SW_TICK 110                            /* samples in upstream's 5 ms main-loop pass (KEYSCAN_PERIOD) */
static int sw_tick_count;
uint64_t sw_samples;                           /* the emulated time (kestrel_sw_host.c's clock) */

/* SIDwizard_resetEngine(1, 0): Shift+F7/F9 restart the editor's program from its safe start. */
static void sw_reset_editor(void)
{
    cRSID_initCPU(SAFESTART_ADDRESS); C64->Finished = 0; C64->Returned = 0;
    ArgFileDataSize = ArgLoading = 0; ArgFileNamePtr = NULL;
}

/* One pass of upstream's main loop, minus the SDL events (kestrel_sw_keys.c) and the display (once a frame). */
static void sw_tick(void)
{
    if (sw_exit_dialog) return;
    if (VICbankBars[INSCREEN_RASTER] != 3) sw_startup_menu = 0;
    getKeyStates();
    sw_keysim();
    handleDiskIO();
}

#if SW_SID_ON_BARD
/* The C64 clocked by the frame's real time: `us` worth of 22.05 kHz "C64 samples" (libcRSID's step: 714/16
 * cycles of CPU, CIAs, VIC, then its disk byte traps), with upstream's 5 ms main-loop pass every 110 of them.
 * Nothing is rendered: the SID's writes went on the BARD queue as they happened (kestrel_sw_bard.c).
 * kestrel_sw_pace.c decides how much of it the main program gets when ZIGGY cannot run it all. */
static uint64_t sw_owed;
static void sw_c64_sample(void)                 /* kestrel_sw_cpu.c's 6502, or upstream's (SW_CPU_UPSTREAM: the before) */
{
#ifndef SW_CPU_UPSTREAM
    if (MOSTLY(cRSID_C64.RealSIDmode && !cRSID_C64.HighQualitySID)) { sw_emulate_c64(); return; }
#endif
    cRSID_emulateC64();
}
static void sw_run_c64(uint32_t us)
{
    sw_owed += (uint64_t)us * SW_RATE;
    uint32_t n = (uint32_t)(sw_owed / 1000000u);
    sw_owed %= 1000000u;
    sw_pace_begin(n);
    for (uint32_t i = 0; i < n; i++) {
        if (!cRSID.Paused) { sw_idle_step(); sw_pace_step(i); sw_c64_sample(); sw_rt_held += (uint32_t)sw_pace_holding; }
#if defined SW_PROFILE_IRQ || defined SW_PROFILE_PC
        sw_profile_sample();
#endif
        sw_samples++; sw_rt_samples++;
        if (++sw_tick_count >= SW_TICK) { sw_tick_count = 0; sw_tick(); }
    }
    sw_bq_frame(sw_cycle + sw_io_cycles);
}
#else
static void sw_mix(void *ctx, int16_t *stereo, int frames)
{
    (void)ctx;
    sw_samples += (uint64_t)frames;
    for (int i = 0; i < frames; i++) {
        cRSID_Output o = cRSID_generateSample();
        stereo[2 * i] = (int16_t)o.L; stereo[2 * i + 1] = (int16_t)o.R;
        if (++sw_tick_count >= SW_TICK) { sw_tick_count = 0; sw_tick(); }
    }
}
#endif

/* main()'s set-up: a PAL C64 with one 8580, the native program in RAM, the CPU at its start. */
static void sw_start_c64(void)
{
    updateSIDamount(1);
    initDiskIO();
    /* main(): device 8 at the start folder (the floppy's root), device 9 = C: (kestrel_sw_files.c) */
    chdir("/"); strcpy(StartUpPath, "/"); strcpy(C64drivePaths[0], "/");
    if (kestrel_c_mounted()) strcpy(C64drivePaths[1], "/C");
    cRSID.SelectedSIDmodel = 8580; cRSID.Stereo = CRSID_CHANNELMODE_MONO;
    cRSID.HighQualitySID = 0; cRSID.HighQualityResampler = 0;
    cRSID_init(SW_RATE, 0);
    cRSID_setC64(); cRSID_initC64(); C64->RAMbank[1] = 0x34;
    cRSID_initCPU(PROGRAMSTART_ADDRESS); C64->Finished = 0; C64->Returned = 0; cRSID.RealSIDmode = 1;
    /* the audio thread's shadows (upstream's cRSID_generateSound() copies them every buffer) */
    C64->RealSIDmode = 1; C64->AudioThread_SIDchipCount = 1; C64->Stereo = CRSID_CHANNELMODE_MONO;
    C64->HighQualitySID = 0; C64->HighQualityResampler = 0;
    initKeyStates();
    loadNativeC64code();
    for (int i = 0; i < 0x800; i++) cRSID_C64.ROMbanks[0x1800 + i] = chargen[i];   /* initUI() */
    cRSID.Paused = 0;
}

__attribute__((export_name("boot"))) void boot(void)
{
    sw_start_c64();
#ifdef SW_CPU_TEST
    sw_cpu_test();
    sw_start_c64();
#endif
    sw_video_init();
    sw_keysim_open(SW_BOOT_SONG);
    kestrel_log("sidwizard: booted");
}

/* The frame's real time. With the SID on BARD the C64 keeps it (kestrel_sw_pace.c: its timers, raster IRQs and
 * so the music's ticks, whatever ZIGGY's frame rate), up to 100 ms (a stall is not caught up). Without, at most
 * 20 ms of it: the light engine on ZIGGY costs ~3.5x real time, so a short cap keeps the editor answering. */
__attribute__((export_name("frame"))) void frame(float elapsed_ms)
{
#if SW_SID_ON_BARD
    sw_run_c64(sw_rt_frame_us(kestrel_frame_us(elapsed_ms, 3600000u)));  /* capped and counted: kestrel_sw_rt.c */
#else
    uint32_t us = kestrel_frame_us(elapsed_ms, 20);
    kestrel_audio_pump(us, SW_RATE, 100, sw_mix, 0);
#endif
    sw_video_frame();
#if SW_SID_ON_BARD
    sw_rt_draw();
#endif
}

__attribute__((export_name("isPlaneEnabled"))) int isPlaneEnabled(int p) { return p == 0; }
__attribute__((export_name("hblDispatch"))) void hblDispatch(unsigned id, unsigned plane, unsigned line, unsigned x) { (void)id; (void)plane; (void)line; (void)x; }
__attribute__((export_name("skipBoot"))) int skipBoot(void) { return 1; }
__attribute__((export_name("setShadeMode"))) void setShadeMode(int m) { (void)m; }
