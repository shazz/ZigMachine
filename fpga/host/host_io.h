/* The native host's scripted inputs (host_io.c), called by host/main.c. */
#ifndef ZM_HOST_IO_H
#define ZM_HOST_IO_H

#include "host.h"

/* --call F:name:a,b,c: queue the call; --disk X.zmd: mount X in the drive. */
void host_io_parse_call(const char* spec);
void host_io_mount_disk(const char* path);
/* --data-disk X.zmd: mount X, and after each frame do what the browser does for GEM over a
 * data disk (host/disk_app.h); a request is reported on stderr. Exits 2 if X is bootable. */
void host_io_data_disk(const char* path);
/* --program: the cart is a program GEM launched off that disk (the browser's req 3): no listing. */
void host_io_program(void);
void host_io_disk_frame(struct w2c_env* e, long f);
/* Before frame f: the --call calls due, then the glass scripts' events. */
void host_io_run_calls(struct w2c_env* e, long f);
void host_io_glass_keys(struct w2c_env* e, long f);
void host_io_glass_mouse(struct w2c_env* e, long f);
/* The i-th --call as given (for the JSON's "calls"), NULL past the last. */
const char* host_io_call_spec(int i);

#endif
