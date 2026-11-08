/* Does the C64 keep real time? (SW_SID_ON_BARD; included by kestrel_sw.c.)
 *
 * The C64 is clocked by the frame's real time, all of it, except past the 100 ms cap: a frame longer than that
 * loses the rest (a stall is not caught up), and the music plays slow. kestrel_sw_pace.c keeps frames short by
 * holding the main program when ZIGGY falls behind, so the cap should never bite; when it does, it is counted
 * here, never silent. Once a second the bottom border shows, and the log says when it is not 100 %:
 *     C64 100% HELD 12% OWED 0.0S
 *   C64   the C64 time run over the wall time passed, last second (100 % = real time, the song's tempo)
 *   HELD  the share of that C64 time the main program (the editor) waited for the IRQs (kestrel_sw_pace.c)
 *   OWED  C64 time lost to the cap since the start, in seconds (stays 0.0 when the C64 keeps up) */

#define SW_RT_CAP_US 100000u                   /* a frame's C64 time at most (sw_run_c64) */

static uint64_t sw_rt_wall, sw_rt_c64, sw_rt_owed; /* this second's wall and C64 us; all the C64 us lost */
static uint32_t sw_rt_samples, sw_rt_held;     /* this second's C64 samples, and those the main program waited */
static char sw_rt_text[32], sw_rt_shown[32];
static uint32_t sw_rt_age;                     /* frames since the line was drawn */

/* This frame's real time (raw_us) -> the C64's (capped), counted. */
static uint32_t sw_rt_frame_us(uint32_t raw_us)
{
    uint32_t us = raw_us > SW_RT_CAP_US ? SW_RT_CAP_US : raw_us;
    sw_rt_wall += raw_us; sw_rt_c64 += us; sw_rt_owed += raw_us - us;
    if (sw_rt_wall >= 1000000u) {
        unsigned pct = (unsigned)(sw_rt_c64 * 100u / sw_rt_wall);
        unsigned held = sw_rt_samples ? (unsigned)((uint64_t)sw_rt_held * 100u / sw_rt_samples) : 0u;
        unsigned owed = (unsigned)(sw_rt_owed / 100000u);   /* tenths of a second */
        snprintf(sw_rt_text, sizeof sw_rt_text, "C64 %3u%% HELD %2u%% OWED %u.%uS", pct, held, owed / 10, owed % 10);
        if (pct < 100) kestrel_log(sw_rt_text);
        sw_rt_wall = sw_rt_c64 = 0; sw_rt_samples = sw_rt_held = 0;
    }
    return us;
}

/* The line in the bottom border (below the picture's 254 rows), redrawn when it changes. */
static void sw_rt_draw(void)
{
    if (!sw_rt_text[0] || (!strcmp(sw_rt_text, sw_rt_shown) && ++sw_rt_age < 60)) return;
    sw_rt_age = 0;
    strcpy(sw_rt_shown, sw_rt_text);
    Uint8 fg = strncmp(sw_rt_text, "C64 100%", 8) ? 2 : 11;  /* red when behind, grey when keeping up */
    for (int i = 0; sw_rt_text[i]; i++) {
        unsigned c = (unsigned char)sw_rt_text[i];
        sw_glyph(4 + 8 * i, SW_H + 2, sw_charset[0] + 8 * c, fg, 0);  /* the mixed set: ASCII capitals and digits */
    }
}
