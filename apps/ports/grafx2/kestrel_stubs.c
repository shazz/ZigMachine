/* What GrafX2 v1 leaves out on the cart: the C64 .PRG loader runs a 6502 emulator (redcode/6502,
 * fetched by upstream's 3rdparty/Makefile); without it a .PRG is "not recognised". */
#include <stdio.h>
struct c64state;
int C64_LoadPrg(struct c64state *c64, FILE *f, unsigned short start) { (void)c64; (void)f; (void)start; return 0; }
int C64_isBinaryProgram(FILE *f) { (void)f; return 0; }

/* mountlist.c lists mounted volumes for the file selector's drive list: the floppy is the only one. */
struct mntent;
FILE *setmntent(const char *file, const char *type) { (void)file; (void)type; return NULL; }
struct mntent *getmntent(FILE *f) { (void)f; return NULL; }
int endmntent(FILE *f) { (void)f; return 1; }
