/* BARD jobs on the sound CPU (sjobs.c): opened by OP_JOB, served from the loop between renders. */
#ifndef ZM_SJOBS_H
#define ZM_SJOBS_H

#include <stdint.h>

void sjobs_open(uint32_t base, uint32_t size, uint32_t block);
void sjobs_take(void);

#endif
