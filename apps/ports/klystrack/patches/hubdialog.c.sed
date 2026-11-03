# KESTREL: this dialog's own loop repaints 30 times a second like the main loop; here only while something
# moves (kestrel_sdl.c kestrel_redraw_due: the key or click that opened it, a changed picture, a timer).
# The same patch is msgbox.c.sed and help.c.sed.
1i\
int kestrel_redraw_due(int tick_due, int playing); /* KESTREL: kestrel_sdl.c */
s/^\t\tif (got_event || gfx_domain_is_next_frame(domain))$/\t\tif (got_event || kestrel_redraw_due(gfx_domain_is_next_frame(domain), 0)) \/* KESTREL *\//
