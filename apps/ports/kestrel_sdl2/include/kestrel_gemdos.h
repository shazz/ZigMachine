/* KOS GEMDOS for C carts (docs/KOS_GEMDOS.md): TOS's file calls, read-only in phase 1, over A: (a FAT
 * floppy image in the drive) and C: (the SD card's /HD; the page's ?c= image; the native host's
 * --c-image). Implemented in Zig (rom/kos/gemdos*.zig), linked as one object built from
 * rom/kos/gemdos_c.zig (see apps/ports/grafx2/Makefile). Answers as TOS's: >= 0 a result, < 0 an error.
 *
 * Most ports never call these: the POSIX layer (kestrel_wasi.c + opt/kestrel_wasi_c.c, built with
 * -DKESTREL_CDRIVE) maps "/C/X/Y.EXT" to C:\X\Y.EXT, so fopen / opendir / stat work unchanged. */
#ifndef KESTREL_GEMDOS_H
#define KESTREL_GEMDOS_H
#include <stdint.h>

/* The disk transfer address: TOS's 44 bytes; its fields in the cart's byte order (little-endian). */
typedef struct {
    uint8_t d_reserved[21]; /* the search's own state */
    uint8_t d_attrib;
    uint8_t d_time[2], d_date[2]; /* DOS time and date words */
    uint8_t d_length[4];
    char d_fname[14];       /* "NAME.EXT", NUL-terminated */
} KDTA;
_Static_assert(sizeof(KDTA) == 44, "TOS's DTA is 44 bytes");

#define FA_RDONLY 0x01
#define FA_HIDDEN 0x02
#define FA_SYSTEM 0x04
#define FA_VOLUME 0x08
#define FA_DIR 0x10
#define FA_ARCHIVE 0x20

#define GEMDOS_EREADF (-11)
#define GEMDOS_EWRPRO (-13)
#define GEMDOS_EINVFN (-32)
#define GEMDOS_EFILNF (-33)
#define GEMDOS_EPTHNF (-34)
#define GEMDOS_ENHNDL (-35)
#define GEMDOS_EACCDN (-36)
#define GEMDOS_EIHNDL (-37)
#define GEMDOS_EDRIVE (-46)
#define GEMDOS_ENMFIL (-49)
#define GEMDOS_ERANGE (-64)

int32_t Dgetdrv(void);
int32_t Dsetdrv(int32_t drive);                  /* 0 A: .. 2 C:; the drives that answer, a bit each */
int32_t Dgetpath(char *buf, int32_t drive);      /* buf: 128 bytes; drive 0 the current, 1 A:, 3 C: */
int32_t Dsetpath(const char *path);
int32_t Fopen(const char *path, int32_t mode);   /* mode 0 only (read); a handle, >= 6 */
int32_t Fclose(int32_t handle);
int32_t Fread(int32_t handle, int32_t count, void *buf);
int32_t Fseek(int32_t offset, int32_t handle, int32_t mode); /* 0 SET, 1 CUR, 2 END; the new position */
int32_t Fattrib(const char *path, int32_t wflag, int32_t attr); /* wflag 0: the attributes */
void Fsetdta(KDTA *dta);
KDTA *Fgetdta(void);
int32_t Fsfirst(const char *spec, int32_t attr);
int32_t Fsnext(void);
void Kgemdos_media_a(void);        /* not TOS: drive A has a new disk */
uint32_t Kgemdos_trips(int32_t drive); /* not TOS: the drive's round trips since start */
#endif
