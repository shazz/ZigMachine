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
