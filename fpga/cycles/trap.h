#ifndef ZM_TRAP_H
#define ZM_TRAP_H

#include <stdint.h>

extern uint32_t zm_misaligned[2]; /* emulated misaligned loads, stores */

void trap_install(void);
void zm_trap(uint32_t* regs);

#endif
