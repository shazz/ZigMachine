# The dialing directory on C: (kestrel_dialdir.c): C: writes a file whole and refuses "r+" (in place).
# Deleting an entry reads the list "rb" and writes it again "wb" (kestrel_rewrite); editing a comment
# opened it "r+b" only to see that it can be written (the write is a "wb" after): there the probe is a read.
1i #include "kestrel_dialdir.h"
/^del_bbs(char \*listpath, struct bbslist \*bbs)$/,/^}$/{
s/"r+b"/"rb"/
s/^\(\t*\)iniRemoveSection(&inifile, bbs->name);$/&\n\1listfile = kestrel_rewrite(listfile, listpath);/
}
/Open with write permissions so it fails if you can't edit/{n;s/"r+b"/"rb"/}
