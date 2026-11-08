/* The BARD queue on the sound CPU (sbardq.c): opened by OP_BARD, taken and answered from the loop. */
#ifndef ZM_SBARDQ_H
#define ZM_SBARDQ_H

#include <stdint.h>

void sbardq_boot(void);
void sbardq_open(uint32_t addr, uint32_t lead);
void sbardq_take(void);
void sbardq_publish(void);
/* snd-bench SND_BARDQ=1 (sbardq_bench.c): a linked command log through the same pump. */
void bq_bench_start(void);
uint32_t bq_bench_frame(uint32_t f);

#endif
