/* The native host's scripted inputs (host_io.c), called by host/main.c. */
#ifndef ZM_HOST_IO_H
#define ZM_HOST_IO_H

#include "host.h"

/* --call F:name:a,b,c: queue the call; --disk X.zmd: mount X in the drive. */
void host_io_parse_call(const char* spec);
void host_io_mount_disk(const char* path);
/* Before frame f: the --call calls due, then the glass scripts' events. */
void host_io_run_calls(struct w2c_env* e, long f);
void host_io_glass_keys(struct w2c_env* e, long f);
void host_io_glass_mouse(struct w2c_env* e, long f);
/* The i-th --call as given (for the JSON's "calls"), NULL past the last. */
const char* host_io_call_spec(int i);

#endif
