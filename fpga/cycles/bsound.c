/* The cart CPU's audio when the players run on the sound CPU (soc/zm_sound_cpu.py,
 * docs/FPGA_SOUND_CPU.md): the same baudio_* entry points as cycles/baudio.c, but the
 * players are not here. This side loads the sound image, starts it, forwards the cart's
 * song requests and effects as mailbox commands (cycles/snd_mailbox.h), and prints the
 * sound CPU's console between frames. The song bridge itself is host/audio_bridge.c's:
 * its audio_play / audio_sndh_call / audio_effects land here. */
#include <stdio.h>
#include <string.h>

#include "baudio.h"
#include "haudio.h"
#include "snd_mailbox.h"
#include "vboard.h"

/* The sound firmware's image, linked in as a blob (cycles/sound.mk: objcopy -I binary). */
extern const uint8_t _binary_snd_bin_start[], _binary_snd_bin_end[];

struct baudio baudio;
static uint32_t g_seq, g_log_read;
static void drain_log(void);
#define READY_WAIT 200000000u /* sys clocks: the sound CPU's boot is its wasm2c instantiation */

void baudio_report_log(void) { drain_log(); }

static void drain_log(void) {
    uint32_t end = SND_REG(SND_S2C + S_LOG);
    if (end == g_log_read) return;
    zmv_flush_dcache(); /* the ring is the sound CPU's stores: drop any line this D-cache holds */
    if (end - g_log_read > SND_LOG_BYTES) g_log_read = end - SND_LOG_BYTES; /* lapped: keep the newest */
    const volatile char* ring = (const volatile char*)SND_LOG_ADDR;
    for (; g_log_read != end; g_log_read++) putchar(ring[g_log_read % SND_LOG_BYTES]);
}

void baudio_boot(void) {
    if (SND_REG(SND_ID) != SND_ID_VALUE) {
        printf("ZM SOUND none (id %08lx)\n", (unsigned long)SND_REG(SND_ID));
        return;
    }
    SND_REG(SND_CTRL) = 0;
    memcpy((void*)SND_BASE, _binary_snd_bin_start, (size_t)(_binary_snd_bin_end - _binary_snd_bin_start));
    /* S2C is the sound CPU's alone, and an earlier run may have left READY in it: the boot answers
     * a nonce instead, the SEQ written before it starts, echoed in ACK once it polls. */
    uint32_t t0 = SND_REG(SND_CYCLES);
    g_seq = t0 | 1u;
    SND_REG(SND_C2S + C_SEQ) = g_seq;
    SND_REG(SND_CTRL) = SND_RUN;
    while (SND_REG(SND_S2C + S_ACK) != g_seq || SND_REG(SND_S2C + S_READY) != S_READY_VALUE) {
        if (SND_REG(SND_CYCLES) - t0 > READY_WAIT) {
            drain_log();
            printf("ZM SOUND no answer\n");
            return;
        }
    }
    baudio.on = 1;
    drain_log();
}

/* The previous command is done (a song load takes a few Mcycles). */
static void wait_ack(void) {
    while (SND_REG(SND_S2C + S_ACK) != g_seq) {
    }
}

/* Post one command; the previous one must be done first. */
static void post(uint32_t op, const char* name, uint32_t arg) {
    if (!baudio.on) return;
    wait_ack();
    const uint8_t* data = NULL;
    int32_t len = -1;
    for (const zm_song* s = zm_songs; s->name; s++) {
        if (strcmp(s->name, name) == 0) {
            data = s->data;
            len = (int32_t)s->len;
            break;
        }
    }
    uint32_t words[C_NAME_WORDS] = {0};
    strncpy((char*)words, name, sizeof words - 1);
    for (uint32_t i = 0; i < C_NAME_WORDS; i++) SND_REG(SND_C2S + C_NAME + i) = words[i];
    SND_REG(SND_C2S + C_OP) = op;
    SND_REG(SND_C2S + C_ARG) = arg;
    SND_REG(SND_C2S + C_PTR) = (uint32_t)(uintptr_t)data;
    SND_REG(SND_C2S + C_LEN) = (uint32_t)len;
    SND_REG(SND_C2S + C_SEQ) = ++g_seq;
}

void audio_play(const char* name, uint32_t tune) { post(OP_PLAY, name, tune); }
void audio_sndh_call(const char* name, uint32_t d0) { post(OP_SNDH_CALL, name, d0); }

/* The frame's effects, C_FX_MAX a command. A play's or a stream feed's bytes are read by the sound
 * CPU from the cart's memory while it runs the command, so a command holding one is waited for:
 * the browser copies them as it drains the queue, and the cart may reuse the buffer next frame (a
 * feed's, within the frame). A sample's (FX_SAMPLE) are read as it plays: the cart keeps them. */
void audio_effects(const audio_fx* fx, uint32_t n) {
#ifdef ZM_SND_FX_DROP /* the mutant tools/bard_fx_run.py --drop builds: the requests never reach BARD */
    (void)fx, (void)n;
    return;
#endif
    if (!baudio.on) return;
    for (uint32_t i = 0; i < n; i += C_FX_MAX) {
        uint32_t k = n - i < C_FX_MAX ? n - i : C_FX_MAX, plays = 0;
        wait_ack();
        for (uint32_t j = 0; j < k; j++) {
            const audio_fx* f = &fx[i + j];
            volatile uint32_t* w = &SND_REG(SND_C2S + C_FX + C_FX_WORDS * j);
            w[0] = f->op | (uint32_t)f->a << 8 | (uint32_t)f->b << 16;
            w[1] = (uint32_t)f->pcm;
            w[2] = f->len;
            w[3] = f->rate;
            plays += f->op == FX_PLAY || f->op == FX_STREAM_FEED;
        }
        SND_REG(SND_C2S + C_OP) = OP_EFFECTS;
        SND_REG(SND_C2S + C_ARG) = k;
        SND_REG(SND_C2S + C_SEQ) = ++g_seq;
        if (plays) wait_ack();
    }
}

void baudio_frame(struct w2c_env* e) {
    if (!baudio.on) return;
    audio_bridge(e);
    drain_log();
}

void baudio_pump(uint32_t min) { (void)min; } /* the sound CPU paces itself */

void baudio_report(void) {
    if (!baudio.on) return;
    drain_log();
    printf("ZM AUD pushed %lu applied %lu status %lx resyncs %lu anchors %lu renders %lu\n",
           (unsigned long)SND_REG(SND_S2C + S_PUSHED), (unsigned long)SND_REG(SND_S2C + S_APPLIED),
           (unsigned long)SND_REG(SND_S2C + S_STATUS), (unsigned long)SND_REG(SND_S2C + S_RESYNCS),
           (unsigned long)SND_REG(SND_S2C + S_ANCHORS), (unsigned long)SND_REG(SND_S2C + S_RENDERS));
}
