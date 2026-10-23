/* The players' console words (host/audio.c): what a native replay and a refused SAP say. */
#ifndef ZM_HOST_AUDIO_NAMES_H
#define ZM_HOST_AUDIO_NAMES_H

/* libs/zig/players/digi.zig Status, as the console says it. Only a native replay
 * and a near miss are said: the general path, Musashi, is silent. */
static const char* const NATIVE[] = {
    NULL,
    "native beat_dis",
    "near miss: the digi handler with an unknown sequencer, on Musashi",
    "near miss: the driver's tables out of range, on Musashi",
    "native replays off, on Musashi",
    "native monty",
    "native wow_scroller",
    "native big_digital (handler)",
    "native hippel_mix4 (handler)",
    "native quartet_singsong (handler)",
    "native tcb_digi (handler)",
    "native sync_mix4 (handler)",
    "native mix3_timer_c (handler)",
    "native tcb_streams (handler)",
    "native mym_drums (handler)",
    "native game_sfx (handler)",
    "native big_digi (play + handler)",
};

/* demo_audio_sap.zig audioSapStatus: why a SAP was refused. */
static const char* const SAP_REFUSED[] = {"", "not a SAP", "no binary data", "a bad tag", "TYPE not B or C",
                                          "STEREO (a second POKEY)", "a missing INIT/MUSIC/PLAYER", "a bad block"};
#endif
