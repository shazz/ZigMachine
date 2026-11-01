#ifndef ZM_TRAP_H
#define ZM_TRAP_H

#include <stdint.h>

extern uint32_t zm_misaligned[2]; /* emulated misaligned loads, stores */
extern uint32_t zm_zmx_emulated;  /* ZM-X ops run as their twin (a core without ZM-X) */

int zm_zmx_probe(void); /* 1: the core has ZM-X; 0: trap.c emulates it */

void trap_install(void);
void zm_trap(uint32_t* regs);

#endif
