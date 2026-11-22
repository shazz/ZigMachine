/* The dialing directory's home on C: (kestrel_dialdir.c). GEMDOS names: 8.3, upper case. */
#ifndef KESTREL_DIALDIR_H
#define KESTREL_DIALDIR_H
#include <stdio.h>

#define KESTREL_DIALDIR "/C/SYNCTERM"
#define KESTREL_DIALDIR_INI KESTREL_DIALDIR "/SYNCTERM.INI"
#define KESTREL_DIALDIR_LST KESTREL_DIALDIR "/SYNCTERM.LST"
#define KESTREL_DOWNLOAD "/C/DOWNLOAD"
#define KESTREL_FAKEBBS "fakebbs.zig"

int kestrel_dialdir_ready(void);   /* C: mounted and C:\SYNCTERM there (made if need be) */
void kestrel_dialdir_seed(void);   /* no list on C: yet: one from DIAL.TXT + the in-cart BBS */
void kestrel_dldir(char *dldir, size_t size);   /* a download folder: one on C:, else C:\DOWNLOAD (made if need be) */
FILE *kestrel_rewrite(FILE *fp, const char *path);   /* close fp, open path "wb" (never NULL) */

#endif
