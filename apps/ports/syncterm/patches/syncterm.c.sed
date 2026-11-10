# main -> syncterm_main: kestrel_main.c runs it as the first fiber, with the fake BBS URL as its argument.
s/^main(int argc, char \*\*argv)$/syncterm_main(int argc, char **argv)/
# The scrollback's default, 2000 lines of 80 cells (2.5 MB), is more than the cart window: 100 (128 KB). The ini
# that could set it is not read (no writable home: see SPIKE.md).
s/"ScrollBackLines", 2000)/"ScrollBackLines", 100)/
