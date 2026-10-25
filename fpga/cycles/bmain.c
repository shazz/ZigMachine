/* The board firmware: vmain.c's boot and frame order (the RTL compositor under
 * the sequencer, vseq.h) on the board's SoC, where main RAM is PS DDR through
 * HP0 and the video DMA is on HP1 (soc/zm_board_mem.py). The same source runs
 * in soc/hp_sim.py and on the Z7-Lite:
 *
 *   ZM_FRAMES > 0   the sim: hash the PFB every ZM_EVERY frames as
 *                   apps/scene_hash.mjs does, print its JSON, "ZM VSTAT", end.
 *   ZM_BOARD        the bitstream: ZM_FRAMES = 0, run forever, no hashing; each
 *                   finished frame is CART_BEAT, the state CART_RUNNING.
 *
 * Lines (sim): "ZM BOOT c", per frame "ZM HF f cycles", the scene_hash JSON,
 * "ZM VSTAT underrun overflow swaps vbls undrained", "ZM MIS ...", "ZM BLIT calls hw cycles" (bblit.h),
 * "ZM END rc". With the audio (cycles/baudio.c; ZM_NO_AUDIO without): per frame "ZM AF f cart audio"
 * (the cycles of cart.frame() and of the players), "ZM SONG ts name" per song, then "ZM AUD ...".
 * Per frame too: "ZM QF f bg planes present" (the sequencer's cycles), "ZM BF f" + calls/cycles/units
 * of each blitter op and "ZM WF f" + the bus counters (report_frame), and with ZM_TRACE_FRAME = f
 * that frame's ops one by one ("ZM BT"). ZM_WARP_MS starts the cart's timeline late.
 * The drive (bdisk.h): "ZM DISK ..." at boot, before the cart's init can read it, and at the end;
 * GEM over a data disk (bdiskapp.h): "ZM GEMDISK ..." at boot, "ZM CARTREQ ..." on a request.
 * A disk's boot sector (bbootsec.h, board images): "ZM BOOTSEC ..." before the cart boots.
 * KOS (bkos.h): "ZM KOS boot ..." at boot, and with a POST "ZM KOSHASH f hash" (sim) and "ZM KOS post n". */
#include <stdio.h>
#include <stdlib.h>

#include "baudio.h"
#include "bblit.h"
#include "bbootsec.h"
#include "bdisk.h"
#include "bdiskapp.h"
#include "bkos.h"
#include "bcursor.h"
#include "binput.h"
#include "bboard.h"
#include "bdiag.h"
#include "bmailbox.h"
#include "bplanes.h"
#include "boot.h"
#include "bsys.h"
#include "sha256.h"
#include "trap.h"
#include "vboard.h"
#include "vplan.h"
#include "vseq.h"
#include "vstat.h"
#include "wasm-rt-exceptions.h"
#include "wasm-rt-impl.h"
#include "zm_memmap.h"

/* ZM_WARP_MS (sim only): frame 1's dt, to start a cart's timeline late (a part that starts after
 * 25 s would take hours of sim to reach); 0 = every frame is 16.6 ms, as on the board. The native
 * host's HOST_WARP_MS is the same switch, for the reference hashes. */
#ifndef ZM_WARP_MS
#define ZM_WARP_MS 0
#endif

/* ZM_TRACE_FRAME (sim only): that frame's hwBlit calls one by one, "ZM BT f i cmd gap cycles units". */
#ifndef ZM_TRACE_FRAME
#define ZM_TRACE_FRAME 0
#endif

/* ZM_MODES (sim only): "a,b,c" -> setShadeMode(a) before frame 1, b before frame 1 + ZM_MODE_FRAMES,
 * ... so one run measures several of a cart's modes (blitter_demo's GLENZ/RUBBER/TILE/DELAY). The
 * native host takes the same calls as --call F:setShadeMode:N, for the reference hashes. */
#ifndef ZM_MODE_FRAMES
#define ZM_MODE_FRAMES 3
#endif

#define PICTURE_BYTES (ZM_RASTER_WIDTH * ZM_RASTER_HEIGHT * 4u)
#define SAMPLES (ZM_FRAMES / (ZM_EVERY ? ZM_EVERY : 1) + 1)

#ifdef ZM_NO_AUDIO
#define AUDIO(call) ((void)0)
#else
#define AUDIO(call) call
#endif

static struct w2c_env g_env;
static char g_hashes[SAMPLES][65];
static uint32_t g_cart, g_seq; /* the last frame's cart.frame() and sequencer cycles (vstat.h) */

/* The hashed frame's sha256 and PFB size, for hash_plane. */
static sha256_ctx* g_h;
static u32 g_pfb_size;

/* After plane p: the PFB once its last row reached memory, past the CPU's stale cache; or "off". */
static void hash_plane(unsigned p, int on) {
    if (!on) {
        char off[16];
        sha256_update(g_h, off, (size_t)snprintf(off, sizeof off, "off%u", p));
        return;
    }
    vseq_idle();
    zmv_flush_dcache();
    sha256_update(g_h, g_env.memory.data + w2c_machine_hwPhysicalPtr(&g_env.machine), g_pfb_size);
}

static void frame(sha256_ctx* h, u32 planes, u32 size, long f) {
    struct w2c_env* e = &g_env;
    uint32_t tc = board_cycles();
    w2c_rom_kosTick(&e->rom); /* KOS's frame counter (sysvars.frames), as the browser's frame */
    vseq_clear(e);
    binput_frame(e); /* the glass's keys, joypad and mouse, before the frame as the browser's */
    bdiskapp_media(e, f); /* KOS: drive A changed under the running cart (glass I / E)? */
    uint32_t t0 = board_cycles();
    HOST_CART_FRAME(e, f == 1 && ZM_WARP_MS ? (float)ZM_WARP_MS : 16.6f);
    bdiskapp_frame(e, f); /* GEM over a data disk: the browser's step after the frame */
    uint32_t t1 = board_cycles();
    AUDIO(baudio_frame(e)); /* the song bridge, then the players up to the sound's lead */
    printf("ZM AF %ld %lu %lu\n", f, (unsigned long)(t1 - t0), (unsigned long)(board_cycles() - t1));
    uint32_t t2 = board_cycles();
    /* Asked once, before any cart code can run between planes; again in video.zig's place when
     * a plane has an HBL handler (vplan.h). Only the lines that changed are composited. */
    unsigned on = 0;
    for (u32 p = 0; p < planes; p++) on |= HOST_CART_PLANE_ON(e, p) ? 1u << p : 0u;
    int handler = vplan_frame(e, on, h != NULL); /* a hashed frame composites every line: its PFB */
    if (h) bplanes_check_pre(e, on, planes, handler);
    g_h = h, g_pfb_size = size; /* a hashed frame is plane-major: its PFB after each plane */
    if (bplanes_run(e, on, planes, handler, !h && bplanes_lm(), h ? hash_plane : NULL)) vseq_mix_only();
    if (h) bplanes_check_post(f);
    vplan_end(f);
    uint32_t t3 = board_cycles();
    bcursor_draw(); /* the board has no host cursor: GEM's arrow over the picture */
    vseq_copper_end(on);
    mb_presenting();
    vseq_present();
    g_cart = t1 - t0, g_seq = (t0 - tc) + (board_cycles() - t2);
    /* the sequencer's share (sim): BG passes, the planes' passes (and hashes), PRESENT */
#ifndef ZM_BOARD /* nothing is printed there, but the formatting would still cost */
    printf("ZM QF %ld %lu %lu %lu\n", f, (unsigned long)(t0 - tc), (unsigned long)(t3 - t2),
           (unsigned long)(board_cycles() - t3));
#endif
}

static void print_json(char* total) {
    printf("{\"cart\":\"%s\",\"frames\":%d,\"every\":%d,\"calls\":[],\"samples\":[", HOST_CART_TAG, ZM_FRAMES, ZM_EVERY);
    for (int i = 0; i < ZM_FRAMES / ZM_EVERY; i++)
        printf("%s{\"frame\":%d,\"hash\":\"%s\"}", i ? "," : "", (i + 1) * ZM_EVERY, g_hashes[i]);
    printf("],\"total\":\"%s\"}\n", total);
}

/* ZM_FRAMES frames (forever if 0), hashing every ZM_EVERY-th. */
static void run(void) {
    u32 size = w2c_machine_hwPhysWidth(&g_env.machine) * w2c_machine_hwPhysHeight(&g_env.machine) * 4;
    u32 planes = w2c_machine_hwPlanesNumber(&g_env.machine);
    sha256_ctx total, h;
    sha256_init(&total);
    for (long f = 1; ZM_FRAMES == 0 || f <= ZM_FRAMES; f++) {
        int sample = ZM_FRAMES && f % ZM_EVERY == 0;
        uint32_t c0[ZM_NCOUNT], c1[ZM_NCOUNT];
#ifdef ZM_MODES
        static const int modes[] = {ZM_MODES};
        long mi = (f - 1) / ZM_MODE_FRAMES;
        if ((f - 1) % ZM_MODE_FRAMES == 0 && mi < (long)(sizeof modes / sizeof modes[0])) {
            double arg = modes[mi];
            host_call(&g_env, "setShadeMode", &arg, 1);
        }
#endif
        bblit_frame_reset();
        board_counters(c0);
        uint32_t t0 = board_cycles();
        if (sample) sha256_init(&h);
        vstat_begin();
        frame(sample ? &h : NULL, planes, size, f);
        vstat_end(f, g_cart, g_seq);
        board_beat((uint32_t)f);
        mb_frame_done((uint32_t)f);
        printf("ZM HF %ld %lu\n", f, (unsigned long)(board_cycles() - t0));
        board_counters(c1);
#ifndef ZM_BOARD
        bblit_report_frame(f, ZM_TRACE_FRAME, c0, c1);
#endif
        if (!sample) continue;
        sha256_hex(&h, g_hashes[f / ZM_EVERY - 1]);
        sha256_update(&total, g_hashes[f / ZM_EVERY - 1], 64);
    }
    char hex[65];
    sha256_hex(&total, hex);
    print_json(hex);
}

static void boot(void) {
    uint32_t t0 = board_cycles();
#ifdef ZM_SPLIT_SYS
    bsys_link(); /* the lean cart image first (bsys.h): its header says where the disk may start */
#endif
    bdisk_boot(); /* host_boot runs the cart's init, which may already read the disk */
    bdiskapp_boot(); /* after bdisk_boot: the disk it found decides */
    int sector = bbootsec_wanted(); /* the disk's boot sector runs before its cart (bbootsec.h) */
    uint32_t post = bkos_post_frames(); /* KOS's POST before both (bkos.h) */
    host_boot_machine(&g_env);
    bkos_boot(&g_env, bdiskapp_bootable); /* the system variables, hwInit */
    if (!sector && !post) host_boot_cart(&g_env);
    /* The pictures at fixed addresses (bmailbox.h), black until the first swap. */
    for (uint32_t i = 0; i < PICTURE_BYTES / 4; i++) {
        ((volatile uint32_t*)ZM_FB0_ADDR)[i] = 0;
        ((volatile uint32_t*)ZM_FB1_ADDR)[i] = 0;
    }
    vseq_init(&g_env, ZM_FB0_ADDR, ZM_FB1_ADDR);
    struct w2c_machine* m = &g_env.machine;
    uint32_t pfb = (uint32_t)(uintptr_t)(g_env.memory.data + w2c_machine_hwPhysicalPtr(m));
    mb_init(pfb, w2c_machine_hwPhysWidth(m), w2c_machine_hwPhysHeight(m));
    vstat_boot(); /* its block of the page mb_init just zeroed */
    printf("ZM MB pfb %08lx %lu x %lu\n", (unsigned long)pfb, (unsigned long)w2c_machine_hwPhysWidth(m),
           (unsigned long)w2c_machine_hwPhysHeight(m));
    if (post) bkos_run(&g_env, post);
    if (sector) bbootsec_run(&g_env);
    if (sector || post) host_boot_cart(&g_env); /* the compositor snoops the cart's boot */
    AUDIO(baudio_boot());
    printf("ZM BOOT %lu\n", (unsigned long)(board_cycles() - t0));
}

int main(void) {
    trap_install(); /* first: it sets mstatus.FS, and on an FPU core (ZM_FPU=1) any F instruction before traps */
    diag_maybe(); /* the write-path diagnostic, when the ARM asked for one (bdiag.h) */
    board_state(ZM_CART_BOOTING);
    wasm_rt_init();
    wasm_rt_trap_t trap = wasm_rt_impl_try();
    if (trap) {
        printf("ZM WASMTRAP %s\n", wasm_rt_strerror(trap));
        board_finish(1);
    }
    boot();
    board_state(ZM_CART_RUNNING);
    run();
    uint32_t st = zmv_status();
    printf("ZM VSTAT %lu %lu %lu %lu %lu\n", (unsigned long)((st & ZMV_BIT(UNDERRUN)) != 0),
           (unsigned long)((st & ZMV_BIT(OVERFLOW)) != 0), (unsigned long)ZMV_REG(SWAPS),
           (unsigned long)ZMV_REG(FRAME), (unsigned long)vseq.undrained);
    printf("ZM MIS %lu %lu\n", (unsigned long)zm_misaligned[0], (unsigned long)zm_misaligned[1]);
    printf("ZM BLIT %lu %lu %lu\n", (unsigned long)bblit.calls, (unsigned long)bblit.hw, (unsigned long)bblit.cycles);
    vplan_report();
    bplanes_report();
    AUDIO(baudio_report());
    bdisk_report();
    board_finish(w2c_machine_hwRamAllocFailures(&g_env.machine) ? 1 : 0);
}
