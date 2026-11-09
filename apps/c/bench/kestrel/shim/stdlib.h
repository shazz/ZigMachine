#ifndef KS_STDLIB_H
#define KS_STDLIB_H
#include <stddef.h>
void *malloc(size_t n);
void free(void *p);
int atoi(const char *s);
long atol(const char *s);
#endif
