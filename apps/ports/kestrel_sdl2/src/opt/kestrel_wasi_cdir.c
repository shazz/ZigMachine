/* C:'s path_open and fd_readdir (docs/KOS_GEMDOS.md §5; the rest in kestrel_wasi_c.c). A folder fd keeps
 * its GEMDOS path and a DTA: readdir is Fsfirst / Fsnext, its cookie the entries already handed out (a
 * cookie other than the next one restarts the search and skips that many, as a rewinddir or a seekdir
 * asks); the first entry is "..", as a POSIX folder lists it (GrafX2's way up; from C:\ it leads to "/",
 * the floppy, once getcwd below has folded it). A create, a truncate or a write right is a write
 * (kestrel_wasi_cfile.c: Fcreate). */
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include "kestrel_wasi_c.h"

#define WRITES (__WASI_RIGHTS_FD_WRITE | __WASI_RIGHTS_FD_ALLOCATE | __WASI_RIGHTS_FD_FILESTAT_SET_SIZE)

int32_t __imported_wasi_snapshot_preview1_path_open(int32_t fd, int32_t dirflags, int32_t path, int32_t len, int32_t oflags,
                                                    int64_t rights_base, int64_t rights_inh, int32_t fdflags, int32_t out)
{
    if (!kcd_is(fd)) return kestrel_floppy_path_open(fd, dirflags, path, len, oflags, rights_base, rights_inh, fdflags, out);
    char p[PATH_MAX_C];
    uint32_t size = 0;
    if (!kcd_path(fd, (const char *)(uintptr_t)path, (uint32_t)len, p)) return __WASI_ERRNO_NAMETOOLONG;
    if ((oflags & (__WASI_OFLAGS_CREAT | __WASI_OFLAGS_TRUNC)) || ((uint64_t)rights_base & WRITES & ~__WASI_RIGHTS_FD_ALLOCATE))
        if (!(oflags & __WASI_OFLAGS_DIRECTORY)) return kcd_create(p, oflags, out); /* kestrel_wasi_cfile.c */
    int32_t k = kcd_kind(p, &size);
    if (k < 0) return kcd_errno(k);
    if ((oflags & __WASI_OFLAGS_DIRECTORY) && !k) return __WASI_ERRNO_NOTDIR;
    for (int i = 0; i < C_FDS; i++) {
        kcd_t *f = &kcd_fds[i];
        if (f->used) continue;
        int32_t h = k ? 0 : Fopen(p, 0);
        if (h < 0) return kcd_errno(h);
        memset(f, 0, sizeof *f);
        f->used = 1, f->dir = k, f->h = h, f->size = size, f->up = k;
        strcpy(f->path, p);
        *(int32_t *)(uintptr_t)out = C_FIRST + i;
        return 0;
    }
    return __WASI_ERRNO_NFILE;
}

/* The working folder, as wasi-libc keeps it: chdir("..") appends "/.." and never folds it, so
 * GrafX2 showed "/C/PICTURES/.." and "/C/.." stayed on C:. kestrel_getcwd (a port maps getcwd to it:
 * grafx2/kestrel_port.h; libc's own getcwd.o cannot be replaced, it also holds the variable) folds "."
 * and ".." in place, the string only ever shrinking, so libc's next path resolves against the folded
 * folder too: "/C/.." is "/", the floppy. */
extern char *__wasilibc_cwd;

static void fold(char *p)
{
    char *o = p; /* p[0] == '/': libc's cwd is absolute */
    const char *s = p;
    while (*s) {
        while (*s == '/') s++;
        const char *e = s;
        while (*e && *e != '/') e++;
        size_t n = (size_t)(e - s);
        if (n == 2 && s[0] == '.' && s[1] == '.') { while (o > p && *--o != '/') {} }
        else if (n && !(n == 1 && s[0] == '.')) { *o++ = '/'; memmove(o, s, n); o += n; }
        s = e;
    }
    if (o == p) *o++ = '/';
    *o = 0;
}

char *kestrel_getcwd(char *buf, size_t size)
{
    if (strcmp(__wasilibc_cwd, "/")) fold(__wasilibc_cwd); /* "/" may be libc's literal; else chdir's malloc */
    size_t n = strlen(__wasilibc_cwd) + 1;
    if (!buf) buf = malloc(size = n);
    if (!buf || size < n) { errno = buf ? ERANGE : ENOMEM; return NULL; }
    memcpy(buf, __wasilibc_cwd, n);
    return buf;
}

/* The folder's entry number f->next into f->dta (the ones before it already read): 0, or a GEMDOS
 * error (ENMFIL at its end). Entry 0 is "..", which no FAT listing shows here. */
static int32_t step(kcd_t *f)
{
    if (f->up && f->next == 0) {
        memset(&f->dta, 0, sizeof f->dta);
        f->dta.d_attrib = FA_DIR;
        strcpy(f->dta.d_fname, "..");
        return 0;
    }
    Fsetdta(&f->dta);
    if (f->next > (uint64_t)f->up) return Fsnext();
    char spec[PATH_MAX_C + 4];
    size_t n = strlen(f->path);
    memcpy(spec, f->path, n);
    if (n && spec[n - 1] != '\\') spec[n++] = '\\';
    strcpy(spec + n, "*.*");
    int32_t r = Fsfirst(spec, FA_DIR | FA_HIDDEN | FA_SYSTEM);
    return r == GEMDOS_EFILNF ? GEMDOS_ENMFIL : r; /* an empty folder */
}

int32_t __imported_wasi_snapshot_preview1_fd_readdir(int32_t fd, int32_t buf, int32_t buf_len, int64_t cookie, int32_t used)
{
    if (!kcd_is(fd)) return kestrel_floppy_fd_readdir(fd, buf, buf_len, cookie, used);
    kcd_t *f = kcd_get(fd);
    if (!f || !f->dir) return __WASI_ERRNO_NOTDIR; /* the preopen itself: libc opens "." first */
    if ((uint64_t)cookie != f->next) f->next = 0; /* restart, then skip to the cookie */
    uint8_t *o = (uint8_t *)(uintptr_t)buf;
    uint32_t pos = 0, cap = (uint32_t)buf_len;
    while (pos < cap) {
        KDTA keep = f->dta;
        uint64_t at = f->next;
        int32_t r = step(f);
        if (r == GEMDOS_ENMFIL) break;
        if (r < 0) return kcd_errno(r);
        f->next = at + 1;
        if (at < (uint64_t)cookie) continue;
        __wasi_dirent_t d = { f->next, f->next + 1, (uint32_t)strlen(f->dta.d_fname),
                              f->dta.d_attrib & FA_DIR ? __WASI_FILETYPE_DIRECTORY : __WASI_FILETYPE_REGULAR_FILE };
        if (cap - pos < sizeof d + d.d_namlen) { /* a cut record tells libc to grow; hand it out again */
            uint32_t k = cap - pos < sizeof d ? cap - pos : (uint32_t)sizeof d;
            memcpy(o + pos, &d, k);
            pos += k;
            if (k == sizeof d) { memcpy(o + pos, f->dta.d_fname, cap - pos); pos = cap; }
            f->dta = keep, f->next = at;
            break;
        }
        memcpy(o + pos, &d, sizeof d);
        memcpy(o + pos + sizeof d, f->dta.d_fname, d.d_namlen);
        pos += sizeof d + d.d_namlen;
    }
    *(uint32_t *)(uintptr_t)used = pos;
    return 0;
}
