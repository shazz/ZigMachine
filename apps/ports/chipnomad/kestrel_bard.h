/* The BARD queue's ring, the cart side (kestrel_bard.cpp). */
#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
int kestrel_bq_open(uint32_t lead);                              /* 1: the host plays the queue; 0: no queue here */
void kestrel_bq_close(void);
int kestrel_bq_is_open(void);
int kestrel_bq_push(uint32_t t, uint32_t addr, uint32_t value);  /* 0: refused (closed, or the ring full: counted) */
void kestrel_bq_frame(void);                                     /* once a frame: the events let go */
uint32_t kestrel_bq_dropped(void);
#ifdef __cplusplus
}
#endif
