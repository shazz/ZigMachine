#ifndef KS_SYS_TIMES_H
#define KS_SYS_TIMES_H
#include <sys/types.h>
/* times() answers microseconds (hostMicros), so Dhrystone is built with -DHZ=1000000. */
struct tms { clock_t tms_utime, tms_stime, tms_cutime, tms_cstime; };
int times(struct tms *t);   /* int: Dhrystone declares it `extern int times ()` */
#endif
