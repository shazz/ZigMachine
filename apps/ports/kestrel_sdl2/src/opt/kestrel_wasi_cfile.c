/* C:'s writes for a C port's POSIX calls (docs/KOS_GEMDOS.md §7; reads in kestrel_wasi_c.c, folders in
 * kestrel_wasi_cdir.c): fopen "w" is Fcreate (the file is saved whole at fclose: the host writes it,
 * never the cart), fwrite is Fwrite, remove / rename / mkdir / rmdir are Fdelete / Frename / Dcreate /
 * Ddelete. A file is written whole or not at all: "r+" and "a" (changing a file in place) are refused
 * (ENOTSUP), as is any write on the floppy (EROFS) and a rename between the floppy and C: (EXDEV). */
#ifdef KESTREL_CDRIVE /* a port without C: (klystrack: its Makefile compiles every opt file) gets an empty object */
#include <string.h>
#include "kestrel_wasi_c.h"

/* fd 4 + "X/Y.EXT" as GEMDOS's "C:\X\Y.EXT"; 0 when it does not fit. */
static int cpath(int32_t fd, int32_t path, int32_t len, char *out) { return kcd_path(fd, (const char *)(uintptr_t)path, (uint32_t)len, out); }

/* path_open with O_CREAT / O_TRUNC or a write right (kestrel_wasi_cdir.c): a new handle from Fcreate. */
int32_t kcd_create(const char *p, int32_t oflags, int32_t out)
{
    uint32_t size = 0;
    int32_t k = kcd_kind(p, &size);
    if (k == 1) return __WASI_ERRNO_ISDIR;
    if (k == 0 && (oflags & __WASI_OFLAGS_EXCL)) return __WASI_ERRNO_EXIST;
    if (k == 0 && !(oflags & __WASI_OFLAGS_TRUNC)) return __WASI_ERRNO_NOTSUP; /* in place: not served */
    if (k < 0 && (k != GEMDOS_EFILNF || !(oflags & __WASI_OFLAGS_CREAT))) return kcd_errno(k);
    for (int i = 0; i < C_FDS; i++) {
        kcd_t *f = &kcd_fds[i];
        if (f->used) continue;
        int32_t h = Fcreate(p, 0);
        if (h < 0) return kcd_errno(h);
        memset(f, 0, sizeof *f);
        f->used = 1, f->w = 1, f->h = h;
        strcpy(f->path, p);
        *(int32_t *)(uintptr_t)out = C_FIRST + i;
        return 0;
    }
    return __WASI_ERRNO_NFILE;
}

int32_t __imported_wasi_snapshot_preview1_path_unlink_file(int32_t fd, int32_t path, int32_t len)
{
    if (!kcd_is(fd)) return kestrel_floppy_path_unlink_file(fd, path, len);
    char p[PATH_MAX_C];
    if (!cpath(fd, path, len, p)) return __WASI_ERRNO_NAMETOOLONG;
    int32_t r = Fdelete(p);
    return r < 0 ? kcd_errno(r) : 0;
}

int32_t __imported_wasi_snapshot_preview1_path_rename(int32_t fd, int32_t path, int32_t len, int32_t fd2, int32_t path2, int32_t len2)
{
    if (!kcd_is(fd) && !kcd_is(fd2)) return kestrel_floppy_path_rename(fd, path, len, fd2, path2, len2);
    if (!kcd_is(fd) || !kcd_is(fd2)) return __WASI_ERRNO_XDEV; /* the floppy and C: */
    char p[PATH_MAX_C], q[PATH_MAX_C];
    if (!cpath(fd, path, len, p) || !cpath(fd2, path2, len2, q)) return __WASI_ERRNO_NAMETOOLONG;
    int32_t r = Frename(0, p, q);
    return r < 0 ? kcd_errno(r) : 0;
}

int32_t __imported_wasi_snapshot_preview1_path_create_directory(int32_t fd, int32_t path, int32_t len)
{
    if (!kcd_is(fd)) return kestrel_floppy_path_create_directory(fd, path, len);
    char p[PATH_MAX_C];
    if (!cpath(fd, path, len, p)) return __WASI_ERRNO_NAMETOOLONG;
    int32_t r = Dcreate(p);
    return r == GEMDOS_EACCDN ? __WASI_ERRNO_EXIST : r < 0 ? kcd_errno(r) : 0;
}

int32_t __imported_wasi_snapshot_preview1_path_remove_directory(int32_t fd, int32_t path, int32_t len)
{
    if (!kcd_is(fd)) return kestrel_floppy_path_remove_directory(fd, path, len);
    char p[PATH_MAX_C];
    if (!cpath(fd, path, len, p)) return __WASI_ERRNO_NAMETOOLONG;
    int32_t r = Ddelete(p);
    return r == GEMDOS_EACCDN ? __WASI_ERRNO_NOTEMPTY : r < 0 ? kcd_errno(r) : 0;
}
#endif
