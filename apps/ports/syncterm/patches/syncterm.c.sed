# main -> syncterm_main: kestrel_main.c runs it as the first fiber (on the dialing directory, or a URL with no C:).
s/^main(int argc, char \*\*argv)$/syncterm_main(int argc, char **argv)/
# The scrollback's default, 2000 lines of 80 cells (2.5 MB), is more than the cart window: 100 (128 KB). The ini
# on C: (kestrel_dialdir.c) can still set it; more than ~1000 lines does not fit.
s/"ScrollBackLines", 2000)/"ScrollBackLines", 100)/
# The dialing directory on C: (kestrel_dialdir.c). C: writes a file whole and refuses "r+" (changing it in
# place), so the LastConnected / TotalCalls update after a connect reads the list "rb" and writes it again
# "wb" (kestrel_rewrite); and with no list on C: yet, one is seeded before the directory first opens.
1i #include "kestrel_dialdir.h"
s/(listfile = fopen(settings.list_path, "r+b")) != NULL/(listfile = fopen(settings.list_path, "rb")) != NULL/
s/^\(\t*\)iniSetInteger(&inifile, bbs->name, "TotalCalls", bbs->calls, &ini_style);$/&\n\1listfile = kestrel_rewrite(listfile, settings.list_path);/
s/^\twhile ((!quitting) && (bbs != NULL || (bbs = show_bbslist(last_bbs, false)) != NULL)) {$/\tkestrel_dialdir_seed();\n&/
