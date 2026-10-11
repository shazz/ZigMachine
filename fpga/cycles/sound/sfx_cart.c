/* The effects bench's cart side (cycles/sound.mk snd-fx, tools/bard_fx_run.py): a scripted cart,
 * so the cart CPU's real path (host/audio_bridge.c, cycles/bsound.c) carries a song request and
 * a zg.requestSndhMode to the sound CPU's own firmware (the play image every cart uses) in a few
 * frames, where a real screen (union_beatdis) takes 130 frames to depack before its music starts.
 *
 * The cart is its exports (host.h host_song_bridge) over a small memory of its own: frame 1
 * requests ZM_SONG (subtune ZM_TUNE), frame ZM_FX_AT queues one requestSndhMode(ZM_FX_MODE),
 * as libs/zig/sfx_queue.zig lays the entry out. A frame is 1/60 s of the sys clock (the cart CPU
 * does not see the audio core's sample counter); after ZM_FRAMES the sim ends. */
#include <stdio.h>
#include <string.h>

#include "baudio.h"
#include "board.h"
#include "haudio.h"
#include "snd_mailbox.h"
#include "trap.h"

#define FRAME_CLOCKS 1666667u /* 100 MHz / 60 */
#define FX_AT_MEM 64u          /* the entries' address in the cart's memory; the name is at 0 */

static uint8_t g_mem[128];
static struct w2c_env g_env;
static long g_frame;

static u32 poll(w2c_cart* c) { (void)c; return g_frame == 1; }
static u32 name_ptr(w2c_cart* c) { (void)c; return 0; }
static u32 name_len(w2c_cart* c) { (void)c; return (u32)strlen((const char*)g_mem); }
static u32 tune(w2c_cart* c) { (void)c; return ZM_TUNE; }
static u32 sfx_poll(w2c_cart* c) { (void)c; return g_frame == ZM_FX_AT; }
static u32 sfx_entries(w2c_cart* c) { (void)c; return FX_AT_MEM; }

const host_song_bridge host_songs = {.poll = poll, .name_ptr = name_ptr, .name_len = name_len, .tune = tune,
                                     .sfx_poll = sfx_poll, .sfx_entries = sfx_entries};

int main(void) {
    trap_install();
    strncpy((char*)g_mem, ZM_SONG, FX_AT_MEM - 1);
    g_mem[FX_AT_MEM] = FX_SNDH_MODE; /* sfx_queue.zig Entry: op, a = the mode, the rest 0 */
    g_mem[FX_AT_MEM + 1] = ZM_FX_MODE;
    g_env.memory.data = g_mem;
    g_env.memory.size = sizeof g_mem;
    baudio_boot();
    if (!baudio.on) board_finish(2);
    uint32_t t = board_cycles();
    for (g_frame = 1; g_frame <= ZM_FRAMES; g_frame++) {
        while (board_cycles() - t < FRAME_CLOCKS) baudio_report_log();
        t += FRAME_CLOCKS;
        baudio_frame(&g_env);
        printf("ZM FXF %ld\n", g_frame);
    }
    baudio_report();
    board_finish(0);
}
