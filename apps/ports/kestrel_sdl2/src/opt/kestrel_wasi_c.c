/* C: for a C port's POSIX calls (docs/KOS_GEMDOS.md §5), opt-in: built with -DKESTREL_CDRIVE and linked
 * with KOS GEMDOS's object (rom/kos/gemdos_c.zig). wasi-libc finds its preopened folders by asking fd 3,
 * 4, ... until one is refused: fd 3 is the floppy ("/", kestrel_wasi.c), fd 4 is C: as "/C" when C:
 * mounts (the card has an HD folder; the page was given ?c=). libc resolves every path against the
 * longest preopen, so "/C/PICTURES/X.PI1", and a relative path once chdir("/C/PICTURES"), arrive here
 * as fd 4 + "PICTURES/X.PI1": GEMDOS's C:\PICTURES\X.PI1. libc never folds "..", GEMDOS does (at the
 * root it stays there). C:'s files and folders are fds 32 and up; every other fd is the floppy's. */
#include <wasi/api.h>
#include <string.h>
#include <stdint.h>
#include "kestrel_gemdos.h"

#include "kestrel_wasi_c.h"

kcd_t kcd_fds[C_FDS];
static int c_state = -1; /* -1 not asked yet, 0 no C:, 1 C: mounted */

int kestrel_c_mounted(void) { if (c_state < 0) c_state = Fattrib("C:\\", 0, 0) >= 0; return c_state; }
kcd_t *kcd_get(int32_t fd) { return fd >= C_FIRST && fd < C_FIRST + C_FDS && kcd_fds[fd - C_FIRST].used ? &kcd_fds[fd - C_FIRST] : NULL; }
int kcd_is(int32_t fd) { return (fd == C_FD && kestrel_c_mounted()) || kcd_get(fd); }
int32_t kcd_errno(int32_t e)
{
    if (e == GEMDOS_EFILNF || e == GEMDOS_EPTHNF || e == GEMDOS_EDRIVE) return __WASI_ERRNO_NOENT;
    if (e == GEMDOS_ENHNDL) return __WASI_ERRNO_NFILE;
    if (e == GEMDOS_EWRPRO) return __WASI_ERRNO_ROFS;
    if (e == GEMDOS_EACCDN) return __WASI_ERRNO_ACCES; /* a read-only file, a name taken, a folder not empty */
    if (e == GEMDOS_EWRITF) return __WASI_ERRNO_NOSPC;
    if (e == GEMDOS_ENSAME) return __WASI_ERRNO_XDEV;
    if (e == GEMDOS_ERANGE) return __WASI_ERRNO_INVAL;
    return __WASI_ERRNO_IO;
}

/* "C:\" + the folder fd's own path + the libc-relative path, '/' as '\'; 0 when it does not fit. */
int kcd_path(int32_t fd, const char *rel, uint32_t len, char *out)
{
    kcd_t *d = kcd_get(fd);
    const char *base = d ? d->path : "C:\\";
    size_t b = strlen(base);
    if (b + 1 + len + 1 > PATH_MAX_C) return 0;
    memcpy(out, base, b);
    if (b && out[b - 1] != '\\') out[b++] = '\\';
    for (uint32_t i = 0; i < len; i++) out[b + i] = rel[i] == '/' ? '\\' : rel[i];
    out[b + len] = 0;
    return 1;
}

void kcd_stat(__wasi_filestat_t *st, int dir, uint32_t size, uint64_t ino)
{
    memset(st, 0, sizeof *st);
    st->nlink = 1;
    st->ino = ino;
    st->filetype = dir ? __WASI_FILETYPE_DIRECTORY : __WASI_FILETYPE_REGULAR_FILE;
    st->size = dir ? 0 : size;
}

/* Is `p` a folder (1), a file (0, *size its length), or neither (a GEMDOS error)? */
int32_t kcd_kind(const char *p, uint32_t *size)
{
    int32_t a = Fattrib(p, 0, 0);
    if (a < 0) return a;
    if (a & FA_DIR) return 1;
    int32_t h = Fopen(p, 0);
    if (h < 0) return h;
    int32_t n = Fseek(0, h, 2);
    Fclose(h);
    *size = n < 0 ? 0 : (uint32_t)n;
    return 0;
}

int32_t __imported_wasi_snapshot_preview1_fd_prestat_get(int32_t fd, int32_t out)
{
    if (fd != C_FD || !kestrel_c_mounted()) return kestrel_floppy_fd_prestat_get(fd, out);
    __wasi_prestat_t *p = (__wasi_prestat_t *)(uintptr_t)out;
    p->tag = __WASI_PREOPENTYPE_DIR;
    p->u.dir.pr_name_len = 2;
    return 0;
}
int32_t __imported_wasi_snapshot_preview1_fd_prestat_dir_name(int32_t fd, int32_t path, int32_t len)
{
    if (fd != C_FD || !kestrel_c_mounted()) return kestrel_floppy_fd_prestat_dir_name(fd, path, len);
    if (len < 2) return __WASI_ERRNO_BADF;
    memcpy((char *)(uintptr_t)path, "/C", 2);
    return 0;
}
int32_t __imported_wasi_snapshot_preview1_fd_fdstat_get(int32_t fd, int32_t out)
{
    if (!kcd_is(fd)) return kestrel_floppy_fd_fdstat_get(fd, out);
    __wasi_fdstat_t *st = (__wasi_fdstat_t *)(uintptr_t)out;
    kcd_t *f = kcd_get(fd);
    memset(st, 0, sizeof *st);
    st->fs_filetype = !f || f->dir ? __WASI_FILETYPE_DIRECTORY : __WASI_FILETYPE_REGULAR_FILE;
    st->fs_rights_base = st->fs_rights_inheriting = ~(__wasi_rights_t)0;
    return 0;
}
int32_t __imported_wasi_snapshot_preview1_fd_fdstat_set_flags(int32_t fd, int32_t f) { return kcd_is(fd) ? 0 : kestrel_floppy_fd_fdstat_set_flags(fd, f); }
int32_t kestrel_wasi_fd_close(int32_t fd) /* close() calls it too (kestrel_wasi.c) */
{
    kcd_t *f = kcd_get(fd);
    if (!f) return fd == C_FD && kestrel_c_mounted() ? 0 : kestrel_floppy_fd_close(fd);
    int32_t r = f->dir ? 0 : Fclose(f->h); /* a file written: Fclose is its save, and its answer */
    f->used = 0;
    return r < 0 ? kcd_errno(r) : 0;
}
int32_t __imported_wasi_snapshot_preview1_fd_close(int32_t fd) { return kestrel_wasi_fd_close(fd); }
int32_t __imported_wasi_snapshot_preview1_fd_read(int32_t fd, int32_t iovs, int32_t n, int32_t got)
{
    kcd_t *f = kcd_get(fd);
    if (!f) return kcd_is(fd) ? __WASI_ERRNO_ISDIR : kestrel_floppy_fd_read(fd, iovs, n, got);
    if (f->dir) return __WASI_ERRNO_ISDIR;
    const __wasi_iovec_t *v = (const __wasi_iovec_t *)(uintptr_t)iovs;
    uint32_t total = 0;
    for (int i = 0; i < n; i++) {
        int32_t r = Fread(f->h, (int32_t)v[i].buf_len, v[i].buf);
        if (r < 0) { *(uint32_t *)(uintptr_t)got = total; return kcd_errno(r); }
        total += (uint32_t)r;
        if ((uint32_t)r < v[i].buf_len) break; /* the file's end */
    }
    *(uint32_t *)(uintptr_t)got = total;
    return 0;
}
int32_t __imported_wasi_snapshot_preview1_fd_write(int32_t fd, int32_t iovs, int32_t n, int32_t put)
{
    kcd_t *f = kcd_get(fd);
    if (!f) return kcd_is(fd) ? __WASI_ERRNO_ISDIR : kestrel_floppy_fd_write(fd, iovs, n, put);
    if (!f->w) return __WASI_ERRNO_BADF; /* opened for reading */
    const __wasi_ciovec_t *v = (const __wasi_ciovec_t *)(uintptr_t)iovs;
    uint32_t total = 0;
    for (int i = 0; i < n; i++) {
        int32_t r = Fwrite(f->h, (int32_t)v[i].buf_len, v[i].buf);
        if (r < 0) { *(uint32_t *)(uintptr_t)put = total; return kcd_errno(r); }
        total += (uint32_t)r;
    }
    *(uint32_t *)(uintptr_t)put = total;
    return 0;
}
int32_t __imported_wasi_snapshot_preview1_fd_seek(int32_t fd, int64_t off, int32_t whence, int32_t out)
{
    kcd_t *f = kcd_get(fd);
    if (!f) return kcd_is(fd) ? __WASI_ERRNO_ISDIR : kestrel_floppy_fd_seek(fd, off, whence, out);
    if (f->dir) return __WASI_ERRNO_ISDIR;
    if (off < INT32_MIN || off > INT32_MAX) return __WASI_ERRNO_INVAL;
    int32_t r = Fseek((int32_t)off, f->h, whence == __WASI_WHENCE_SET ? 0 : whence == __WASI_WHENCE_CUR ? 1 : 2);
    if (r < 0) return __WASI_ERRNO_INVAL;
    *(uint64_t *)(uintptr_t)out = (uint64_t)r;
    return 0;
}
int32_t __imported_wasi_snapshot_preview1_fd_filestat_get(int32_t fd, int32_t out)
{
    if (!kcd_is(fd)) return kestrel_floppy_fd_filestat_get(fd, out);
    kcd_t *f = kcd_get(fd);
    uint32_t size = f ? f->size : 0;
    if (f && f->w) { /* a file being written: its size so far, the position kept */
        int32_t at = Fseek(0, f->h, 1);
        int32_t end = Fseek(0, f->h, 2);
        Fseek(at, f->h, 0);
        size = end < 0 ? 0 : (uint32_t)end;
    }
    kcd_stat((__wasi_filestat_t *)(uintptr_t)out, !f || f->dir, size, (uint64_t)fd << 32);
    return 0;
}
int32_t __imported_wasi_snapshot_preview1_path_filestat_get(int32_t fd, int32_t flags, int32_t path, int32_t len, int32_t out)
{
    if (!kcd_is(fd)) return kestrel_floppy_path_filestat_get(fd, flags, path, len, out);
    char p[PATH_MAX_C];
    uint32_t size = 0;
    if (!kcd_path(fd, (const char *)(uintptr_t)path, (uint32_t)len, p)) return __WASI_ERRNO_NAMETOOLONG;
    int32_t k = kcd_kind(p, &size);
    if (k < 0) return kcd_errno(k);
    kcd_stat((__wasi_filestat_t *)(uintptr_t)out, k, size, 0x100000000ull + (uint32_t)len);
    return 0;
}
