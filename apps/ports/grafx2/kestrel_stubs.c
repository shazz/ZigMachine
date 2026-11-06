/* What GrafX2 v1 leaves out on the cart: the C64 .PRG loader runs a 6502 emulator (redcode/6502,
 * fetched by upstream's 3rdparty/Makefile); without it a .PRG is "not recognised". */
#include <stdio.h>
#include <mntent.h>
struct c64state;
int C64_LoadPrg(struct c64state *c64, FILE *f, unsigned short start) { (void)c64; (void)f; (void)start; return 0; }
int C64_isBinaryProgram(FILE *f) { (void)f; return 0; }

/* mountlist.c lists mounted volumes for the file selector's drive list, after "/" (the floppy): C:, the
 * SD card's /HD, as "/C" when it mounts (KOS GEMDOS, docs/KOS_GEMDOS.md; ../kestrel_sdl2/src/opt/
 * kestrel_wasi_c.c), with a hard disk's icon ("ext2fs" is a type GrafX2 draws one for). */
int kestrel_c_mounted(void);
static struct mntent c_drive = { "C:", "/C", "ext2fs", "ro", 0, 0 };
static int listed;
FILE *setmntent(const char *file, const char *type) { (void)file; (void)type; listed = 0; return kestrel_c_mounted() ? (FILE *)&c_drive : NULL; }
struct mntent *getmntent(FILE *f) { (void)f; return listed++ ? NULL : &c_drive; }
int endmntent(FILE *f) { (void)f; return 1; }
