// The handful of libc symbols Musashi still references once it is compiled for
// wasm32-freestanding, all of them from code a plain 68000 cannot reach:
//
//   sin / cos          FSIN / FCOS in m68kfpu.c (68881 opcodes)
//   sprintf / sscanf   the FPU's decimal <-> extended conversion helpers
//   fprintf / vfprintf / stderr / exit
//                      m68kfpu.c + m68kmmu.h complaining about unimplemented
//                      68030/68040 instructions
//
// m68kcpu.c includes both files unconditionally and the generated opcode table
// carries every handler whatever CPU type is configured, so these must LINK —
// but reaching one means the emulated CPU executed an opcode a 68000 does not
// have, i.e. the replay routine has run off into garbage. Trapping is the right
// answer: wasm unwinds to the host with a clear fault instead of playing on with
// a silently wrong result.
//
// setjmp/longjmp are the exception: m68k_execute() arms a bus-error trap on
// every entry, so setjmp is genuinely called and must return 0 ("no jump").
// Nothing can take that jump here — every address in the SNDH player's map is
// answered, so the bus never errors — and wasm has no stack to unwind anyway,
// hence the trapping longjmp.
#include <stdio.h>
#include <math.h>
#include <setjmp.h>

FILE *stderr;

int setjmp(jmp_buf env) { (void)env; return 0; }
void longjmp(jmp_buf env, int val) { (void)env; (void)val; __builtin_trap(); }

static double trap(void) { __builtin_trap(); }

double sin(double x) { (void)x; return trap(); }
double cos(double x) { (void)x; return trap(); }

int sprintf(char *buf, const char *fmt, ...) { (void)buf; (void)fmt; __builtin_trap(); }
int sscanf(const char *s, const char *fmt, ...) { (void)s; (void)fmt; __builtin_trap(); }
int fprintf(FILE *f, const char *fmt, ...) { (void)f; (void)fmt; __builtin_trap(); }
int vfprintf(FILE *f, const char *fmt, __builtin_va_list ap) { (void)f; (void)fmt; (void)ap; __builtin_trap(); }
void exit(int code) { (void)code; __builtin_trap(); }
