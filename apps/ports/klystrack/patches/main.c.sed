# KESTREL: main() is called by kestrel_main.c (Asyncify coroutine); the song tables are statics, not stack.
s/^int main(int argc, char \*\*argv)$/int klystrack_main(int argc, char **argv)/
s/^\tMusInstrument instrument\[NUM_INSTRUMENTS\];$/\tstatic MusInstrument instrument[NUM_INSTRUMENTS];/
s/^\tMusPattern pattern\[NUM_PATTERNS\];$/\tstatic MusPattern pattern[NUM_PATTERNS];/
s/^\tMusSeqPattern sequence\[MUS_MAX_CHANNELS\]\[NUM_SEQUENCES\];$/\tstatic MusSeqPattern sequence[MUS_MAX_CHANNELS][NUM_SEQUENCES];/
s/^\tMusChannel channel\[CYD_MAX_CHANNELS\];$/\tstatic MusChannel channel[CYD_MAX_CHANNELS];/
# no MIDI on the cart (midi.c is ALSA): the clock/transport messages it handles never arrive
s/^\t\t\t\t\tmidi_event(&e);$/\t\t\t\t\t\/* KESTREL: no MIDI *\//
# Linux's default (CONFIG_DEFAULT_DISABLE_RENDER_TO_TEXTURE) from the first gfx_domain_update, not only after the
# config is applied: otherwise a 320x240 intermediate texture is created at boot and never freed.
/^\tdomain->fps = 30;$/a\
\tdomain->flags |= GFX_DOMAIN_DISABLE_RENDER_TO_TEXTURE; /* KESTREL */
# Repaint at 30 Hz only while something moves (kestrel_sdl.c kestrel_redraw_due: a song plays, the last repaints
# changed the picture, a timer fired); upstream repaints the whole UI 30 times a second even idle (~45 Mc each on
# the board). Events and song-position changes still repaint at once.
s/^\t\tif (active && (got_event || gfx_domain_is_next_frame(domain) || prev_position != mused.stat_song_position))$/\t\tif (active \&\& (got_event || kestrel_redraw_due(gfx_domain_is_next_frame(domain), (mused.flags \& SONG_PLAYING) != 0) || prev_position != mused.stat_song_position)) \/* KESTREL *\//
/^int klystrack_main(int argc, char \*\*argv)$/i\
int kestrel_redraw_due(int tick_due, int playing); /* KESTREL: kestrel_sdl.c */\
void kestrel_view_event(const SDL_Event *e); /* KESTREL: kestrel_view.c */
# Round 4: each event polled tells kestrel_view.c that the views must draw (kestrel_view_event: not a bare pointer
# move, nor a move while the menu owns the pointer).
s/^\t\twhile (SDL_PollEvent(&e))$/\t\twhile (SDL_PollEvent(\&e) \&\& (kestrel_view_event(\&e), 1)) \/* KESTREL *\//
