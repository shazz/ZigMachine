/* The native host's scripted inputs (host/main.c): --call, --disk, and the glass's key
 * FIFO and mouse as ZM_GLASS_KEYS / ZM_GLASS_POINTER scripts, through the board's router. */
#include "host_io.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "boot.h"
#include "disk.h"
#include "input_bridge.h"

#define MAX_CALLS 64

typedef struct {
    long frame;
    char name[64];
    double args[HOST_MAX_ARGS];
    int nargs;
    const char* spec;
} call_t;

static call_t g_calls[MAX_CALLS];
static int g_ncalls;

/* "F:name:a,b,c" -> call_t; JS Number() semantics are approximated by strtod
 * (a malformed number becomes NaN, as Number("x") does). */
void host_io_parse_call(const char* spec) {
    if (g_ncalls == MAX_CALLS) { fprintf(stderr, "host: too many --call\n"); exit(1); }
    call_t* c = &g_calls[g_ncalls++];
    c->spec = spec;
    c->frame = strtol(spec, NULL, 10);
    const char* name = strchr(spec, ':');
    if (!name) { fprintf(stderr, "host: bad --call %s\n", spec); exit(1); }
    name++;
    const char* args = strchr(name, ':');
    size_t len = args ? (size_t)(args - name) : strlen(name);
    snprintf(c->name, sizeof c->name, "%.*s", (int)len, name);
    for (const char* p = args ? args + 1 : NULL; p && *p && c->nargs < HOST_MAX_ARGS;) {
        char* end;
        double v = strtod(p, &end);
        c->args[c->nargs++] = (end == p || (*end && *end != ',')) ? NAN : v;
        p = strchr(p, ',');
        if (p) p++;
    }
}

/* --disk: the whole image in memory, as the browser's mountDisk holds it. */
void host_io_mount_disk(const char* path) {
    FILE* f = fopen(path, "rb");
    long n = f && fseek(f, 0, SEEK_END) == 0 ? ftell(f) : -1;
    uint8_t* buf = n > 0 ? malloc((size_t)n) : NULL;
    if (!buf || fseek(f, 0, SEEK_SET) != 0 || fread(buf, 1, (size_t)n, f) != (size_t)n) {
        fprintf(stderr, "host: cannot read disk %s\n", path);
        exit(1);
    }
    fclose(f);
    host_disk = (host_disk_t){.data = buf, .size = (uint32_t)n};
}

const char* host_io_call_spec(int i) { return i < g_ncalls ? g_calls[i].spec : NULL; }

void host_io_run_calls(struct w2c_env* e, long f) {
    for (int i = 0; i < g_ncalls; i++)
        if (g_calls[i].frame == f && host_call(e, g_calls[i].name, g_calls[i].args, g_calls[i].nargs))
            exit(1);
}

/* ZM_GLASS_KEYS: this frame's events, through the router (cycles/binput.c's job on the board). */
void host_io_glass_keys(struct w2c_env* e, long f) {
    static const char* at;
    static int started;
    if (!started) at = getenv("ZM_GLASS_KEYS"), started = 1;
    uint32_t ev[32], n = 0;
    while (at && *at) {
        long frame = 0;
        unsigned long event = 0;
        int used = 0;
        if (sscanf(at, "%ld:%lx%n", &frame, &event, &used) != 2 || frame > f) break;
        at += used + (at[used] == ',');
        if (frame == f && n < 32) ev[n++] = (uint32_t)event;
    }
    input_events(&e->cart, ev, n);
}

/* ZM_GLASS_POINTER: this frame's REG_POINTER, polled and acked as cycles/binput.c does. */
void host_io_glass_mouse(struct w2c_env* e, long f) {
    static const char* at;
    static int started;
    static uint32_t ptr, seen;
    if (!started) at = getenv("ZM_GLASS_POINTER"), started = 1;
    if (!at) return;
    if (input_pointer_script(&at, f, &ptr)) {
        fprintf(stderr, "host: bad ZM_GLASS_POINTER entry before frame %ld\n", f);
        exit(2);
    }
    (void)input_pointer(&e->cart, ptr, &seen); /* the ack: nothing latched to drop here */
}
