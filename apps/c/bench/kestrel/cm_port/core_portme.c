/* CoreMark port layer, see core_portme.h. Apache-2.0 (EEMBC barebones template). */
#include "coremark.h"

__attribute__((import_module("env"), import_name("hostMicros"))) extern ee_u32 hostMicros(void);

static CORE_TICKS start_val, stop_val;
CORE_TICKS cm_last_ticks;
ee_u32 default_num_contexts = MULTITHREAD;

void start_time(void) { start_val = hostMicros(); }
void stop_time(void) { stop_val = hostMicros(); }
CORE_TICKS get_time(void) { return cm_last_ticks = stop_val - start_val; }
secs_ret time_in_secs(CORE_TICKS ticks) { return (secs_ret)ticks / (secs_ret)EE_TICKS_PER_SEC; }

void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc; (void)argv;
    p->portable_id = 1;
}
void portable_fini(core_portable *p) { p->portable_id = 0; }
