# KESTREL: refuse a song with more patterns / sequence entries than the capped tables hold (kestrel_port.h)
# instead of writing past them.
/^\t\t\tFIX_ENDIAN(song->num_sequences\[i\]);$/a\
\
\t\tif (song->num_patterns > KESTREL_MAX_PATTERNS) { warning("KESTREL: song has %u patterns, max %u", (unsigned)song->num_patterns, KESTREL_MAX_PATTERNS); return 0; }\
\t\tfor (int i = 0 ; i < (int)song->num_channels ; ++i)\
\t\t\tif (song->num_sequences[i] > KESTREL_MAX_SEQUENCES) { warning("KESTREL: song has %u sequence entries, max %u", (unsigned)song->num_sequences[i], KESTREL_MAX_SEQUENCES); return 0; }
# KESTREL: before a song's FX settings are applied, free the reverb / chorus buffers of every bus the new
# settings leave off (patches/cydfx.c.sed allocates them on demand), so a song change gives their memory back
# before the new song's buses ask for theirs.
/^void mus_set_fx(MusEngine \*mus, MusSong \*song)$/,/^}$/{
/^\tcyd_lock(mus->cyd, 1);$/a\
\tfor (int f = 0 ; f < CYD_MAX_FX_CHANNELS ; ++f)\
\t{\
\t\tCydFx *fx = &mus->cyd->fx[f];\
\t\tif (!(song->fx[f].flags & CYDFX_ENABLE_REVERB) && fx->rvb.buffer) { fx->flags &= ~CYDFX_ENABLE_REVERB; free(fx->rvb.buffer); fx->rvb.buffer = NULL; }\
\t\tif (!(song->fx[f].flags & CYDFX_ENABLE_CHORUS) && fx->chr.lut) { fx->flags &= ~CYDFX_ENABLE_CHORUS; free(fx->chr.buffer); free(fx->chr.lut); fx->chr.buffer = fx->chr.lut = NULL; }\
\t}
}
