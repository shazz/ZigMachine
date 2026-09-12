// ZigMachine's Musashi configuration, force-included ahead of every Musashi
// source (build.zig passes `-include zm_musashi.h`).
//
// Why this and not a m68kconf.h of our own: upstream's m68kcpu.h says
// `#include "m68kconf.h"`, and a QUOTED include resolves next to the including
// file before it ever looks at -I paths — so a shadowing copy in another
// directory is silently ignored, however early that directory appears. Every
// option in upstream's m68kconf.h is wrapped in `#ifndef`, though, which is
// exactly the hook we need: define it first and upstream keeps our value. The
// vendored tree then stays byte-for-byte upstream.
#ifndef ZM_MUSASHI_H
#define ZM_MUSASHI_H

// An SNDH replay routine is 68000 code on a plain ST. Switching the later CPUs
// off lets the compiler fold away their paths. (0 == M68K_OPT_OFF, which
// m68kconf.h has not defined yet at this point — hence the literals.)
#define M68K_EMULATE_010 0
#define M68K_EMULATE_EC020 0
#define M68K_EMULATE_020 0
#define M68K_EMULATE_030 0
#define M68K_EMULATE_040 0

// The SNDH player calls init/exit/play as subroutines and has to know the
// instant one returns: it pushes a return address pointing at a planted NOP and
// watches for it here, ending the timeslice so the CPU cannot wander on past
// the end of the routine. (2 == M68K_OPT_SPECIFY_HANDLER.)
#define M68K_INSTRUCTION_HOOK 2
#define M68K_INSTRUCTION_CALLBACK(pc) zmSndhInstructionHook(pc)

extern void zmSndhInstructionHook(unsigned int pc);

#endif
