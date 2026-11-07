/* WASI on the cart, over the cart's own floppy.
 *
 * wasi-libc calls __wasi_* functions whose definitions import from "wasi_snapshot_preview1", which a
 * cart may not do (only "env"). Defining __imported_wasi_snapshot_preview1_* here resolves libc's
 * imports inside the cart (a defined symbol beats an import in wasm-ld); the types are the raw import
 * forms of __wasilibc_real.c (pointers and sizes are i32 on wasm32).
 *
 * The file system is the mounted .zmd's FAT, read-only, one flat directory, through the machine's
 * drive ABI (env.diskReadBlock: one 512-byte block into RAM). fd 3 is the preopened root "/";
 * stdout/stderr go to the console. Names match case-insensitively (the FAT stores them upper case). */
#include <wasi/api.h>
#include <string.h>
#include <stdint.h>

void kestrel_log(const char *m);
__attribute__((import_module("env"), import_name("consoleLogJS"))) extern void consoleLogJS(const char *p, int len);
__attribute__((import_module("env"), import_name("diskReadBlock"))) extern int diskReadBlock(int block, int dst);

/* --- the disk: .zmd v1 (directory at 0x300, count at 0x2E4) or v2 (wasm boot sector; 0x800 / 0x4F4) --- */
#define MAX_FILES 64
typedef struct { char name[17]; uint32_t start, len; } entry_t;
static entry_t files[MAX_FILES];
static int nfiles = -1;                 /* -1: not read yet */
static uint8_t blk[512];
static int blk_no = -1;

static const uint8_t *block(uint32_t n)
{
    if ((int)n != blk_no) {
        if (diskReadBlock((int)n, (int)(uintptr_t)blk) != 512) { blk_no = -1; return NULL; }
        blk_no = (int)n;
    }
    return blk;
}
static uint32_t rd32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

static void disk_scan(void)
{
    if (nfiles >= 0) return;
    nfiles = 0;
    const uint8_t *b0 = block(0);
    if (!b0) return;
    int v2 = b0[0] == 0 && b0[1] == 'a' && b0[2] == 's' && b0[3] == 'm';
    uint32_t count_at = v2 ? 0x4F4 : 0x2E4, dir_at = v2 ? 0x800 : 0x300;
    const uint8_t *cb = block(count_at / 512);
    if (!cb) return;
    int n = cb[count_at % 512] | cb[count_at % 512 + 1] << 8;
    if (n > MAX_FILES) n = MAX_FILES;
    for (int i = 0; i < n; i++) {
        uint32_t e = dir_at + (uint32_t)i * 32;
        const uint8_t *b = block(e / 512);
        if (!b) break;
        const uint8_t *p = b + e % 512;
        memcpy(files[i].name, p, 16);
        files[i].name[16] = 0;
        files[i].start = rd32(p + 0x10);
        files[i].len = rd32(p + 0x14);
        nfiles = i + 1;
    }
}

/* The floppy is flat: a path names a file by its last component ("/share/skins/X.GIF" is X.GIF). */
static int name_eq(const char *a, uint32_t alen, const char *b)
{
    for (uint32_t k = alen; k > 0; k--) if (a[k - 1] == '/') { a += k; alen -= k; break; }
    uint32_t i = 0;
    for (; i < alen && b[i]; i++) {
        char x = a[i], y = b[i];
        if (x >= 'a' && x <= 'z') x -= 32;
        if (y >= 'a' && y <= 'z') y -= 32;
        if (x != y) return 0;
    }
    return i == alen && b[i] == 0;
}
/* Directories: the root, and (so programs that look for their data folders find them) any path whose last
 * component has no '.' and is not a file; they all show the same flat floppy. */
static int find(const char *p, uint32_t len);
static int is_root(const char *p, uint32_t len)
{
    while (len && p[len - 1] == '/') len--;
    if (len == 0 || (len == 1 && p[0] == '.')) return 1;
    uint32_t k = len;
    while (k > 0 && p[k - 1] != '/') k--;
    if (len - k == 2 && p[k] == '.' && p[k + 1] == '.') return 1;            /* ".." */
    for (uint32_t i = k; i < len; i++) if (p[i] == '.') return 0;
    return find(p, len) < 0;
}
static int find(const char *p, uint32_t len)
{
    disk_scan();
    for (int i = 0; i < nfiles; i++) if (name_eq(p, len, files[i].name)) return i;
    return -1;
}

/* --- file descriptors: 0-2 console, 3 the root (preopen), 4.. open files or directory handles --- */
#define ROOT_FD 3
#define MAX_FDS 12
/* KESTREL_CDRIVE (a port linking KOS GEMDOS, docs/KOS_GEMDOS.md): the functions below are the floppy's
 * half; opt/kestrel_wasi_c.c holds the WASI entry points, which hand fd 4 (C:, the preopen "/C") and
 * C:'s files to GEMDOS and the rest here. Without it they are the entry points, as before. */
#ifdef KESTREL_CDRIVE
#define WASI(name) kestrel_floppy_##name
#define FIRST_FD (ROOT_FD + 2) /* fd 4 is C:'s preopen */
#else
#define WASI(name) __imported_wasi_snapshot_preview1_##name
#define FIRST_FD (ROOT_FD + 1)
#endif
typedef struct { int used, dir, file; uint64_t pos; } fdesc_t;
static fdesc_t fds[MAX_FDS];
#ifdef WASI_TRACE
int snprintf(char *, unsigned long, const char *, ...);
#define TRACE(...) do { char tb_[160]; snprintf(tb_, sizeof tb_, __VA_ARGS__); kestrel_log(tb_); } while (0)
#else
#define TRACE(...) do { } while (0)
#endif

static fdesc_t *fd_get(int32_t fd) { return fd > ROOT_FD && fd < MAX_FDS && fds[fd].used ? &fds[fd] : NULL; }
static int is_dir_fd(int32_t fd) { fdesc_t *f; return fd == ROOT_FD || ((f = fd_get(fd)) && f->dir); }

int32_t __imported_wasi_snapshot_preview1_args_get(int32_t argv, int32_t buf) { (void)argv; (void)buf; return 0; }
int32_t __imported_wasi_snapshot_preview1_args_sizes_get(int32_t argc, int32_t size) { *(uint32_t *)(uintptr_t)argc = 0; *(uint32_t *)(uintptr_t)size = 0; return 0; }
int32_t __imported_wasi_snapshot_preview1_environ_get(int32_t env, int32_t buf) { (void)env; (void)buf; return 0; }
int32_t __imported_wasi_snapshot_preview1_environ_sizes_get(int32_t n, int32_t size) { *(uint32_t *)(uintptr_t)n = 0; *(uint32_t *)(uintptr_t)size = 0; return 0; }

int32_t WASI(fd_prestat_get)(int32_t fd, int32_t out)
{
    if (fd != ROOT_FD) return __WASI_ERRNO_BADF;
    __wasi_prestat_t *p = (__wasi_prestat_t *)(uintptr_t)out;
    p->tag = __WASI_PREOPENTYPE_DIR;
    p->u.dir.pr_name_len = 1;
    return 0;
}
int32_t WASI(fd_prestat_dir_name)(int32_t fd, int32_t path, int32_t len)
{
    if (fd != ROOT_FD || len < 1) return __WASI_ERRNO_BADF;
    *(char *)(uintptr_t)path = '/';
    return 0;
}

int32_t WASI(fd_fdstat_get)(int32_t fd, int32_t out)
{
    __wasi_fdstat_t *st = (__wasi_fdstat_t *)(uintptr_t)out;
    memset(st, 0, sizeof *st);
    if (fd >= 0 && fd <= 2) st->fs_filetype = __WASI_FILETYPE_CHARACTER_DEVICE;
    else if (is_dir_fd(fd)) st->fs_filetype = __WASI_FILETYPE_DIRECTORY;
    else if (fd_get(fd)) st->fs_filetype = __WASI_FILETYPE_REGULAR_FILE;
    else return __WASI_ERRNO_BADF;
    st->fs_rights_base = st->fs_rights_inheriting = ~(__wasi_rights_t)0;
    return 0;
}
int32_t WASI(fd_fdstat_set_flags)(int32_t fd, int32_t f) { (void)f; return (fd >= 0 && fd <= ROOT_FD) || fd_get(fd) ? 0 : __WASI_ERRNO_BADF; }

int32_t WASI(fd_close)(int32_t fd)
{
    fdesc_t *f = fd_get(fd);
    if (f) { f->used = 0; return 0; }
    return fd >= 0 && fd <= ROOT_FD ? 0 : __WASI_ERRNO_BADF;
}
/* Zig 0.16 implements close() in Zig (lib/c/unistd.zig closeWasi), importing fd_close directly past the
 * symbols above; this close() keeps that one out of the link. */
#ifdef KESTREL_CDRIVE
int32_t kestrel_wasi_fd_close(int32_t fd); /* opt/kestrel_wasi_c.c: C:'s or the floppy's */
#define CLOSE_FD kestrel_wasi_fd_close
#else
#define CLOSE_FD __imported_wasi_snapshot_preview1_fd_close
#endif
int close(int fd) { return CLOSE_FD(fd) ? -1 : 0; }

int32_t WASI(fd_read)(int32_t fd, int32_t iovs, int32_t n, int32_t got)
{
    uint32_t total = 0;
    fdesc_t *f = fd_get(fd);
    if (fd == 0) { *(uint32_t *)(uintptr_t)got = 0; return 0; }
    if (!f || f->dir) return __WASI_ERRNO_BADF;
    const entry_t *e = &files[f->file];
    const __wasi_iovec_t *v = (const __wasi_iovec_t *)(uintptr_t)iovs;
    for (int i = 0; i < n; i++) {
        uint8_t *dst = v[i].buf;
        uint32_t want = (uint32_t)v[i].buf_len;
        while (want && f->pos < e->len) {
            uint32_t abs = e->start + (uint32_t)f->pos;
            const uint8_t *b = block(abs / 512);
            if (!b) { *(uint32_t *)(uintptr_t)got = total; return __WASI_ERRNO_IO; }
            uint32_t chunk = 512 - abs % 512;
            if (chunk > want) chunk = want;
            if (chunk > e->len - f->pos) chunk = e->len - (uint32_t)f->pos;
            memcpy(dst, b + abs % 512, chunk);
            dst += chunk; want -= chunk; total += chunk; f->pos += chunk;
        }
    }
    *(uint32_t *)(uintptr_t)got = total;
    return 0;
}

int32_t WASI(fd_write)(int32_t fd, int32_t iovs, int32_t n, int32_t put)
{
    if (fd != 1 && fd != 2) return fd_get(fd) ? __WASI_ERRNO_ROFS : __WASI_ERRNO_BADF;
    const __wasi_ciovec_t *v = (const __wasi_ciovec_t *)(uintptr_t)iovs;
    uint32_t total = 0;
    for (int i = 0; i < n; i++) {
        if (v[i].buf_len) consoleLogJS((const char *)v[i].buf, (int)v[i].buf_len);
        total += (uint32_t)v[i].buf_len;
    }
    *(uint32_t *)(uintptr_t)put = total;
    return 0;
}

int32_t WASI(fd_seek)(int32_t fd, int64_t off, int32_t whence, int32_t out)
{
    fdesc_t *f = fd_get(fd);
    if (!f) return fd >= 0 && fd <= 2 ? __WASI_ERRNO_SPIPE : __WASI_ERRNO_BADF;
    if (f->dir) return __WASI_ERRNO_ISDIR;
    int64_t base = whence == __WASI_WHENCE_SET ? 0 : whence == __WASI_WHENCE_CUR ? (int64_t)f->pos : (int64_t)files[f->file].len;
    if (base + off < 0) return __WASI_ERRNO_INVAL;
    f->pos = (uint64_t)(base + off);
    *(uint64_t *)(uintptr_t)out = f->pos;
    return 0;
}

static void fill_stat(__wasi_filestat_t *st, int file)
{
    memset(st, 0, sizeof *st);
    st->nlink = 1;
    if (file < 0) { st->filetype = __WASI_FILETYPE_DIRECTORY; st->ino = 1; }
    else { st->filetype = __WASI_FILETYPE_REGULAR_FILE; st->ino = (uint64_t)file + 2; st->size = files[file].len; }
}
int32_t WASI(fd_filestat_get)(int32_t fd, int32_t out)
{
    fdesc_t *f = fd_get(fd);
    if (fd == ROOT_FD || (f && f->dir)) { fill_stat((__wasi_filestat_t *)(uintptr_t)out, -1); return 0; }
    if (!f) return __WASI_ERRNO_BADF;
    fill_stat((__wasi_filestat_t *)(uintptr_t)out, f->file);
    return 0;
}
int32_t WASI(path_filestat_get)(int32_t fd, int32_t flags, int32_t path, int32_t len, int32_t out)
{
    (void)flags;
    TRACE("filestat fd %d '%.*s'", (int)fd, (int)len, (const char *)(uintptr_t)path);
    if (!is_dir_fd(fd)) return __WASI_ERRNO_NOTDIR;
    const char *p = (const char *)(uintptr_t)path;
    if (is_root(p, (uint32_t)len)) { fill_stat((__wasi_filestat_t *)(uintptr_t)out, -1); return 0; }
    int i = find(p, (uint32_t)len);
    if (i < 0) return __WASI_ERRNO_NOENT;
    fill_stat((__wasi_filestat_t *)(uintptr_t)out, i);
    return 0;
}

int32_t WASI(path_open)(int32_t fd, int32_t dirflags, int32_t path, int32_t len, int32_t oflags,
                                                    int64_t rights_base, int64_t rights_inh, int32_t fdflags, int32_t out)
{
    (void)dirflags; (void)rights_base; (void)rights_inh; (void)fdflags;
    TRACE("path_open fd %d '%.*s' oflags %d", (int)fd, (int)len, (const char *)(uintptr_t)path, (int)oflags);
    if (!is_dir_fd(fd)) return __WASI_ERRNO_NOTDIR;
    if (oflags & (__WASI_OFLAGS_CREAT | __WASI_OFLAGS_TRUNC)) return __WASI_ERRNO_ROFS;
    const char *p = (const char *)(uintptr_t)path;
    int dir = is_root(p, (uint32_t)len), file = dir ? -1 : find(p, (uint32_t)len);
    if (!dir && file < 0) return __WASI_ERRNO_NOENT;
    if ((oflags & __WASI_OFLAGS_DIRECTORY) && !dir) return __WASI_ERRNO_NOTDIR;
    for (int i = FIRST_FD; i < MAX_FDS; i++) {
        if (fds[i].used) continue;
        fds[i] = (fdesc_t){ 1, dir, file, 0 };
        *(int32_t *)(uintptr_t)out = i;
        return 0;
    }
    return __WASI_ERRNO_NFILE;
}

/* Directory entries: one record (24-byte dirent + name) per file; the cookie is the next index. */
int32_t WASI(fd_readdir)(int32_t fd, int32_t buf, int32_t buf_len, int64_t cookie, int32_t used)
{
    TRACE("readdir fd %d cookie %d cap %d", (int)fd, (int)cookie, (int)buf_len);
    if (!is_dir_fd(fd)) return __WASI_ERRNO_NOTDIR;
    disk_scan();
    TRACE("readdir: %d files", nfiles);
    uint8_t *out = (uint8_t *)(uintptr_t)buf;
    uint32_t pos = 0, cap = (uint32_t)buf_len;
    for (int64_t i = cookie; i < nfiles && pos < cap; i++) {
        __wasi_dirent_t d = { (__wasi_dircookie_t)(i + 1), (__wasi_inode_t)(i + 2), (uint32_t)strlen(files[i].name), __WASI_FILETYPE_REGULAR_FILE };
        uint32_t n = cap - pos < sizeof d ? cap - pos : (uint32_t)sizeof d;     /* a cut record tells libc to grow */
        memcpy(out + pos, &d, n); pos += n;
        uint32_t m = cap - pos < d.d_namlen ? cap - pos : d.d_namlen;
        memcpy(out + pos, files[i].name, m); pos += m;
    }
    *(uint32_t *)(uintptr_t)used = pos;
    return 0;
}

/* Writes: the floppy is read-only (for now). With KESTREL_CDRIVE these are its half: C:'s are opt/kestrel_wasi_cfile.c's. */
int32_t WASI(path_create_directory)(int32_t fd, int32_t p, int32_t l) { (void)fd; (void)p; (void)l; return __WASI_ERRNO_ROFS; }
int32_t WASI(path_remove_directory)(int32_t fd, int32_t p, int32_t l) { (void)fd; (void)p; (void)l; return __WASI_ERRNO_ROFS; }
int32_t WASI(path_unlink_file)(int32_t fd, int32_t p, int32_t l) { (void)fd; (void)p; (void)l; return __WASI_ERRNO_ROFS; }
int32_t WASI(path_rename)(int32_t fd, int32_t p, int32_t l, int32_t fd2, int32_t p2, int32_t l2)
{ (void)fd; (void)p; (void)l; (void)fd2; (void)p2; (void)l2; return __WASI_ERRNO_ROFS; }
int32_t __imported_wasi_snapshot_preview1_path_readlink(int32_t fd, int32_t p, int32_t l, int32_t buf, int32_t len, int32_t used)
{ (void)fd; (void)p; (void)l; (void)buf; (void)len; *(uint32_t *)(uintptr_t)used = 0; return __WASI_ERRNO_INVAL; } /* no links */

/* Clocks: the frame clock (each port's SDL_GetPerformanceCounter, microseconds at 60 Hz). Carts are
 * frame-locked, so wall time is VBLs, the same on the board and in the browser. */
uint64_t SDL_GetPerformanceCounter(void);
int32_t __imported_wasi_snapshot_preview1_clock_time_get(int32_t id, int64_t precision, int32_t out)
{
    (void)id; (void)precision;
    *(uint64_t *)(uintptr_t)out = SDL_GetPerformanceCounter() * 1000u;
    return 0;
}

/* usleep/nanosleep: the cart never blocks, so a sleep returns at once with every event "fired". */
int32_t __imported_wasi_snapshot_preview1_poll_oneoff(int32_t in, int32_t out, int32_t n, int32_t nev)
{
    const __wasi_subscription_t *s = (const __wasi_subscription_t *)(uintptr_t)in;
    __wasi_event_t *e = (__wasi_event_t *)(uintptr_t)out;
    for (int32_t i = 0; i < n; i++) {
        memset(&e[i], 0, sizeof e[i]);
        e[i].userdata = s[i].userdata;
        e[i].type = s[i].u.tag;
    }
    *(uint32_t *)(uintptr_t)nev = (uint32_t)n;
    return 0;
}

/* exit(): the program cannot carry on. It asks to go back to the desktop (kestrel_quit.c), then traps. */
void kestrel_quit(void);
_Noreturn void __imported_wasi_snapshot_preview1_proc_exit(int32_t code)
{
    (void)code;
    kestrel_log("exit() called");
    kestrel_quit();
    __builtin_trap();
}
