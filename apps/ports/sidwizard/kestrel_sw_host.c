/* What the shared layer (../kestrel_sdl2/src: WASI over the floppy and C:, heap, quit, audio feed) expects from
 * its port: a log line and the frame clock libc's clock reads (kestrel_wasi.c clock_time_get). SID-Wizard has no
 * SDL, so these are all there is of it. */
#include <stdint.h>
#include <string.h>

__attribute__((import_module("env"), import_name("consoleLogJS"))) extern void consoleLogJS(const char *p, int len);

void kestrel_log(const char *m) { consoleLogJS(m, (int)strlen(m)); }

/* Microseconds of emulated C64 time: 22,050 samples a second (kestrel_sw.c counts them). */
extern uint64_t sw_samples;
uint64_t SDL_GetPerformanceCounter(void) { return sw_samples * 1000000u / 22050u; }
