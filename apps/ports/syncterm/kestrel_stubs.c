/* What the SyncTERM cart leaves out, as the entry points the rest still names:
 * - modem / serial (comio) and the local shell (conn_pty.c): no serial port, no processes. A BBS entry of
 *   those types fails to connect, with SyncTERM's own message.
 * - webget.c (the BBS-list download over HTTPS): it needs cryptlib.
 * - the window icon (syncicon64.c): there is no window.
 * - termios, for ciolib's ANSI-on-stdout backend, which is linked but never chosen (kestrel_cio.c is). */
#include <stdbool.h>
#include <string.h>
#include <termios.h>

struct bbslist;
struct webget_request;
void kestrel_log(const char *m);

int modem_connect(struct bbslist *bbs) { (void)bbs; kestrel_log("syncterm: no modem on this machine"); return -1; }
int modem_close(void) { return 0; }
int serial_close(void) { return 0; }
int pty_connect(struct bbslist *bbs) { (void)bbs; kestrel_log("syncterm: no shell on this machine"); return -1; }
int pty_close(void) { return 0; }

bool init_webget_req(struct webget_request *req, const char *cache_root, const char *name, const char *uri)
{
    (void)req; (void)cache_root; (void)name; (void)uri;
    return false;
}
bool iniReadHttp(struct webget_request *req) { (void)req; return false; }

const char syncicon64[64 * 64 * 4];

int tcgetattr(int fd, struct termios *t) { (void)fd; memset(t, 0, sizeof *t); return -1; }
int tcsetattr(int fd, int act, const struct termios *t) { (void)fd; (void)act; (void)t; return -1; }
void cfmakeraw(struct termios *t) { (void)t; }

/* WASI calls the shared layer (kestrel_wasi.c) does not answer and SyncTERM reaches: clock_getres (xpdev's
 * timers), ftruncate and utime (its list and cache files: the floppy is read-only, so they fail as a
 * write does). Defined here, they resolve wasi-libc's imports inside the cart, as kestrel_wasi.c's do. */
#include <stdint.h>
#include <wasi/api.h>
int32_t __imported_wasi_snapshot_preview1_clock_res_get(int32_t id, int32_t out)
{
    (void)id;
    *(uint64_t *)(uintptr_t)out = 1000000000ull / 60;   /* the frame clock ticks at 60 Hz */
    return 0;
}
/* ftruncate: xpdev's iniWriteFile truncates the file it has just written at its end (chsize). On a C: file
 * being written (made "wb", so it is exactly what was written) that is already so: answered, as nothing
 * to do. Any other truncation is refused, a C: file is written whole (docs/os/KOS_GEMDOS.md §7). */
#include "../kestrel_sdl2/src/opt/kestrel_wasi_c.h"
int32_t __imported_wasi_snapshot_preview1_fd_filestat_set_size(int32_t fd, int64_t size)
{
    kcd_t *f = kcd_get(fd);
    if (!f) return __WASI_ERRNO_ROFS;
    if (f->dir || !f->w) return __WASI_ERRNO_BADF;
    int32_t at = Fseek(0, f->h, 1), end = Fseek(0, f->h, 2);
    Fseek(at, f->h, 0);
    return end >= 0 && size == end ? 0 : __WASI_ERRNO_NOTSUP;
}
int32_t __imported_wasi_snapshot_preview1_path_filestat_set_times(int32_t fd, int32_t flags, int32_t p, int32_t l,
                                                                  int64_t atim, int64_t mtim, int32_t fst)
{
    (void)fd; (void)flags; (void)p; (void)l; (void)atim; (void)mtim; (void)fst;
    return __WASI_ERRNO_ROFS;
}
