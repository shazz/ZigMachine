/* The board's audio backend (host/haudio.h): the players run here, on the cart
 * CPU, and their chip calls go to the audio core's stamped write queue
 * (soc/zm_audio_soc.py, rtl/audio/zm_audio_sched.v) at AUDIO_WINDOW.
 *
 * Pacing: the core makes 44.1 kHz from the system clock and counts its samples
 * (NOW). Each frame the players render up to NOW + the lead, so the writes
 * reach the queue before their samples; the stamps themselves are the
 * machine's (host/audio_imports.c), so the core hears every write at the sample
 * the machine would, whatever the frame's timing. If the cart CPU falls behind
 * (a frame longer than the latency), the stamp jumps ahead of NOW again and the
 * jump is counted (`resyncs`); the writes in between land late (STATUS.late).
 * The songs are linked in (tools/song_pack.py: the cart's literal song names), and found
 * by name in cycles/bsongs.c; on the sound CPU a song comes in its mailbox command
 * (cycles/sound/smain.c). */
#include <stdio.h>
#include <string.h>

#include "audio_queue.h"
#include "audio_regs.h"
#include "baudio.h"
#include "board.h"
#include "haudio.h"
#include "bsndinfo.h"

#ifdef ZM_SND /* the players on BARD: its own cycle counter (the cart CPU's CSRs are not on its bus) */
#include "snd_mailbox.h"
#define SND_ROUTE ROUTE_BARD
static inline uint32_t render_clock(void) { return SND_REG(SND_CYCLES); }
#else
#define SND_ROUTE ROUTE_ZIGGY
static inline uint32_t render_clock(void) { return board_cycles(); }
#endif

#define ZMA_WINDOW 0x92000000u /* soc/zm_audio_soc.py AUDIO_WINDOW */
#define ZMA_REG(w) (*(volatile uint32_t*)(ZMA_WINDOW + 4u * (w)))
enum { ZMA_QA = 0, ZMA_QD = 1, ZMA_NOW = 2, ZMA_LEVEL = 3, ZMA_STATUS = 4, ZMA_PCM_BASE = 5, ZMA_APPLIED = 6,
       ZMA_ID = 7 };
/* The lead (host/audio_queue.h zma_lead): samples ahead of the sound, four 60 Hz frames (67 ms;
 * the board runs a cart at 30-40 fps: a frame must never outlast it), three for a native digi. */
static uint32_t g_lead = 4u * ZMA_FRAME;
static zma_dedup g_dedup = {{~0u, ~0u, ~0u}};
#define ZMA_MAX_RENDER 4096u
/* The audio words of the debug mailbox (bmailbox.h): ZM_MB_ADDR + 0x80 = PS DDR 0x05ffff80, for
 * `md.l 0x05ffff80 8` from U-Boot: 'ZMAU', pushed, applied, status, resyncs, anchors, now, level. */
#define ZMA_MB ((volatile uint32_t*)0x41ffff80u)

struct baudio baudio;
static uint32_t g_credits;
static uint32_t g_native; /* the last audio_backend_native: the debug page's player */
static void mailbox(void);

void audio_backend_boot(void) {
    ZMA_REG(ZMA_PCM_BASE) = (uint32_t)(uintptr_t)g_aud.memory.data;
    ZMA_REG(ZMA_STATUS) = 0;
}

/* The players are instantiated (a few Mcycles of data segments): stamp from now on. */
void audio_backend_start(void) { zma_set_ts(ZMA_REG(ZMA_NOW) + g_lead); }

void audio_backend_native(uint32_t native) {
    g_lead = zma_lead(native);
    g_native = native;
}

/* A song request (host/audio.c): the debug page's song until its player starts. */
void audio_backend_song(const char* name, uint32_t tune) { sndinfo_song(SND_ROUTE, name, tune); }

/* A song was just staged and loaded: that can take a few Mcycles (an SNDH's depack and its
 * 1 MiB of 68000 RAM zeroed), past the sound's lead. Its first write then starts a full lead
 * ahead again, so the song plays from its start, on time (counted in `anchors`). */
void audio_song_loaded(const char* name) {
    uint32_t now = ZMA_REG(ZMA_NOW);
    if ((int32_t)(zma_ts() - now) < (int32_t)(g_lead / 2)) {
        zma_set_ts(now + g_lead);
        baudio.anchors++;
    }
    sndinfo_started(g_native);
    printf("ZM SONG %lu %lu %s\n", (unsigned long)zma_ts(), (unsigned long)baudio.pushed, name);
}

/* Room in the queue: wait while it is full (the core drains it as time passes). */
static void refill(void) {
    uint32_t level;
    level = ZMA_REG(ZMA_LEVEL);
    if (level >= ZMA_DEPTH) baudio.full++;
    while (level >= ZMA_DEPTH) level = ZMA_REG(ZMA_LEVEL);
    g_credits = ZMA_DEPTH - level;
}

void zma_put(uint32_t addr, uint32_t data) {
    if (!zma_dedup_keep(&g_dedup, addr, data)) {
        baudio.dropped++;
        return;
    }
    if (!g_credits) refill();
    g_credits--;
    ZMA_REG(ZMA_QA) = (zma_ts() << 10) | (addr & 0x3FFu);
    ZMA_REG(ZMA_QD) = data;
    baudio.pushed++;
}

void baudio_boot(void) {
    if (ZMA_REG(ZMA_ID) != 0x5A410100u) {
        printf("ZM AUDIO none (id %08lx)\n", (unsigned long)ZMA_REG(ZMA_ID));
        return;
    }
    baudio.on = 1;
    g_credits = 0;
    sndinfo_boot(SND_ROUTE);
    audio_boot();
}

#ifndef ZM_SND /* the sound CPU's image has no cart, so no bridge: it calls baudio_pump itself */
void baudio_frame(struct w2c_env* e) {
    if (!baudio.on) return;
    audio_bridge(e);
    baudio_pump(1);
}
#endif

/* Render up to the lead, if at least `min` samples are due; the debug mailbox after. */
void baudio_pump(uint32_t min) {
    uint32_t now = ZMA_REG(ZMA_NOW);
    int32_t ahead = (int32_t)(zma_ts() - now);
    if (ahead < 0) { /* fell behind the sound: jump ahead again, count it */
        zma_set_ts(now + g_lead / 2);
        baudio.resyncs++;
        ahead = (int32_t)(g_lead / 2);
    }
    int32_t want = (int32_t)g_lead - ahead;
    if (want >= (int32_t)min) {
        uint32_t n = (uint32_t)want < ZMA_MAX_RENDER ? (uint32_t)want : ZMA_MAX_RENDER, t0 = render_clock();
        audio_render(n);
        sndinfo_render(render_clock() - t0, n);
    }
    mailbox();
}

static void mailbox(void) {
    ZMA_MB[0] = 0x55414d5au; /* "ZMAU" */
    ZMA_MB[1] = baudio.pushed;
    ZMA_MB[2] = ZMA_REG(ZMA_APPLIED);
    ZMA_MB[3] = ZMA_REG(ZMA_STATUS);
    ZMA_MB[4] = baudio.resyncs;
    ZMA_MB[5] = baudio.anchors;
    ZMA_MB[6] = ZMA_REG(ZMA_NOW);
    ZMA_MB[7] = ZMA_REG(ZMA_LEVEL);
}

void baudio_report(void) {
    if (!baudio.on) return;
    printf("ZM AUD pushed %lu applied %lu status %lx level %lu now %lu ts %lu resyncs %lu anchors %lu"
           " dropped %lu full %lu\n",
           (unsigned long)baudio.pushed, (unsigned long)ZMA_REG(ZMA_APPLIED), (unsigned long)ZMA_REG(ZMA_STATUS),
           (unsigned long)ZMA_REG(ZMA_LEVEL), (unsigned long)ZMA_REG(ZMA_NOW), (unsigned long)zma_ts(),
           (unsigned long)baudio.resyncs, (unsigned long)baudio.anchors, (unsigned long)baudio.dropped,
           (unsigned long)baudio.full);
}
