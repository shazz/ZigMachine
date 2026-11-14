# ciolib's output on the cart is kestrel_cio.c, entered where the libretro backend is (-DWITH_RETRO,
# kestrel_cio.c sets retro_set): no curses (no terminal), and retro.h's bitmap backend is not linked
# (bitmap_con.c's 32-bit pixel buffers, 1 MB each at 640x400, do not fit the cart window).
/^ #include "curs_cio.h"$/d
s/^ #include "retro.h"$/ #include "kestrel_cio.h"/
/^static int try_curses_init(int mode)$/,/^}$/d
s/try_curses_init(mode)/0/
/^static int try_retro_init(int mode)$/,/^}$/d
s/!try_retro_init(mode)/!kestrel_cio_init(mode)/
