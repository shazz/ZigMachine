# KESTREL: kestrel_bard.c writes the song as a .kt for the machine's player on every Play (and edit while
# playing): save_song_inner must not ask "Save unused song elements?" then (a dialog in the middle of the mix);
# it keeps everything, as answering yes does.
/^int save_song_inner(SDL_RWops \*f, SongStats \*stats)$/i\
extern int kestrel_bard_saving; /* KESTREL: kestrel_bard.c */
s/^\tif (!confirm(domain, mused.slider_bevel, &mused.largefont, "Save unused song elements?"))$/\tif (!kestrel_bard_saving \&\& !confirm(domain, mused.slider_bevel, \&mused.largefont, "Save unused song elements?")) \/* KESTREL *\//
