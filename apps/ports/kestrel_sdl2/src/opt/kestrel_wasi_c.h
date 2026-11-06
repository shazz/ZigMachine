/* C: for a C port's POSIX calls, shared by opt/kestrel_wasi_c.c and opt/kestrel_wasi_cdir.c (path_open,
 * fd_readdir): C:'s fds, and the floppy's half of every WASI entry point (kestrel_wasi.c). */
#ifndef KESTREL_WASI_C_H
#define KESTREL_WASI_C_H
#include <wasi/api.h>
#include <stdint.h>
#include "kestrel_gemdos.h"

#define C_FD 4        /* the preopen "/C" */
#define C_FIRST 32    /* C:'s files and folders: fds C_FIRST .. C_FIRST + C_FDS - 1 */
#define C_FDS 8
#define PATH_MAX_C 160
typedef struct { int used, dir, up; int32_t h; uint32_t size; char path[PATH_MAX_C]; KDTA dta; uint64_t next; } kcd_t;
extern kcd_t kcd_fds[C_FDS];

int kestrel_c_mounted(void);
kcd_t *kcd_get(int32_t fd);
int kcd_is(int32_t fd);
int32_t kcd_errno(int32_t gemdos_error);
int kcd_path(int32_t fd, const char *rel, uint32_t len, char *out);
void kcd_stat(__wasi_filestat_t *st, int dir, uint32_t size, uint64_t ino);
int32_t kcd_kind(const char *path, uint32_t *size);

int32_t kestrel_floppy_fd_prestat_get(int32_t, int32_t);
int32_t kestrel_floppy_fd_prestat_dir_name(int32_t, int32_t, int32_t);
int32_t kestrel_floppy_fd_fdstat_get(int32_t, int32_t);
int32_t kestrel_floppy_fd_fdstat_set_flags(int32_t, int32_t);
int32_t kestrel_floppy_fd_close(int32_t);
int32_t kestrel_floppy_fd_read(int32_t, int32_t, int32_t, int32_t);
int32_t kestrel_floppy_fd_write(int32_t, int32_t, int32_t, int32_t);
int32_t kestrel_floppy_fd_seek(int32_t, int64_t, int32_t, int32_t);
int32_t kestrel_floppy_fd_filestat_get(int32_t, int32_t);
int32_t kestrel_floppy_path_filestat_get(int32_t, int32_t, int32_t, int32_t, int32_t);
int32_t kestrel_floppy_path_open(int32_t, int32_t, int32_t, int32_t, int32_t, int64_t, int64_t, int32_t, int32_t);
int32_t kestrel_floppy_fd_readdir(int32_t, int32_t, int32_t, int64_t, int32_t);

#endif
