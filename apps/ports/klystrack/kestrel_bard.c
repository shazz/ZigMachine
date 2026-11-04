/* The song klystrack plays, on the machine's .kt player (libs/zig/players/kt.zig: BARD on the board, the audio
 * thread in the browser) instead of cyd on the cart CPU (~23 Mc a frame playing on ZIGGY, ~5 fps).
 *
 * On Play (klystrack's play(): the music engine gets the song) the song is written as a .kt (save_song_inner,
 * the "save unused elements?" question skipped: patches/diskop.c.sed) into a buffer and handed over through the
 * effects queue: zg.requestSongBytes's entry (libs/zig/sfx_queue.zig, op 8, kind 5 = .kt) with the sequence row
 * to start at. cyd then stops synthesising: the cart's stream is stopped (kestrel_audio_quiet) and only the
 * sequencer runs, at the song's rate, so the play position, the pattern view and the follow-play cursor move as
 * before. While it plays, the song is hashed every CHECK_SAMPLES of its clock (a quarter second): an edit
 * re-sends it from the row playing (a restart of the voices there: the simple first form). The cart's clock
 * runs in real time meanwhile (kestrel_bard_owns: kestrel_main.c lifts cyd's 33 ms cap, as the sequencer
 * alone is cheap), so the row the cart shows and re-sends is the one the machine plays. On Stop the request "none" stops the machine's player
 * and cyd takes the stream back. Keyjazz while a handed-over song plays is silent (cyd is not mixing).
 *
 * Fallback, nothing regresses: a song the machine's player would refuse (more than 16 channels, a .kt over the
 * queue's 256 KiB, more song RAM than it has: kt_fits) stays on cyd, as before. */
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stddef.h>

#include "SDL.h"
#include "mused.h"
#include "diskop.h"
#include "kestrel_audio.h"

void kestrel_log(const char *m);

enum { CHECK_SAMPLES = 22050 / 4, SONG_MAX = 256 * 1024, KT_MAX_CH = 16, OP_SONG = 8, KIND_KT = 5 };
/* libs/zig/players/kt.zig's song RAM: 1 MiB less the four Paula rings (64 KiB). */
#define KT_RAM (1048576u - 65536u)

int kestrel_bard_saving; /* patches/diskop.c.sed: save_song_inner asks nothing while it is set */

static uint8_t *buf;     /* the .kt handed over: read by the host when it drains the frame's queue */
static uint32_t sent_len, sent_hash;
static enum { IDLE, HANDED, REFUSED } state;
static uint32_t samples_since_check;

int kestrel_bard_owns(void) { return state == HANDED; }

/* --- the cart's side of the song bridge and the effects queue (docs/MUSIC.md) --- */
static uint8_t queue[16];
static uint32_t queued;
static int stop_asked;
static const char none[] = "none";

__attribute__((export_name("pollSfx"))) uint32_t pollSfx(void) { uint32_t n = queued; queued = 0; return n; }
__attribute__((export_name("sfxEntriesPtr"))) const void *sfxEntriesPtr(void) { return queue; }
__attribute__((export_name("pollSongRequest"))) uint32_t pollSongRequest(void) { int r = stop_asked; stop_asked = 0; return (uint32_t)r; }
__attribute__((export_name("songNamePtr"))) const char *songNamePtr(void) { return none; }
__attribute__((export_name("songNameLen"))) uint32_t songNameLen(void) { return 4; }
__attribute__((export_name("songTune"))) uint32_t songTune(void) { return 0; }

static void put32(uint8_t *p, uint32_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24); }

/* --- what the machine's player takes --- */
/* FNV over words where the block is word-aligned (all the big ones: patterns, sequences, instruments,
 * wavetables), bytes for the rest: a quarter of the multiplies of a byte FNV (song_hash ran ~1 M rv32
 * instructions every quarter second of song time). Only ever compared with itself (sent_hash). */
typedef uint32_t __attribute__((may_alias)) u32_alias;
static uint32_t fnv(uint32_t h, const void *p, size_t n)
{
    const uint8_t *b = p;
    size_t i = 0;
    if (((uintptr_t)b & 3) == 0)
        for (; i + 4 <= n; i += 4) h = (h ^ *(const u32_alias *)(const void *)(b + i)) * 16777619u;
    for (; i < n; i++) h = (h ^ b[i]) * 16777619u;
    return h;
}

/* Everything the .kt carries that an edit can change, hashed (cheaper than writing the song). */
static uint32_t song_hash(void)
{
    const MusSong *s = &mused.song;
    uint32_t h = 2166136261u;
    h = fnv(h, &s->num_channels, 1);
    h = fnv(h, &s->song_length, 2); h = fnv(h, &s->loop_point, 2);
    h = fnv(h, &s->song_speed, 1); h = fnv(h, &s->song_speed2, 1); h = fnv(h, &s->song_rate, 1);
    h = fnv(h, s->fx, sizeof s->fx);
    h = fnv(h, s->default_volume, sizeof s->default_volume); h = fnv(h, s->default_panning, sizeof s->default_panning);
    h = fnv(h, s->instrument, sizeof s->instrument[0] * s->num_instruments);
    for (int c = 0; c < s->num_channels; c++) h = fnv(h, s->sequence[c], sizeof s->sequence[c][0] * s->num_sequences[c]);
    for (int p = 0; p < s->num_patterns; p++) h = fnv(h, s->pattern[p].step, sizeof s->pattern[p].step[0] * s->pattern[p].num_steps);
    for (int w = 0; w < CYD_WAVE_MAX_ENTRIES; w++) {
        const CydWavetableEntry *e = &mused.mus.cyd->wavetable_entries[w];
        h = fnv(h, e, offsetof(CydWavetableEntry, data));
        if (e->data) h = fnv(h, e->data, sizeof e->data[0] * e->samples);
    }
    return h;
}

/* kt_core's memory for this song (an upper bound): the file, its tables, 2 s of reverb a reverb bus, the
 * chorus lines and the render block (libs/zig/players/kt_load.zig, kt_core.zig, kt.zig). */
static int kt_fits(uint32_t len)
{
    const MusSong *s = &mused.song;
    uint32_t need = len + 16384u + (uint32_t)s->num_instruments * 128u + 32u * 128u;
    for (int c = 0; c < s->num_channels; c++) need += 8u * s->num_sequences[c];
    for (int p = 0; p < s->num_patterns; p++) need += 16u + 8u * s->pattern[p].num_steps;
    for (int w = 0; w < CYD_WAVE_MAX_ENTRIES; w++) need += 2u * mused.mus.cyd->wavetable_entries[w].samples;
    for (int f = 0; f < CYD_MAX_FX_CHANNELS; f++) {
        if (s->fx[f].flags & CYDFX_ENABLE_REVERB) need += 2u * 22050u * 4u;
        if (s->fx[f].flags & CYDFX_ENABLE_CHORUS) need += 2u * 1102u * 4u;
    }
    return s->num_channels <= KT_MAX_CH && need <= KT_RAM;
}

/* The song as a .kt into buf, queued to start at sequence row `row`. 0: the machine's player would refuse it. */
static int send(uint16_t row)
{
    if (!buf && !(buf = malloc(SONG_MAX))) return 0;
    SDL_RWops *rw = SDL_RWFromMem(buf, SONG_MAX);
    if (!rw) return 0;
    kestrel_bard_saving = 1;
    save_song_inner(rw, NULL);
    kestrel_bard_saving = 0;
    Sint64 len = SDL_RWtell(rw);
    SDL_RWclose(rw);
    if (len <= 0 || len >= SONG_MAX || !kt_fits((uint32_t)len)) return 0;
    memset(queue, 0, sizeof queue);
    queue[0] = OP_SONG;
    queue[1] = KIND_KT;
    put32(queue + 4, (uint32_t)(uintptr_t)buf);
    put32(queue + 8, (uint32_t)len);
    put32(queue + 12, row); /* a .kt's tune: the row to start at (32 bits here, the entry's last word) */
    queued = 1;
    sent_len = (uint32_t)len;
    sent_hash = song_hash();
    return 1;
}

/* The sequencer alone for `frames` samples: cyd's callback at its rate (cyd_output_buffer's counter), no synth. */
static void sequencer_only(CydEngine *cyd, int frames)
{
    uint32_t left = (uint32_t)frames;
    while (left > 0) {
        if (cyd->callback_counter == 0) {
            cyd->callback_counter = cyd->callback_period - 1;
            if (!cyd->callback(cyd->callback_parameter)) return;
            left--;
            continue;
        }
        uint32_t k = cyd->callback_counter < left ? cyd->callback_counter : left;
        cyd->callback_counter -= k;
        left -= k;
    }
}

/* kestrel_sdl.c's mix, first: 1 when the machine plays the song (stereo is silence, the sequencer moved). */
int kestrel_bard_mix(CydEngine *cyd, int16_t *stereo, int frames)
{
#ifdef KESTREL_NO_BARD /* the build that keeps cyd (apps/frame_cost.mjs before/after: make EXTRA=-DKESTREL_NO_BARD) */
    (void)cyd; (void)stereo; (void)frames; (void)send; (void)sequencer_only;
    return 0;
#endif
    const MusEngine *mus = cyd->callback ? cyd->callback_parameter : NULL;
    if (!mus || mus->song != &mused.song) {
        if (state == HANDED) { stop_asked = 1; kestrel_audio_quiet(0); }
        state = IDLE;
        return 0;
    }
    if (state == REFUSED) return 0;
    if (state == IDLE) {
        if (!send(mus->song_position)) { state = REFUSED; kestrel_log("klystrack: song kept on cyd (too big for the .kt player)"); return 0; }
        state = HANDED;
        samples_since_check = 0;
        kestrel_audio_quiet(1);
    } else if ((samples_since_check += (uint32_t)frames) >= CHECK_SAMPLES) {
        samples_since_check = 0;
        if (song_hash() != sent_hash && !send(mus->song_position)) {
            state = REFUSED; /* grown past the player: cyd takes the song back where it is */
            stop_asked = 1;
            kestrel_audio_quiet(0);
            return 0;
        }
    }
    sequencer_only(cyd, frames);
    memset(stereo, 0, (size_t)frames * 4);
    return 1;
}
